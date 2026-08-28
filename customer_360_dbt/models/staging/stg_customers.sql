-- Cleansed customer master.
-- Cleansing applied:
--   * email lower-cased and trimmed
--   * mobile standardized to international +63 format (source has mixed 09.. / +639.. formats)
--   * duplicate-email flag for potential duplicate customer records

with source as (

    select * from {{ source('raw', 'customer_raw') }}

),

cleaned as (

    select
        customer_id,
        trim(first_name)                                    as first_name,
        trim(last_name)                                     as last_name,
        lower(trim(email))                                  as email,
        case
            when mobile like '0%'  then concat('+63', substring(mobile, 2, 20))
            when mobile like '+63%' then mobile
            else mobile
        end                                                 as mobile,
        gender,
        date_of_birth,
        signup_date
    from source

)

select
    c.*,
    case when dup.email is not null then 1 else 0 end as is_duplicate_email
from cleaned c
left join (
    select email
    from cleaned
    group by email
    having count(*) > 1
) dup on c.email = dup.email
