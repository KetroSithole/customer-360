-- customer_360 must contain exactly one row for every source customer.
-- Returns rows (fails) when a customer is missing or duplicated.

select c.customer_id
from {{ source('raw', 'customer_raw') }} c
left join {{ ref('customer_360') }} c360 on c.customer_id = c360.customer_id
where c360.customer_id is null
