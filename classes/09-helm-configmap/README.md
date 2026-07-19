# 09 — Helm: ConfigMaps

## Objective

Add application configuration to the Helm chart without putting it inside
the container image. A `ConfigMap` stores non-sensitive configuration and can
be consumed by a Pod as environment variables or as files.

This class is based on class 08 and keeps the same application resources:

```text
Ingress → Services → Deployments → Pods
                         ↑
                     ConfigMap
```

## Structure

```text
09-helm-configmap/
├── README.md
└── apps/
    ├── Chart.yaml
    ├── values.yaml
    ├── values-dev.yaml
    ├── values-prod.yaml
    └── templates/
        ├── configmap.yaml
        ├── echo-deployment.yaml
        ├── echo-service.yaml
        ├── whoami-deployment.yaml
        ├── whoami-service.yaml
        └── ingress.yaml
```

## Inspect the chart

From the repository root:

```bash
helm lint classes/09-helm-configmap/apps
helm template apps-dev classes/09-helm-configmap/apps \
  -f classes/09-helm-configmap/apps/values-dev.yaml
helm template apps-prod classes/09-helm-configmap/apps \
  -f classes/09-helm-configmap/apps/values-prod.yaml
```

Find the rendered `ConfigMap` and inspect its `data` section. Development and
production use different values, while the template remains unchanged.

## How the applications consume the ConfigMap

The `echo` Deployment imports every key as an environment variable:

```yaml
envFrom:
  - configMapRef:
      name: apps-dev-config
```

The `whoami` Deployment mounts the same configuration as files under
`/etc/app-config`. Each key becomes a file with the key as its filename.

A ConfigMap is for non-sensitive values. Passwords, tokens, and API keys
belong in a Kubernetes `Secret`.

## Install an environment

Install development:

```bash
helm install apps-dev ./classes/09-helm-configmap/apps \
  -f ./classes/09-helm-configmap/apps/values-dev.yaml \
  -n apps-dev --create-namespace
```

Check the ConfigMap and the application resources:

```bash
kubectl get configmap,deployments,services -n apps-dev
kubectl describe configmap apps-dev-config -n apps-dev
```

Inspect the environment variables configured for the `echo` container:

```bash
kubectl exec -n apps-dev deploy/echo -- printenv APP_NAME LOG_LEVEL
```

Verify the volume mounted in the `whoami` Pod:

```bash
kubectl describe pod -l app=whoami -n apps-dev
```

The description shows `/etc/app-config` as the mount path. Inside that
directory, Kubernetes creates one file for each key: `APP_NAME`, `LOG_LEVEL`,
and `WELCOME_MESSAGE`.

## Update configuration

Change a value in `values-dev.yaml`, then render and upgrade the release:

```bash
helm template apps-dev ./classes/09-helm-configmap/apps \
  -f ./classes/09-helm-configmap/apps/values-dev.yaml

helm upgrade apps-dev ./classes/09-helm-configmap/apps \
  -f ./classes/09-helm-configmap/apps/values-dev.yaml -n apps-dev
```

The chart adds a checksum of the `ConfigMap` to the Pod template. When the
configuration changes, Helm changes that checksum and Kubernetes restarts the
Pods automatically during the upgrade:

```bash
kubectl rollout status deployment/echo -n apps-dev
kubectl rollout status deployment/whoami -n apps-dev
```

## Practice tasks

1. Change `logLevel` in `values-dev.yaml` and render the ConfigMap again.
2. Add a new key and make it available to the `echo` container.
3. Add a `staging` values file without changing the templates.
4. Try changing a ConfigMap key to a value containing special characters and
   inspect the rendered YAML.
5. Explain why a database password should not be stored in this ConfigMap.

To remove the practice installation:

```bash
helm uninstall apps-dev -n apps-dev
```

## Notes

> Write down anything you discover while practising.
