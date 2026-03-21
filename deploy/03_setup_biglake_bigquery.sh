#!/usr/bin/env bash
# Cria conexao BigLake, tabela externa Parquet e views no BigQuery
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=variables.sh
source "${SCRIPT_DIR}/variables.sh"

echo "==> Criando dataset ${DATASET_ID}..."
bq mk --dataset \
  --location="${REGION}" \
  --project_id="${PROJECT_ID}" \
  "${DATASET_ID}" 2>/dev/null || echo "    Dataset ja existe."

echo "==> Criando conexao BigLake..."
bq mk --connection \
  --connection_type=CLOUD_RESOURCE \
  --location="${REGION}" \
  --project_id="${PROJECT_ID}" \
  "${BIGLAKE_CONNECTION}" 2>/dev/null || echo "    Conexao ja existe."

echo "==> Obtendo service account da conexao BigLake..."
CONNECTION_SA=$(bq show --connection --format=json \
  --project_id="${PROJECT_ID}" \
  --location="${REGION}" \
  "${BIGLAKE_CONNECTION}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['cloudResource']['serviceAccountId'])")

echo "    SA: ${CONNECTION_SA}"

echo "==> Concedendo leitura no bucket para a conexao..."
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${CONNECTION_SA}" \
  --role="roles/storage.objectViewer" \
  --project="${PROJECT_ID}"

echo "==> Criando tabela externa BigLake (transactions_raw)..."
bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "
CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT_ID}.${DATASET_ID}.transactions_raw\`
WITH CONNECTION \`${PROJECT_ID}.${REGION}.${BIGLAKE_CONNECTION}\`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://${BUCKET_NAME}/processed/*.parquet']
)
"

echo "==> Criando view v_transactions..."
bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.v_transactions\` AS
SELECT
  transaction_id,
  customer_id,
  CAST(transaction_date AS DATE) AS transaction_date,
  transaction_amount,
  transaction_status,
  transaction_type,
  qtty,
  price,
  customer_name,
  customer_email,
  (qtty * price) AS total_value
FROM \`${PROJECT_ID}.${DATASET_ID}.transactions_raw\`
"

echo "==> Criando views de negocio..."

echo "    v_aprovadas_por_mes"
bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.v_aprovadas_por_mes\` AS
SELECT
  FORMAT_DATE('%Y-%m', transaction_date) AS mes,
  COUNT(*)                               AS total_aprovadas,
  SUM(transaction_amount)                AS valor_total
FROM \`${PROJECT_ID}.${DATASET_ID}.v_transactions\`
WHERE transaction_status = 'approved'
GROUP BY mes
"

echo "    v_top_cliente_3m"
bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.v_top_cliente_3m\` AS
WITH ref AS (
  SELECT MAX(transaction_date) AS dt
  FROM \`${PROJECT_ID}.${DATASET_ID}.v_transactions\`
)
SELECT
  t.customer_id,
  t.customer_name,
  COUNT(*)                   AS total_transacoes,
  SUM(t.transaction_amount)  AS volume_total
FROM \`${PROJECT_ID}.${DATASET_ID}.v_transactions\` t
CROSS JOIN ref r
WHERE t.transaction_status = 'approved'
  AND t.transaction_date >= DATE_SUB(r.dt, INTERVAL 3 MONTH)
GROUP BY t.customer_id, t.customer_name
"

echo "    v_media_rejeicoes_mes"
bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.v_media_rejeicoes_mes\` AS
WITH ref AS (
  SELECT MAX(transaction_date) AS dt
  FROM \`${PROJECT_ID}.${DATASET_ID}.v_transactions\`
),
por_mes AS (
  SELECT
    FORMAT_DATE('%Y-%m', t.transaction_date) AS mes,
    COUNT(*)                                 AS total_rejeitadas
  FROM \`${PROJECT_ID}.${DATASET_ID}.v_transactions\` t
  CROSS JOIN ref r
  WHERE t.transaction_status = 'rejected'
    AND t.transaction_date >= DATE_SUB(r.dt, INTERVAL 1 YEAR)
  GROUP BY mes
)
SELECT
  ROUND(AVG(total_rejeitadas), 2) AS media_rejeicoes_por_mes
FROM por_mes
"

echo "    fn_preco_medio (UDF persistente)"
bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "
CREATE OR REPLACE FUNCTION \`${PROJECT_ID}.${DATASET_ID}.fn_preco_medio\`(
  types ARRAY<STRING>,
  qtds  ARRAY<FLOAT64>,
  prices ARRAY<FLOAT64>
)
RETURNS ARRAY<STRUCT<estoque FLOAT64, pm FLOAT64>>
LANGUAGE js AS r\"\"\"
  var res = [];
  var est = 0.0, pm = 0.0;
  for (var i = 0; i < types.length; i++) {
    if (types[i] === 'buy') {
      var custo_ant = est * pm;
      est += qtds[i];
      pm = est > 0 ? (custo_ant + qtds[i] * prices[i]) / est : 0;
    } else {
      est -= qtds[i];
      if (est <= 0) { est = 0; pm = 0; }
    }
    res.push({
      estoque: Math.round(est * 100) / 100,
      pm: Math.round(pm * 100) / 100
    });
  }
  return res;
\"\"\"
"

echo "    v_preco_medio_estoque"
bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.v_preco_medio_estoque\` AS
WITH ordenadas AS (
  SELECT
    transaction_id,
    customer_id,
    transaction_date,
    transaction_type,
    qtty,
    price,
    ROW_NUMBER() OVER (
      PARTITION BY customer_id
      ORDER BY transaction_date, transaction_id
    ) AS rn_cliente
  FROM \`${PROJECT_ID}.${DATASET_ID}.v_transactions\`
  WHERE transaction_status = 'approved'
),
sem_abertura AS (
  SELECT
    transaction_id,
    transaction_date,
    transaction_type,
    qtty,
    price
  FROM ordenadas
  WHERE rn_cliente > 1
  ORDER BY transaction_date, transaction_id
),
arrays AS (
  SELECT
    ARRAY_AGG(transaction_id ORDER BY transaction_date, transaction_id)   AS ids,
    ARRAY_AGG(transaction_date ORDER BY transaction_date, transaction_id) AS dates,
    ARRAY_AGG(transaction_type ORDER BY transaction_date, transaction_id) AS types,
    ARRAY_AGG(qtty ORDER BY transaction_date, transaction_id)            AS qtds,
    ARRAY_AGG(price ORDER BY transaction_date, transaction_id)           AS prices
  FROM sem_abertura
),
calc AS (
  SELECT
    ids, dates, types, qtds, prices,
    \`${PROJECT_ID}.${DATASET_ID}.fn_preco_medio\`(types, qtds, prices) AS resultado
  FROM arrays
)
SELECT
  ids[OFFSET(i)]              AS transaction_id,
  dates[OFFSET(i)]            AS transaction_date,
  types[OFFSET(i)]            AS transaction_type,
  qtds[OFFSET(i)]             AS qtty,
  prices[OFFSET(i)]           AS price,
  resultado[OFFSET(i)].estoque AS estoque_acumulado,
  resultado[OFFSET(i)].pm      AS preco_medio
FROM calc,
UNNEST(GENERATE_ARRAY(0, ARRAY_LENGTH(ids) - 1)) AS i
"

echo "==> Setup BigLake + BigQuery concluido."
