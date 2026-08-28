# Data Quality

## Profiling findings

The raw dbo tables were profiled with
[../scripts/profile_dq.py](../scripts/profile_dq.py).

### Issues found

| # | Issue | Extent | Severity | Handling |
|---|---|---|---|---|
| 1 | Same email used by different customer_ids | 3 emails, 6+ records | Medium | Flagged as is_duplicate_email in staging and customer_360. The dbt test warns instead of failing. Probably duplicate registrations; needs KYC review before merging records. |
| 2 | Mixed mobile formats: 49,971 local (09) vs 50,029 international (+639) | half of all customers | Medium | Standardized to +63 in stg_customers, enforced by the assert_mobile_standardized test. |
| 3 | Data ends 2025-07 but today is later | whole extract | Design risk | All recency logic anchored to as_of_date from the data, not GETDATE(). |
| 4 | Column named limit, a T-SQL reserved word | 1 column | Low | Renamed to credit_limit in staging. |
| 5 | Transaction sign convention is implicit (negative = outflow) | all transactions | Low | Made explicit with a derived transaction_direction column. |

### Checked and found clean

- no duplicate primary keys in any source table
- no null, empty or malformed emails, no null names
- no orphaned foreign keys anywhere
- no transaction whose customer_id contradicts the product owner
- no future-dated records, no impossible dates of birth
- no enrollments before customer signup, no negative credit limits
- every customer holds at least one product

## dbt test coverage (62 checks)

### Generic tests (in the model YAML files)

| Test | Applied to |
|---|---|
| unique + not_null | every primary key at every layer |
| relationships | all source foreign keys (customer_id, product_id) |
| accepted_values | gender, product_type, interaction_type, transaction_direction, and every derived segment |

### Singular tests (in [../customer_360_dbt/tests](../customer_360_dbt/tests))

| Test | Checks that | Severity |
|---|---|---|
| assert_customer_360_covers_all_customers | the gold table covers every source customer | error |
| assert_no_duplicate_customer_emails | duplicate-customer suspects get surfaced | warn |
| assert_transactions_match_enrollment_owner | transaction customer = product owner | error |
| assert_no_future_dates | no future-dated activity anywhere | error |
| assert_mobile_standardized | every mobile is +63 format, 13 chars | error |
| assert_enrollment_not_before_signup | enrollment dates are chronologically valid | error |

### Latest results

```
dbt build: 61 pass, 1 warn, 0 errors (62 checks)
```

The single warning is issue #1 (duplicate emails). It is a warning on purpose
so the pipeline stays green while the issue stays visible in every run log.

## Recommendations

1. Duplicate customers: review the 3 shared emails with KYC and decide on a
   merge rule or a golden_customer_id mapping.
2. Mobile capture: fix at the source system, enforce one format at entry.
3. Monitoring: schedule dbt build so test failures surface daily, and add
   source freshness checks once the feed becomes incremental.
