-- No activity dates may lie in the future relative to the load.

select 'transaction' as record_type, transaction_id as record_id
from {{ ref('stg_transactions') }}
where transaction_date > current_timestamp()

union all

select 'interaction', interaction_id
from {{ ref('stg_crm_interactions') }}
where interaction_date > current_date()

union all

select 'enrollment', product_id
from {{ ref('stg_product_enrollments') }}
where enrollment_date > current_date()
