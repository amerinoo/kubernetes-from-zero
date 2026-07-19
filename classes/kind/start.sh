#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/kind-config.yaml"
readonly CLUSTER_NAME="${KIND_CLUSTER_NAME:-argocd-cluster}"
readonly KUBE_CONTEXT="kind-${CLUSTER_NAME}"

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found in PATH."
}

require_command docker
require_command kind
require_command kubectl

[[ -f "${CONFIG_FILE}" ]] || die "kind configuration not found: ${CONFIG_FILE}"

docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker and try again."

if kind get clusters 2>/dev/null | grep -Fxq -- "${CLUSTER_NAME}"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Reusing it."
else
  echo "Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --config "${CONFIG_FILE}"
fi

kubectl config use-context "${KUBE_CONTEXT}" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null

echo "Cluster '${CLUSTER_NAME}' is ready."
echo "Current context: ${KUBE_CONTEXT}"
