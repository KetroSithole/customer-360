-- Product holdings aggregated per customer.

select
    customer_id,
    count(*)                                                            as product_count,
    sum(case when product_type = 'Savings' then 1 else 0 end)           as savings_count,
    sum(case when product_type = 'Credit Card' then 1 else 0 end)       as credit_card_count,
    max(case when product_type = 'Savings' then 1 else 0 end)           as has_savings,
    max(case when product_type = 'Credit Card' then 1 else 0 end)       as has_credit_card,
    sum(case when product_type = 'Credit Card' then credit_limit else 0 end) as total_credit_limit,
    min(enrollment_date)                                                as first_enrollment_date,
    max(enrollment_date)                                                as last_enrollment_date
from {{ ref('stg_product_enrollments') }}
group by customer_id
