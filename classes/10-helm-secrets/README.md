# 10 — Helm: Secrets

## Objective

Add sensitive configuration to the application using a Kubernetes `Secret`
created outside Helm. The class is based on class 09: the applications still
use a `ConfigMap` for non-sensitive settings, but credentials are stored
separately and injected into the Pods.

```text
Ingress → Services → Deployments → Pods
                         ↑       ↑
                    ConfigMap  Secret
```

Secrets are not a replacement for a proper secrets manager. Kubernetes
Secrets are base64-encoded in the API representation, not encrypted by
default in every cluster. The values in this class are intentionally dummy
values for practising.

## Structure

```text
10-helm-secrets/
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
helm lint classes/10-helm-secrets/apps
helm template apps-dev classes/10-helm-secrets/apps \
  -f classes/10-helm-secrets/apps/values-dev.yaml
```

The rendered output references an existing Secret but does not contain its
values. Helm does not create or manage the Secret in this class.

## Consume the Secret

The Secret is created outside Helm. Helm only receives its name through
`values-dev.yaml`:

```yaml
secret:
  existingSecret: apps-dev-secret
```

The expression below reads that value from Helm and writes the name into the
rendered Deployment:

```yaml
name: {{ .Values.secret.existingSecret }}
```

The Secret must exist in the same namespace as the Pods. Kubernetes does not
search for Secrets in other namespaces.

### `echo`: import all Secret keys with `secretRef`

The `echo` Deployment imports every key from the Secret as an environment
variable:

```yaml
envFrom:
  - secretRef:
      name: {{ .Values.secret.existingSecret }}
```

The Secret created in this class contains two keys:

```text
API_USERNAME → $API_USERNAME
API_TOKEN    → $API_TOKEN
```

The container receives them as environment variables named `API_USERNAME` and
`API_TOKEN`. `envFrom` imports all keys, so it is convenient for this exercise
but should be used carefully when a Secret contains unrelated values.

### `whoami`: import one key with `secretKeyRef`

The `whoami` Deployment imports only `API_TOKEN`:

```yaml
env:
  - name: API_TOKEN
    valueFrom:
      secretKeyRef:
        name: {{ .Values.secret.existingSecret }}
        key: API_TOKEN
```

The parameters have different roles:

| Field | Meaning |
|---|---|
| `env[].name` | Name of the environment variable inside the container |
| `secretKeyRef.name` | Name of the Kubernetes Secret |
| `secretKeyRef.key` | Key inside the Secret to read |

This form is more explicit: adding another key to the Secret does not expose
it automatically to the container.

If the Secret does not exist, the Pod cannot start correctly. Kubernetes will
report an event such as `secret "apps-dev-secret" not found`.

## Create the Secret outside Helm

Create the development Secret before installing the chart. The command below
creates a Secret named `apps-dev-secret` with two entries:

```bash
kubectl create namespace apps-dev

kubectl create secret generic apps-dev-secret \
  --from-literal=API_USERNAME='dev-user' \
  --from-literal=API_TOKEN='dev-token-only-for-class' \
  -n apps-dev
```

Parameter by parameter:

| Parameter | Meaning |
|---|---|
| `kubectl create secret` | Starts the Kubernetes command to create a Secret |
| `generic` | Creates a general-purpose Secret made of key/value pairs |
| `apps-dev-secret` | Name of the Secret resource |
| `--from-literal=API_USERNAME=...` | Creates the `API_USERNAME` key with the supplied value |
| `--from-literal=API_TOKEN=...` | Creates the `API_TOKEN` key with the supplied value |
| `-n apps-dev` | Creates the Secret in the `apps-dev` namespace |
| `kubectl create namespace apps-dev` | Creates the namespace before the Secret |

`--from-literal` is convenient for a class, but the value can be visible in
shell history or process information. For real credentials, read values from
protected environment variables, an interactive prompt, or a secrets manager:

