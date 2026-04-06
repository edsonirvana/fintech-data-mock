# 🏦 PayBridge Financeira — Modern Data Stack on GCP

> **Stack:** Python · dbt Core · BigQuery · Cloud Storage · LookML · Looker · AWS EC2

---

## Contexto

A **PayBridge Financeira** é uma fintech brasileira de médio porte que processa pagamentos B2B e oferece crédito para PMEs. Após anos operando com um banco de dados PostgreSQL monolítico e planilhas manuais, a empresa migrou para uma arquitetura analítica moderna no GCP.

**O problema:** a área de risco e o CFO não conseguiam visualizar exposição de crédito, inadimplência e TPV em tempo real. Cada relatório era construído manualmente, com dados inconsistentes entre áreas e sem rastreabilidade.

**A solução:** pipeline completo de dados — da ingestão bruta até a camada semântica no Looker — com governança, qualidade de dados e auditoria em cada camada.

---

## Arquitetura

```
PostgreSQL (legado)         CSV Exports (ERP)
        │                         │
        └──────────┬──────────────┘
                   │  Python ETL scripts
                   ▼
         Cloud Storage (raw zone)
                   │
                   │  bq load / Python SDK
                   ▼
         BigQuery: dataset `raw`
                   │
                   │  dbt (staging → intermediate → marts)
                   ▼
         BigQuery: dataset `analytics`
                   │
                   │  LookML
                   ▼
              Looker Explores
                   │
                   ▼
         Dashboards (Risco · Financeiro · Operacional)
```

> Orquestração local via `cron` + `Makefile`. Em produção: Cloud Composer (Airflow) ou Dagster.

---

## Estrutura do Repositório

```
fintech-data-challenge/
├── README.md                        ← você está aqui
├── ARCHITECTURE.md                  ← decisões técnicas detalhadas
├── GOVERNANCE.md                    ← políticas de dados, RLS, data quality
│
├── infra/                           ← provisionamento GCP
│   ├── setup_gcp.sh                 ← cria projeto, datasets, service account
│   └── terraform/ (opcional)
│
├── ingestion/                       ← ETL Python (extração e carga raw)
│   ├── extract_postgres.py          ← extrai tabelas do PostgreSQL legado
│   ├── load_to_gcs.py               ← upload para Cloud Storage
│   ├── load_to_bigquery.py          ← carga GCS → BigQuery raw
│   └── requirements.txt
│
├── dbt_project/                     ← projeto dbt completo
│   ├── dbt_project.yml
│   ├── profiles.yml.example
│   ├── packages.yml
│   ├── models/
│   │   ├── staging/                 ← limpeza e padronização (materialized: view)
│   │   ├── intermediate/            ← joins e lógica de negócio (materialized: table)
│   │   └── marts/                   ← camada analítica final (materialized: table)
│   ├── macros/                      ← macros Jinja reutilizáveis
│   └── tests/                       ← testes customizados de qualidade
│
├── looker/                          ← projeto LookML
│   ├── models/
│   ├── views/
│   └── dashboards/
│
├── scripts/                         ← utilitários e automação
│   └── run_pipeline.sh              ← executa pipeline completo
│
└── docs/
    ├── data_dictionary.md           ← dicionário de dados
    └── screenshots/                 ← evidências de execução
```

---

## Pré-requisitos

