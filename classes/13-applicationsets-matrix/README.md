# 13 — Argo CD: ApplicationSet Matrix

## Objective

Deploy each application independently in each environment.

Class 12 used one Application per environment. Each generated Application
deployed both `echo` and `whoami` together:

```text
apps-dev  → echo + whoami in development
apps-prod → echo + whoami in production
```

This class separates the services into individual Helm charts and uses an
ApplicationSet matrix to create every application/environment combination:

```text
                     ┌──────────────┐
                     │  dev / prod  │
                     └──────┬───────┘
                            ×
                     ┌──────┴───────┐
                     │ echo / whoami│
                     └──────┬───────┘
                            ↓
echo-dev     whoami-dev     whoami-prod
```

## Structure

```text
13-applicationsets-matrix/
├── README.md
├── applicationset.yaml
├── apps/
    ├── echo/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    │       ├── configmap.yaml
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       └── ingress.yaml
    └── whoami/
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
            ├── configmap.yaml
            ├── deployment.yaml
            ├── service.yaml
            └── ingress.yaml
└── environments/
    ├── dev/
    │   ├── cluster-config.yaml
    │   ├── echo.yaml
    │   └── whoami.yaml
    └── prod/
        ├── cluster-config.yaml
        ├── echo.yaml
        └── whoami.yaml
```

## Why separate Applications?

With class 12, changing `echo` and changing `whoami` affect the same Argo CD
Application. They have one sync status, one health status, and one deployment
unit.

With this class, every service has its own Application:

| Application | Chart | Values file | Namespace |
|---|---|---|---|
| `echo-dev` | `apps/echo` | `environments/dev/echo.yaml` | `apps-dev` |
| `whoami-dev` | `apps/whoami` | `environments/dev/whoami.yaml` | `apps-dev` |
| `whoami-prod` | `apps/whoami` | `environments/prod/whoami.yaml` | `apps-prod` |

This is useful when services have independent versions, owners, permissions,
release schedules, or rollback requirements.

## New concept: the matrix generator

The matrix generator combines the output of two generators. In this class, the
first generator reads each environment's `cluster-config.yaml` from Git. The
second generator reads that environment's `components` list:

```yaml
env: dev
components:
  - app: echo
  - app: whoami
```

The matrix creates one Application for every component listed by each
environment:

```text
(dev, echo)     (dev, whoami)
(prod, whoami)
```

This keeps the relationship in Git: removing `echo` from production's
`components` list means Argo CD does not generate `echo-prod`.

The generator data is used by the Application template:

```yaml
metadata:
  name: '{{ .app }}-{{ .env }}'
spec:
  source:
    path: 'classes/13-applicationsets-matrix/apps/{{ .app }}'
    helm:
      releaseName: '{{ .app }}-{{ .env }}'
      valueFiles:
        - '../../environments/{{ .env }}/cluster-config.yaml'
        - '../../environments/{{ .env }}/{{ .app }}.yaml'
  destination:
    namespace: 'apps-{{ .env }}'
```

The template creates `whoami-prod` by replacing `.app` with `whoami` and
`.env` with `prod`.

## Environment values

The charts keep only service defaults in `apps/echo/values.yaml` and
`apps/whoami/values.yaml`. Everything that differs by environment lives under
`environments/`:

```text
environments/
├── dev/
│   ├── cluster-config.yaml
│   ├── echo.yaml
│   └── whoami.yaml
└── prod/
    ├── cluster-config.yaml
    └── whoami.yaml
```

This answers a useful question directly: “what is deployed in production?”
Review `environments/prod/` without searching inside every service chart. The
ApplicationSet derives the relative Helm path from both matrix parameters.

`cluster-config.yaml` contains settings shared by every service in one
environment, plus the list of services enabled there:

```yaml
env: prod
components:
  - app: whoami

image:
  tag:
    whoami: latest
```

Argo CD passes value files to Helm in their listed order. The chart's
`values.yaml` supplies service defaults, `cluster-config.yaml` supplies the
required environment-specific image tags, and `echo.yaml` or `whoami.yaml`
supplies service-specific settings. The later file has higher precedence when
both files define the same key.

The charts intentionally do not define a fallback image tag. Their Deployment
template requires the tag for its own chart name; rendering without the
environment `cluster-config.yaml` fails with a clear error.

Use a real, immutable image tag rather than `latest` in a production system.
Changing `image.tag.whoami` updates `whoami-prod`.

The Deployment templates use `index .Values.image.tag .Chart.Name` to select the
tag dynamically. `.Chart.Name` is `echo` in the echo chart and `whoami` in the
whoami chart, so one template expression reads the matching key from
`image.tag`.

## Prerequisites

- Class 12 complete: Argo CD and the `apps-dev` and `apps-prod` namespaces
  already exist.
- An NGINX Ingress Controller is installed to test HTTP routes.

## 1. Inspect the charts

Each service now has its own Helm chart.

The `echo` chart owns only its ConfigMap, Deployment, Service, and `/echo`
Ingress route.

The `whoami` chart owns only its ConfigMap, Deployment, Service, and
`/whoami` Ingress route.

This class focuses on the matrix generator and independent deployment units.

Render the three enabled combinations before involving Argo CD:

