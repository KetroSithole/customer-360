-- =====================================================================
-- Customer 360 — full pipeline in one script
-- Paste into the Databricks SQL editor (or add as a single SQL File task)
-- and run on any SQL warehouse. Prerequisite: the four CSVs uploaded via
-- the Catalog upload UI into gotyme.default as customer_raw,
-- product_enrollments, crm_interactions, transaction_history.
--
-- Order: staging views -> intermediate views -> gold table -> quality checks.
-- Any failing assert_true() aborts the run with a named error message.
-- =====================================================================


-- =====================================================================
-- 1. STAGING — one view per source: cleaning, renaming, typing
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS gotyme.staging;

-- Cleansed customer master: email lower-cased/trimmed, mobile standardized
-- to +63, duplicate-email flag for potential duplicate customer records.
CREATE OR REPLACE VIEW gotyme.staging.stg_customers AS
WITH cleaned AS (
    SELECT
        customer_id,
        TRIM(first_name)                        AS first_name,
        TRIM(last_name)                         AS last_name,
        LOWER(TRIM(email))                      AS email,
        CASE
            WHEN mobile LIKE '0%'   THEN CONCAT('+63', SUBSTRING(mobile, 2))
            WHEN mobile LIKE '+63%' THEN mobile
            ELSE mobile
        END                                     AS mobile,
        gender,
        date_of_birth,
        signup_date
    FROM gotyme.default.customer_raw
)
SELECT
    c.*,
    CASE WHEN dup.email IS NOT NULL THEN 1 ELSE 0 END AS is_duplicate_email
FROM cleaned c
LEFT JOIN (
    SELECT email
    FROM cleaned
    GROUP BY email
    HAVING COUNT(*) > 1
) dup ON c.email = dup.email;

-- `limit` renamed to credit_limit (reserved word; only meaningful for credit cards).
CREATE OR REPLACE VIEW gotyme.staging.stg_product_enrollments AS
SELECT
    product_id,
    customer_id,
    product_type,
    enrollment_date,
    `limit` AS credit_limit
FROM gotyme.default.product_enrollments;

CREATE OR REPLACE VIEW gotyme.staging.stg_crm_interactions AS
SELECT
    interaction_id,
    customer_id,
    interaction_type,
    interaction_date
FROM gotyme.default.crm_interactions;

-- Derived direction flag: negative amounts are outflows.
CREATE OR REPLACE VIEW gotyme.staging.stg_transactions AS
SELECT
    transaction_id,
    product_id,
    customer_id,
    transaction_amount,
    closing_balance,
    transaction_date,
    CASE WHEN transaction_amount < 0 THEN 'outflow' ELSE 'inflow' END AS transaction_direction
FROM gotyme.default.transaction_history;


-- =====================================================================
-- 2. INTERMEDIATE — per-customer aggregations, one topic each
-- =====================================================================

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


-- =====================================================================
-- 3. GOLD — customer_360: one row per customer, BI-ready Delta table
-- =====================================================================

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


-- =====================================================================
-- 4. DATA QUALITY CHECKS — a failing assert_true() aborts the run
-- =====================================================================

-- ---------- unique + not_null on every primary key ----------
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_customers WHERE customer_id IS NULL) = 0,
    'not_null failed: stg_customers.customer_id');
SELECT assert_true(
    (SELECT COUNT(*) FROM (SELECT customer_id FROM gotyme.staging.stg_customers
     GROUP BY customer_id HAVING COUNT(*) > 1)) = 0,
    'unique failed: stg_customers.customer_id');

SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_product_enrollments WHERE product_id IS NULL) = 0,
    'not_null failed: stg_product_enrollments.product_id');
SELECT assert_true(
    (SELECT COUNT(*) FROM (SELECT product_id FROM gotyme.staging.stg_product_enrollments
     GROUP BY product_id HAVING COUNT(*) > 1)) = 0,
    'unique failed: stg_product_enrollments.product_id');

SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_crm_interactions WHERE interaction_id IS NULL) = 0,
    'not_null failed: stg_crm_interactions.interaction_id');
SELECT assert_true(
    (SELECT COUNT(*) FROM (SELECT interaction_id FROM gotyme.staging.stg_crm_interactions
     GROUP BY interaction_id HAVING COUNT(*) > 1)) = 0,
    'unique failed: stg_crm_interactions.interaction_id');

SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_transactions WHERE transaction_id IS NULL) = 0,
    'not_null failed: stg_transactions.transaction_id');
SELECT assert_true(
    (SELECT COUNT(*) FROM (SELECT transaction_id FROM gotyme.staging.stg_transactions
     GROUP BY transaction_id HAVING COUNT(*) > 1)) = 0,
    'unique failed: stg_transactions.transaction_id');

SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.marts.customer_360 WHERE customer_id IS NULL) = 0,
    'not_null failed: customer_360.customer_id');
