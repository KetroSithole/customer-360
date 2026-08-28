-- Cleansed product enrollments. `limit` is renamed to credit_limit to avoid
-- the reserved word downstream; it is only meaningful for credit cards.

select
    product_id,
    customer_id,
    product_type,
    enrollment_date,
    [limit] as credit_limit
from {{ source('raw', 'product_enrollments') }}
