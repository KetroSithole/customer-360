-- 01 — Staging layer (pure SQL, runs on a SQL warehouse)
-- Source tables were created by the Databricks upload UI in gotyme.default.

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