SELECT assert_true(
    (SELECT COUNT(*) FROM (SELECT customer_id FROM gotyme.marts.customer_360
     GROUP BY customer_id HAVING COUNT(*) > 1)) = 0,
    'unique failed: customer_360.customer_id');

-- ---------- relationships (foreign keys) ----------
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_product_enrollments e
     LEFT JOIN gotyme.staging.stg_customers c ON e.customer_id = c.customer_id
     WHERE c.customer_id IS NULL) = 0,
    'fk failed: enrollments.customer_id -> customers');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_crm_interactions i
     LEFT JOIN gotyme.staging.stg_customers c ON i.customer_id = c.customer_id
     WHERE c.customer_id IS NULL) = 0,
    'fk failed: interactions.customer_id -> customers');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_transactions t
     LEFT JOIN gotyme.staging.stg_customers c ON t.customer_id = c.customer_id
     WHERE c.customer_id IS NULL) = 0,
    'fk failed: transactions.customer_id -> customers');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_transactions t
     LEFT JOIN gotyme.staging.stg_product_enrollments p ON t.product_id = p.product_id
     WHERE p.product_id IS NULL) = 0,
    'fk failed: transactions.product_id -> enrollments');

-- ---------- accepted_values ----------
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_customers
     WHERE gender NOT IN ('Male', 'Female', 'Other')) = 0,
    'accepted_values failed: stg_customers.gender');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_product_enrollments
     WHERE product_type NOT IN ('Savings', 'Credit Card')) = 0,
    'accepted_values failed: stg_product_enrollments.product_type');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_crm_interactions
     WHERE interaction_type NOT IN ('Call', 'Chat', 'Email')) = 0,
    'accepted_values failed: stg_crm_interactions.interaction_type');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_transactions
     WHERE transaction_direction NOT IN ('inflow', 'outflow')) = 0,
    'accepted_values failed: stg_transactions.transaction_direction');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.marts.customer_360
     WHERE lifecycle_stage NOT IN ('New', 'Active', 'At Risk', 'Dormant', 'Never Active')) = 0,
    'accepted_values failed: customer_360.lifecycle_stage');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.marts.customer_360
     WHERE value_segment NOT IN ('Platinum', 'Gold', 'Silver', 'Bronze')) = 0,
    'accepted_values failed: customer_360.value_segment');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.marts.customer_360
     WHERE engagement_level NOT IN ('Highly Engaged', 'Engaged', 'Previously Engaged', 'Never Engaged')) = 0,
    'accepted_values failed: customer_360.engagement_level');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.marts.customer_360
     WHERE preferred_channel NOT IN ('Chat', 'Email', 'Call', 'None')) = 0,
    'accepted_values failed: customer_360.preferred_channel');
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.marts.customer_360
     WHERE age_band NOT IN ('18-24', '25-34', '35-44', '45-54', '55+')) = 0,
    'accepted_values failed: customer_360.age_band');

-- ---------- singular tests ----------
SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_customers c
     LEFT JOIN gotyme.marts.customer_360 g ON c.customer_id = g.customer_id
     WHERE g.customer_id IS NULL) = 0,
    'singular failed: customer_360 does not cover all customers');

SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_transactions t
     JOIN gotyme.staging.stg_product_enrollments p ON t.product_id = p.product_id
     WHERE t.customer_id <> p.customer_id) = 0,
    'singular failed: transaction customer does not match enrollment owner');

SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_transactions t
     CROSS JOIN gotyme.intermediate.int_reference_date r
     WHERE CAST(t.transaction_date AS DATE) > r.as_of_date) +
    (SELECT COUNT(*) FROM gotyme.staging.stg_crm_interactions i
     CROSS JOIN gotyme.intermediate.int_reference_date r
     WHERE i.interaction_date > r.as_of_date) = 0,
    'singular failed: future-dated activity found');

SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_customers
     WHERE mobile NOT LIKE '+63%' OR LENGTH(mobile) <> 13) = 0,
    'singular failed: mobile not standardized to +63 / 13 chars');

SELECT assert_true(
    (SELECT COUNT(*) FROM gotyme.staging.stg_product_enrollments e
     JOIN gotyme.staging.stg_customers c ON e.customer_id = c.customer_id
     WHERE e.enrollment_date < c.signup_date) = 0,
    'singular failed: enrollment before customer signup');

-- ---------- warn-only: duplicate customer emails ----------
-- Expected to return 3 rows; surfaced in the output, never fails the run.
SELECT email, COUNT(*) AS customers
FROM gotyme.staging.stg_customers
GROUP BY email
HAVING COUNT(*) > 1
ORDER BY customers DESC;


-- =====================================================================
-- 5. DONE — final summary
-- =====================================================================

SELECT
    lifecycle_stage,
    value_segment,
    COUNT(*) AS customers
FROM gotyme.marts.customer_360
GROUP BY lifecycle_stage, value_segment
ORDER BY lifecycle_stage, value_segment;
