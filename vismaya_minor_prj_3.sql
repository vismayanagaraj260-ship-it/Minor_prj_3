show databases;
use redflag;

-- ====================================================================
-- P1: Velocity Fraud
-- Find users making 30 or more transactions on the same day
-- ====================================================================
SELECT
    user_id,
    DATE(txn_time) AS txn_date,
    COUNT(*) AS transaction_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY transaction_count DESC;

-- FINDING: 50 user-days had 30 or more transactions,
-- indicating unusually high transaction velocity.


-- ==========================================================================
-- P2: Round-Amount Clustering
-- Find users with 15 or more transactions using common round amounts

SELECT
    user_id,
    COUNT(*) AS round_amount_transactions
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_amount_transactions DESC;

-- FINDING: 25 users had 15 or more transactions
-- involving common round amounts.

-- =====================================================================
-- P3: Card Testing
-- Find users making 30 or more transactions below ₹10 on the same day
-- ======================================================================

SELECT
    user_id,
    DATE(txn_time) AS txn_date,
    COUNT(*) AS small_transactions
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY small_transactions DESC;

-- FINDING: 20 user-days had 30 or more transactions below ₹10,
-- which may indicate card testing activity.

-- ==================================================================
-- P4: Failed-Then-Succeeded
-- Find users with a high number of failed transactions
-- ===================================================================

SELECT
    user_id,
    COUNT(*) AS failed_transactions
FROM transactions
WHERE status = 'FAILED'
GROUP BY user_id
HAVING COUNT(*) >= 20
ORDER BY failed_transactions DESC;

-- FINDING: 25 users had 20 or more failed transactions,
-- indicating repeated payment failures that may be followed
-- by successful attempts.

-- ===================================================================
-- P5: Odd-Hour Concentration
-- Find users with 30 or more transactions and at least
-- 80% of their transactions between 2 AM and 5 AM
-- ====================================================================