| Ferramenta | Versão | Instalação |
|---|---|---|
| Python | 3.11+ | `pyenv install 3.11` |
| dbt Core (BigQuery) | 1.8+ | `pip install dbt-bigquery` |
| Google Cloud SDK | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk) |
| Looker | Trial ou licença | [looker.com](https://looker.com) |
| PostgreSQL client | 15+ | `apt install postgresql-client` |

---

## Setup Rápido

### 1. Infraestrutura GCP

```bash
# Clone o repositório
git clone https://github.com/edsonmachadosilva/fintech-data-challenge
cd fintech-data-challenge

# Configure variáveis de ambiente
cp .env.example .env
# edite .env com seu GCP_PROJECT_ID e caminhos

# Execute o setup de infraestrutura
chmod +x infra/setup_gcp.sh
./infra/setup_gcp.sh
```

O script `setup_gcp.sh` irá:
- Criar datasets no BigQuery (`raw`, `staging`, `analytics`, `audit`)
- Criar e configurar a Service Account `dbt-sa`
- Baixar a chave JSON para autenticação
- Configurar permissões mínimas (BigQuery Data Editor + Job User)

### 2. Pipeline de Ingestão

```bash
cd ingestion
pip install -r requirements.txt

# Extração do PostgreSQL → CSV
python extract_postgres.py

# Upload para Cloud Storage
python load_to_gcs.py

# Carga no BigQuery raw
python load_to_bigquery.py
```

### 3. Transformações dbt

```bash
cd dbt_project

# Valida conexão
dbt debug

# Instala pacotes (dbt_utils, dbt_expectations)
dbt deps

# Executa todos os modelos
dbt run

# Executa testes de qualidade
dbt test

# Gera documentação
dbt docs generate && dbt docs serve
```

### 4. Looker (LookML)

```bash
# Siga o guia em looker/README.md para:
# 1. Criar projeto LookML no Looker
# 2. Conectar ao BigQuery via service account
# 3. Importar os arquivos de views/ e models/
# 4. Validar e implantar os dashboards
```

---

## Dados do Cenário

### Fontes Operacionais

| Tabela | Fonte | Descrição |
|---|---|---|
| `transactions` | PostgreSQL | Transações financeiras processadas |
| `customers` | PostgreSQL | Cadastro de clientes PJ e PF |
| `credit_contracts` | PostgreSQL | Contratos de crédito e parcelas |
| `merchants` | CSV (ERP) | Cadastro de estabelecimentos |
| `daily_rates` | CSV (manual) | Taxas de câmbio e CDI diários |
| `chargebacks` | PostgreSQL | Contestações e chargebacks |

### Camadas dbt

```
raw.*                    ← dados brutos, sem transformação
staging.*                ← cast de tipos, renomeação, filtros nulos
intermediate.*           ← joins, regras de negócio, deduplicação
marts.fin_*              ← métricas financeiras (TPV, receita, MDR)
marts.risk_*             ← métricas de risco (inadimplência, exposição)
marts.ops_*              ← métricas operacionais (chargeback, aprovação)
```

---

## Governança de Dados

Veja [`GOVERNANCE.md`](./GOVERNANCE.md) para detalhes sobre:

- **Row-Level Security (RLS)** no BigQuery e no Looker por área de negócio
- **Data Quality** com testes dbt nativos + `dbt_expectations`
- **Lineage** completo via `dbt docs`
- **Auditoria** com tabela `audit.pipeline_runs`
- **PII Masking** em campos sensíveis (CPF, dados bancários)

---

## KPIs Entregues

| KPI | Descrição | Mart |
|---|---|---|
| TPV (Total Payment Volume) | Volume total processado por período | `marts.fin_daily_summary` |
| MDR (Merchant Discount Rate) | Taxa média cobrada dos lojistas | `marts.fin_merchant_metrics` |
| Taxa de Aprovação | % de transações aprovadas | `marts.ops_transaction_metrics` |
| Inadimplência (NPL) | % de crédito em default | `marts.risk_credit_portfolio` |
| Exposição de Crédito | Saldo devedor total da carteira | `marts.risk_credit_portfolio` |
| Chargeback Rate | % de transações contestadas | `marts.ops_chargeback_metrics` |
| Receita Líquida | MDR – custos operacionais | `marts.fin_revenue` |
| CAC | Custo de Aquisição de Cliente | `marts.ops_customer_acquisition` |

---

## Execução e Validação

Para verificar o pipeline funcionando de ponta a ponta:

1. Rode `./scripts/run_pipeline.sh` — extração, carga e transformações dbt em sequência
2. No terminal: `dbt run` + `dbt test` com saída dos testes de qualidade
3. BigQuery Console — inspecione os marts particionados com dados finais
4. Looker — abra o Explore de risco de crédito e filtre por classificação BACEN
5. Dashboard executivo com TPV, MDR e inadimplência por período
