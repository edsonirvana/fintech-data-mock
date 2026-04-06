-- models/marts/risk/mart_risk_credit_portfolio.sql
-- Portfolio de Crédito: Exposição, Inadimplência, NPL
-- Alinhado com Resolução CMN 2682 (classificação de risco BACEN)

{{ config(
    materialized='table',
    cluster_by=["risk_classification_bacen", "product_type"],
    tags=["mart", "risk", "kpi", "regulated"],
    meta={
        "sensitivity": "confidential",
        "regulatory_basis": "Resolução CMN 2682/1999",
        "owner": "risk-team"
    }
) }}

WITH contracts AS (
    SELECT * FROM {{ ref('stg_credit_contracts') }}
),

customers AS (
    SELECT
        customer_id,
        customer_segment,
        credit_rating
    FROM {{ ref('stg_customers') }}
),

enriched_contracts AS (
    SELECT
        c.*,
        cu.customer_segment,
        cu.credit_rating AS customer_credit_rating,

        -- Bucket de inadimplência para relatórios regulatórios
        CASE
            WHEN c.days_past_due = 0                    THEN 'Adimplente'
            WHEN c.days_past_due BETWEEN 1 AND 30       THEN '1-30 dias'
            WHEN c.days_past_due BETWEEN 31 AND 60      THEN '31-60 dias'
            WHEN c.days_past_due BETWEEN 61 AND 90      THEN '61-90 dias'
            WHEN c.days_past_due BETWEEN 91 AND 180     THEN '91-180 dias (NPL)'
            ELSE '>180 dias (Perda)'
        END                                             AS dpd_bucket,

        -- Perda esperada simplificada (Expected Loss)
        CASE UPPER(c.risk_classification_bacen)
            WHEN 'AA' THEN 0.000
            WHEN 'A'  THEN 0.005
            WHEN 'B'  THEN 0.010
            WHEN 'C'  THEN 0.030
            WHEN 'D'  THEN 0.100
            WHEN 'E'  THEN 0.300
            WHEN 'F'  THEN 0.500
            WHEN 'G'  THEN 0.700
            WHEN 'H'  THEN 1.000
        END * c.outstanding_balance_brl                AS expected_loss_brl

    FROM contracts c
    LEFT JOIN customers cu USING (customer_id)
),

portfolio_summary AS (
    SELECT
        product_type,
        risk_classification_bacen,
        dpd_bucket,
        customer_segment,
        collateral_type,

        -- Contagens
        COUNT(DISTINCT contract_id)                     AS total_contracts,
        COUNT(DISTINCT customer_id)                     AS total_customers,

        -- Exposição
        SUM(principal_brl)                              AS total_principal_brl,
        SUM(outstanding_balance_brl)                    AS total_outstanding_brl,

        -- Inadimplência
        COUNTIF(is_npl)                                 AS npl_contracts,
        SUM(CASE WHEN is_npl THEN outstanding_balance_brl ELSE 0 END)
                                                        AS npl_balance_brl,

        -- Baixas contábeis
        COUNTIF(is_written_off)                         AS written_off_contracts,
        SUM(CASE WHEN is_written_off THEN outstanding_balance_brl ELSE 0 END)
                                                        AS written_off_balance_brl,

        -- Perda esperada total
        SUM(expected_loss_brl)                          AS total_expected_loss_brl,

        -- Cobertura de colateral
        SUM(collateral_value_brl)                       AS total_collateral_brl,
        SAFE_DIVIDE(
            SUM(collateral_value_brl),
            SUM(outstanding_balance_brl)
        )                                               AS portfolio_coverage_ratio

    FROM enriched_contracts
    WHERE is_active OR is_npl  -- inclui NPL mesmo que vencido
    GROUP BY 1, 2, 3, 4, 5
)

SELECT
    product_type,
    risk_classification_bacen,
    dpd_bucket,
    customer_segment,
    collateral_type,
    total_contracts,
    total_customers,
    ROUND(total_principal_brl, 2)                       AS total_principal_brl,
    ROUND(total_outstanding_brl, 2)                     AS total_outstanding_brl,
    npl_contracts,
    ROUND(npl_balance_brl, 2)                           AS npl_balance_brl,
    ROUND(
        SAFE_DIVIDE(npl_balance_brl, total_outstanding_brl) * 100,
        4
    )                                                   AS npl_rate_pct,
    written_off_contracts,
    ROUND(written_off_balance_brl, 2)                   AS written_off_balance_brl,
    ROUND(total_expected_loss_brl, 2)                   AS total_expected_loss_brl,
    ROUND(total_collateral_brl, 2)                      AS total_collateral_brl,
    ROUND(portfolio_coverage_ratio, 4)                  AS portfolio_coverage_ratio,
    CURRENT_TIMESTAMP()                                 AS _dbt_updated_at,
    CURRENT_DATE()                                      AS snapshot_date

FROM portfolio_summary
