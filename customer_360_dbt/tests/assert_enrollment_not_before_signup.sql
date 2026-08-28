-- Enrollment dates must not precede the customer's signup date.

select p.product_id
from {{ ref('stg_product_enrollments') }} p
join {{ ref('stg_customers') }} c on p.customer_id = c.customer_id
where p.enrollment_date < c.signup_date
