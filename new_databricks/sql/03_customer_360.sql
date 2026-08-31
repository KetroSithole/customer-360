-- 03 — Gold layer: customer_360 (pure SQL, runs on a SQL warehouse)
-- One row per customer unifying profile, product holdings, transaction
-- behaviour, CRM engagement, and derived segments.

CREATE SCHEMA IF NOT EXISTS gotyme.marts;

CREATE OR REPLACE TABLE gotyme.marts.customer_360 AS
WITH customers AS (
    SELECT * FROM gotyme.staging.stg_customers
),
products AS (
    SELECT * FROM gotyme.intermediate.int_customer_products
),
transactions AS (
    SELECT * FROM gotyme.intermediate.int_customer_transactions
),
interactions AS (
    SELECT * FROM gotyme.intermediate.int_customer_interactions
),
reference_date AS (
    SELECT as_of_date FROM gotyme.intermediate.int_reference_date
),

joined AS (
    SELECT
        -- profile
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email,
        c.mobile,
        c.gender,
        c.date_of_birth,
        CAST(FLOOR(MONTHS_BETWEEN(r.as_of_date, c.date_of_birth) / 12) AS INT)  AS age,
        c.signup_date,
        (YEAR(r.as_of_date) - YEAR(c.signup_date)) * 12
            + (MONTH(r.as_of_date) - MONTH(c.signup_date))                      AS tenure_months,
        r.as_of_date,

        -- product holdings
        COALESCE(p.product_count, 0)                                    AS product_count,
        COALESCE(p.savings_count, 0)                                    AS savings_count,
        COALESCE(p.credit_card_count, 0)                                AS credit_card_count,
        COALESCE(p.has_savings, 0)                                      AS has_savings,
        COALESCE(p.has_credit_card, 0)                                  AS has_credit_card,
        COALESCE(p.total_credit_limit, 0)                               AS total_credit_limit,
        p.first_enrollment_date,
        p.last_enrollment_date,

        -- transaction metrics
        COALESCE(t.transaction_count, 0)                                AS transaction_count,
        COALESCE(t.total_transaction_value, 0)                          AS total_transaction_value,
        COALESCE(t.total_inflow, 0)                                     AS total_inflow,
        COALESCE(t.total_outflow, 0)                                    AS total_outflow,
        COALESCE(t.avg_transaction_value, 0)                            AS avg_transaction_value,
        COALESCE(t.current_total_balance, 0)                            AS current_total_balance,
        t.first_transaction_date,
        t.last_transaction_date,
        COALESCE(t.transactions_last_90d, 0)                            AS transactions_last_90d,
        COALESCE(t.transaction_value_last_90d, 0)                       AS transaction_value_last_90d,

        -- interaction metrics
        COALESCE(i.interaction_count, 0)                                AS interaction_count,
        COALESCE(i.call_count, 0)                                       AS call_count,
        COALESCE(i.chat_count, 0)                                       AS chat_count,
        COALESCE(i.email_count, 0)                                      AS email_count,
        i.last_interaction_date,
        COALESCE(i.interactions_last_90d, 0)                            AS interactions_last_90d,

        -- recency
        CASE
            WHEN t.last_transaction_date IS NULL AND i.last_interaction_date IS NULL THEN NULL
            WHEN t.last_transaction_date IS NULL THEN CAST(i.last_interaction_date AS DATE)
            WHEN i.last_interaction_date IS NULL THEN CAST(t.last_transaction_date AS DATE)
            WHEN CAST(t.last_transaction_date AS DATE) >= i.last_interaction_date
                THEN CAST(t.last_transaction_date AS DATE)
            ELSE i.last_interaction_date
        END                                                             AS last_activity_date,

        -- data quality
        c.is_duplicate_email

    FROM customers c
    CROSS JOIN reference_date r
    LEFT JOIN products     p ON c.customer_id = p.customer_id
    LEFT JOIN transactions t ON c.customer_id = t.customer_id
    LEFT JOIN interactions i ON c.customer_id = i.customer_id
),

final AS (
    SELECT
        j.*,
        DATEDIFF(j.as_of_date, j.last_activity_date)                    AS days_since_last_activity,

        -- Active = any transaction or interaction within 90 days of as_of_date
        CASE WHEN DATEDIFF(j.as_of_date, j.last_activity_date) <= 90
             THEN 1 ELSE 0 END                                          AS is_active,

        -- Lifecycle stage
        CASE
            WHEN j.last_activity_date IS NULL                           THEN 'Never Active'
            WHEN j.tenure_months <= 6                                   THEN 'New'
            WHEN DATEDIFF(j.as_of_date, j.last_activity_date) <= 90     THEN 'Active'
            WHEN DATEDIFF(j.as_of_date, j.last_activity_date) <= 180    THEN 'At Risk'
            ELSE 'Dormant'
        END                                                             AS lifecycle_stage,

        -- Value segment: quartiles of lifetime transaction value
        CASE NTILE(4) OVER (ORDER BY j.total_transaction_value DESC)
            WHEN 1 THEN 'Platinum'
            WHEN 2 THEN 'Gold'
            WHEN 3 THEN 'Silver'
            ELSE 'Bronze'
        END                                                             AS value_segment,

        -- Engagement with CRM channels in the last 90 days
        CASE
            WHEN j.interactions_last_90d >= 3 THEN 'Highly Engaged'
            WHEN j.interactions_last_90d >= 1 THEN 'Engaged'
            WHEN j.interaction_count     >= 1 THEN 'Previously Engaged'
            ELSE 'Never Engaged'
        END                                                             AS engagement_level,

        -- Preferred CRM contact channel (lifetime)
        CASE
            WHEN j.interaction_count = 0 THEN 'None'
            WHEN j.chat_count >= j.email_count AND j.chat_count >= j.call_count THEN 'Chat'
            WHEN j.email_count >= j.call_count THEN 'Email'
            ELSE 'Call'
        END                                                             AS preferred_channel,

        -- Cross-sell flag: savings-only customers are credit card prospects
        CASE WHEN j.has_savings = 1 AND j.has_credit_card = 0
             THEN 1 ELSE 0 END                                          AS is_cross_sell_candidate,

        -- Age band for demographic reporting
        CASE
            WHEN YEAR(j.as_of_date) - YEAR(j.date_of_birth) < 25 THEN '18-24'
            WHEN YEAR(j.as_of_date) - YEAR(j.date_of_birth) < 35 THEN '25-34'
            WHEN YEAR(j.as_of_date) - YEAR(j.date_of_birth) < 45 THEN '35-44'
            WHEN YEAR(j.as_of_date) - YEAR(j.date_of_birth) < 55 THEN '45-54'
            ELSE '55+'
        END                                                             AS age_band

    FROM joined j
)

SELECT * FROM final;

-- Delta optimizations (replaces the SQL Server columnstore + index post-hook)
OPTIMIZE gotyme.marts.customer_360 ZORDER BY (customer_id);
ANALYZE TABLE gotyme.marts.customer_360 COMPUTE STATISTICS;
