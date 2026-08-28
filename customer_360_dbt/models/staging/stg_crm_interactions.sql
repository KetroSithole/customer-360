-- Cleansed CRM interactions.

select
    interaction_id,
    customer_id,
    interaction_type,
    interaction_date
from {{ source('raw', 'crm_interactions') }}
