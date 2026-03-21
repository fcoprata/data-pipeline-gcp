#!/usr/bin/env bash
# Executa o pipeline ETL chamando a Cloud Function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=variables.sh
source "${SCRIPT_DIR}/variables.sh"

echo "==> Obtendo URL da Cloud Function..."
FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
  --gen2 \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(serviceConfig.uri)")

echo "==> Executando pipeline: ${FUNCTION_URL}"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${FUNCTION_URL}")
HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
BODY=$(echo "${RESPONSE}" | sed '$d')

echo "${BODY}" | python3 -m json.tool

if [[ "${HTTP_CODE}" -ne 200 ]]; then
  echo "ERRO: Function retornou HTTP ${HTTP_CODE}" >&2
  exit 1
fi

echo "==> Pipeline executado com sucesso."
