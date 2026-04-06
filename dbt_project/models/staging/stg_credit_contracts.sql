-- models/staging/stg_credit_contracts.sql
-- Limpeza de contratos + classificação BACEN normalizada

WITH source AS (
    SELECT * FROM {{ source('raw', 'credit_contracts') }}
),

cleaned AS (
    SELECT
        TRIM(contract_id)                                   AS contract_id,
        TRIM(customer_id)                                   AS customer_id,
        LOWER(TRIM(product_type))                           AS product_type,
        LOWER(TRIM(collateral_type))                        AS collateral_type,

        CAST(principal_brl AS NUMERIC)                      AS principal_brl,
        CAST(outstanding_balance_brl AS NUMERIC)            AS outstanding_balance_brl,
        CAST(monthly_rate_pct AS NUMERIC)                   AS monthly_rate_pct,
        CAST(collateral_value_brl AS NUMERIC)               AS collateral_value_brl,

        CAST(term_months AS INT64)                          AS term_months,
        CAST(days_past_due AS INT64)                        AS days_past_due,

        CAST(contract_date AS DATE)                         AS contract_date,
        CAST(maturity_date AS DATE)                         AS maturity_date,

        UPPER(TRIM(risk_classification_bacen))              AS risk_classification_bacen,
        CAST(is_npl AS BOOL)                                AS is_npl,
        CAST(is_written_off AS BOOL)                        AS is_written_off,

        -- Nível de risco numérico (para ordenação e cálculos)
        CASE UPPER(TRIM(risk_classification_bacen))
            WHEN 'AA' THEN 0
            WHEN 'A'  THEN 1
            WHEN 'B'  THEN 2
            WHEN 'C'  THEN 3
            WHEN 'D'  THEN 4
            WHEN 'E'  THEN 5
            WHEN 'F'  THEN 6
            WHEN 'G'  THEN 7
            WHEN 'H'  THEN 8
            ELSE NULL
        END                                                 AS risk_level_num,

        -- Cobertura de colateral
        SAFE_DIVIDE(
            CAST(collateral_value_brl AS NUMERIC),
            CAST(outstanding_balance_brl AS NUMERIC)
        )                                                   AS collateral_coverage_ratio,

        -- Contrato ativo (não vencido e não baixado)
        NOT CAST(is_written_off AS BOOL)
            AND CAST(maturity_date AS DATE) >= CURRENT_DATE()
                                                            AS is_active,

        CURRENT_TIMESTAMP()                                 AS _dbt_updated_at

    FROM source
    WHERE
        contract_id IS NOT NULL
        AND principal_brl > 0
)

SELECT * FROM cleaned


-- ─────────────────────────────────────────────────────────────────────────────


-- models/staging/stg_customers.sql
-- Limpeza de clientes com mascaramento de PII

-- NOTA: Este arquivo representa dois modelos separados.
-- Na implementação real, cada modelo vai em seu próprio arquivo .sql


-- models/staging/stg_merchants.sql
-- Limpeza de estabelecimentos com validação de MDR

WITH source AS (
    SELECT * FROM {{ source('raw', 'merchants') }}
)

SELECT
    TRIM(merchant_id)                       AS merchant_id,
    TRIM(merchant_name)                     AS merchant_name,
    LOWER(TRIM(merchant_segment))           AS merchant_segment,
    TRIM(customer_id)                       AS customer_id,

    CAST(mdr_credit AS NUMERIC)             AS mdr_credit_pct,
    CAST(mdr_debit AS NUMERIC)              AS mdr_debit_pct,
    CAST(mdr_pix AS NUMERIC)               AS mdr_pix_pct,

    CAST(activated_at AS DATE)              AS activated_at,
    CAST(is_active AS BOOL)                 AS is_active,

    -- MDR médio ponderado (estimativa de mix 60% crédito, 25% débito, 15% pix)
    ROUND(
        CAST(mdr_credit AS NUMERIC) * 0.60
        + CAST(mdr_debit AS NUMERIC) * 0.25
        + CAST(mdr_pix AS NUMERIC) * 0.15,
        4
    )                                       AS blended_mdr_pct,

    CURRENT_TIMESTAMP()                     AS _dbt_updated_at

FROM source
WHERE merchant_id IS NOT NULL
