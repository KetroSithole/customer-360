-- 02 — Intermediate layer (pure SQL, runs on a SQL warehouse)
-- Per-customer aggregations, one topic each.

CREATE SCHEMA IF NOT EXISTS gotyme.intermediate;

-- Anchor for all recency logic: latest activity date in the data,
-- not CURRENT_DATE(), so results stay stable for a static extract.
CREATE OR REPLACE VIEW gotyme.intermediate.int_reference_date AS
SELECT CAST(MAX(activity_date) AS DATE) AS as_of_date
FROM (
    SELECT MAX(transaction_date) AS activity_date FROM gotyme.staging.stg_transactions
    UNION ALL
    SELECT CAST(MAX(interaction_date) AS TIMESTAMP) FROM gotyme.staging.stg_crm_interactions
) activity;

-- Product holdings per customer.
CREATE OR REPLACE VIEW gotyme.intermediate.int_customer_products AS
SELECT
    customer_id,
    COUNT(*)                                                                  AS product_count,
    SUM(CASE WHEN product_type = 'Savings' THEN 1 ELSE 0 END)                 AS savings_count,
    SUM(CASE WHEN product_type = 'Credit Card' THEN 1 ELSE 0 END)             AS credit_card_count,
    MAX(CASE WHEN product_type = 'Savings' THEN 1 ELSE 0 END)                 AS has_savings,
    MAX(CASE WHEN product_type = 'Credit Card' THEN 1 ELSE 0 END)             AS has_credit_card,
    SUM(CASE WHEN product_type = 'Credit Card' THEN credit_limit ELSE 0 END)  AS total_credit_limit,
    MIN(enrollment_date)                                                      AS first_enrollment_date,
    MAX(enrollment_date)                                                      AS last_enrollment_date
FROM gotyme.staging.stg_product_enrollments
GROUP BY customer_id;

-- Transaction behaviour per customer.
-- current_total_balance sums the latest closing balance of each product account.
CREATE OR REPLACE VIEW gotyme.intermediate.int_customer_transactions AS
WITH transactions AS (
    SELECT * FROM gotyme.staging.stg_transactions
),
reference_date AS (
    SELECT as_of_date FROM gotyme.intermediate.int_reference_date
),
per_customer AS (
    SELECT
        t.customer_id,
        COUNT(*)                                                       AS transaction_count,
        SUM(ABS(t.transaction_amount))                                 AS total_transaction_value,
        SUM(CASE WHEN t.transaction_direction = 'inflow'
                 THEN t.transaction_amount ELSE 0 END)                 AS total_inflow,
        SUM(CASE WHEN t.transaction_direction = 'outflow'
                 THEN ABS(t.transaction_amount) ELSE 0 END)            AS total_outflow,
        AVG(ABS(t.transaction_amount))                                 AS avg_transaction_value,
        MIN(t.transaction_date)                                        AS first_transaction_date,
        MAX(t.transaction_date)                                        AS last_transaction_date,
        SUM(CASE WHEN t.transaction_date >= DATE_SUB(r.as_of_date, 90)
                 THEN 1 ELSE 0 END)                                    AS transactions_last_90d,
        SUM(CASE WHEN t.transaction_date >= DATE_SUB(r.as_of_date, 90)
                 THEN ABS(t.transaction_amount) ELSE 0 END)            AS transaction_value_last_90d
    FROM transactions t
    CROSS JOIN reference_date r
    GROUP BY t.customer_id
),
latest_balance_per_product AS (
    SELECT
        customer_id,
        product_id,
        closing_balance,
        ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY transaction_date DESC, transaction_id DESC
        ) AS rn
    FROM transactions
),
balances AS (
    SELECT
        customer_id,
        SUM(closing_balance) AS current_total_balance
    FROM latest_balance_per_product
    WHERE rn = 1
    GROUP BY customer_id
)
SELECT
    p.*,
    b.current_total_balance
FROM per_customer p
LEFT JOIN balances b ON p.customer_id = b.customer_id;

-- CRM engagement per customer.
CREATE OR REPLACE VIEW gotyme.intermediate.int_customer_interactions AS
SELECT
    i.customer_id,
    COUNT(*)                                                       AS interaction_count,
    SUM(CASE WHEN i.interaction_type = 'Call'  THEN 1 ELSE 0 END)  AS call_count,
    SUM(CASE WHEN i.interaction_type = 'Chat'  THEN 1 ELSE 0 END)  AS chat_count,
    SUM(CASE WHEN i.interaction_type = 'Email' THEN 1 ELSE 0 END)  AS email_count,
    MAX(i.interaction_date)                                        AS last_interaction_date,
    SUM(CASE WHEN i.interaction_date >= DATE_SUB(r.as_of_date, 90)
             THEN 1 ELSE 0 END)                                    AS interactions_last_90d
FROM gotyme.staging.stg_crm_interactions i
CROSS JOIN gotyme.intermediate.int_reference_date r
GROUP BY i.customer_id;
