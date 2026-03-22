# Pipeline de Dados - Transacoes Financeiras

Pipeline ETL na Google Cloud Platform que processa transacoes financeiras de arquivos CSV, transforma em Parquet e disponibiliza no BigQuery via BigLake para consultas analiticas.

## Arquitetura

```
                          ┌──────────────────────┐
                          │  CSVs (dados brutos)  │
                          └──────────┬───────────┘
                                     │ upload
                                     v
                          ┌──────────────────────┐
                          │  Cloud Storage        │
                          │  gs://bucket/raw/     │
                          └──────────┬───────────┘
                                     │ HTTP trigger
                                     v
                          ┌──────────────────────┐
                          │  Cloud Function       │
                          │  (Python 3.12)        │
                          │  - Join 3 CSVs        │
                          │  - Limpeza/validacao   │
                          │  - Normalizacao IDs    │
                          └──────────┬───────────┘
                                     │ write parquet
                                     v
                          ┌──────────────────────┐
                          │  Cloud Storage        │
                          │  gs://bucket/processed│
                          └──────────┬───────────┘
                                     │ BigLake connection
                                     v
                          ┌──────────────────────┐
                          │  BigQuery             │
                          │  - Tabela externa     │
                          │  - Views de negocio   │
                          │  - UDF preco medio    │
                          └──────────┬───────────┘
                                     │
                                     v
                          ┌──────────────────────┐
                          │  Looker Studio        │
                          │  (dashboard)          │
                          └──────────────────────┘
```

### Decisoes tecnicas

| Escolha | Alternativa | Justificativa |
|---|---|---|
| **Parquet** | CSV direto no BQ | Compressao colunar, schema tipado, leitura eficiente para consultas analiticas |
| **BigLake** | Tabela nativa BQ | Dados ficam no Storage (custo menor), BQ le sob demanda. Reprocessamento sem re-ingestao |
| **Cloud Functions** | Dataflow | Volume pequeno (~100 registros/dia), Dataflow seria over-engineering. Functions escala se o volume crescer |
| **UDF persistente** | CTE recursiva | BigQuery nao suporta CTE recursiva em views. UDF JS no dataset resolve o calculo do preco medio |
| **Timestamp no Parquet** | Sobrescrever arquivo | Rastreabilidade de execucoes e possibilidade de rollback |

## Estrutura do projeto

```
├── data/
│   ├── credentials/
│   │   └── service-account.json       # Chave da service account GCP
│   └── raw/                           # CSVs fonte
│       ├── transactions_file1.csv     # transaction_id, customer_id, date, amount, status
│       ├── transactions_file2.csv     # transaction_id, type, qtty, price
│       └── customers_file3.csv        # customer_id, name, email
├── functions/
│   └── etl_pipeline/
│       ├── main.py                    # Cloud Function - ETL
│       └── requirements.txt
├── deploy/
│   ├── variables.sh                   # Configuracao centralizada
│   ├── 00_grant_sa_permissions.sh     # Permissoes minimas da SA
│   ├── 01_setup_infra.sh              # Cria bucket + upload CSVs
│   ├── 02_deploy_function.sh          # Deploy da Cloud Function
│   ├── 03_setup_biglake_bigquery.sh   # BigLake + tabelas + UDF + views
│   ├── 04_run_pipeline.sh             # Executa o ETL
│   └── run_all.sh                     # Executa tudo na ordem
├── queries/
│   └── business_queries.sql           # DDL das views e UDF de negocio
├── pyproject.toml                     # Configuracao do ruff (linter)
└── README.md
```

## Pre-requisitos

- Conta GCP com billing habilitado (free tier e suficiente)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) instalado
- Python 3.12+

### Habilitacao de APIs (uma vez, com conta pessoal)

```bash
gcloud auth login && gcloud services enable \
  cloudfunctions.googleapis.com \
  storage.googleapis.com \
  bigquery.googleapis.com \
  bigqueryconnection.googleapis.com \
  cloudbuild.googleapis.com \
  --project="iron-crane-411118"
```

### Permissoes da Service Account (uma vez, com conta pessoal)

A SA precisa apenas dos roles abaixo (sem Owner):

```bash
gcloud auth login
bash deploy/00_grant_sa_permissions.sh
```

Roles concedidos:
| Role | Finalidade |
|---|---|
| `roles/storage.admin` | Criar/ler/escrever no bucket |
| `roles/cloudfunctions.developer` | Deploy e invoke de functions |
| `roles/bigquery.admin` | Criar datasets, tabelas, views, UDFs |
| `roles/bigquery.connectionAdmin` | Criar conexao BigLake |
| `roles/iam.serviceAccountUser` | Necessario para deploy de functions |
| `roles/cloudbuild.builds.editor` | Build da function no deploy |
| `roles/run.invoker` | Invocar a Cloud Function (Gen2) via HTTP autenticado |

