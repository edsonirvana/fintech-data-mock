# looker/models/paybridge_financial.model.lkml
# Modelo principal do domínio financeiro
# Organiza explores por área de negócio com controle de acesso

connection: "paybridge_bigquery"

# Importa todas as views do projeto
include: "/views/*.view.lkml"
include: "/dashboards/*.dashboard.lookml"

# ─── Access Grants (RLS semântico no Looker) ─────────────────────────────────

access_grant: risk_team_only {
  user_attribute: department
  allowed_values: ["risk", "executive", "data_engineering"]
}

access_grant: finance_team {
  user_attribute: department
  allowed_values: ["finance", "risk", "executive", "data_engineering"]
}

access_grant: executive_only {
  user_attribute: department
  allowed_values: ["executive", "data_engineering"]
}

# ─── Formatos de valor customizados ──────────────────────────────────────────

named_value_format: brazilian_real {
  value_format: "\"R$\" #,##0.00"
}

named_value_format: percentage_2dp {
  value_format: "0.00\"%\""
}

named_value_format: large_brl {
  value_format: "\"R$\" #,##0,,\"M\""
}


# ─── Explore: Resumo Financeiro Diário ───────────────────────────────────────
# Disponível para: financeiro, risco, executivo

explore: daily_financial_summary {
  label: "Resumo Financeiro Diário"
  description: "TPV, MDR, receita e taxas de aprovação por dia e método de pagamento"
  group_label: "Financeiro"

  join: daily_rates {
    type: left_outer
    relationship: many_to_one
    sql_on: ${daily_financial_summary.summary_date} = ${daily_rates.rate_date} ;;
  }

  always_filter: {
    filters: [daily_financial_summary.summary_date: "90 days"]
  }

  tags: ["financial", "kpi", "daily"]
}


# ─── Explore: Portfolio de Crédito ───────────────────────────────────────────
# Disponível para: risco e executivo (access_grant aplicado na view)

explore: credit_portfolio {
  label: "Portfolio de Crédito"
  description: "Exposição de crédito, inadimplência (NPL) e classificação BACEN"
  group_label: "Risco"

  required_access_grants: [risk_team_only]

  join: customers {
    type: left_outer
    relationship: many_to_one
    sql_on: ${credit_portfolio.customer_id} = ${customers.customer_id} ;;
    fields: [customers.customer_segment, customers.customer_id, customers.state]
  }

  tags: ["risk", "credit", "regulated"]
}


# ─── Explore: Métricas Operacionais ──────────────────────────────────────────
# Disponível para: todas as equipes

explore: transaction_operations {
  label: "Operações de Transações"
  description: "Volume transacional, chargebacks, taxa de aprovação e performance por adquirente"
  group_label: "Operacional"

  join: merchants {
    type: left_outer
    relationship: many_to_one
    sql_on: ${transaction_operations.merchant_id} = ${merchants.merchant_id} ;;
  }

  join: customers {
    type: left_outer
    relationship: many_to_one
    sql_on: ${merchants.customer_id} = ${customers.customer_id} ;;
    fields: [customers.customer_segment, customers.state, customers.customer_id]
  }

  always_filter: {
    filters: [transaction_operations.transaction_date: "30 days"]
  }

  tags: ["operations", "transactions", "kpi"]
}


# ─── Explore: Desempenho de Merchants ────────────────────────────────────────

explore: merchant_performance {
  label: "Desempenho de Estabelecimentos"
  description: "MDR por merchant, TPV e receita por segmento"
  group_label: "Financeiro"

  join: merchants {
    type: left_outer
    relationship: many_to_one
    sql_on: ${merchant_performance.merchant_id} = ${merchants.merchant_id} ;;
  }

  join: customers {
    type: left_outer
    relationship: many_to_one
    sql_on: ${merchants.customer_id} = ${customers.customer_id} ;;
    fields: [customers.customer_segment, customers.state]
  }

  tags: ["financial", "merchants", "mdr"]
}
