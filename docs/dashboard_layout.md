# Dashboard - Looker Studio

Guia de construcao do dashboard no Looker Studio conectado ao BigQuery.

**Link do dashboard:** [Looker Studio](https://lookerstudio.google.com/reporting/886b3f44-0f78-4aeb-9d2e-4a2e878f00f9)

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
│                                                    [filtro: data]   │
├────────────┬────────────┬─────────────────┬─────────────────────────┤
│  SCORECARD │  SCORECARD │    SCORECARD    │       SCORECARD          │
│  Total de  │  Total     │  Media Mensal   │  Top cliente (volume)    │
│  transacoes│  Aprovadas │  de Rejeicoes   │  nome + valor            │
│  (500)     │  (205)     │  (14,2)         │  Customer_1  5.744,5     │
├────────────┴────────────┴────────┬────────┴─────────────────────────┤
│                                  │                                   │
│  GRAFICO DE BARRAS HORIZONTAIS   │  COMBO CHART (linha + area)       │
│  EMPILHADAS                      │  Evolucao do Preco Medio          │
│  Transacoes por mes              │  e Estoque                        │
│  (approved/rejected/pending)     │                                   │
│  eixo Y: mes | eixo X: count    │  eixo X: mes                      │
│  cor: status                     │  eixo Y: preco_medio / estoque    │
│                                  │                                   │
├──────────────────────────────────┼───────────────────────────────────┤
│                                  │                                   │
│  GRAFICO DE BARRAS HORIZONTAL    │  DONUT                            │
│  Top 5 Transacoes por Valor      │  Distribuicao por Status          │
│  (transaction_amount)            │  approved 41%                     │
│                                  │  rejected 34%                     │
│                                  │  pending 25%                      │
│                                  │                                   │
├──────────────────────────────────┼───────────────────────────────────┤
│                                  │                                   │
│  TABELA                          │                                   │
│  Ranking de Clientes             │                                   │
│  (ultimos 3 meses)              │                                   │
│  customer_name | total | volume  │                                   │
│                                  │                                   │
└──────────────────────────────────┴───────────────────────────────────┘
```

## Componentes

### Linha 1 — Scorecards (KPIs)

#### Total de transacoes
- **Tipo:** Scorecard
- **Fonte:** `v_transactions`
- **Metrica:** `COUNT(transaction_id)` — Record Count
- **Formato:** Numero inteiro
- **Estilo:** Fundo branco, borda cinza claro

#### Total Aprovadas
- **Tipo:** Scorecard
- **Fonte:** `v_transactions`
- **Metrica:** `COUNT(transaction_id)` com filtro `transaction_status = approved`
- **Formato:** Numero inteiro
- **Estilo:** Fundo Verde (#34A853), texto branco

#### Media Mensal de Rejeicoes
- **Tipo:** Scorecard
- **Fonte:** `v_media_rejeicoes_mes`
- **Metrica:** `media_rejeicoes_por_mes`
- **Formato:** Numero decimal (1 casa)
- **Estilo:** Fundo Verde (#34A853), texto branco

#### Top cliente (volume)
- **Tipo:** Scorecard
- **Fonte:** `v_top_cliente_3m`
- **Metrica principal:** `volume_total` (MAX)
- **Metrica secundaria:** `customer_name`
- **Ordenacao:** `volume_total DESC`
- **Limite:** 1 registro
- **Formato:** Numero com separador decimal (virgula)
- **Estilo:** Fundo branco, texto escuro

### Linha 2 — Transacoes por mes + Preco medio

#### Barras horizontais empilhadas (coluna esquerda)
- **Tipo:** Stacked Horizontal Bar Chart
- **Fonte:** `v_transactions`
- **Dimensao (eixo Y):** `transaction_date` formatado como nome do mes (janeiro-dezembro)
- **Metrica (eixo X):** `COUNT(transaction_id)` — Record Count
- **Breakdown (dimensao de cor):** `transaction_status`
- **Cores:**
  - approved: Verde (#34A853)
  - rejected: Vermelho (#EA4335)
  - pending: Amarelo (#FBBC04)
- **Ordenacao:** mes crescente (janeiro no topo)

#### Combo chart — linha + area (coluna direita)
- **Tipo:** Combo Chart
- **Fonte:** `v_preco_medio_estoque`
- **Dimensao (eixo X):** `transaction_date` formatado como nome do mes
- **Serie 1 (linha tracejada, eixo Y esquerdo):** `preco_medio`
  - Cor: Azul (#4285F4)
  - Tipo: Linha tracejada com pontos
- **Serie 2 (area, eixo Y direito):** `estoque_acumulado`
  - Cor: Cinza (#9AA0A6) com opacidade 30%
  - Tipo: Area preenchida
- **Ordenacao:** `transaction_date` crescente
- **Titulo:** Evolucao do Preco Medio e Estoque

### Linha 3 — Top transacoes + Distribuicao

#### Barras horizontais (coluna esquerda)
- **Tipo:** Horizontal Bar Chart
- **Fonte:** `v_transactions`
- **Dimensao:** `transaction_id`
- **Metrica:** `transaction_amount`
- **Ordenacao:** `transaction_amount DESC`
- **Limite:** 5 registros
- **Cor:** Azul (#4285F4)
- **Titulo:** Top 5 Transacoes por Valor

#### Donut chart (coluna direita)
- **Tipo:** Donut / Pie Chart
- **Fonte:** `v_transactions`
- **Dimensao:** `transaction_status`
- **Metrica:** `COUNT(transaction_id)` — Record Count
- **Cores:**
  - approved: Verde (#34A853) — 41%
  - rejected: Vermelho (#EA4335) — 34%
  - pending: Amarelo (#FBBC04) — 25%
- **Mostrar:** percentual
- **Titulo:** Distribuicao por Status

### Linha 4 — Ranking de clientes

#### Tabela de ranking (coluna esquerda)
- **Tipo:** Table
- **Fonte:** `v_top_cliente_3m`
- **Colunas:**
  - `customer_name` (Texto)
  - `total_transacoes` (Inteiro)
  - `volume_total` (Moeda R$)
- **Ordenacao:** `volume_total DESC`
- **Barra condicional:** aplicar em `volume_total` (gradiente verde)
- **Titulo:** Ranking de Clientes (ultimos 3 meses)

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
