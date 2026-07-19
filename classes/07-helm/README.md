# 07 — Helm: First Chart

## Objective

Progressively convert the application from class 06 into a Helm chart.
The chart keeps the same Kubernetes resources while exposing replica counts,
container images, and the Ingress hostname through `values.yaml`.

The application still contains exactly the same resources:

```text
Ingress → Services → Deployments → Pods
```

## Structure

```text
07-helm/
├── README.md
└── apps/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── echo-deployment.yaml
        ├── echo-service.yaml
        ├── whoami-deployment.yaml
        ├── whoami-service.yaml
        └── ingress.yaml
```

## Inspect the chart

From the repository root:

```bash
helm lint classes/07-helm/apps
helm template apps classes/07-helm/apps
```

`helm template` renders the resources locally. At this stage, the output
should match the manifests in `classes/06-ingress/`.

The configurable values are grouped by application:

```yaml
echo:
  replicaCount: 2
  image:
    repository: ealen/echo-server
    tag: latest

whoami:
  replicaCount: 2
  image:
    repository: traefik/whoami
    tag: latest

ingress:
  host: hello.local
```

## Install it in the cluster

From the `classes/07-helm` directory:

```bash
helm install apps ./apps -n apps --create-namespace
```

Check the resources in the `apps` namespace:

```bash
kubectl get deployments,services,ingress -n apps
```

To upgrade it after changing the chart:

```bash
helm upgrade apps ./apps -n apps
```

Helm values can also be overridden from the command line:

```bash
helm upgrade apps ./apps -n apps \
  --set echo.replicaCount=3 \
  --set echo.image.tag=v2 \
  --set ingress.host=demo.local
```

These overrides are applied only to the current release and do not modify
`values.yaml`.

To remove the installation:

```bash
helm uninstall apps -n apps
```

## Next step

The next step can introduce reusable helpers and common labels, then continue
reducing duplication between the two application templates.

## Notes

> Write down anything you discover while practising.