```bash
helm lint classes/13-applicationsets-matrix/apps/echo \
  -f classes/13-applicationsets-matrix/environments/dev/cluster-config.yaml \
  -f classes/13-applicationsets-matrix/environments/dev/echo.yaml

helm lint classes/13-applicationsets-matrix/apps/whoami \
  -f classes/13-applicationsets-matrix/environments/dev/cluster-config.yaml \
  -f classes/13-applicationsets-matrix/environments/dev/whoami.yaml

helm template echo-dev classes/13-applicationsets-matrix/apps/echo \
  -f classes/13-applicationsets-matrix/environments/dev/cluster-config.yaml \
  -f classes/13-applicationsets-matrix/environments/dev/echo.yaml

helm template whoami-prod classes/13-applicationsets-matrix/apps/whoami \
  -f classes/13-applicationsets-matrix/environments/prod/cluster-config.yaml \
  -f classes/13-applicationsets-matrix/environments/prod/whoami.yaml
```

Notice that `echo` and `whoami` use different release names. Their generated
ConfigMaps are therefore independent: `echo-dev-config` and
`whoami-dev-config` in development, for example.

## 2. Migrate from the class 12 ApplicationSet

Class 12 created an ApplicationSet named `apps`, which generated `apps-dev`
and `apps-prod`. This class creates different Application names, so remove the
old ApplicationSet before applying the matrix version.

The old Applications use resource finalizers. Remove those finalizers first so
their workloads remain running while the new Applications take ownership:

```bash
kubectl patch application apps-dev -n argocd --type json -p \
  '[{"op":"remove","path":"/metadata/finalizers"}]'

kubectl patch application apps-prod -n argocd --type json -p \
  '[{"op":"remove","path":"/metadata/finalizers"}]'

kubectl delete applicationset apps -n argocd
```

The old shared ConfigMaps and Ingresses are no longer part of the new charts.
After the new Applications are healthy, remove these obsolete resources:

```bash
kubectl delete configmap apps-dev-config -n apps-dev
kubectl delete configmap apps-prod-config -n apps-prod
kubectl delete ingress apps -n apps-dev
kubectl delete ingress apps -n apps-prod
```

This migration is only needed when continuing directly from class 12. On a
fresh cluster, skip this section.

## 3. Apply the matrix ApplicationSet

Argo CD reads the generated Applications' charts from GitHub, not from your
working directory. Publish this class before applying its ApplicationSet:

```bash
git add README.md classes/13-applicationsets-matrix
git commit -m "Add ApplicationSet matrix class"
git push origin main
```

From the repository root:

```bash
kubectl apply -f classes/13-applicationsets-matrix/applicationset.yaml
```

The ApplicationSet controller should generate three Applications:

```bash
kubectl get applications -n argocd
```

Expected result:

```text
echo-dev
whoami-dev
whoami-prod
```

The template enables `automated`, `prune`, and `selfHeal`, so each Application
synchronizes independently.

Wait for all three Applications:

```bash
kubectl get applications -n argocd -w
```

Use `Ctrl+C` when every Application is `Synced` and `Healthy`.

## 4. Verify independent deployments

Check the replica counts:

```bash
kubectl get deployments -n apps-dev
kubectl get deployments -n apps-prod
```

Development has one replica of each service. Production has three replicas of
`whoami` only. The same matrix template selected the correct values file for
each generated Application.

Test the enabled services:

```bash
curl -H 'Host: hello-dev.local' http://localhost:8080/echo
curl -H 'Host: hello-dev.local' http://localhost:8080/whoami

curl -H 'Host: hello.local' http://localhost:8080/whoami
```

## 5. Change only one service

Change `image.tag.whoami` in `environments/prod/cluster-config.yaml`, then commit
and push it:

```bash
git add classes/13-applicationsets-matrix/environments/prod/cluster-config.yaml
git commit -m "Change production image tag"
git push origin main
```

Only `whoami-prod` should become `OutOfSync` and synchronize. The other two
Applications should remain unchanged.

This keeps version decisions grouped by environment, while preserving
independent deployment operations for each service.

## Practice tasks

1. Change `image.tag.whoami` in production and confirm that only `whoami-prod`
   changes.
2. Change `whoami` production replicas and confirm that only `whoami-prod`
   changes.
3. Delete the `whoami-prod` Service manually and observe that only `whoami-prod`
   self-heals it.
4. Add `echo` to production's `components` list, create
   `environments/prod/echo.yaml`, and observe Argo CD generate `echo-prod`.
5. Add a `staging` `cluster-config.yaml` and explain why its components list
   determines the generated Applications.
6. Compare the ApplicationSet UI hierarchy from classes 12 and 13.

## Cleanup

Deleting the ApplicationSet deletes its generated Applications. Their
finalizers then delete each service's resources:

```bash
kubectl delete applicationset course-apps -n argocd
kubectl delete namespace apps-dev apps-prod
```

## References

- [ApplicationSet matrix generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Matrix/)
- [ApplicationSet generators](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators/)
- [Argo CD Helm support](https://argo-cd.readthedocs.io/en/latest/user-guide/helm/)

## Notes

> Write down anything you discover while practising.
