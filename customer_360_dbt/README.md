# customer_360 dbt project

dbt project that builds the gold-layer `customer_360` table in
`CaseStudyDB` on `GHOST\MSSQLSERVER02`.

## Layout

```
customer_360_dbt/
├── dbt_project.yml          # Project config: layer schemas + materializations
├── profiles.yml             # Connection (Windows auth, ODBC Driver 17)
├── macros/
│   └── generate_schema_name.sql   # Use schema names as-is (staging/intermediate/marts)
├── models/
│   ├── sources.yml          # Raw dbo tables + source tests
│   ├── staging/             # Cleansed 1:1 views  (schema: staging)
│   ├── intermediate/        # Per-customer aggregates (schema: intermediate)
│   └── marts/
│       ├── customer_360.sql # Gold table (schema: marts)
│       └── customer_360.yml # Column docs + tests
└── tests/                   # Singular data quality tests
```

## Commands

```bash
dbt debug --profiles-dir .    # verify connection
dbt build --profiles-dir .    # run all models + all tests
dbt test  --profiles-dir .    # tests only
dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .   # docs site + lineage graph
```

Full design, lineage, business logic, and data quality documentation lives in
[../docs](../docs).
