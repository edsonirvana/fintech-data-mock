{# macros/fintech_utils.sql #}
{# Macros reutilizáveis para cálculos financeiros específicos de fintech #}


{# ─── MDR (Merchant Discount Rate) ─────────────────────────────────────────── #}
{% macro calculate_mdr(gross_amount, net_amount) %}
  SAFE_DIVIDE(
    ({{ gross_amount }} - {{ net_amount }}),
    {{ gross_amount }}
  ) * 100
{% endmacro %}


{# ─── Classificação BACEN (Resolução CMN 2682) ──────────────────────────────── #}
{# Classifica operações de crédito por dias de atraso conforme regulação BACEN   #}
{% macro classify_risk_bacen(days_past_due_col) %}
  CASE
    WHEN {{ days_past_due_col }} = 0                    THEN 'AA'
    WHEN {{ days_past_due_col }} BETWEEN 1 AND 14       THEN 'A'
    WHEN {{ days_past_due_col }} BETWEEN 15 AND 30      THEN 'B'
    WHEN {{ days_past_due_col }} BETWEEN 31 AND 60      THEN 'C'
    WHEN {{ days_past_due_col }} BETWEEN 61 AND 90      THEN 'D'
    WHEN {{ days_past_due_col }} BETWEEN 91 AND 120     THEN 'E'
    WHEN {{ days_past_due_col }} BETWEEN 121 AND 150    THEN 'F'
    WHEN {{ days_past_due_col }} BETWEEN 151 AND 180    THEN 'G'
    ELSE 'H'
  END
{% endmacro %}


{# ─── Provisão mínima BACEN ─────────────────────────────────────────────────── #}
{# Percentual mínimo de provisão por nível de risco (Res. CMN 2682 art. 6º)     #}
{% macro bacen_provision_rate(risk_class_col) %}
  CASE {{ risk_class_col }}
    WHEN 'AA' THEN 0.000
    WHEN 'A'  THEN 0.005
    WHEN 'B'  THEN 0.010
    WHEN 'C'  THEN 0.030
    WHEN 'D'  THEN 0.100
    WHEN 'E'  THEN 0.300
    WHEN 'F'  THEN 0.500
    WHEN 'G'  THEN 0.700
    WHEN 'H'  THEN 1.000
    ELSE NULL
  END
{% endmacro %}


{# ─── Mascaramento de PII ────────────────────────────────────────────────────── #}
{# Aplica mascaramento em campos sensíveis conforme LGPD                          #}
{% macro mask_pii(column_name, mask_type='default') %}
  {% if mask_type == 'cnpj' %}
    CONCAT(
      LEFT(CAST({{ column_name }} AS STRING), 2),
      '.***.***/',
      RIGHT(CAST({{ column_name }} AS STRING), 6)
    )
  {% elif mask_type == 'cpf' %}
    CONCAT(
      LEFT(CAST({{ column_name }} AS STRING), 3),
      '.***.***-**'
    )
  {% elif mask_type == 'bank_account' %}
    CONCAT('****', RIGHT(CAST({{ column_name }} AS STRING), 4))
  {% elif mask_type == 'email' %}
    CONCAT(
      LEFT({{ column_name }}, 2),
      '***@***.**'
    )
  {% elif mask_type == 'phone' %}
    CONCAT(
      LEFT(CAST({{ column_name }} AS STRING), 4),
      '****',
      RIGHT(CAST({{ column_name }} AS STRING), 4)
    )
  {% else %}
    SHA256(CAST({{ column_name }} AS STRING))
  {% endif %}
{% endmacro %}


{# ─── Dias úteis entre duas datas (Brasil) ──────────────────────────────────── #}
{# Aproximação: exclui fins de semana (feriados requerem tabela de referência)   #}
{% macro business_days_between(start_date, end_date) %}
  (
    DATE_DIFF({{ end_date }}, {{ start_date }}, DAY)
    - 2 * DIV(DATE_DIFF({{ end_date }}, {{ start_date }}, WEEK), 1)
    - CASE WHEN EXTRACT(DAYOFWEEK FROM {{ start_date }}) = 1 THEN 1 ELSE 0 END
    - CASE WHEN EXTRACT(DAYOFWEEK FROM {{ end_date }}) = 7 THEN 1 ELSE 0 END
  )
{% endmacro %}


{# ─── Taxa efetiva anual a partir da taxa mensal (juros compostos) ───────────── #}
{% macro monthly_to_annual_rate(monthly_rate_col) %}
  (POWER(1 + {{ monthly_rate_col }} / 100, 12) - 1) * 100
{% endmacro %}


{# ─── Formato de valor em BRL ────────────────────────────────────────────────── #}
{# Padroniza a formatação de NUMERIC para apresentação                            #}
{% macro format_brl(amount_col, decimals=2) %}
  ROUND(CAST({{ amount_col }} AS NUMERIC), {{ decimals }})
{% endmacro %}


{# ─── Teste de reconciliação financeira ─────────────────────────────────────── #}
{# Macro de teste customizado: valida que dois campos somam ao mesmo valor        #}
{% macro test_financial_reconciliation(model, column_a, column_b, tolerance=0.01) %}
  SELECT
    COUNT(*) AS divergent_rows
  FROM {{ model }}
  WHERE ABS({{ column_a }} - {{ column_b }}) > {{ tolerance }}
{% endmacro %}


{# ─── Geração de surrogate key para dimensões ─────────────────────────────────── #}
{% macro generate_surrogate_key(fields) %}
  {{ dbt_utils.generate_surrogate_key(fields) }}
{% endmacro %}
