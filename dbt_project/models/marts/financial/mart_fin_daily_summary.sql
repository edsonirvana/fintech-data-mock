-- models/marts/financial/mart_fin_daily_summary.sql
-- KPI Financeiro Diário: TPV, MDR, Receita
-- Particionado por data para otimização de queries

{{ config(
    materialized='table',
    partition_by={
      "field": "summary_date",
      "data_type": "date",
      "granularity": "day"
    },
    cluster_by=["payment_method"],
    tags=["mart", "financial", "kpi"]
) }}

WITH transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
),

daily_aggregated AS (
    SELECT
        transaction_date                                    AS summary_date,
        payment_method,

        -- Volume (TPV)
        COUNT(*)                                            AS total_transactions,
        COUNTIF(is_approved)                               AS approved_transactions,
        COUNTIF(is_chargeback)                             AS chargeback_transactions,

        -- Valores financeiros (apenas aprovadas)
        SUM(CASE WHEN is_approved THEN amount_brl ELSE 0 END)
                                                            AS total_tpv_brl,
        SUM(CASE WHEN is_approved THEN mdr_amount_brl ELSE 0 END)
                                                            AS total_mdr_revenue_brl,
        SUM(CASE WHEN is_approved THEN net_amount_brl ELSE 0 END)
                                                            AS total_net_amount_brl,

        -- Médias
        AVG(CASE WHEN is_approved THEN amount_brl END)     AS avg_ticket_brl,
        AVG(CASE WHEN is_approved THEN mdr_rate_pct END)   AS avg_mdr_rate_pct,

        -- Taxas de aprovação e chargeback
        SAFE_DIVIDE(
            COUNTIF(is_approved),
            COUNT(*)
        ) * 100                                             AS approval_rate_pct,

        SAFE_DIVIDE(
            COUNTIF(is_chargeback),
            COUNTIF(is_approved)
        ) * 100                                             AS chargeback_rate_pct,

        -- Recorrência de parcelamento
        COUNTIF(is_installment AND is_approved)            AS installment_transactions,
        SAFE_DIVIDE(
            COUNTIF(is_installment AND is_approved),
            COUNTIF(is_approved)
        ) * 100                                             AS installment_rate_pct

    FROM transactions
    GROUP BY 1, 2
)

SELECT
    summary_date,
    payment_method,
    total_transactions,
    approved_transactions,
    chargeback_transactions,
    ROUND(total_tpv_brl, 2)                                AS total_tpv_brl,
    ROUND(total_mdr_revenue_brl, 2)                        AS total_mdr_revenue_brl,
    ROUND(total_net_amount_brl, 2)                         AS total_net_amount_brl,
    ROUND(avg_ticket_brl, 2)                               AS avg_ticket_brl,
    ROUND(avg_mdr_rate_pct, 4)                             AS avg_mdr_rate_pct,
    ROUND(approval_rate_pct, 2)                            AS approval_rate_pct,
    ROUND(chargeback_rate_pct, 4)                          AS chargeback_rate_pct,
    installment_transactions,
    ROUND(installment_rate_pct, 2)                         AS installment_rate_pct,
    CURRENT_TIMESTAMP()                                     AS _dbt_updated_at

FROM daily_aggregated