```bash
kubectl create secret generic apps-dev-secret \
  --from-literal=API_USERNAME="$API_USERNAME" \
  --from-literal=API_TOKEN="$API_TOKEN" \
  -n apps-dev
```

The Secret data is not stored in `values-dev.yaml`. That file stores only the
reference needed by the chart.

### Revisar las keys sin mostrar los valores

Con `describe` puedes comprobar las keys y el tamaño de cada valor:

```bash
kubectl describe secret apps-dev-secret -n apps-dev
```

Para imprimir únicamente los nombres de las keys, usa `go-template`:

```bash
kubectl get secret apps-dev-secret -n apps-dev \
  -o go-template='{{range $key, $value := .data}}{{$key}}{{"\n"}}{{end}}' \
  | sort
```

La salida esperada es:

```text
API_TOKEN
API_USERNAME
```

No uses `kubectl get secret ... -o yaml` si solo quieres revisar las keys:
también mostrará los valores codificados en base64.

For production, create a separate Secret such as `apps-prod-secret` and use
`values-prod.yaml`.

## Install an environment

```bash
helm install apps-dev ./classes/10-helm-secrets/apps \
  -f ./classes/10-helm-secrets/apps/values-dev.yaml \
  -n apps-dev --create-namespace
```

Check the resources without printing the Secret value:

```bash
kubectl get configmap,secret,deployments,services -n apps-dev
kubectl describe secret apps-dev-secret -n apps-dev
```

Verify that the variables exist inside the Pods without displaying the
credentials:

```bash
kubectl exec -n apps-dev deploy/echo -- printenv API_TOKEN >/dev/null \
  && echo API_TOKEN is set
kubectl describe pod -l app=whoami -n apps-dev
```

The Pod description shows that `API_TOKEN` comes from `apps-dev-secret`,
without printing the secret value.

Avoid commands such as `kubectl get secret apps-dev-secret -o yaml` in shared
terminals: the encoded values can be decoded easily from the output.

## Rotate a Secret

Update the external Secret without putting the new value in Git:

```bash
kubectl create secret generic apps-dev-secret \
  --from-literal=API_USERNAME="$API_USERNAME" \
  --from-literal=API_TOKEN="$API_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/echo deployment/whoami -n apps-dev
```

In this update command:

- `--dry-run=client` builds the Secret locally without sending it yet.
- `-o yaml` prints the generated Kubernetes manifest.
- `| kubectl apply -f -` sends that manifest to the cluster. The `-` means
  that `kubectl apply` reads from standard input.
- `kubectl rollout restart` recreates the Pods so environment variables are
  read again from the updated Secret.

Use `helm upgrade` when the chart itself changes:

```bash
helm template apps-dev ./classes/10-helm-secrets/apps \
  -f ./classes/10-helm-secrets/apps/values-dev.yaml

helm upgrade apps-dev ./classes/10-helm-secrets/apps \
  -f ./classes/10-helm-secrets/apps/values-dev.yaml -n apps-dev
```

The chart adds a checksum of the `ConfigMap` to each Pod template. Because the
Secret is managed outside Helm, changing it does not change the Pod template
automatically.

Important: Helm stores the values used by a release in its release metadata.
Passing real credentials through `values.yaml`, `--set`, or a rendered chart
can expose them to users with access to Helm metadata. For real workloads,
prefer an externally managed Secret, an external-secrets operator, or a
secrets manager integrated with the cluster.

## Practice tasks

1. Add `API_URL` to the external Secret and consume it with `secretKeyRef`.
2. Compare `envFrom` with an explicit `secretKeyRef`.
3. Render the chart and explain why base64 is encoding, not encryption.
4. Change the Secret name in `values-dev.yaml` and observe the Deployment
   reference after rendering.
5. Explain why an external Secret change does not change a Deployment by
   itself.

To remove the practice installation:

```bash
helm uninstall apps-dev -n apps-dev
```

## Notes

> Write down anything you discover while practising.
