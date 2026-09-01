-- ============================================================
-- PROJECT: DATA BANK - ANALYSIS PART D
-- FILE: 06_analysis_d_interest.sql
-- TOPIC: Extra Challenge — Interest-based Data Growth
-- DELIVERABLES:
--   D.1  Simple interest (KHÔNG compounding) — yêu cầu chính của đề
--   D.1b Interest phát sinh theo tháng (sanity + insight cho report)
--   D.2  Daily COMPOUNDING interest (bonus "stamina")
-- RULES / ASSUMPTIONS:
--   [D-RATE]  daily rate = 6%/365 (ước lệ ngân hàng chuẩn; 2020 là năm
--             nhuận 366 ngày — đã tài liệu hóa lựa chọn 365).
--   [D-FLOOR] KHÔNG trả lãi trên balance âm (ngân hàng không "thưởng"
--             cho overdraft); allocation floor tại 0 — nhất quán [C-NEG].
--   [D-SNAP]  Provisioning tháng = tổng allocation cuối tháng của mọi
--             customer (cùng convention snapshot với Option 1).
--   [P-10]    April cắt cụt → cum_interest tháng 4 chỉ phủ 28 ngày.
-- ============================================================

-- ============================================================
-- D.1. Simple interest (no compounding), monthly basis
-- Logic: mỗi ngày, interest = GREATEST(balance,0) × 6%/365;
--        interest KHÔNG nhập gốc; allocation = balance + cum_interest.
-- ============================================================
WITH daily_net AS (
    SELECT customer_id, txn_date,
           SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END) AS net_amount
    FROM data_bank.customer_transactions
    GROUP BY customer_id, txn_date
),
running_daily AS (
    SELECT customer_id, txn_date,
           SUM(net_amount) OVER (PARTITION BY customer_id ORDER BY txn_date) AS balance
    FROM daily_net
),
customers AS (
    SELECT DISTINCT customer_id FROM data_bank.customer_transactions
),
dates AS (
    SELECT generate_series((SELECT MIN(txn_date) FROM data_bank.customer_transactions),
                           (SELECT MAX(txn_date) FROM data_bank.customer_transactions),
                           INTERVAL '1 day')::date AS d
),
daily_balance AS (
    SELECT c.customer_id, dt.d,
           COALESCE((SELECT r.balance FROM running_daily r
                     WHERE r.customer_id = c.customer_id AND r.txn_date <= dt.d
                     ORDER BY r.txn_date DESC LIMIT 1), 0) AS balance
    FROM customers c CROSS JOIN dates dt
),
daily_interest AS (
    SELECT customer_id, d,
           GREATEST(balance, 0)                    AS earnable_balance,
           GREATEST(balance, 0) * 0.06 / 365       AS interest_earned
    FROM daily_balance
),
allocation AS (
    SELECT customer_id, d, earnable_balance,
           earnable_balance
             + SUM(interest_earned) OVER (PARTITION BY customer_id ORDER BY d
                                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             AS data_allocation
    FROM daily_interest
),
month_end_alloc AS (
    SELECT customer_id, d, data_allocation,
           ROW_NUMBER() OVER (PARTITION BY customer_id, DATE_TRUNC('month', d)
                              ORDER BY d DESC) AS rn
    FROM allocation
)
SELECT
    TO_CHAR(DATE_TRUNC('month', d), 'YYYY-MM') AS txn_month,
    ROUND(SUM(data_allocation), 2) AS total_data_required
FROM month_end_alloc
WHERE rn = 1
GROUP BY 1
ORDER BY 1;
-- Export: d1_simple_interest_monthly.csv  (kỳ vọng 4 dòng)

-- ============================================================
-- D.1b. Interest phát sinh trong từng tháng (sanity + insight)
-- Chain giống hệt D.1, chỉ đổi SELECT cuối:
-- ============================================================
WITH daily_net AS (
    SELECT customer_id, txn_date,
           SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END) AS net_amount
    FROM data_bank.customer_transactions
    GROUP BY customer_id, txn_date
),
running_daily AS (
    SELECT customer_id, txn_date,
           SUM(net_amount) OVER (PARTITION BY customer_id ORDER BY txn_date) AS balance
    FROM daily_net
),
customers AS (
    SELECT DISTINCT customer_id FROM data_bank.customer_transactions
),
dates AS (
    SELECT generate_series((SELECT MIN(txn_date) FROM data_bank.customer_transactions),
                           (SELECT MAX(txn_date) FROM data_bank.customer_transactions),
                           INTERVAL '1 day')::date AS d
),
daily_balance AS (
    SELECT c.customer_id, dt.d,
           COALESCE((SELECT r.balance FROM running_daily r
                     WHERE r.customer_id = c.customer_id AND r.txn_date <= dt.d
                     ORDER BY r.txn_date DESC LIMIT 1), 0) AS balance
    FROM customers c CROSS JOIN dates dt
)
SELECT
    TO_CHAR(DATE_TRUNC('month', d), 'YYYY-MM') AS txn_month,
    ROUND(SUM(GREATEST(balance, 0) * 0.06 / 365), 2) AS interest_earned_in_month
FROM daily_balance
GROUP BY 1
ORDER BY 1;
-- Export: d1b_interest_by_month.csv

-- ============================================================
-- D.2. Daily COMPOUNDING interest (bonus)
-- Logic đệ quy theo ngày: V_t = (V_{t-1} + net_t) × (1+r) nếu dương,
--                          ngược lại giữ nguyên (không lãi trên nợ).
-- ============================================================
WITH RECURSIVE daily_net AS (
    SELECT customer_id, txn_date,
           SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END) AS net_amount
    FROM data_bank.customer_transactions
    GROUP BY customer_id, txn_date
),
customers AS (
    SELECT DISTINCT customer_id FROM data_bank.customer_transactions
),
dates AS (
    SELECT generate_series((SELECT MIN(txn_date) FROM data_bank.customer_transactions),
                           (SELECT MAX(txn_date) FROM data_bank.customer_transactions),
                           INTERVAL '1 day')::date AS d
),
grid AS (
    SELECT c.customer_id, dt.d, COALESCE(n.net_amount, 0) AS net_amount
    FROM customers c
    CROSS JOIN dates dt
    LEFT JOIN daily_net n ON n.customer_id = c.customer_id AND n.txn_date = dt.d
),
comp AS (
    SELECT customer_id, d,
           CASE WHEN net_amount > 0 THEN net_amount * (1 + 0.06/365)
                ELSE net_amount END AS comp_balance
    FROM grid
    WHERE d = (SELECT MIN(txn_date) FROM data_bank.customer_transactions)
    UNION ALL
    SELECT g.customer_id, g.d,
           CASE WHEN c.comp_balance + g.net_amount > 0
                THEN (c.comp_balance + g.net_amount) * (1 + 0.06/365)
                ELSE c.comp_balance + g.net_amount END
    FROM comp c
    JOIN grid g ON g.customer_id = c.customer_id AND g.d = c.d + 1
),
month_end_comp AS (
    SELECT customer_id, d, comp_balance,
           ROW_NUMBER() OVER (PARTITION BY customer_id, DATE_TRUNC('month', d)
                              ORDER BY d DESC) AS rn
    FROM comp
)
SELECT
    TO_CHAR(DATE_TRUNC('month', d), 'YYYY-MM') AS txn_month,
    ROUND(SUM(GREATEST(comp_balance, 0)), 2) AS total_data_required
FROM month_end_comp
WHERE rn = 1
GROUP BY 1
ORDER BY 1;
-- Export: d2_compound_interest_monthly.csv  (kỳ vọng 4 dòng)