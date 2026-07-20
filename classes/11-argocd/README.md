# 11 — Argo CD: GitOps

## Objective

Deploy the Helm application from class 10 with Argo CD.

Until now, we have deployed changes ourselves with `helm install` and `helm
upgrade`. In this class, Git declares the desired state and Argo CD makes the
cluster match it.

```text
GitHub → Argo CD → Helm → Kubernetes
                         ↓
              Ingress → Services → Pods
```

This class deploys:

```text
Repository: https://github.com/amerinoo/kubernetes-from-zero
Chart:      classes/10-helm-secrets/apps
Values:     values-dev.yaml
Namespace:  apps-dev
```

## New concepts

### GitOps

GitOps is an operational model where Git stores the desired state of an
environment. A commit is not only source code history: it is also the record
of what should be running in Kubernetes.

Instead of a person running a deployment command after every change, a
controller reads Git and reconciles the cluster continuously.

### Desired state and live state

- **Desired state** is what Argo CD renders from the Git repository.
- **Live state** is what is currently running in Kubernetes.

When both states are equal, the application is **Synced**. When they differ,
it is **OutOfSync**. Argo CD can show the difference and apply the desired
state to the cluster.

### Reconciliation

Reconciliation is the repeated comparison between desired and live state.
This is the central idea behind Kubernetes controllers, and Argo CD is also a
controller. It does not run Helm once and disappear: it keeps checking the
application over time.

### Argo CD Application

An Argo CD `Application` is a Kubernetes custom resource. It answers two
questions:

1. Where is the desired configuration? In this class: a Helm chart in GitHub.
2. Where should it be deployed? In this class: the `apps-dev` namespace in
   the local cluster.

The manifest for this Application is
[`application.yaml`](application.yaml).

### Helm in Argo CD

Argo CD uses Helm to render the chart into Kubernetes manifests. It does not
create a normal Helm release that you manage with `helm upgrade`; Argo CD owns
the deployment lifecycle. After this class, change the chart in Git and let
Argo CD synchronize it.

## Prerequisites

- Docker, kind, and `kubectl` installed.
- Helm installed.
- A cluster created with `./classes/kind/start.sh`.
- NGINX Ingress Controller installed to test HTTP routes.

Check that `kubectl` points to the course cluster:

```bash
kubectl config current-context
kubectl get nodes
```

The expected context is `kind-argocd-cluster`.

The optional `argocd` CLI is used in a few alternative commands below. The UI
and `kubectl` are enough to complete the class.

## 1. Install Argo CD

Argo CD runs inside Kubernetes, in its own `argocd` namespace. Its installation
contains several components, including an API server, a repository server, and
an application controller.

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  --server-side \
  --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

`--server-side --force-conflicts` is required by the official installation
because some Argo CD CRDs are too large for client-side apply.

Wait for the server to become available:

```bash
kubectl get pods -n argocd
kubectl wait --for=condition=Available deployment/argocd-server \
  -n argocd --timeout=180s
```

## 2. Open the Argo CD UI

Argo CD is not exposed outside the cluster by default. `port-forward` creates
a temporary local tunnel without adding an Ingress or a LoadBalancer.

Use port `8081`, not `8080`: the kind configuration reserves `8080` for the
NGINX Ingress Controller used by the course.

```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443
```

Keep this command running and open `https://localhost:8081`. Your browser may
warn about Argo CD's local TLS certificate.

Log in with the username `admin`. Retrieve the generated initial password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Change the password after the first login. Once changed, remove the initial
password Secret:

```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

## 3. Create the external Secret

The class 10 chart references `apps-dev-secret`, but deliberately does not
create it. The Secret must exist in `apps-dev` before the Pods start:

```bash
kubectl create namespace apps-dev

kubectl create secret generic apps-dev-secret \
  --from-literal=API_USERNAME='dev-user' \
  --from-literal=API_TOKEN='dev-token-only-for-class' \
  -n apps-dev
```

Check only the key names, not their values:

```bash
kubectl get secret apps-dev-secret -n apps-dev \
  -o go-template='{{range $key, $value := .data}}{{$key}}{{"\\n"}}{{end}}' \
  | sort
