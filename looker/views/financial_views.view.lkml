# looker/views/daily_financial_summary.view.lkml
# View principal do domínio financeiro
# Fonte: mart_fin_daily_summary no BigQuery

view: daily_financial_summary {
  sql_table_name: `{{ _user_attributes['gcp_project'] }}.analytics.mart_fin_daily_summary` ;;
  label: "Resumo Financeiro"

  # ─── Dimensões ──────────────────────────────────────────────────────────────

  dimension_group: summary {
    type: time
    timeframes: [date, week, month, quarter, year]
    datatype: date
    sql: ${TABLE}.summary_date ;;
    label: "Data"
    description: "Data de referência do resumo financeiro"
  }

  dimension: payment_method {
    type: string
    sql: ${TABLE}.payment_method ;;
    label: "Método de Pagamento"
    description: "Método utilizado: credit_card, debit_card, pix, boleto, ted"
  }

  dimension: payment_method_label {
    type: string
    label: "Método (PT)"
    description: "Rótulo em português do método de pagamento"
    sql: CASE ${TABLE}.payment_method
      WHEN 'credit_card' THEN 'Cartão de Crédito'
      WHEN 'debit_card'  THEN 'Cartão de Débito'
      WHEN 'pix'         THEN 'PIX'
      WHEN 'boleto'      THEN 'Boleto'
      WHEN 'ted'         THEN 'TED'
      ELSE ${TABLE}.payment_method
    END ;;
  }

  # ─── Medidas de Volume ───────────────────────────────────────────────────────

  measure: total_transactions {
    type: sum
    sql: ${TABLE}.total_transactions ;;
    label: "Total de Transações"
    description: "Total de transações no período (aprovadas + negadas + canceladas)"
    value_format_name: decimal_0
    drill_fields: [summary_date, payment_method, total_transactions]
  }

  measure: approved_transactions {
    type: sum
    sql: ${TABLE}.approved_transactions ;;
    label: "Transações Aprovadas"
    value_format_name: decimal_0
  }

  # ─── Medidas Financeiras (KPIs Principais) ────────────────────────────────

  measure: total_tpv_brl {
    type: sum
    sql: ${TABLE}.total_tpv_brl ;;
    label: "TPV (R$)"
    description: "Total Payment Volume — soma das transações aprovadas"
    value_format_name: brazilian_real
    drill_fields: [summary_date, payment_method, total_tpv_brl]
    tags: ["kpi", "primary"]
  }

  measure: total_mdr_revenue_brl {
    type: sum
    sql: ${TABLE}.total_mdr_revenue_brl ;;
    label: "Receita MDR (R$)"
    description: "Receita bruta de MDR (Merchant Discount Rate)"
    value_format_name: brazilian_real
    tags: ["kpi", "revenue"]
  }

  measure: avg_mdr_rate_pct {
    type: average
    sql: ${TABLE}.avg_mdr_rate_pct ;;
    label: "MDR Médio (%)"
    description: "Taxa média de MDR cobrada dos lojistas"
    value_format_name: percentage_2dp
    tags: ["kpi"]
  }

  measure: approval_rate_pct {
    type: average
    sql: ${TABLE}.approval_rate_pct ;;
    label: "Taxa de Aprovação (%)"
    description: "Percentual de transações aprovadas sobre o total"
    value_format_name: percentage_2dp
    tags: ["kpi", "operations"]
  }

  measure: chargeback_rate_pct {
    type: average
    sql: ${TABLE}.chargeback_rate_pct ;;
    label: "Taxa de Chargeback (%)"
    description: "Percentual de chargebacks sobre transações aprovadas"
    value_format_name: percentage_2dp
    tags: ["kpi", "risk"]
  }

  measure: avg_ticket_brl {
    type: average
    sql: ${TABLE}.avg_ticket_brl ;;
    label: "Ticket Médio (R$)"
    value_format_name: brazilian_real
  }
}


