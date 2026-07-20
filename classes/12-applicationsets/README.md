# 12 — Argo CD: ApplicationSets

## Objective

Replace one hand-written Argo CD `Application` with an `ApplicationSet` that
generates applications for both `dev` and `prod`.

Class 11 deployed only development with one Application:

```text
Application apps-dev → values-dev.yaml → apps-dev namespace
```

This class defines a reusable template and a list of environments:

```text
ApplicationSet apps
├── Application apps-dev  → values-dev.yaml  → apps-dev
└── Application apps-prod → values-prod.yaml → apps-prod
```

## New concepts

### ApplicationSet

An `ApplicationSet` is an Argo CD custom resource that generates one or more
`Application` resources. It is useful when applications follow the same
pattern but differ by parameters such as an environment, cluster, namespace,
or values file.

An ApplicationSet is not a replacement for the generated Applications. It is
their parent: the ApplicationSet controller creates and maintains them.

### Generator

A generator provides the input values used to create Applications. This class
uses a `list` generator because the environments are a small, explicit list:

```yaml
elements:
  - env: dev
  - env: prod
```

Each element is rendered once. Adding a third element would generate a third
Application without copying the Application template.

### Template

The `template` section is an Application blueprint. Values from each generator
element replace expressions such as `{{ .env }}` and
the namespace and values file are derived as `apps-{{ .env }}` and
`values-{{ .env }}.yaml`.

For the `prod` element, the template produces the same essential configuration
as writing this by hand:

```yaml
metadata:
  name: apps-prod
spec:
  source:
    helm:
      releaseName: apps-prod
      valueFiles:
        - values-prod.yaml
  destination:
    namespace: apps-prod
```

`goTemplateOptions: [missingkey=error]` makes a missing generator field fail
instead of silently producing an incorrect Application name, namespace, or
values file.

## Prerequisites

- Class 11 completed: Argo CD is installed and reachable.
- The class 10 Helm chart is available in the `main` branch on GitHub.
- The `apps-dev-secret` and `apps-prod-secret` Secrets exist in their matching
  namespaces.

Create the production Secret before deploying production:

```bash
kubectl create namespace apps-prod

kubectl create secret generic apps-prod-secret \
  --from-literal=API_USERNAME='prod-user' \
  --from-literal=API_TOKEN='prod-token-only-for-class' \
  -n apps-prod
```

The Secret remains outside Git and outside the ApplicationSet. It contains
sensitive values; the ApplicationSet only selects the non-sensitive Helm
values file that references it.

## 1. Inspect the ApplicationSet

Read [`applicationset.yaml`](applicationset.yaml). The important fields are:

| Field | Purpose |
|---|---|
| `generators.list.elements` | The environments to create. |
| `template` | The shared Application definition. |
| `env` | Builds the Application name, Helm release name, namespace, and values file. |
| `values-{{ .env }}.yaml` | Selects the Helm values file derived from `env`. |
| `automated` | Synchronizes changes from Git automatically. |
| `prune` | Deletes managed resources removed from Git. |
| `selfHeal` | Restores managed resources changed directly in Kubernetes. |

The list generator is deliberately simple. It targets two environments in one
cluster. Other generators can discover clusters or read configuration files
from Git when the number of environments grows.

## 2. Migrate from the class 11 Application

The ApplicationSet will generate an Application named `apps-dev`, which is the
same name used in class 11. Remove the old standalone Application first.

The class 11 Application has a finalizer. That finalizer would delete the
resources it manages, so remove the finalizer before deleting the old
Application. The workloads remain running during the migration:

```bash
kubectl patch application apps-dev -n argocd --type json -p \
  '[{"op":"remove","path":"/metadata/finalizers"}]'

kubectl delete application apps-dev -n argocd
```

Confirm that the development resources still exist:

```bash
kubectl get deployments,services,ingress -n apps-dev
```

This is a deliberate migration step, not the usual cleanup workflow. In a
normal cleanup, keep the finalizer so Argo CD removes managed resources.

## 3. Apply the ApplicationSet

From the repository root:

```bash
kubectl apply -f classes/12-applicationsets/applicationset.yaml
```

The ApplicationSet controller creates two Applications. Check both the parent
and its generated children:

```bash
kubectl get applicationset apps -n argocd
kubectl get applications -n argocd
```

Expected Applications:

```text
apps-dev
apps-prod
```

Because automated synchronization is in the template, Argo CD deploys both
environments after it creates their Applications. Wait for them to become
healthy:

```bash
kubectl get applications -n argocd -w
```

Use `Ctrl+C` when both Applications show `Synced` and `Healthy`.

## 4. Verify both environments

Compare the workloads:

```bash
kubectl get deployments -n apps-dev
kubectl get deployments -n apps-prod
```

`dev` has one replica of each application; `prod` has three. Those differences
come from `values-dev.yaml` and `values-prod.yaml`, while the chart and
Application template remain the same.

Test both Ingress hosts:

```bash
curl -H 'Host: hello-dev.local' http://localhost:8080/echo
curl -H 'Host: hello.local' http://localhost:8080/echo
```

## 5. Change one environment

Edit only `values-prod.yaml`, for example change a replica count. Commit and
push the change:

```bash
git add classes/10-helm-secrets/apps/values-prod.yaml
git commit -m "Change production replicas"
git push origin main
```

Argo CD renders the same chart for both Applications, but only `apps-prod`
becomes `OutOfSync` because only its values file changed. Auto-sync then
updates production.

## 6. Add an environment

To add a new environment, add one list element and create its external Secret:

```yaml
- env: staging
```

The ApplicationSet controller then creates `apps-staging` and deploys it to
the `apps-staging` namespace. The chart must have `values-staging.yaml`, and
the namespace must contain the Secret named by that file.

## Troubleshooting

If an Application is missing, inspect the parent ApplicationSet:

```bash
kubectl describe applicationset apps -n argocd
```

If only production is `Degraded`, inspect its Pods and Secret:

```bash
kubectl get pods -n apps-prod
kubectl get secret apps-prod-secret -n apps-prod
kubectl describe pod -n apps-prod -l app=echo
```

If the ApplicationSet reports a template error, check that every generator
element supplies `env`. The `missingkey=error` option makes this mistake
explicit.

## Cleanup

Deleting the ApplicationSet deletes its generated Applications. Their
finalizers then delete the resources managed by each Application:

```bash
kubectl delete applicationset apps -n argocd
kubectl delete namespace apps-dev apps-prod
```

## References

- [Generating Applications with ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [List generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-List/)
- [ApplicationSet templates](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Template/)

## Notes

> Write down anything you discover while practising.
