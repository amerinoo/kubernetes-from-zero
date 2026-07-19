# 08 — Helm: Development and Production Environments

## Objective

Use one Helm chart with different values for development and production.
The chart is based on class 07 and keeps the same application resources:

```text
Ingress → Services → Deployments → Pods
```

The environment-specific values change the replica counts and Ingress host.
Every resource also receives an environment label so that it is easy to
identify the selected environment in the cluster.

## Structure

```text
08-helm-envs/
├── README.md
└── apps/
    ├── Chart.yaml
    ├── values.yaml
    ├── values-dev.yaml
    ├── values-prod.yaml
    └── templates/
        ├── echo-deployment.yaml
        ├── echo-service.yaml
        ├── whoami-deployment.yaml
        ├── whoami-service.yaml
        └── ingress.yaml
```

`values.yaml` contains the shared defaults. The environment files contain
only the values that differ between environments.

## Inspect the chart

From the repository root:

```bash
helm lint classes/08-helm-envs/apps
helm template apps-dev classes/08-helm-envs/apps -f classes/08-helm-envs/apps/values-dev.yaml
helm template apps-prod classes/08-helm-envs/apps -f classes/08-helm-envs/apps/values-prod.yaml
```

Compare the rendered output. Development runs one replica of each
application and uses `hello-dev.local`. Production runs three replicas of
each application and uses `hello.local`.

The last values file passed to Helm has precedence over earlier values files.
For example, the production configuration can be tested with an additional
temporary override:

```bash
helm template apps-prod classes/08-helm-envs/apps \
  -f classes/08-helm-envs/apps/values-prod.yaml \
  --set echo.replicaCount=5
```

## Install both environments

Install development in its own namespace:

```bash
helm install apps-dev ./classes/08-helm-envs/apps \
  -f ./classes/08-helm-envs/apps/values-dev.yaml \
  -n apps-dev --create-namespace
```

Install production in a separate namespace:

```bash
helm install apps-prod ./classes/08-helm-envs/apps \
  -f ./classes/08-helm-envs/apps/values-prod.yaml \
  -n apps-prod --create-namespace
```

Check each environment independently:

```bash
kubectl get deployments,services,ingress -n apps-dev
kubectl get deployments,services,ingress -n apps-prod
```

Inspect the values used by the development release:

```bash
helm get values apps-dev -n apps-dev
```

The release name and namespace are different, but both installations use the
same chart templates.

## Upgrade an environment

After changing the chart or an environment file, upgrade only the selected
release:

```bash
helm upgrade apps-dev ./classes/08-helm-envs/apps \
  -f ./classes/08-helm-envs/apps/values-dev.yaml \
  -n apps-dev
```

Production can be upgraded independently:

```bash
helm upgrade apps-prod ./classes/08-helm-envs/apps \
  -f ./classes/08-helm-envs/apps/values-prod.yaml \
  -n apps-prod
```

To remove the practice installations:

```bash
helm uninstall apps-dev -n apps-dev
helm uninstall apps-prod -n apps-prod
```

## Practice tasks

1. Render both environments and compare their replica counts.
2. Add a different image tag to `values-dev.yaml` and render the chart again.
3. Add a `staging` values file without changing the templates.
4. Use `kubectl get pods --show-labels` to find the environment label.

## Notes

> Write down anything you discover while practising.
