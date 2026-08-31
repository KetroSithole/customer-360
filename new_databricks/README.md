# Databricks SQL pipeline — Customer 360

Pure SQL port of the dbt project for Databricks / Unity Catalog.
Same layered design, same business logic, same tests — targeting the
`gotyme` catalog. No Python needed: the raw tables are created by the
Databricks **upload UI** into `gotyme.default`, and everything downstream
runs on a SQL warehouse.

## Layout

| Script | What it does |
|---|---|
| `sql/01_staging.sql` | staging views in `gotyme.staging`: email/mobile cleanup, `is_duplicate_email`, `limit` → `credit_limit`, `transaction_direction` |
| `sql/02_intermediate.sql` | per-customer aggregation views in `gotyme.intermediate`, plus the `as_of_date` anchor |
| `sql/03_customer_360.sql` | gold Delta table `gotyme.marts.customer_360` (one row per customer), then `OPTIMIZE ... ZORDER BY (customer_id)` |
| `sql/04_data_quality_checks.sql` | full test suite via `assert_true()` — any failing check raises and fails the job task; the duplicate-email check is warn-only (returns rows, never fails) |

## Schema layout (mirrors the SQL Server schemas)

| SQL Server | Databricks |
|---|---|
| `CaseStudyDB.dbo` (raw) | `gotyme.default` (uploaded CSVs) |
| `CaseStudyDB.staging` | `gotyme.staging` (views) |
| `CaseStudyDB.intermediate` | `gotyme.intermediate` (views) |
| `CaseStudyDB.marts` | `gotyme.marts` (Delta table) |

## One-time setup

1. Upload the four CSVs with **Catalog > Add data > Upload files** (pipe `|`
   delimiter) into `gotyme.default` as: `customer_raw`, `product_enrollments`,
   `crm_interactions`, `transaction_history`.
2. Verify the row counts:

   ```sql
   SELECT 'customer_raw' AS table_name, COUNT(*) AS row_count FROM gotyme.default.customer_raw
   UNION ALL
   SELECT 'product_enrollments', COUNT(*) FROM gotyme.default.product_enrollments
   UNION ALL
   SELECT 'crm_interactions', COUNT(*) FROM gotyme.default.crm_interactions
   UNION ALL
   SELECT 'transaction_history', COUNT(*) FROM gotyme.default.transaction_history;
   ```

## Run it manually (SQL editor)

Paste and run the scripts in order on any SQL warehouse:
`01_staging.sql` → `02_intermediate.sql` → `03_customer_360.sql` → `04_data_quality_checks.sql`.

Then query the result:

```sql
SELECT * FROM gotyme.marts.customer_360;
```

## Automate it (Workflows job with a schedule)

1. Add these files to the workspace: **Workspace > your folder > Import**
   (or sync the repo with Repos).
2. **Jobs & Pipelines > Create > Job**, then add four tasks of type **SQL >
   File**, each pointing at one script and running on your SQL warehouse:

   | Task name | SQL file | Depends on |
   |---|---|---|
   | `staging` | `sql/01_staging.sql` | — |
   | `intermediate` | `sql/02_intermediate.sql` | `staging` |
   | `customer_360` | `sql/03_customer_360.sql` | `intermediate` |
   | `data_quality_checks` | `sql/04_data_quality_checks.sql` | `customer_360` |

3. Add a **Schedule** trigger (e.g. daily at 06:00) and an email notification
   on failure. A failing `assert_true()` in the checks task fails the run, so
   data quality problems surface automatically.

Alternative for quick setups: save each script as a query in the **SQL editor**
and use the query **Schedule** button — but the Workflows job is preferred since
it enforces run order and gives one place to monitor the whole pipeline.

## Notable T-SQL → Spark SQL translations

| T-SQL | Spark SQL |
|---|---|
| `DATEADD(day, -90, d)` | `DATE_SUB(d, 90)` |
| `DATEDIFF(day, a, b)` | `DATEDIFF(b, a)` (argument order flips) |
| `DATEDIFF(month, a, b)` | `(YEAR(b)-YEAR(a))*12 + (MONTH(b)-MONTH(a))` |
| age with birthday adjustment | `FLOOR(MONTHS_BETWEEN(as_of, dob) / 12)` |
| `[limit]` | `` `limit` `` |
| `'+63' + SUBSTRING(...)` | `CONCAT('+63', SUBSTRING(...))` |
| columnstore + nonclustered index | Delta + `OPTIMIZE ... ZORDER BY (customer_id)` |
