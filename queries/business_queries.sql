-- =============================================
-- Views de negocio
-- =============================================


-- 1. Total de transacoes aprovadas por mes
CREATE OR REPLACE VIEW `iron-crane-411118.financial_data.v_aprovadas_por_mes` AS
SELECT
  FORMAT_DATE('%Y-%m', transaction_date) AS mes,
  COUNT(*)                               AS total_aprovadas,
  SUM(transaction_amount)                AS valor_total
FROM `iron-crane-411118.financial_data.v_transactions`
WHERE transaction_status = 'approved'
GROUP BY mes;


-- 2. Cliente com maior volume de transacoes aprovadas nos ultimos 3 meses
CREATE OR REPLACE VIEW `iron-crane-411118.financial_data.v_top_cliente_3m` AS
WITH ref AS (
  SELECT MAX(transaction_date) AS dt
  FROM `iron-crane-411118.financial_data.v_transactions`
)
SELECT
  t.customer_id,
  t.customer_name,
  COUNT(*)                   AS total_transacoes,
  SUM(t.transaction_amount)  AS volume_total
FROM `iron-crane-411118.financial_data.v_transactions` t
CROSS JOIN ref r
WHERE t.transaction_status = 'approved'
  AND t.transaction_date >= DATE_SUB(r.dt, INTERVAL 3 MONTH)
GROUP BY t.customer_id, t.customer_name;


-- 3. Media de transacoes rejeitadas por mes no ultimo ano
CREATE OR REPLACE VIEW `iron-crane-411118.financial_data.v_media_rejeicoes_mes` AS
WITH ref AS (
  SELECT MAX(transaction_date) AS dt
  FROM `iron-crane-411118.financial_data.v_transactions`
),
por_mes AS (
  SELECT
    FORMAT_DATE('%Y-%m', t.transaction_date) AS mes,
    COUNT(*)                                 AS total_rejeitadas
  FROM `iron-crane-411118.financial_data.v_transactions` t
  CROSS JOIN ref r
  WHERE t.transaction_status = 'rejected'
    AND t.transaction_date >= DATE_SUB(r.dt, INTERVAL 1 YEAR)
  GROUP BY mes
)
SELECT
  ROUND(AVG(total_rejeitadas), 2) AS media_rejeicoes_por_mes
FROM por_mes;


-- 4. Preco medio do estoque do ativo (metodo PM - Receita Federal)
--    Desconsidera a 1a transacao de cada cliente (abertura).
--    Buy: PM = (estoque * PM_anterior + qtd * preco) / estoque_novo
--    Sell: PM nao muda, so reduz estoque.
--    Usa UDF persistente fn_preco_medio para calculo recursivo.

CREATE OR REPLACE FUNCTION `iron-crane-411118.financial_data.fn_preco_medio`(
  types ARRAY<STRING>,
  qtds  ARRAY<FLOAT64>,
  prices ARRAY<FLOAT64>
)
RETURNS ARRAY<STRUCT<estoque FLOAT64, pm FLOAT64>>
LANGUAGE js AS r"""
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
""";

CREATE OR REPLACE VIEW `iron-crane-411118.financial_data.v_preco_medio_estoque` AS
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
  FROM `iron-crane-411118.financial_data.v_transactions`
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
    `iron-crane-411118.financial_data.fn_preco_medio`(types, qtds, prices) AS resultado
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
UNNEST(GENERATE_ARRAY(0, ARRAY_LENGTH(ids) - 1)) AS i;
