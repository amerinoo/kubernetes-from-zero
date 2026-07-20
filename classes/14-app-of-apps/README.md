# 14 — Argo CD: App of Apps

## Objective

Bootstrap the class 13 ApplicationSet from one parent Argo CD Application.

In class 13, we applied the ApplicationSet directly with `kubectl`:

```text
kubectl → ApplicationSet → Applications → Kubernetes resources
```

In this class, `kubectl` creates one root Application. Argo CD then manages the
ApplicationSet from Git, and the ApplicationSet manages the generated
Applications:

```text
kubectl
  ↓
Application: course-bootstrap
  ↓
ApplicationSet: course-apps
  ↓
Applications: echo-dev, whoami-dev, whoami-prod
  ↓
Deployments, Services, Ingresses, ConfigMaps
```

This hierarchy is called the **App of Apps** pattern: an Argo CD Application
whose desired resources are other Argo CD resources.

## New concepts

### Root Application

`course-bootstrap` is the root Application in
[`root-application.yaml`](root-application.yaml). Its source is the class 13
directory in Git:

```yaml
source:
  repoURL: https://github.com/amerinoo/kubernetes-from-zero.git
  targetRevision: main
  path: classes/13-applicationsets-matrix
```

The directory contains `applicationset.yaml`. Because `recurse` is `false`,
the root Application reads only manifests in that directory and does not walk
into the Helm chart directories below `apps/`.

### Bootstrap boundary

Something must create the first Argo CD Application. In this class, that is
one `kubectl apply` command. After that bootstrap step, changes to the class 13
ApplicationSet are reconciled from Git by Argo CD.

The root Application manifest is also stored in Git. In a larger system it is
normally created by a tightly controlled bootstrap process such as Terraform,
a cluster provisioning pipeline, or a one-time administrative command.

### Cascading ownership

The root Application has a resource finalizer:

```yaml
finalizers:
  - resources-finalizer.argocd.argoproj.io
```

Deleting it cascades through the hierarchy:

```text
course-bootstrap deletion
  → course-apps ApplicationSet deletion
    → generated Applications deletion
      → managed Kubernetes resources deletion
```

This is convenient for a disposable course cluster, but it is powerful. Only
trusted administrators should be able to change a parent Application or its
Git source.

## Prerequisites

- Class 13 complete and committed.
- The class 13 files pushed to the `main` branch on GitHub.
- Argo CD installed in the local cluster.

Check that the ApplicationSet from class 13 exists:

```bash
kubectl get applicationset course-apps -n argocd
```

It is fine if it already exists: the root Application will adopt its manifest
as the desired state.

## 1. Publish the class 14 bootstrap manifest

The root Application itself is applied locally, but the ApplicationSet it
manages is read from GitHub. Commit and push the course files before creating
the root Application:

```bash
git add README.md classes/13-applicationsets-matrix classes/14-app-of-apps
git commit -m "Add App of Apps class"
git push origin main
```

## 2. Create the root Application

From the repository root:

```bash
kubectl apply -f classes/14-app-of-apps/root-application.yaml
```

Check the root Application:

```bash
kubectl get application course-bootstrap -n argocd
kubectl describe application course-bootstrap -n argocd
```

Its automatic sync policy applies the ApplicationSet from Git. Check the full
hierarchy:

```bash
kubectl get applicationset course-apps -n argocd
kubectl get applications -n argocd
kubectl get deployments -n apps-dev
kubectl get deployments -n apps-prod
```

In the Argo CD UI, open `course-bootstrap`. Its resource tree contains the
`course-apps` ApplicationSet. From there, inspect the Applications generated
for each enabled component and environment.

## 3. Change the ApplicationSet through Git

The root Application tracks the class 13 directory. Edit the ApplicationSet
or an environment `cluster-config.yaml`, then commit and push the change.

For example, add `echo` to production's `components` list and add its matching
environment values file. The update flows through the complete hierarchy:

```text
Git commit
  → course-bootstrap synchronizes course-apps
    → course-apps generates echo-prod
      → echo-prod deploys the echo chart
```

Do not edit the live ApplicationSet as the normal workflow. Argo CD will
compare it with Git and restore the Git version.

## 4. Observe self-healing at each level

Change the ApplicationSet directly in the cluster, for example remove an app
from its generator list. The root Application detects that the ApplicationSet
no longer matches Git and restores it.

The ApplicationSet then ensures its generated Applications match its template,
and each generated Application ensures its Kubernetes resources match its
chart. This is reconciliation at multiple levels.

## Troubleshooting

If `course-bootstrap` is `OutOfSync` or `Degraded`:

```bash
kubectl describe application course-bootstrap -n argocd
kubectl get events -n argocd --sort-by=.lastTimestamp
```

If the ApplicationSet is missing from the root Application's resource tree,
check that class 13 is pushed to GitHub and that `source.path` is exactly
`classes/13-applicationsets-matrix`.

If a generated Application is missing, inspect the ApplicationSet:

```bash
kubectl describe applicationset course-apps -n argocd
```

## Cleanup

Deleting the root Application cascades to every child resource:

```bash
kubectl delete application course-bootstrap -n argocd
```

Use this only for the disposable course cluster. To preserve child resources,
remove the root finalizer before deleting the root Application.

## References

- [Argo CD cluster bootstrapping and App of Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ApplicationSet generators](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators/)

## Notes

> Write down anything you discover while practising.