```

Do not commit this Secret to Git. The important boundary is:

| Managed by Argo CD | Managed outside Argo CD |
|---|---|
| Deployments, Services, Ingress, ConfigMap | `apps-dev-secret` |
| The Helm chart and its non-sensitive values | Real secret values |

This keeps the class faithful to class 10. A future class can introduce a
dedicated secret-management tool such as External Secrets or Sealed Secrets.

## 4. Create the Application

From the repository root, apply the Argo CD custom resource:

```bash
kubectl apply -f classes/11-argocd/application.yaml
```

Read the important parts of the manifest:

| Field | Meaning |
|---|---|
| `repoURL` | The public Git repository Argo CD watches. |
| `targetRevision` | The Git revision to use: the `main` branch. |
| `path` | The Helm chart directory inside that repository. |
| `valueFiles` | The values file passed to Helm: `values-dev.yaml`. |
| `destination` | The target cluster and namespace. |
| `CreateNamespace=true` | Argo CD creates `apps-dev` if it is missing. |
| `finalizers` | Deleting the Application also deletes the resources it manages. |

Check its state:

```bash
kubectl get application apps-dev -n argocd
kubectl describe application apps-dev -n argocd
```

The application should initially be `OutOfSync`. This is expected: Argo CD has
found the desired manifests in Git, but no synchronization has applied them.

## 5. Synchronize manually

In the UI, open `apps-dev`, select **Sync**, inspect the list of resources,
and confirm.

This first manual sync is intentional. It makes the Git → comparison → deploy
flow visible before automatic synchronization is enabled.

If the `argocd` CLI is installed, the equivalent is:

```bash
argocd app sync apps-dev --port-forward-namespace argocd
argocd app wait apps-dev --health --sync --port-forward-namespace argocd
```

Verify the result:

```bash
kubectl get configmap,deployments,services,ingress -n apps-dev
kubectl get pods -n apps-dev
```

The UI distinguishes two useful status values:

- **Sync status** compares Git and Kubernetes: `Synced` or `OutOfSync`.
- **Health status** reports whether Kubernetes resources are working:
  `Healthy`, `Progressing`, `Degraded`, or `Missing`.

For example, an application may be `Synced` but `Progressing` while a new
Deployment is still starting Pods.

## 6. Test the application

The class 10 Ingress uses the host `hello-dev.local`:

```bash
curl -H 'Host: hello-dev.local' http://localhost:8080/echo
curl -H 'Host: hello-dev.local' http://localhost:8080/whoami
```

The `echo` Pod should receive the Secret without printing its value:

```bash
kubectl exec -n apps-dev deploy/echo -- printenv API_TOKEN >/dev/null \
  && echo API_TOKEN is set
```

## 7. Change the application through Git

Edit `classes/10-helm-secrets/apps/values-dev.yaml`. For example, change
`config.logLevel` from `debug` to `info`.

Validate the rendered chart, then commit and push the change:

```bash
helm lint classes/10-helm-secrets/apps
helm template apps-dev classes/10-helm-secrets/apps \
  -f classes/10-helm-secrets/apps/values-dev.yaml >/dev/null

git add classes/10-helm-secrets/apps/values-dev.yaml
git commit -m "Change development log level"
git push origin main
```

Argo CD eventually detects the new commit and shows `OutOfSync`. In the UI,
use **Refresh** to check immediately, inspect the diff, then select **Sync**.

At this point, do not run `helm upgrade`. Git is now the deployment input and
Argo CD is the component that applies it.

## 8. Enable automatic synchronization

After seeing the manual workflow, enable automatic synchronization:

```bash
kubectl patch application apps-dev -n argocd --type merge -p \
  '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}'
```

The options have different responsibilities:

- `automated` applies a Git change without clicking Sync.
- `prune` deletes resources previously managed by the Application when they
  are removed from Git.
- `selfHeal` restores a managed resource after someone changes it directly in
  the cluster.

Test `selfHeal` by changing the live state manually:

```bash
kubectl scale deployment/echo --replicas=2 -n apps-dev
kubectl get deployment echo -n apps-dev -w
```

The deployment should return to the replica count defined by Helm values in
Git. This shows why direct production changes are risky in a GitOps workflow:
they are temporary and leave no desired-state record.

## 9. Basic troubleshooting

If the Application is `Degraded`, inspect its workloads:

```bash
kubectl get pods -n apps-dev
kubectl describe pod -n apps-dev -l app=echo
kubectl describe pod -n apps-dev -l app=whoami
```

If Pods cannot start because the Secret is missing:

```bash
kubectl get secret apps-dev-secret -n apps-dev
```

If Argo CD reports `ComparisonError`, check the repository URL, branch, chart
path, and values file in the Application:

```bash
kubectl get application apps-dev -n argocd -o yaml
```

If the Pods are healthy but the HTTP requests fail, verify that the NGINX
Ingress Controller is installed and that port `8080` is available.

## Practice tasks

1. Change `replicaCount` in `values-dev.yaml` and inspect the Argo CD diff.
2. Change `welcomeMessage`, push it, and verify the Pod rollout.
3. Delete the `whoami` Service manually and observe self-healing.
4. Change the Secret name in `values-dev.yaml` and explain the resulting Pod
   failure.
5. Explain which resources belong in Git and why the Secret does not.

## Cleanup

The Application has a resource finalizer, so this command removes the
Application and the Kubernetes resources it manages:

```bash
kubectl delete application apps-dev -n argocd
kubectl delete namespace apps-dev
```

To remove Argo CD from this practice cluster:

```bash
kubectl delete namespace argocd
```

## References

- [Try Argo CD Locally](https://argo-cd.readthedocs.io/en/stable/try_argo_cd_locally/)
- [Argo CD Helm support](https://argo-cd.readthedocs.io/en/latest/user-guide/helm/)
- [Automated Sync](https://argo-cd.readthedocs.io/en/latest/user-guide/auto_sync/)

## Notes

> Write down anything you discover while practising.
