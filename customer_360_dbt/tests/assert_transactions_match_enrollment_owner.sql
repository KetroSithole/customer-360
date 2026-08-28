-- Every transaction's customer must match the customer who owns the product
-- account. A mismatch means broken referential integrity between systems.

select t.transaction_id
from {{ ref('stg_transactions') }} t
join {{ ref('stg_product_enrollments') }} p on t.product_id = p.product_id
where t.customer_id <> p.customer_id
