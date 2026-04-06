# Governança de Dados — PayBridge Financeira

## Princípios

1. **Rastreabilidade:** toda transformação é documentada e versionada no Git
2. **Qualidade por design:** testes executam em cada pipeline run, não são opcionais
3. **Mínimo privilégio:** cada serviço e usuário acessa apenas o que precisa
4. **PII by default:** dados sensíveis são mascarados nas camadas de consumo
5. **Auditoria completa:** toda execução é registrada na tabela `audit.pipeline_runs`

---

## Classificação de Dados

| Classificação | Exemplos | Controles |
|---|---|---|
| Público | Taxas de câmbio, feriados | Sem restrições |
| Interno | TPV agregado, métricas por segmento | IAM por grupo |
| Confidencial | Contratos individuais, margens | RLS + Looker Access Grants |
| Restrito (PII) | CPF, CNPJ, dados bancários, endereço | Mascaramento + RLS + logs de acesso |

---

## Row-Level Security (RLS)

### BigQuery — Row Access Policies

```sql
-- Apenas equipe de risco acessa portfolio de crédito individual
CREATE ROW ACCESS POLICY rls_risk_credit
  ON `paybridge-prod.analytics.risk_credit_portfolio`
  GRANT TO ("group:risk-analysts@paybridge.com.br",
            "serviceAccount:looker-sa@paybridge-prod.iam.gserviceaccount.com")
  FILTER USING (TRUE);

-- Equipe financeira: apenas sua unidade de negócio
CREATE ROW ACCESS POLICY rls_finance_bu
  ON `paybridge-prod.analytics.fin_merchant_metrics`
  GRANT TO ("group:finance@paybridge.com.br")
  FILTER USING (business_unit IN ('finance', 'executive'));

-- Comercial: apenas dados agregados, sem valores individuais
CREATE ROW ACCESS POLICY rls_sales_aggregated
  ON `paybridge-prod.analytics.ops_transaction_metrics`
  GRANT TO ("group:sales@paybridge.com.br")
  FILTER USING (granularity = 'monthly');
```

### Looker — User Attributes e Access Grants

```lookml
# model: paybridge_financial.model
access_grant: risk_team_only {
  user_attribute: department
  allowed_values: ["risk", "executive"]
}

access_grant: finance_team {
  user_attribute: department
  allowed_values: ["finance", "risk", "executive"]
}
```

```lookml
# view: credit_portfolio.view
dimension: individual_exposure_brl {
  type: number
  sql: ${TABLE}.exposure_brl ;;
  required_access_grants: [risk_team_only]  # campo invisível para outros grupos
}
```

---

## PII Masking

A macro `mask_pii` no dbt aplica mascaramento nos modelos de staging:

```sql
-- macro: mask_pii.sql
{% macro mask_pii(column_name, mask_type='cpf') %}
  {% if mask_type == 'cpf' %}
    CONCAT(LEFT(CAST({{ column_name }} AS STRING), 3), '.***.***-**')
  {% elif mask_type == 'bank_account' %}
    CONCAT('****', RIGHT(CAST({{ column_name }} AS STRING), 4))
  {% elif mask_type == 'email' %}
    CONCAT(LEFT({{ column_name }}, 2), '***@***.***')
  {% endif %}
{% endmacro %}
```

Nos modelos de staging, CPF e dados bancários são sempre mascarados antes de chegarem ao BigQuery:

```sql
-- staging/stg_customers.sql (exemplo de uso)
SELECT
  customer_id,
  {{ mask_pii('cpf', 'cpf') }}                AS cpf_masked,
  {{ mask_pii('bank_account', 'bank_account') }} AS account_masked,
  customer_segment,
  registration_date,
  is_active
FROM {{ source('raw', 'customers') }}
WHERE customer_id IS NOT NULL
```

---

## Framework de Qualidade de Dados

### Testes dbt Nativos (schema.yml)

```yaml
models:
  - name: stg_transactions
    columns:
      - name: transaction_id
        tests:
          - not_null
          - unique
      - name: amount_brl
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: "> 0"
      - name: status
        tests:
          - accepted_values:
              values: ['approved', 'denied', 'cancelled', 'chargeback', 'pending']
      - name: transaction_date
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: "<= CURRENT_DATE()"
```

### Testes dbt_expectations (negócio/fintech)

```yaml
  - name: mart_fin_daily_summary
    tests:
      - dbt_expectations.expect_column_sum_to_be_between:
          column_name: total_tpv_brl
          min_value: 0
          max_value: 1000000000  # R$ 1 bilhão/dia — alerta se ultrapassar
      - dbt_expectations.expect_column_proportion_of_unique_values_to_be_between:
          column_name: summary_date
          min_value: 0.99  # cada data deve aparecer uma vez
```

### Teste de Reconciliação Financeira (macro customizada)

```sql
-- tests/assert_tpv_reconciliation.sql
-- Valida que TPV no mart bate com soma das transações aprovadas
SELECT
  summary_date,
  mart_tpv,
  source_tpv,
  ABS(mart_tpv - source_tpv) AS divergence_brl
FROM (
  SELECT
    s.summary_date,
    s.total_tpv_brl AS mart_tpv,
    t.calculated_tpv AS source_tpv
  FROM {{ ref('mart_fin_daily_summary') }} s
  JOIN (
    SELECT
      DATE(transaction_date) AS tx_date,
      SUM(amount_brl) AS calculated_tpv
    FROM {{ ref('stg_transactions') }}
    WHERE status = 'approved'
    GROUP BY 1
  ) t ON s.summary_date = t.tx_date
)
WHERE ABS(mart_tpv - source_tpv) > 0.01  -- tolerância de R$ 0,01
```

---

## Tabela de Auditoria

Cada execução do pipeline registra metadados na tabela `audit.pipeline_runs`:

```sql
CREATE TABLE `paybridge-prod.audit.pipeline_runs` (
  run_id          STRING NOT NULL,
  pipeline_name   STRING NOT NULL,
  step            STRING NOT NULL,
  status          STRING NOT NULL,   -- 'success', 'failed', 'skipped'
  rows_processed  INT64,
  rows_failed     INT64,
  started_at      TIMESTAMP NOT NULL,
  finished_at     TIMESTAMP,
  error_message   STRING,
  triggered_by    STRING,            -- 'cron', 'manual', 'api'
  git_commit_sha  STRING
)
PARTITION BY DATE(started_at)
OPTIONS (require_partition_filter = false);
```

---

## Controle de Acesso — Matriz RACI

| Recurso | Eng. Dados | Analista | Risco | Financeiro | Comercial | Exec |
|---|---|---|---|---|---|---|
| `raw.*` | R/W | — | — | — | — | — |
| `staging.*` | R/W | R | — | — | — | — |
| `analytics.fin_*` | R/W | R | R | R | — | R |
| `analytics.risk_*` | R/W | — | R | — | — | R (agregado) |
| `analytics.ops_*` | R/W | R | — | R | R (agregado) | R |
| Looker Explore: Financial | Config | R | R | R | — | R |
| Looker Explore: Risk | Config | — | R | — | — | R |
| Looker Explore: Operations | Config | R | — | — | R | R |

---

## Política de Retenção

| Camada | Retenção | Justificativa |
|---|---|---|
| `raw` | 7 anos | Exigência regulatória (BACEN) |
| `staging` | 90 dias | Apenas para reprocessamento |
| `analytics` (marts) | 5 anos | Histórico analítico |
| `audit` | 7 anos | Rastreabilidade regulatória |
| Logs de acesso PII | 5 anos | LGPD art. 37 |
