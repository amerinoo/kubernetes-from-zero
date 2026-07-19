# kind Cluster Setup

This directory contains the configuration for running the course with [kind](https://kind.sigs.k8s.io/), which runs Kubernetes nodes as Docker containers.

## Prerequisites

- Docker installed and running
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- `kubectl` installed

## Create the cluster

Run this command from the `classes/kind/` directory:

```bash
kind create cluster \
  --name argocd-cluster \
  --config kind-config.yaml
```

Verify that the cluster is ready:

```bash
kubectl cluster-info --context kind-argocd-cluster
kubectl get nodes
```

If your current `kubectl` context is different, select the kind cluster explicitly:

```bash
kubectl config use-context kind-argocd-cluster
```

## Port mappings

[`kind-config.yaml`](kind-config.yaml) maps ports from the kind control-plane container to the host:

| Host port | Container port | Typical use |
|---:|---:|---|
| `8080` | `80` | HTTP traffic, including an NGINX Ingress Controller |
| `8443` | `443` | HTTPS traffic |

For example, an HTTP request to `localhost:8080` is forwarded to port `80` inside the kind node.

When using the Ingress exercise, send the expected host header as well:

```bash
curl -v \
  -H "Host: hello.local" \
  http://localhost:8080/whoami
```

The host must match the hostname declared in the Ingress manifest.

## Use the cluster with the course

From the repository root, apply the manifests for a class as documented in that class's README. For example:

```bash
kubectl apply -f classes/01-pods/
```

For the Ingress class, install an Ingress Controller first, then apply the backend and Ingress manifests.

## Delete the cluster

```bash
kind delete cluster --name argocd-cluster
```

Deleting the cluster removes its nodes and all resources running inside it.
