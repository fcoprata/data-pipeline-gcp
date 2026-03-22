#!/usr/bin/env bash
# Concede permissoes minimas para a service account (rodar com conta pessoal)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=variables.sh
source "${SCRIPT_DIR}/variables.sh"

SA_EMAIL="sa-dev-local@iron-crane-411118.iam.gserviceaccount.com"

ROLES=(
  "roles/storage.admin"
  "roles/cloudfunctions.developer"
  "roles/bigquery.admin"
  "roles/bigquery.connectionAdmin"
  "roles/iam.serviceAccountUser"
  "roles/cloudbuild.builds.editor"
  "roles/run.invoker"
)

echo "==> Concedendo permissoes para ${SA_EMAIL}..."
for role in "${ROLES[@]}"; do
  echo "    ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --quiet
done

echo "==> Permissoes concedidas."
