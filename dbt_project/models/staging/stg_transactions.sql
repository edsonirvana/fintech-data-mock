-- models/staging/stg_transactions.sql
-- Limpeza e padronização das transações brutas
-- Materializado como VIEW para evitar duplicação de dados

WITH source AS (
    SELECT * FROM {{ source('raw', 'transactions') }}
),

cleaned AS (
    SELECT
        -- Identidades
        TRIM(transaction_id)                        AS transaction_id,
        TRIM(merchant_id)                           AS merchant_id,
        TRIM(customer_id)                           AS customer_id,
        TRIM(authorization_code)                    AS authorization_code,
        LOWER(TRIM(acquirer))                       AS acquirer,

        -- Valores financeiros com cast explícito
        CAST(amount_brl AS NUMERIC)                 AS amount_brl,
        CAST(mdr_rate_pct AS NUMERIC)               AS mdr_rate_pct,
        CAST(mdr_amount_brl AS NUMERIC)             AS mdr_amount_brl,
        CAST(net_amount_brl AS NUMERIC)             AS net_amount_brl,

        -- Datas
        CAST(transaction_date AS DATE)              AS transaction_date,
        CAST(transaction_ts AS TIMESTAMP)           AS transaction_ts,

        -- Atributos categóricos padronizados
        LOWER(TRIM(payment_method))                 AS payment_method,
        LOWER(TRIM(status))                         AS status,
        CAST(installments AS INT64)                 AS installments,

        -- Flags derivadas
        status = 'approved'                         AS is_approved,
        status = 'chargeback'                       AS is_chargeback,
        installments > 1                            AS is_installment,
        EXTRACT(DAYOFWEEK FROM CAST(transaction_date AS DATE)) IN (1, 7)
                                                    AS is_weekend,

        -- Metadados de ingestão
        CURRENT_TIMESTAMP()                         AS _dbt_updated_at

    FROM source
    WHERE
        transaction_id IS NOT NULL
        AND amount_brl > 0
        AND transaction_date IS NOT NULL
)

SELECT * FROM cleaned
