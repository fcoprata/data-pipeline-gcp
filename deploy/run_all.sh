#!/usr/bin/env bash
# Executa o pipeline completo: infra -> function -> ETL -> BigLake/BQ
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=variables.sh
source "${SCRIPT_DIR}/variables.sh"

run_step() {
  local step="$1" script="$2"
  echo ""
  echo "=========================================="
  echo "  STEP ${step}"
  echo "=========================================="
  bash "${SCRIPT_DIR}/${script}"
}

run_step "1: Setup Infra (GCS + upload CSVs)" "01_setup_infra.sh"
run_step "2: Deploy Cloud Function"           "02_deploy_function.sh"
run_step "3: Executar pipeline ETL"           "04_run_pipeline.sh"
run_step "4: Setup BigLake + BigQuery"        "03_setup_biglake_bigquery.sh"

echo ""
echo "=========================================="
echo "  Pipeline completo!"
echo "  Dados raw:  gs://${BUCKET_NAME}/raw/"
echo "  Parquet:    gs://${BUCKET_NAME}/processed/"
echo "  BigQuery:   ${PROJECT_ID}.${DATASET_ID}"
echo "=========================================="