SELECT
    user_id,
    COUNT(*) AS total_transactions,
    SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
        END
    ) AS odd_hour_transactions,
    ROUND(
        SUM(
            CASE
                WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS odd_hour_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 30
   AND SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
       END
   ) / COUNT(*) >= 0.80
ORDER BY odd_hour_percentage DESC;

-- FINDING: 20 users had at least 30 transactions,
-- with 80% or more occurring between 2 AM and 5 AM.

-- ========================================================================
-- P6: Mule Accounts
-- Find users receiving 8 or more credit transactions
-- ========================================================================
SELECT
    user_id,
    COUNT(*) AS credit_transactions
FROM transactions
WHERE txn_type = 'CREDIT'
GROUP BY user_id
HAVING COUNT(*) >= 8
ORDER BY credit_transactions DESC;

-- FINDING: 30 users had 8 or more credit transactions,
-- which may indicate accounts receiving funds from multiple sources.

-- =========================================================================
-- P7: Refund Abuse
-- Find users with at least 20 transactions and more than
-- 40% of their transactions being refunds
-- ==========================================================================

SELECT
    user_id,
    COUNT(*) AS total_transactions,
    SUM(
        CASE
            WHEN txn_type = 'REFUND' THEN 1
            ELSE 0
        END
    ) AS refund_transactions,
    ROUND(
        SUM(
            CASE
                WHEN txn_type = 'REFUND' THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS refund_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 20
   AND SUM(
        CASE
            WHEN txn_type = 'REFUND' THEN 1
            ELSE 0
        END
       ) / COUNT(*) > 0.40
ORDER BY refund_percentage DESC;

-- FINDING: 24 users had at least 20 transactions,
-- with more than 40% of their transactions being refunds.

-- ==========================================================================
-- P8: Merchant Collusion
-- Find merchants where the top 5 users contribute more than
-- 60% of the total transaction value
-- ===========================================================================

WITH user_merchant_totals AS
(
    SELECT
        merchant_id,
        user_id,
        SUM(amount) AS user_total_amount
    FROM transactions
    GROUP BY merchant_id, user_id
),

ranked_users AS
(
    SELECT
        merchant_id,
        user_id,
        user_total_amount,
        ROW_NUMBER() OVER
        (
            PARTITION BY merchant_id
            ORDER BY user_total_amount DESC
        ) AS user_rank
    FROM user_merchant_totals
),

top_five AS
(
    SELECT
        merchant_id,
        SUM(user_total_amount) AS top_five_amount
    FROM ranked_users
    WHERE user_rank <= 5
    GROUP BY merchant_id
),

merchant_totals AS
(
    SELECT
        merchant_id,
        SUM(amount) AS merchant_total_amount
    FROM transactions
    GROUP BY merchant_id
)

SELECT
    t.merchant_id,
    t.top_five_amount,
    m.merchant_total_amount,
    ROUND(
        t.top_five_amount / m.merchant_total_amount * 100,
        2
    ) AS top_five_percentage
FROM top_five t
JOIN merchant_totals m
    ON t.merchant_id = m.merchant_id
WHERE t.top_five_amount / m.merchant_total_amount > 0.60
ORDER BY top_five_percentage DESC;

-- FINDING: 15 merchants had more than 60% of their
-- transaction value concentrated among their top 5 users.

-- ====================================================================
-- P9: Just-Under-Threshold
-- Find users making 10 or more transactions exactly at ₹9999
-- ====================================================================

SELECT
    user_id,
    COUNT(*) AS threshold_transactions
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY threshold_transactions DESC;

-- FINDING: 20 users made 10 or more transactions of exactly ₹9999,
-- which may indicate attempts to stay just below a reporting threshold.

-- ========================================================================
-- P10: Dormant-Then-Active
-- Find users who became active after a gap of at least 90 days
-- ========================================================================

WITH transaction_history AS
(
    SELECT
        user_id,
        txn_time,
        LAG(txn_time) OVER
        (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS previous_time
    FROM transactions
),

post_gap_transactions AS
(
    SELECT
        user_id,
        txn_time
    FROM transaction_history
    WHERE previous_time IS NOT NULL
      AND DATEDIFF(txn_time, previous_time) >= 90
)

SELECT
    p.user_id,
    p.txn_time AS activity_after_gap,
    COUNT(t.txn_id) AS transactions_after_gap
FROM post_gap_transactions p
JOIN transactions t
    ON t.user_id = p.user_id
   AND t.txn_time >= p.txn_time
GROUP BY p.user_id, p.txn_time
HAVING COUNT(t.txn_id) >= 15
ORDER BY transactions_after_gap DESC;

-- FINDING: 26 users became highly active after a dormant period
-- of at least 90 days, with 15 or more transactions afterward.

-- ========================================================================
-- P11: Velocity Spike
-- Find users whose peak monthly transaction count is
-- at least 5 times their average monthly transaction count
-- =========================================================================

WITH monthly_counts AS
(
    SELECT
        user_id,
        MONTH(txn_time) AS txn_month,
        COUNT(*) AS monthly_txn_count
    FROM transactions
    GROUP BY user_id, MONTH(txn_time)
),

all_months AS
(
    SELECT 1 AS txn_month
    UNION ALL
    SELECT 2
    UNION ALL
    SELECT 3
    UNION ALL
    SELECT 4
    UNION ALL
    SELECT 5
    UNION ALL
    SELECT 6
),

user_months AS
(
    SELECT
        u.user_id,
        m.txn_month,
        COALESCE(mc.monthly_txn_count, 0) AS monthly_txn_count
    FROM
        (SELECT DISTINCT user_id FROM transactions) u
    CROSS JOIN all_months m
    LEFT JOIN monthly_counts mc
        ON u.user_id = mc.user_id
        AND m.txn_month = mc.txn_month
),

user_stats AS
(
    SELECT
        user_id,
        MAX(monthly_txn_count) AS peak_month_count,
        AVG(monthly_txn_count) AS average_month_count,
        SUM(
            CASE
                WHEN monthly_txn_count > 0 THEN 1
                ELSE 0
            END
        ) AS active_months
    FROM user_months
    GROUP BY user_id
)

SELECT
    user_id,
    peak_month_count,
    ROUND(average_month_count, 2) AS average_month_count,
    ROUND(
        peak_month_count / average_month_count,
        2
    ) AS spike_ratio
FROM user_stats
WHERE peak_month_count >= 20
  AND peak_month_count / average_month_count > 5
  AND active_months >= 2
ORDER BY spike_ratio DESC;

-- FINDING: 43 users showed a significant monthly transaction spike.
-- Their peak monthly transaction count was more than 5 times
-- their average monthly transaction count, with at least 20
-- transactions in the peak month.

-- =====================================================================
-- P12: Geographic Impossibility
-- Find users whose consecutive transactions happen
-- in different cities within 60 minutes
-- ======================================================================

WITH transaction_history AS
(
    SELECT
        user_id,
        city,
        txn_time,
        LAG(city) OVER
        (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS previous_city,
        LAG(txn_time) OVER
        (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS previous_time
    FROM transactions
)

SELECT DISTINCT
    user_id
FROM transaction_history
WHERE previous_city IS NOT NULL
  AND city <> previous_city
  AND TIMESTAMPDIFF(MINUTE, previous_time, txn_time) <= 60
ORDER BY user_id;

-- FINDING: 15 users showed geographically impossible transactions.
-- These users made consecutive transactions in different cities
-- within 60 minutes, which may indicate suspicious account activity.