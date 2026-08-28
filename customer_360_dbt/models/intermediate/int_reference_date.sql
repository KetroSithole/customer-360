-- Analysis anchor date: the most recent activity in the data.
-- All recency logic (active flag, lifecycle stage) is measured against this
-- date rather than the current date, so results stay stable for a static extract.

select
    cast(max(activity_date) as date) as as_of_date
from (
    select max(transaction_date) as activity_date from {{ ref('stg_transactions') }}
    union all
    select cast(max(interaction_date) as timestamp) from {{ ref('stg_crm_interactions') }}
) activity
