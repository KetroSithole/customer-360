# Customer 360 Data Mart

A unified view of customer behaviour across savings and credit card products.
Built on SQL Server with dbt, using a simple layered approach:
raw -> staging -> intermediate -> gold.

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

```bash
# 1. Load the raw CSVs into SQL Server (safe to re-run)
python scripts/load_to_sqlserver.py

# 2. Build all models and run all tests
cd customer_360_dbt
dbt build --profiles-dir .
```

Environment: server `GHOST\MSSQLSERVER02`, database `CaseStudyDB`,
Windows authentication, ODBC Driver 17.

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
