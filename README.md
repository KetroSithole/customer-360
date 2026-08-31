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
    .env.example              template for local connection settings
    requirements.txt          Python dependencies
    README.md
```

## Prerequisites

- Python 3.10+
- SQL Server instance you can log into with Windows authentication
- "ODBC Driver 17 for SQL Server" (or newer - set `MSSQL_DRIVER` accordingly)

## Setup

```bash
# 1. Create and activate a virtual environment
python -m venv .venv
.venv\Scripts\activate        # Windows
# source .venv/bin/activate   # macOS / Linux

# 2. Install dependencies (pandas, pyodbc, python-dotenv, dbt-sqlserver)
pip install -r requirements.txt

# 3. Create your local environment file and edit it for your machine
copy .env.example .env        # Windows
# cp .env.example .env        # macOS / Linux
```

`.env` holds all connection settings and is git-ignored:

| Variable | Purpose | Default |
|---|---|---|
| `MSSQL_SERVER` | SQL Server instance | `GHOST\MSSQLSERVER02` |
| `MSSQL_DATABASE` | Target database | `CaseStudyDB` |
| `MSSQL_DRIVER` | ODBC driver name | `ODBC Driver 17 for SQL Server` |
| `DBT_SCHEMA` | Base schema for dbt models | `analytics` |

The Python scripts load `.env` automatically. dbt reads the same variables
from the shell environment, so either rely on the defaults in
[customer_360_dbt/profiles.yml](customer_360_dbt/profiles.yml) or export them
before running dbt:

```powershell
# PowerShell: load .env into the current session
Get-Content .env | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
  $name, $value = $_ -split '=', 2; [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim())
}
```

## How to run

```bash
# 1. Load the raw CSVs into SQL Server (idempotent - safe to re-run)
python scripts/load_to_sqlserver.py

# 2. Build all models and run all tests
cd customer_360_dbt
dbt build --profiles-dir .

# Optional: run only the models, or only the tests
dbt run --profiles-dir .
dbt test --profiles-dir .

# Optional: one-off data quality profiling of the raw tables
python ../scripts/profile_dq.py
```

When the build finishes, the gold table is at
`CaseStudyDB.marts.customer_360`.

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
