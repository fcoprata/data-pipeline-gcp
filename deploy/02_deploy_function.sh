#!/usr/bin/env bash
# Deploy da Cloud Function (2nd gen)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=variables.sh
source "${SCRIPT_DIR}/variables.sh"

FUNCTION_DIR="${SCRIPT_DIR}/../functions/etl_pipeline"

echo "==> Deploy da Cloud Function '${FUNCTION_NAME}'..."
gcloud functions deploy "${FUNCTION_NAME}" \
  --gen2 \
  --region="${REGION}" \
  --runtime=python312 \
  --source="${FUNCTION_DIR}" \
  --entry-point=etl_handler \
  --trigger-http \
  --no-allow-unauthenticated \
  --memory=512MB \
  --timeout=300s \
  --project="${PROJECT_ID}"

FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
  --gen2 \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(serviceConfig.uri)")

echo "==> Function deployed: ${FUNCTION_URL}"
