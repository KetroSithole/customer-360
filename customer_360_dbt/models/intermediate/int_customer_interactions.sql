-- CRM interaction behaviour aggregated per customer.

with interactions as (

    select * from {{ ref('stg_crm_interactions') }}

),

reference_date as (

    select as_of_date from {{ ref('int_reference_date') }}

)

select
    i.customer_id,
    count(*)                                                       as interaction_count,
    sum(case when i.interaction_type = 'Call'  then 1 else 0 end)  as call_count,
    sum(case when i.interaction_type = 'Chat'  then 1 else 0 end)  as chat_count,
    sum(case when i.interaction_type = 'Email' then 1 else 0 end)  as email_count,
    max(i.interaction_date)                                        as last_interaction_date,
    sum(case when i.interaction_date >= date_add(r.as_of_date, -90)
             then 1 else 0 end)                                    as interactions_last_90d
from interactions i
cross join reference_date r
group by i.customer_id
