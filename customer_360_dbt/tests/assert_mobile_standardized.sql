-- Mobile numbers must all be standardized to +63XXXXXXXXXX after staging.

select customer_id, mobile
from {{ ref('stg_customers') }}
where mobile not like '+63%' or len(mobile) <> 13
