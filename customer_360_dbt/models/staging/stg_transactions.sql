-- Cleansed transactions with a derived direction flag.
-- Negative amounts are outflows (debits), positive amounts are inflows (credits).

select
    transaction_id,
    product_id,
    customer_id,
    transaction_amount,
    closing_balance,
    transaction_date,
    case when transaction_amount < 0 then 'outflow' else 'inflow' end as transaction_direction
from {{ source('raw', 'transaction_history') }}
