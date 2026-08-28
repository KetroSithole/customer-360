-- Databricks ingestion: raw CSVs -> bronze tables in Unity Catalog.
-- Run once in a notebook or the SQL editor after uploading the CSVs to the volume.
--
-- Upload first (from a local terminal with the Databricks CLI):
--   databricks fs cp data/raw/customer_raw.csv          dbfs:/Volumes/casestudy/raw/files/
--   databricks fs cp data/raw/product_enrollments.csv   dbfs:/Volumes/casestudy/raw/files/
--   databricks fs cp data/raw/crm_interactions.csv      dbfs:/Volumes/casestudy/raw/files/
--   databricks fs cp data/raw/transaction_history.csv   dbfs:/Volumes/casestudy/raw/files/

CREATE CATALOG IF NOT EXISTS casestudy;
CREATE SCHEMA IF NOT EXISTS casestudy.raw;
CREATE VOLUME IF NOT EXISTS casestudy.raw.files;

CREATE OR REPLACE TABLE casestudy.raw.customer_raw AS
SELECT
    CAST(customer_id AS INT)      AS customer_id,
    first_name,
    last_name,
    email,
    mobile,
    gender,
    CAST(date_of_birth AS DATE)   AS date_of_birth,
    CAST(signup_date AS DATE)     AS signup_date
FROM read_files(
    '/Volumes/casestudy/raw/files/customer_raw.csv',
    format => 'csv', sep => '|', header => true,
    schemaHints => 'mobile string'  -- keep leading zeros
);

CREATE OR REPLACE TABLE casestudy.raw.product_enrollments AS
SELECT
    CAST(product_id AS INT)             AS product_id,
    CAST(customer_id AS INT)            AS customer_id,
    product_type,
    CAST(enrollment_date AS DATE)       AS enrollment_date,
    CAST(`limit` AS DECIMAL(18, 2))     AS `limit`
FROM read_files(
    '/Volumes/casestudy/raw/files/product_enrollments.csv',
    format => 'csv', sep => '|', header => true
);

CREATE OR REPLACE TABLE casestudy.raw.crm_interactions AS
SELECT
    CAST(interaction_id AS INT)         AS interaction_id,
    CAST(customer_id AS INT)            AS customer_id,
    interaction_type,
    CAST(interaction_date AS DATE)      AS interaction_date
FROM read_files(
    '/Volumes/casestudy/raw/files/crm_interactions.csv',
    format => 'csv', sep => '|', header => true
);

CREATE OR REPLACE TABLE casestudy.raw.transaction_history AS
SELECT
    CAST(transaction_id AS INT)                 AS transaction_id,
    CAST(product_id AS INT)                     AS product_id,
    CAST(customer_id AS INT)                    AS customer_id,
    CAST(transaction_amount AS DECIMAL(18, 2))  AS transaction_amount,
    CAST(closing_balance AS DECIMAL(18, 2))     AS closing_balance,
    CAST(transaction_date AS TIMESTAMP)         AS transaction_date
FROM read_files(
    '/Volumes/casestudy/raw/files/transaction_history.csv',
    format => 'csv', sep => '|', header => true
);
