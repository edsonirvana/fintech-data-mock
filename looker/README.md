# Looker — Setup e Configuração LookML

## Pré-requisitos

- Acesso a uma instância Looker (trial, licença própria ou Looker Studio Pro)
- Service Account GCP com permissões BigQuery Data Viewer no dataset `analytics`
- Git configurado para deploy do projeto LookML

---

## 1. Conexão BigQuery no Looker

No painel admin do Looker:

1. Acesse **Admin → Connections → New Connection**
2. Configure:

```
Name:               paybridge_bigquery
Dialect:            Google BigQuery Standard SQL
Project ID:         paybridge-data-challenge
Dataset:            analytics
Authentication:     Service Account (JSON key)
```

3. Faça upload da Service Account key (gerada em `infra/setup_gcp.sh`)
4. Clique em **Test** — todos os checks devem passar
5. Salve a conexão

---

## 2. Criar Projeto LookML

1. **Develop → Manage LookML Projects → New LookML Project**
2. Nome do projeto: `paybridge`
3. Fonte: **Clone from Git Repository**
4. URL do repositório: `https://github.com/edsonmachadosilva/fintech-data-challenge`
5. Pasta raiz do LookML: `looker/`

---

## 3. Estrutura dos Arquivos

```
looker/
├── models/
│   └── paybridge_financial.model.lkml   ← define explores e access grants
├── views/
│   └── financial_views.view.lkml        ← dimensões, medidas, RLS semântico
└── dashboards/
    └── executive_overview.dashboard.lookml
```

---

## 4. Configurar User Attributes (RLS semântico)

Em **Admin → User Attributes → New User Attribute**:

| Attribute Name | Label | Type | Default Value |
|---|---|---|---|
| `department` | Departamento | String | `operations` |
| `gcp_project` | GCP Project ID | String | `paybridge-data-challenge` |

Depois, atribua a cada grupo de usuários:

| Grupo Looker | `department` |
|---|---|
| Engenharia de Dados | `data_engineering` |
| Risco de Crédito | `risk` |
| Financeiro | `finance` |
| Comercial | `sales` |
| Executivo | `executive` |

---

## 5. Validar e Deployar

```bash
# No Looker IDE (Develop mode)
# 1. Abrir o arquivo paybridge_financial.model.lkml
# 2. Clicar em "Validate LookML" — sem erros esperados
# 3. Commit das mudanças
# 4. Deploy to Production
```

---

## 6. Access Grants — Como Funciona

O modelo define 3 access grants:

| Grant | Departamentos com acesso |
|---|---|
| `risk_team_only` | risk, executive, data_engineering |
| `finance_team` | finance, risk, executive, data_engineering |
| `executive_only` | executive, data_engineering |

Campos protegidos pelo `risk_team_only` (ex: `individual_exposure_brl`, `npl_balance_brl`) ficam **invisíveis** no Explore para usuários sem o grant — sem mensagem de erro, simplesmente não aparecem.

---

## 7. Explores Disponíveis

| Explore | Grupo | Acesso |
|---|---|---|
| Resumo Financeiro Diário | Financeiro | finance + risk + executive |
| Portfolio de Crédito | Risco | risk + executive (restricted) |
| Operações de Transações | Operacional | todos |
| Desempenho de Merchants | Financeiro | finance + risk + executive |

---

## 8. Dashboard Executivo

Após o deploy, acesse **Dashboards → PayBridge — Visão Executiva**.

KPIs exibidos:
- TPV Total do período
- Receita MDR
- Taxa de Aprovação (com alerta verde/vermelho)
- Índice de Inadimplência (NPL)
- Exposição Total de Crédito
- Taxa de Chargeback
- Evolução semanal do TPV por método
- Distribuição por classificação BACEN
- NPL por segmento de cliente
