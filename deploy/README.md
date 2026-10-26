# Astronomy Shop on the shared AKS lab

This fork owns the Astronomy Shop source and its app-only deployment workflow. It does not create/destroy AKS. Cluster lifecycle lives in [`nr-azure-demo-opentelemetry`](https://github.com/nr-tanderson/nr-azure-demo-opentelemetry).

The manual **OpenTelemetry Astronomy Shop on shared AKS** workflow installs chart `0.42.6` (app `3.1.0`) or uninstalls only namespace `otel-demo`. It validates the active cluster generation and uses the shared Azure Blob operation lock, so it cannot race ReliBank, PetClinic, or cluster teardown. It exposes only `frontend-proxy` with a tagged public Azure LoadBalancer; other services stay internal. The public URL appears in the workflow summary. Uninstall the app when you finish; anyone who knows the temporary IP can access it.

## Default: New Relic off

Leave `enable_monitoring` unchecked. No New Relic key is read and no telemetry secret is created. The chart uses its built-in demo backends in this mode. This app workflow does not install a cluster-wide New Relic agent.

Later, with the owner, add a fresh repository Actions secret `LAB_NR_LICENSE_KEY` and explicitly check `enable_monitoring`. The workflow exports the demo collector's traces, metrics, and logs through OTLP to New Relic. An optional `NEW_RELIC_OTLP_ENDPOINT` Actions variable selects the region (`https://otlp.nr-data.net` US or `https://otlp.eu01.nr-data.net` EU). Never place keys in source code, values files, or chat.

## One-time setup

Build the shared cluster first from the infra repo. Configure a GitHub Actions environment named `lab-application`, with required reviewers and an OIDC federated credential for this repository/environment. Add these Actions secrets:

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`

Add these Actions variables, matching the infra repo exactly:

- `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`, `TFSTATE_KEY`

The federated identity needs state-blob access, AKS RBAC cluster access, and permission to read the active generation handoff. This repo contains upstream app source plus the workflow/config; no local clone of the upstream is needed for ordinary fixes. Edit this fork, test, PR, merge, then manually deploy the chosen commit.

The upstream Helm chart does not support upgrades. The workflow refuses deploy when the release already exists; run `operation=uninstall` first, then deploy again. Cluster teardown also removes the chart, but ordinary app reset should use this workflow rather than deleting AKS.