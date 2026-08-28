# Business Logic

This file explains every metric in customer_360 and the reasoning behind it.

## The anchor date (as_of_date)

All recency logic is measured against as_of_date, which is the most recent
transaction or interaction date in the data (2025-07-09). It is not the
current date.

Why: this is a static extract. If we used GETDATE(), every customer would
slowly become "dormant" as the extract ages, and results would change from
one day to the next without the data changing. With a live feed the anchor
would naturally become today.

## Required metrics

### Active customer (is_active)

A customer is active when they have any transaction or CRM interaction
within 90 days of as_of_date.

Why:
- Transactions alone undercount engagement. A customer who contacts the bank
  every month but only transacts quarterly is clearly not lost.
- 90 days lines up with a quarterly banking cycle. It is long enough to allow
  normal gaps between salary cycles, and short enough to still act before
  real churn.

### Product holdings

Aggregated per customer: product_count, savings_count, credit_card_count,
has_savings, has_credit_card and total_credit_limit. The flags make BI
filtering easy, the counts support cross-holding analysis.

### Last interaction date and total transaction value

- last_interaction_date: most recent CRM touchpoint.
- total_transaction_value: lifetime sum of absolute transaction amounts.
  Absolute values measure activity volume. A signed sum would let deposits
  cancel out spending and make heavy users look inactive. The signed detail
  is still available as total_inflow and total_outflow.

## Additional metrics and dimensions

| Column | Definition | Why it is useful |
|---|---|---|
| lifecycle_stage | New (6 months or less tenure) / Active (last 90 days) / At Risk (91-180 days) / Dormant (over 180 days) / Never Active | Retention targeting. "At Risk" is the window where outreach still works |
| value_segment | Quartiles of lifetime transaction value: Platinum / Gold / Silver / Bronze | Relative ranking needs no hand-tuned thresholds and finds the top 25% who drive most revenue |
| engagement_level | Highly Engaged (3+ interactions in 90 days) / Engaged (1-2) / Previously Engaged / Never Engaged | Separates service-heavy customers from silent ones |
| preferred_channel | Most used CRM channel over lifetime (Chat / Email / Call) | Contact customers on the channel they actually use |
| is_cross_sell_candidate | Has savings but no credit card | Ready-made marketing list. About 60% of the base holds no credit card |
| current_total_balance | Sum of each product's latest closing balance | Point-in-time book value without scanning history |
| transactions_last_90d, transaction_value_last_90d | Recent activity | Compare recent vs lifetime behaviour, feeds RFM analysis |
| days_since_last_activity | Recency in days | Sortable churn-risk indicator |
| age, age_band, tenure_months, gender | Demographics | Standard reporting cuts without re-deriving buckets in every BI tool |
| total_inflow, total_outflow | Signed transaction flows | Net flow analysis, deposit vs spend behaviour |
| avg_transaction_value | Average absolute ticket size | Tells many-small transactors apart from few-large ones |
| is_duplicate_email | Data quality flag | Marketing dedup and KYC follow-up without blocking the pipeline |

## Thresholds

| Rule | Threshold | Reason |
|---|---|---|
| Active | 90 days | quarterly banking cycle |
| At Risk | 91-180 days | re-engagement window |
| Dormant | over 180 days | common dormancy cut-off |
| New | 6 months tenure or less | onboarding period, judged separately |
| Highly Engaged | 3+ interactions in 90 days | roughly monthly contact |

All thresholds live in one place (the customer_360 model) so they are easy
to review with the business and change later.
