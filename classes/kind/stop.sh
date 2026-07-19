#!/usr/bin/env bash

set -Eeuo pipefail

readonly CLUSTER_NAME="${KIND_CLUSTER_NAME:-argocd-cluster}"

command -v kind >/dev/null 2>&1 || {
  echo "Error: 'kind' is required but was not found in PATH." >&2
  exit 1
}

if kind get clusters 2>/dev/null | grep -Fxq -- "${CLUSTER_NAME}"; then
  echo "Deleting kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "Cluster '${CLUSTER_NAME}' deleted."
else
  echo "Cluster '${CLUSTER_NAME}' does not exist. Nothing to do."
fi
