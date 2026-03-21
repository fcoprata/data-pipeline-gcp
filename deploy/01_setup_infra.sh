#!/usr/bin/env bash
# Cria bucket GCS e faz upload dos CSVs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=variables.sh
source "${SCRIPT_DIR}/variables.sh"

echo "==> Autenticando com service account..."
gcloud auth activate-service-account --key-file="${SA_KEY_PATH}"
gcloud config set project "${PROJECT_ID}"

echo "==> Criando bucket gs://${BUCKET_NAME}..."
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access
else
  echo "    Bucket ja existe."
fi

echo "==> Upload dos CSVs para raw/..."
DATA_RAW="${SCRIPT_DIR}/../data/raw"
gcloud storage cp "${DATA_RAW}/transactions_file1.csv" "gs://${BUCKET_NAME}/raw/transactions_file1.csv"
gcloud storage cp "${DATA_RAW}/transactions_file2.csv" "gs://${BUCKET_NAME}/raw/transactions_file2.csv"
gcloud storage cp "${DATA_RAW}/customers_file3.csv"    "gs://${BUCKET_NAME}/raw/customers_file3.csv"

echo "==> Infra pronta."
