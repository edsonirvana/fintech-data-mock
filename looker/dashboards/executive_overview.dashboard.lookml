# looker/dashboards/executive_overview.dashboard.lookml
# Dashboard Executivo: visão consolidada dos principais KPIs
# Disponível para: executivo e acima

- dashboard: executive_overview
  title: "PayBridge — Visão Executiva"
  layout: newspaper
  preferred_viewer: dashboards-next
  description: "KPIs financeiros e de risco consolidados para decisão em nível C-level"
  refresh: 1 hours

  filters:
  - name: date_range
    title: "Período"
    type: date_filter
    default_value: "30 days"
    allow_multiple_values: true
    required: false

  - name: payment_method
    title: "Método de Pagamento"
    type: field_filter
    explore: daily_financial_summary
    field: daily_financial_summary.payment_method
    default_value: ""
    allow_multiple_values: true
    required: false

  elements:

  # ─── Linha 1: KPIs Financeiros ─────────────────────────────────────────────

  - title: "TPV Total"
    name: kpi_tpv
    model: paybridge_financial
    explore: daily_financial_summary
    type: single_value
    fields: [daily_financial_summary.total_tpv_brl]
    filters:
      daily_financial_summary.summary_date: "{% date_start date_range %} to {% date_end date_range %}"
    value_format: '"R$" #,##0,,,"B"'
    width: 4
    height: 2
    note_state: collapsed
    note_display: hover
    note_text: "Total Payment Volume — soma das transações aprovadas no período"

  - title: "Receita MDR"
    name: kpi_mdr_revenue
    model: paybridge_financial
    explore: daily_financial_summary
    type: single_value
    fields: [daily_financial_summary.total_mdr_revenue_brl]
    filters:
      daily_financial_summary.summary_date: "{% date_start date_range %} to {% date_end date_range %}"
    value_format: '"R$" #,##0,,"M"'
    width: 4
    height: 2

  - title: "Taxa de Aprovação"
    name: kpi_approval_rate
    model: paybridge_financial
    explore: daily_financial_summary
    type: single_value
    fields: [daily_financial_summary.approval_rate_pct]
    filters:
      daily_financial_summary.summary_date: "{% date_start date_range %} to {% date_end date_range %}"
    value_format: '0.00"%"'
    width: 4
    height: 2
    conditional_formatting_include_totals: false
    conditional_formatting:
    - type: greater than
      value: 85
      background_color: "#00b860"
      font_color: ''
    - type: less than
      value: 75
      background_color: "#e53a3a"
      font_color: ''

  # ─── Linha 1 (cont.): KPIs de Risco ────────────────────────────────────────

  - title: "Índice de Inadimplência (NPL)"
    name: kpi_npl
    model: paybridge_financial
    explore: credit_portfolio
    type: single_value
    fields: [credit_portfolio.npl_rate_pct]
    value_format: '0.00"%"'
    width: 4
    height: 2
    note_state: collapsed
    note_display: hover
    note_text: "Saldo NPL (>90 dias) como % do total da carteira — referência: <3% para carteiras saudáveis"

  - title: "Exposição Total de Crédito"
    name: kpi_exposure
    model: paybridge_financial
    explore: credit_portfolio
    type: single_value
    fields: [credit_portfolio.total_outstanding_brl]
    value_format: '"R$" #,##0,,"M"'
    width: 4
    height: 2

  - title: "Taxa de Chargeback"
    name: kpi_chargeback
    model: paybridge_financial
    explore: daily_financial_summary
    type: single_value
    fields: [daily_financial_summary.chargeback_rate_pct]
    filters:
      daily_financial_summary.summary_date: "{% date_start date_range %} to {% date_end date_range %}"
    value_format: '0.000"%"'
    width: 4
    height: 2

  # ─── Linha 2: Evolução do TPV ───────────────────────────────────────────────

  - title: "Evolução do TPV por Método de Pagamento"
    name: chart_tpv_trend
    model: paybridge_financial
    explore: daily_financial_summary
    type: looker_area
    fields: [daily_financial_summary.summary_week, daily_financial_summary.payment_method_label, daily_financial_summary.total_tpv_brl]
    pivots: [daily_financial_summary.payment_method_label]
    filters:
      daily_financial_summary.summary_date: "{% date_start date_range %} to {% date_end date_range %}"
    sorts: [daily_financial_summary.summary_week asc]
    x_axis_gridlines: false
    y_axis_gridlines: true
    show_view_names: false
    width: 12
    height: 6

  # ─── Linha 3: Distribuição de Risco ────────────────────────────────────────

  - title: "Portfolio por Classificação BACEN"
    name: chart_bacen_distribution
    model: paybridge_financial
    explore: credit_portfolio
    type: looker_bar
    fields: [credit_portfolio.risk_classification_bacen, credit_portfolio.total_outstanding_brl, credit_portfolio.npl_balance_brl]
    sorts: [credit_portfolio.risk_classification_bacen asc]
    x_axis_gridlines: false
    y_axis_gridlines: true
    show_view_names: false
    width: 6
    height: 6

  - title: "Inadimplência por Segmento de Cliente"
    name: chart_npl_by_segment
    model: paybridge_financial
    explore: credit_portfolio
    type: looker_pie
    fields: [credit_portfolio.customer_segment, credit_portfolio.npl_balance_brl]
    sorts: [credit_portfolio.npl_balance_brl desc]
    width: 6
    height: 6
