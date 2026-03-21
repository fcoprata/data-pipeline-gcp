#!/usr/bin/env bash
# Variaveis do projeto

PROJECT_ID="iron-crane-411118"
REGION="us-central1"
BUCKET_NAME="${PROJECT_ID}-data-pipeline"
DATASET_ID="financial_data"
BIGLAKE_CONNECTION="biglake-connection"
FUNCTION_NAME="etl-pipeline"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SA_KEY_PATH="${SCRIPT_DIR}/../data/credentials/service-account.json"

export PROJECT_ID REGION BUCKET_NAME DATASET_ID BIGLAKE_CONNECTION FUNCTION_NAME
export GOOGLE_APPLICATION_CREDENTIALS="${SA_KEY_PATH}"