## Como executar

### Pipeline completo (um comando)

```bash
bash deploy/run_all.sh
```

Executa na ordem:
1. Autentica com a service account
2. Cria o bucket GCS e faz upload dos CSVs para `raw/`
3. Deploya a Cloud Function (Python 3.12, HTTP trigger)
4. Chama a Function via HTTP (executa ETL, grava Parquet em `processed/`)
5. Cria conexao BigLake, tabela externa, UDF e views no BigQuery

### Passo a passo

```bash
bash deploy/01_setup_infra.sh           # Bucket + upload CSVs
bash deploy/02_deploy_function.sh       # Deploy da function
bash deploy/04_run_pipeline.sh          # Executa o ETL
bash deploy/03_setup_biglake_bigquery.sh # BigLake + BigQuery
```

### Re-executar apenas o ETL

```bash
bash deploy/04_run_pipeline.sh
```

A cada execucao, um novo Parquet e gerado com timestamp. A tabela BigLake le todos os Parquets em `processed/*.parquet` automaticamente.

## Processamento ETL

A Cloud Function (`functions/etl_pipeline/main.py`) executa 3 etapas:

### Extract

Le os 3 CSVs do bucket `gs://iron-crane-411118-data-pipeline/raw/`:

| Arquivo | Conteudo | Colunas |
|---|---|---|
| `transactions_file1.csv` | Dados da transacao | transaction_id, customer_id, date, amount, status |
| `transactions_file2.csv` | Detalhes operacionais | transaction_id, type, qtty, price |
| `customers_file3.csv` | Cadastro de clientes | customer_id, name, email |

### Transform

| Etapa | Descricao |
|---|---|
| **Join** | Une `file1` e `file2` por `transaction_id` (inner), depois enriquece com `file3` por `customer_id` (left) |
| **Normalizacao** | Corrige inconsistencia de `customer_id` entre arquivos: `file3` usa `C01` (zero-padded), `file1` usa `C1`. Normaliza para `C1` |
| **Deduplicacao** | Remove duplicatas por `transaction_id`, mantendo a primeira ocorrencia |
| **Nulos** | Remove linhas com campos obrigatorios nulos (transaction_id, customer_id, date, amount, status, type, qtty, price) |
| **Validacao categorica** | Filtra status fora de `{approved, rejected, pending}` e tipos fora de `{buy, sell}` |
| **Validacao numerica** | Remove registros com qtty, price ou amount negativos ou zero |
| **Tipagem** | Converte para tipos corretos: DATE, FLOAT64 |

### Load

Grava o DataFrame limpo como Parquet (via PyArrow) no bucket `processed/`, com timestamp no nome do arquivo para rastreabilidade.

Retorna JSON com metricas da execucao:
```json
{
  "status": "success",
  "raw_records": 100,
  "clean_records": 98,
  "removed_records": 2,
  "output_path": "gs://bucket/processed/transactions_20240101_120000.parquet"
}
```

## Modelo de dados no BigQuery

### Camada raw: `transactions_raw` (BigLake external table)

Tabela externa apontando para `gs://bucket/processed/*.parquet` via conexao BigLake.

| Coluna | Tipo | Descricao |
|---|---|---|
| transaction_id | STRING | Identificador unico da transacao |
| customer_id | STRING | Identificador do cliente (normalizado) |
| transaction_date | DATE | Data da transacao |
| transaction_amount | FLOAT64 | Valor da transacao |
| transaction_status | STRING | approved, rejected, pending |
| transaction_type | STRING | buy, sell |
| qtty | FLOAT64 | Quantidade de unidades |
| price | FLOAT64 | Preco unitario |
| customer_name | STRING | Nome do cliente |
| customer_email | STRING | Email do cliente |

### Camada curada: `v_transactions` (view)

Mesmas colunas + campo calculado `total_value` (qtty * price). Inclui deduplicacao por `transaction_id` via `ROW_NUMBER()`, garantindo que re-execucoes do pipeline nao dupliquem registros.

### Camada de negocio: views analiticas

| View | Pergunta de negocio |
|---|---|
| `v_aprovadas_por_mes` | Qual o total de transacoes aprovadas por mes? |
| `v_top_cliente_3m` | Qual cliente teve o maior volume de transacoes aprovadas nos ultimos 3 meses? |
| `v_media_rejeicoes_mes` | Qual a media de transacoes rejeitadas por mes no ultimo ano? |
| `v_preco_medio_estoque` | Qual o preco medio do estoque desconsiderando abertura, e como evolui? |

