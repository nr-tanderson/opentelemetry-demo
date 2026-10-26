#!/usr/bin/env bash
set -euo pipefail

connection=$(mktemp)
values_file=$(mktemp)
trap 'rm -f "$connection" "$values_file"' EXIT

az storage blob download \
  --account-name "$TFSTATE_STORAGE_ACCOUNT" \
  --container-name "$TFSTATE_CONTAINER" \
  --name "${TFSTATE_KEY}.connection.json" \
  --file "$connection" \
  --auth-mode login \
  --overwrite \
  --output none

test "$(jq -r .state "$connection")" = active
resource_group=$(jq -r .resource_group "$connection")
cluster=$(jq -r .cluster "$connection")
generation=$(jq -r .generation "$connection")
actual_generation=$(az aks show --resource-group "$resource_group" --name "$cluster" --query tags.LAB_GENERATION --output tsv)
test "$actual_generation" = "$generation"
az aks get-credentials --resource-group "$resource_group" --name "$cluster" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

if [[ "$OTEL_OPERATION" == uninstall ]]; then
  if helm status otel-demo --namespace otel-demo >/dev/null 2>&1; then
    helm uninstall otel-demo --namespace otel-demo --wait --timeout 10m
  fi
  kubectl delete namespace otel-demo --ignore-not-found --wait=true --timeout=5m
  printf 'Astronomy Shop removed from generation %s.\n' "$generation" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

[[ "$OTEL_OPERATION" == deploy ]]
if helm status otel-demo --namespace otel-demo >/dev/null 2>&1; then
  echo "The upstream chart does not support upgrades. Run this workflow with operation=uninstall before reinstalling." >&2
  exit 1
fi

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update open-telemetry

chart_args=(install otel-demo open-telemetry/opentelemetry-demo --version 0.42.6 --namespace otel-demo --create-namespace --values deploy/otel-demo-public-values.yaml --wait --timeout 15m)
if [[ "${MONITORING_ENABLED:-false}" == true ]]; then
  : "${NEW_RELIC_LICENSE_KEY:?Configure a new LAB_NR_LICENSE_KEY before opting in}"
  kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic newrelic-license --namespace otel-demo --from-literal=license-key="$NEW_RELIC_LICENSE_KEY" --dry-run=client -o yaml | kubectl apply -f -
  export NEW_RELIC_OTLP_ENDPOINT="${NEW_RELIC_OTLP_ENDPOINT:-https://otlp.nr-data.net}"
  # shellcheck disable=SC2016 # envsubst, not the shell, expands this variable.
  envsubst '${NEW_RELIC_OTLP_ENDPOINT}' < deploy/otel-demo-newrelic-values.yaml > "$values_file"
  chart_args+=(--values "$values_file")
fi

helm "${chart_args[@]}"
kubectl get pods --namespace otel-demo
kubectl wait --namespace otel-demo --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' service/frontend-proxy --timeout=300s
public_ip=$(kubectl get service frontend-proxy --namespace otel-demo --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl --fail --silent --output /dev/null --write-out 'Astronomy Shop HTTP %{http_code}\n' "http://${public_ip}:8080/"
printf 'Astronomy Shop URL: http://%s:8080/\nGeneration: %s\nNew Relic enabled: %s\n' "$public_ip" "$generation" "${MONITORING_ENABLED:-false}" >> "$GITHUB_STEP_SUMMARY"