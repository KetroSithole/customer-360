-- Transaction behaviour aggregated per customer.
-- current_total_balance sums the latest closing balance of each product account.

with transactions as (

    select * from {{ ref('stg_transactions') }}

),

reference_date as (

    select as_of_date from {{ ref('int_reference_date') }}

),

per_customer as (

    select
        t.customer_id,
        count(*)                                                     as transaction_count,
        sum(abs(t.transaction_amount))                               as total_transaction_value,
        sum(case when t.transaction_direction = 'inflow'
                 then t.transaction_amount else 0 end)               as total_inflow,
        sum(case when t.transaction_direction = 'outflow'
                 then abs(t.transaction_amount) else 0 end)          as total_outflow,
        avg(abs(t.transaction_amount))                               as avg_transaction_value,
        min(t.transaction_date)                                      as first_transaction_date,
        max(t.transaction_date)                                      as last_transaction_date,
        sum(case when t.transaction_date >= date_add(r.as_of_date, -90)
                 then 1 else 0 end)                                  as transactions_last_90d,
        sum(case when t.transaction_date >= date_add(r.as_of_date, -90)
                 then abs(t.transaction_amount) else 0 end)          as transaction_value_last_90d
    from transactions t
    cross join reference_date r
    group by t.customer_id

),

latest_balance_per_product as (

    select
        customer_id,
        product_id,
        closing_balance,
        row_number() over (
            partition by product_id
            order by transaction_date desc, transaction_id desc
        ) as rn
    from transactions

),

balances as (

    select
        customer_id,
        sum(closing_balance) as current_total_balance
    from latest_balance_per_product
    where rn = 1
    group by customer_id

)

select
    p.*,
    b.current_total_balance
from per_customer p
left join balances b on p.customer_id = b.customer_id
