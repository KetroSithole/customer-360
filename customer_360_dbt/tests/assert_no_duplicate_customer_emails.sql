-- Highlight potential duplicate customer records sharing one email address.
-- Known issue in source data (3 emails affected) - warn, don't fail the build.

{{ config(severity='warn') }}

select email, count(*) as customer_count
from {{ ref('stg_customers') }}
group by email
having count(*) > 1