# ─────────────────────────────────────────────────────────────────────────────


# looker/views/credit_portfolio.view.lkml
# View do portfolio de crédito — campos sensíveis protegidos por access_grant

view: credit_portfolio {
  sql_table_name: `{{ _user_attributes['gcp_project'] }}.analytics.mart_risk_credit_portfolio` ;;
  label: "Portfolio de Crédito"

  dimension: product_type {
    type: string
    sql: ${TABLE}.product_type ;;
    label: "Produto de Crédito"
  }

  dimension: risk_classification_bacen {
    type: string
    sql: ${TABLE}.risk_classification_bacen ;;
    label: "Classificação BACEN"
    description: "Classificação de risco conforme Resolução CMN 2682/1999"
    order_by_field: risk_level_order
  }

  dimension: risk_level_order {
    type: string
    sql: CASE ${TABLE}.risk_classification_bacen
      WHEN 'AA' THEN '0'
      WHEN 'A'  THEN '1'
      WHEN 'B'  THEN '2'
      WHEN 'C'  THEN '3'
      WHEN 'D'  THEN '4'
      WHEN 'E'  THEN '5'
      WHEN 'F'  THEN '6'
      WHEN 'G'  THEN '7'
      WHEN 'H'  THEN '8'
    END ;;
    hidden: yes
  }

  dimension: dpd_bucket {
    type: string
    sql: ${TABLE}.dpd_bucket ;;
    label: "Bucket de Atraso"
    description: "Faixa de dias em atraso para análise de inadimplência"
  }

  dimension: customer_segment {
    type: string
    sql: ${TABLE}.customer_segment ;;
    label: "Segmento do Cliente"
  }

  dimension: collateral_type {
    type: string
    sql: ${TABLE}.collateral_type ;;
    label: "Tipo de Colateral"
  }

  dimension: snapshot_date {
    type: date
    sql: ${TABLE}.snapshot_date ;;
    label: "Data do Snapshot"
  }

  # ─── Medidas de Exposição ────────────────────────────────────────────────────

  measure: total_outstanding_brl {
    type: sum
    sql: ${TABLE}.total_outstanding_brl ;;
    label: "Saldo Devedor Total (R$)"
    description: "Exposição total da carteira de crédito"
    value_format_name: brazilian_real
    required_access_grants: [risk_team_only]
    tags: ["kpi", "exposure"]
  }

  measure: npl_balance_brl {
    type: sum
    sql: ${TABLE}.npl_balance_brl ;;
    label: "Saldo NPL (R$)"
    description: "Saldo em atraso >90 dias (Non-Performing Loans)"
    value_format_name: brazilian_real
    required_access_grants: [risk_team_only]
    tags: ["kpi", "npl"]
  }

  measure: npl_rate_pct {
    type: average
    sql: ${TABLE}.npl_rate_pct ;;
    label: "Índice de Inadimplência (%)"
    description: "NPL como % do saldo total da carteira"
    value_format_name: percentage_2dp
    required_access_grants: [risk_team_only]
    tags: ["kpi", "npl", "primary"]
  }

  measure: total_expected_loss_brl {
    type: sum
    sql: ${TABLE}.total_expected_loss_brl ;;
    label: "Perda Esperada (R$)"
    description: "Provisão mínima exigida conforme Res. CMN 2682"
    value_format_name: brazilian_real
    required_access_grants: [risk_team_only]
  }

  measure: portfolio_coverage_ratio {
    type: average
    sql: ${TABLE}.portfolio_coverage_ratio ;;
    label: "Cobertura de Colateral"
    description: "Valor do colateral / Saldo devedor"
    value_format: "0.00\"x\""
    required_access_grants: [risk_team_only]
  }

  measure: total_contracts {
    type: sum
    sql: ${TABLE}.total_contracts ;;
    label: "Total de Contratos"
    value_format_name: decimal_0
  }
}
