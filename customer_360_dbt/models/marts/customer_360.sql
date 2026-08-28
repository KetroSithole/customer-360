-- Gold-layer Customer 360: one row per customer unifying profile, product
-- holdings, transaction behaviour, CRM engagement, and derived segments.
--
-- Key business logic (see README for rationale):
--   * as_of_date        : max activity date in the data (static extract anchor)
--   * is_active         : any transaction OR CRM interaction in the 90 days
--                         up to as_of_date
--   * lifecycle_stage   : New / Active / At Risk / Dormant
--   * value_segment     : quartiles of lifetime transaction value
--                         (Platinum / Gold / Silver / Bronze)
--   * engagement_level  : CRM interaction intensity in the last 90 days

{{
    config(
        materialized='table',
        post_hook=[
            "create unique nonclustered index ix_customer_360_customer_id on {{ this }} (customer_id)"
        ]
    )
}}

with customers as (
    select * from {{ ref('stg_customers') }}
),

products as (
    select * from {{ ref('int_customer_products') }}
),

transactions as (
    select * from {{ ref('int_customer_transactions') }}
),

interactions as (
    select * from {{ ref('int_customer_interactions') }}
),

reference_date as (
    select as_of_date from {{ ref('int_reference_date') }}
),

joined as (

    select
        -- profile
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email,
        c.mobile,
        c.gender,
        c.date_of_birth,
        datediff(year, c.date_of_birth, r.as_of_date)
            - case when dateadd(year, datediff(year, c.date_of_birth, r.as_of_date), c.date_of_birth) > r.as_of_date
                   then 1 else 0 end                                    as age,
        c.signup_date,
        datediff(month, c.signup_date, r.as_of_date)                    as tenure_months,
        r.as_of_date,

        -- product holdings
        coalesce(p.product_count, 0)                                    as product_count,
        coalesce(p.savings_count, 0)                                    as savings_count,
        coalesce(p.credit_card_count, 0)                                as credit_card_count,
        coalesce(p.has_savings, 0)                                      as has_savings,
        coalesce(p.has_credit_card, 0)                                  as has_credit_card,
        coalesce(p.total_credit_limit, 0)                               as total_credit_limit,
        p.first_enrollment_date,
        p.last_enrollment_date,

        -- transaction metrics
        coalesce(t.transaction_count, 0)                                as transaction_count,
        coalesce(t.total_transaction_value, 0)                          as total_transaction_value,
        coalesce(t.total_inflow, 0)                                     as total_inflow,
        coalesce(t.total_outflow, 0)                                    as total_outflow,
        coalesce(t.avg_transaction_value, 0)                            as avg_transaction_value,
        coalesce(t.current_total_balance, 0)                            as current_total_balance,
        t.first_transaction_date,
        t.last_transaction_date,
        coalesce(t.transactions_last_90d, 0)                            as transactions_last_90d,
        coalesce(t.transaction_value_last_90d, 0)                       as transaction_value_last_90d,

        -- interaction metrics
        coalesce(i.interaction_count, 0)                                as interaction_count,
        coalesce(i.call_count, 0)                                       as call_count,
        coalesce(i.chat_count, 0)                                       as chat_count,
        coalesce(i.email_count, 0)                                      as email_count,
        i.last_interaction_date,
        coalesce(i.interactions_last_90d, 0)                            as interactions_last_90d,

        -- recency
        case
            when t.last_transaction_date is null and i.last_interaction_date is null then null
            when t.last_transaction_date is null then cast(i.last_interaction_date as date)
            when i.last_interaction_date is null then cast(t.last_transaction_date as date)
            when cast(t.last_transaction_date as date) >= i.last_interaction_date
                then cast(t.last_transaction_date as date)
            else i.last_interaction_date
        end                                                             as last_activity_date,

        -- data quality
        c.is_duplicate_email

    from customers c
    cross join reference_date r
    left join products     p on c.customer_id = p.customer_id
    left join transactions t on c.customer_id = t.customer_id
    left join interactions i on c.customer_id = i.customer_id

),

final as (

    select
        j.*,
        datediff(day, j.last_activity_date, j.as_of_date)               as days_since_last_activity,

        -- Active = any transaction or interaction within 90 days of as_of_date
        case when datediff(day, j.last_activity_date, j.as_of_date) <= 90
             then 1 else 0 end                                          as is_active,

        -- Lifecycle stage
        case
            when j.last_activity_date is null                                    then 'Never Active'
            when datediff(month, j.signup_date, j.as_of_date) <= 6               then 'New'
            when datediff(day, j.last_activity_date, j.as_of_date) <= 90         then 'Active'
            when datediff(day, j.last_activity_date, j.as_of_date) <= 180        then 'At Risk'
            else 'Dormant'
        end                                                             as lifecycle_stage,

        -- Value segment: quartiles of lifetime transaction value
        case ntile(4) over (order by j.total_transaction_value desc)
            when 1 then 'Platinum'
            when 2 then 'Gold'
            when 3 then 'Silver'
            else 'Bronze'
        end                                                             as value_segment,

        -- Engagement with CRM channels in the last 90 days
        case
            when j.interactions_last_90d >= 3 then 'Highly Engaged'
            when j.interactions_last_90d >= 1 then 'Engaged'
            when j.interaction_count      >= 1 then 'Previously Engaged'
            else 'Never Engaged'
        end                                                             as engagement_level,

        -- Preferred CRM contact channel (lifetime)
        case
            when j.interaction_count = 0 then 'None'
            when j.chat_count >= j.email_count and j.chat_count >= j.call_count then 'Chat'
            when j.email_count >= j.call_count then 'Email'
            else 'Call'
        end                                                             as preferred_channel,

        -- Cross-sell flag: savings-only customers are credit card prospects
        case when j.has_savings = 1 and j.has_credit_card = 0
             then 1 else 0 end                                          as is_cross_sell_candidate,

        -- Age band for demographic reporting
        case
            when datediff(year, j.date_of_birth, j.as_of_date) < 25 then '18-24'
            when datediff(year, j.date_of_birth, j.as_of_date) < 35 then '25-34'
            when datediff(year, j.date_of_birth, j.as_of_date) < 45 then '35-44'
            when datediff(year, j.date_of_birth, j.as_of_date) < 55 then '45-54'
            else '55+'
        end                                                             as age_band

    from joined j

)

select * from final