### UDF: `fn_preco_medio`

Funcao persistente no dataset que calcula o preco medio ponderado do estoque pelo metodo da Receita Federal:

- **Compra (buy):** `PM = (estoque_anterior * PM_anterior + qtd * preco) / estoque_novo`
- **Venda (sell):** PM nao muda, apenas reduz a posicao
- **Estoque zerado:** PM reseta para zero

## Consultas de negocio

Todas as queries estao materializadas como views. Para consultar:

```sql
-- 1. Aprovadas por mes
SELECT * FROM `iron-crane-411118.financial_data.v_aprovadas_por_mes`
ORDER BY mes;

-- 2. Top cliente (ultimos 3 meses)
SELECT * FROM `iron-crane-411118.financial_data.v_top_cliente_3m`
ORDER BY volume_total DESC
LIMIT 1;

-- 3. Media de rejeicoes mensais
SELECT * FROM `iron-crane-411118.financial_data.v_media_rejeicoes_mes`;

-- 4. Evolucao do preco medio do estoque
SELECT * FROM `iron-crane-411118.financial_data.v_preco_medio_estoque`
ORDER BY transaction_date;
```

### Detalhamento das queries

**Query 1 - Aprovadas por mes:** agrupa transacoes aprovadas por mes (FORMAT_DATE), contabiliza quantidade e soma valores.

**Query 2 - Top cliente 3 meses:** usa `MAX(transaction_date)` como data de referencia (dados historicos de 2023) para calcular a janela de 3 meses. Retorna todos os clientes com volume no periodo — o `LIMIT 1` e aplicado na consulta.

**Query 3 - Media rejeicoes:** calcula o total de rejeitadas por mes dentro do ultimo ano, depois aplica AVG sobre esses totais mensais.

**Query 4 - Preco medio estoque:** remove a primeira transacao de cada cliente (abertura de posicao), ordena cronologicamente, e aplica a UDF `fn_preco_medio` que calcula iterativamente o PM e estoque a cada transacao. Mostra a evolucao completa linha a linha.

## Dashboard (Looker Studio)

Apos o pipeline, conecte o BigQuery ao Looker Studio:

1. Acesse [lookerstudio.google.com](https://lookerstudio.google.com)
2. Novo relatorio > Adicionar dados > BigQuery
3. Selecione o projeto `iron-crane-411118` > dataset `financial_data`
4. Adicione as views como fontes de dados

Visualizacoes sugeridas:

| Componente | Fonte | Tipo |
|---|---|---|
| Transacoes aprovadas por mes | `v_aprovadas_por_mes` | Grafico de barras (mes x total_aprovadas) |
| Ranking de clientes | `v_top_cliente_3m` | Tabela ordenada por volume_total |
| Media de rejeicoes | `v_media_rejeicoes_mes` | Scorecard / KPI |
| Evolucao preco medio | `v_preco_medio_estoque` | Grafico de linha (transaction_date x preco_medio) |
| Evolucao estoque | `v_preco_medio_estoque` | Grafico de area (transaction_date x estoque_acumulado) |

## Linting e qualidade

```bash
# Python (ruff)
ruff check functions/
ruff format functions/

# Shell (shellcheck)
shellcheck deploy/*.sh
```

Configuracao do ruff em `pyproject.toml`. Regras ativas: E, F, W, I (isort), N, UP, DTZ, BLE, B, A, ISC, RET, SIM, ARG.

## Configuracao

Todas as variaveis estao centralizadas em `deploy/variables.sh`:

| Variavel | Valor | Descricao |
|---|---|---|
| PROJECT_ID | iron-crane-411118 | ID do projeto GCP |
| REGION | us-central1 | Regiao dos recursos |
| BUCKET_NAME | iron-crane-411118-data-pipeline | Nome do bucket GCS |
| DATASET_ID | financial_data | Dataset no BigQuery |
| BIGLAKE_CONNECTION | biglake-connection | Nome da conexao BigLake |
| FUNCTION_NAME | etl-pipeline | Nome da Cloud Function |
| SA_KEY_PATH | data/credentials/service-account.json | Caminho da chave da SA |

## Recursos GCP utilizados (free tier)

| Servico | Uso estimado | Limite gratuito |
|---|---|---|
| Cloud Storage | ~1 MB | 5 GB/mes |
| Cloud Functions | ~1 invocacao/dia | 2M invocacoes/mes |
| BigQuery | ~1 MB/consulta | 1 TB/mes em consultas |
| BigQuery Storage | ~1 MB | 10 GB/mes |
