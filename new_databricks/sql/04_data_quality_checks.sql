-- 04 — Data quality checks (pure SQL, runs on a SQL warehouse)
-- Each assert_true() raises an error and fails the job task when the check
-- finds offending rows. The duplicate-email check is warn-only: it is
-- surfaced as a result set instead of an assert, so the run stays green.
-- ---------- unique + not_null on every primary key ----------
SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_customers
            WHERE
                customer_id IS NULL
        ) = 0,
        'not_null failed: stg_customers.customer_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                (
                    SELECT
                        customer_id
                    FROM
                        gotyme.staging.stg_customers
                    GROUP BY
                        customer_id
                    HAVING
                        COUNT(*) > 1
                )
        ) = 0,
        'unique failed: stg_customers.customer_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_product_enrollments
            WHERE
                product_id IS NULL
        ) = 0,
        'not_null failed: stg_product_enrollments.product_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                (
                    SELECT
                        product_id
                    FROM
                        gotyme.staging.stg_product_enrollments
                    GROUP BY
                        product_id
                    HAVING
                        COUNT(*) > 1
                )
        ) = 0,
        'unique failed: stg_product_enrollments.product_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_crm_interactions
            WHERE
                interaction_id IS NULL
        ) = 0,
        'not_null failed: stg_crm_interactions.interaction_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                (
                    SELECT
                        interaction_id
                    FROM
                        gotyme.staging.stg_crm_interactions
                    GROUP BY
                        interaction_id
                    HAVING
                        COUNT(*) > 1
                )
        ) = 0,
        'unique failed: stg_crm_interactions.interaction_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_transactions
            WHERE
                transaction_id IS NULL
        ) = 0,
        'not_null failed: stg_transactions.transaction_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                (
                    SELECT
                        transaction_id
                    FROM
                        gotyme.staging.stg_transactions
                    GROUP BY
                        transaction_id
                    HAVING
                        COUNT(*) > 1
                )
        ) = 0,
        'unique failed: stg_transactions.transaction_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.marts.customer_360
            WHERE
                customer_id IS NULL
        ) = 0,
        'not_null failed: customer_360.customer_id'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                (
                    SELECT
                        customer_id
                    FROM
                        gotyme.marts.customer_360
                    GROUP BY
                        customer_id
                    HAVING
                        COUNT(*) > 1
                )
        ) = 0,
        'unique failed: customer_360.customer_id'
    );

-- ---------- relationships (foreign keys) ----------
SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_product_enrollments e
                LEFT JOIN gotyme.staging.stg_customers c ON e.customer_id = c.customer_id
            WHERE
                c.customer_id IS NULL
        ) = 0,
        'fk failed: enrollments.customer_id -> customers'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_crm_interactions i
                LEFT JOIN gotyme.staging.stg_customers c ON i.customer_id = c.customer_id
            WHERE
                c.customer_id IS NULL
        ) = 0,
        'fk failed: interactions.customer_id -> customers'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_transactions t
                LEFT JOIN gotyme.staging.stg_customers c ON t.customer_id = c.customer_id
            WHERE
                c.customer_id IS NULL
        ) = 0,
        'fk failed: transactions.customer_id -> customers'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_transactions t
                LEFT JOIN gotyme.staging.stg_product_enrollments p ON t.product_id = p.product_id
            WHERE
                p.product_id IS NULL
        ) = 0,
        'fk failed: transactions.product_id -> enrollments'
    );

-- ---------- accepted_values ----------
SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_customers
            WHERE
                gender NOT IN ('Male', 'Female', 'Other')
        ) = 0,
        'accepted_values failed: stg_customers.gender'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_product_enrollments
            WHERE
                product_type NOT IN ('Savings', 'Credit Card')
        ) = 0,
        'accepted_values failed: stg_product_enrollments.product_type'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_crm_interactions
            WHERE
                interaction_type NOT IN ('Call', 'Chat', 'Email')
        ) = 0,
        'accepted_values failed: stg_crm_interactions.interaction_type'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_transactions
            WHERE
                transaction_direction NOT IN ('inflow', 'outflow')
        ) = 0,
        'accepted_values failed: stg_transactions.transaction_direction'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.marts.customer_360
            WHERE
                lifecycle_stage NOT IN (
                    'New',
                    'Active',
                    'At Risk',
                    'Dormant',
                    'Never Active'
                )
        ) = 0,
        'accepted_values failed: customer_360.lifecycle_stage'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.marts.customer_360
            WHERE
                value_segment NOT IN ('Platinum', 'Gold', 'Silver', 'Bronze')
        ) = 0,
        'accepted_values failed: customer_360.value_segment'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.marts.customer_360
            WHERE
                engagement_level NOT IN (
                    'Highly Engaged',
                    'Engaged',
                    'Previously Engaged',
                    'Never Engaged'
                )
        ) = 0,
        'accepted_values failed: customer_360.engagement_level'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.marts.customer_360
            WHERE
                preferred_channel NOT IN ('Chat', 'Email', 'Call', 'None')
        ) = 0,
        'accepted_values failed: customer_360.preferred_channel'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.marts.customer_360
            WHERE
                age_band NOT IN ('18-24', '25-34', '35-44', '45-54', '55+')
        ) = 0,
        'accepted_values failed: customer_360.age_band'
    );

-- ---------- singular tests ----------
SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_customers c
                LEFT JOIN gotyme.marts.customer_360 g ON c.customer_id = g.customer_id
            WHERE
                g.customer_id IS NULL
        ) = 0,
        'singular failed: customer_360 does not cover all customers'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_transactions t
                JOIN gotyme.staging.stg_product_enrollments p ON t.product_id = p.product_id
            WHERE
                t.customer_id <> p.customer_id
        ) = 0,
        'singular failed: transaction customer does not match enrollment owner'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_transactions t
                CROSS JOIN gotyme.intermediate.int_reference_date r
            WHERE
                CAST(t.transaction_date AS DATE) > r.as_of_date
        ) + (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_crm_interactions i
                CROSS JOIN gotyme.intermediate.int_reference_date r
            WHERE
                i.interaction_date > r.as_of_date
        ) = 0,
        'singular failed: future-dated activity found'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_customers
            WHERE
                mobile NOT LIKE '+63%'
                OR LENGTH(mobile) <> 13
        ) = 0,
        'singular failed: mobile not standardized to +63 / 13 chars'
    );

SELECT
    assert_true(
        (
            SELECT
                COUNT(*)
            FROM
                gotyme.staging.stg_product_enrollments e
                JOIN gotyme.staging.stg_customers c ON e.customer_id = c.customer_id
            WHERE
                e.enrollment_date < c.signup_date
        ) = 0,
        'singular failed: enrollment before customer signup'
    );

-- ---------- warn-only: duplicate customer emails ----------
-- Expected to return 3 rows; surfaced in the run output, never fails the job.
SELECT
    email,
    COUNT(*) AS customers
FROM
    gotyme.staging.stg_customers
GROUP BY
    email
HAVING
    COUNT(*) > 1
ORDER BY
    customers DESC;