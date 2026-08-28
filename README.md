# Customer 360 Data Mart

A unified view of customer behaviour across savings and credit card products.
Built on SQL Server with dbt, using a simple layered approach:
raw -> staging -> intermediate -> gold.

## Documentation

- [docs/data_model.md](docs/data_model.md) - model design, layers, lineage diagram
- [docs/business_logic.md](docs/business_logic.md) - metric definitions and the reasoning behind them
- [docs/data_quality.md](docs/data_quality.md) - issues found, test coverage, recommendations
- [customer_360_dbt/README.md](customer_360_dbt/README.md) - dbt project notes

## Folder structure

```
Case_study_data/
    data/
        raw/                  source CSV files (pipe-delimited)
        excel/                Excel copies of the raw data
    scripts/
        load_to_sqlserver.py  loads the CSVs into CaseStudyDB
        profile_dq.py         one-off data quality profiling
    customer_360_dbt/         dbt project (models, tests)
    docs/
        data_model.md         model design and lineage
        business_logic.md     metric definitions and why they exist
        data_quality.md       issues found and test coverage
    README.md
```

## How to run

This branch targets Databricks. The main branch targets SQL Server.

```bash
# 1. Upload the CSVs and create the bronze tables
#    (run scripts/databricks_ingest.sql in the Databricks SQL editor)

# 2. Set connection details
export DATABRICKS_HOST=adb-xxxx.azuredatabricks.net
export DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/xxxx
export DATABRICKS_TOKEN=xxxx

# 3. Build all models and run all tests
pip install dbt-databricks
cd customer_360_dbt
dbt build --profiles-dir .
```

Environment: Unity Catalog `casestudy`, schemas `raw`, `staging`,
`intermediate` and `marts`.

## Deliverables

| Deliverable | Where |
|---|---|
| customer_360 gold table | CaseStudyDB.marts.customer_360 |
| dbt models | [customer_360_dbt/models](customer_360_dbt/models) |
| dbt tests (62 checks) | model YAML files and [customer_360_dbt/tests](customer_360_dbt/tests) |
| Data model and lineage | [docs/data_model.md](docs/data_model.md) |
| Business logic | [docs/business_logic.md](docs/business_logic.md) |
| Data quality report | [docs/data_quality.md](docs/data_quality.md) |

## Source data

| Table | Rows | What it is |
|---|---|---|
| customer_raw | 100,000 | customer master (profile, contact, signup) |
| product_enrollments | 140,089 | product holdings: Savings, Credit Card |
| crm_interactions | 243,725 | call, chat and email interactions |
| transaction_history | 886,971 | transactions per product account |

The data covers 2023-01 to 2025-07. All recency logic is measured against the
latest activity date in the data (called as_of_date), not the current date.
See [docs/business_logic.md](docs/business_logic.md) for why.

## Build status

Latest dbt build: 61 pass, 1 warn, 0 errors out of 62 checks.
The warning is expected: 3 email addresses are shared by more than one
customer record. This is flagged on purpose instead of failing the build.
