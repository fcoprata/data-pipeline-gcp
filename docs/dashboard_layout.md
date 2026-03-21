# Dashboard - Looker Studio

Guia de construcao do dashboard no Looker Studio conectado ao BigQuery.

## Conexao com BigQuery

1. Acesse [lookerstudio.google.com](https://lookerstudio.google.com)
2. Criar relatorio > Adicionar dados > BigQuery
3. Projeto `iron-crane-411118` > Dataset `financial_data`
4. Adicione as 5 views como fontes de dados:
   - `v_transactions`
   - `v_aprovadas_por_mes`
   - `v_top_cliente_3m`
   - `v_media_rejeicoes_mes`
   - `v_preco_medio_estoque`

## Layout da pagina

```
┌─────────────────────────────────────────────────────────────────────┐
│  HEADER: Pipeline de Transacoes Financeiras          [filtro: mes] │
├────────────┬────────────┬────────────┬──────────────────────────────┤
│  SCORECARD │  SCORECARD │  SCORECARD │         SCORECARD            │
│  Total     │  Total     │  Media     │    Top cliente (volume)      │
│  transacoes│  aprovadas │  rejeicoes │    nome + valor              │
│            │            │  /mes      │                              │
├────────────┴────────────┴────────────┴──────────────────────────────┤
│                                                                     │
│  GRAFICO DE BARRAS EMPILHADAS                                       │
│  Transacoes por mes (approved / rejected / pending)                 │
│  eixo X: mes | eixo Y: count | cor: status                         │
│                                                                     │
├─────────────────────────────────┬───────────────────────────────────┤
│                                 │                                   │
│  GRAFICO DE LINHA (2 eixos)     │  TABELA                           │
│  Evolucao do preco medio        │  Ranking clientes                 │
│  e estoque acumulado            │  (ultimos 3 meses)                │
│                                 │                                   │
│  eixo X: data                   │  customer_name | total | volume   │
│  eixo Y1: preco_medio (linha)   │  ordenado por volume DESC         │
│  eixo Y2: estoque (area)        │                                   │
│                                 │                                   │
├─────────────────────────────────┴───────────────────────────────────┤
│  DONUT                    │  GRAFICO DE BARRAS HORIZONTAL           │
│  Distribuicao por status  │  Top 5 transacoes por valor             │
│  (approved/rejected/      │  (transaction_amount)                   │
│   pending) %              │                                         │
└───────────────────────────┴─────────────────────────────────────────┘
```

## Componentes

### Linha 1 — Scorecards (KPIs)

#### Total de transacoes
- **Tipo:** Scorecard
- **Fonte:** `v_transactions`
- **Metrica:** `COUNT(transaction_id)` — Record Count
- **Formato:** Numero inteiro

#### Total aprovadas
- **Tipo:** Scorecard
- **Fonte:** `v_transactions`
- **Metrica:** `COUNT(transaction_id)` com filtro `transaction_status = approved`
- **Formato:** Numero inteiro
- **Cor:** Verde (#34A853)

#### Media de rejeicoes por mes
- **Tipo:** Scorecard
- **Fonte:** `v_media_rejeicoes_mes`
- **Metrica:** `media_rejeicoes_por_mes`
- **Formato:** Numero decimal (2 casas)
- **Cor:** Vermelho (#EA4335)

#### Top cliente (volume)
- **Tipo:** Scorecard
- **Fonte:** `v_top_cliente_3m`
- **Metrica principal:** `volume_total` (MAX)
- **Metrica secundaria:** `customer_name`
- **Ordenacao:** `volume_total DESC`
- **Limite:** 1 registro
- **Formato:** Moeda (R$)

### Linha 2 — Transacoes por mes

#### Barras empilhadas
- **Tipo:** Stacked Bar Chart
- **Fonte:** `v_transactions`
- **Dimensao:** `transaction_date` formatado como `YYYYMM` (mes)
- **Metrica:** `COUNT(transaction_id)` — Record Count
- **Breakdown (dimensao de cor):** `transaction_status`
- **Cores:**
  - approved: Verde (#34A853)
  - rejected: Vermelho (#EA4335)
  - pending: Amarelo (#FBBC04)
- **Ordenacao:** mes crescente

### Linha 3 — Preco medio + Ranking

#### Combo chart (linha + area)
- **Tipo:** Combo Chart
- **Fonte:** `v_preco_medio_estoque`
- **Dimensao (eixo X):** `transaction_date`
- **Serie 1 (linha, eixo Y esquerdo):** `preco_medio`
  - Cor: Azul (#4285F4)
  - Tipo: Linha com pontos
- **Serie 2 (area, eixo Y direito):** `estoque_acumulado`
  - Cor: Cinza (#9AA0A6) com opacidade 30%
  - Tipo: Area preenchida
- **Ordenacao:** `transaction_date` crescente
- **Titulo:** Evolucao do Preco Medio e Estoque

#### Tabela de ranking
- **Tipo:** Table
- **Fonte:** `v_top_cliente_3m`
- **Colunas:**
  - `customer_name` (Texto)
  - `total_transacoes` (Inteiro)
  - `volume_total` (Moeda R$)
- **Ordenacao:** `volume_total DESC`
- **Barra condicional:** aplicar em `volume_total` (gradiente verde)
- **Titulo:** Ranking de Clientes (ultimos 3 meses)

### Linha 4 — Distribuicao + Top transacoes

#### Donut chart
- **Tipo:** Donut / Pie Chart
- **Fonte:** `v_transactions`
- **Dimensao:** `transaction_status`
- **Metrica:** `COUNT(transaction_id)` — Record Count
- **Cores:**
  - approved: Verde (#34A853)
  - rejected: Vermelho (#EA4335)
  - pending: Amarelo (#FBBC04)
- **Mostrar:** percentual e valor absoluto
- **Titulo:** Distribuicao por Status

#### Barras horizontais
- **Tipo:** Horizontal Bar Chart
- **Fonte:** `v_transactions`
- **Dimensao:** `transaction_id`
- **Metrica:** `transaction_amount`
- **Ordenacao:** `transaction_amount DESC`
- **Limite:** 5 registros
- **Cor:** Azul (#4285F4)
- **Titulo:** Top 5 Transacoes por Valor

## Filtro global

- **Tipo:** Date Range Control
- **Campo:** `transaction_date`
- **Posicao:** canto superior direito do header
- **Range padrao:** Todo o periodo (01/01/2023 a 31/12/2023)
- **Vincular a:** todas as fontes de dados que possuem `transaction_date`

## Paleta de cores

| Elemento | Hex | Uso |
|---|---|---|
| Approved / Positivo | #34A853 | Scorecards, barras, donut |
| Rejected / Negativo | #EA4335 | Scorecards, barras, donut |
| Pending / Neutro | #FBBC04 | Barras, donut |
| Preco medio / Destaque | #4285F4 | Linha, barras horizontais |
| Estoque / Fundo | #9AA0A6 | Area preenchida |
| Background | #FFFFFF | Fundo da pagina |
| Texto principal | #202124 | Titulos e labels |
| Texto secundario | #5F6368 | Subtitulos e notas |

## Dicas

- Use a fonte **Roboto** para manter consistencia com o estilo Google
- Agrupe os scorecards com um retangulo de fundo cinza claro (#F8F9FA) para destaca-los
- Adicione bordas arredondadas nos graficos (8px)
- Coloque o titulo do dashboard em negrito 24px e subtitulos em 14px
- Tamanho da pagina recomendado: 1200 x 900 px
