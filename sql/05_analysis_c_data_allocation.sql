-- ============================================================
-- PROJECT: DATA BANK - ANALYSIS PART C
-- FILE: 05_analysis_c_data_allocation.sql
-- TOPIC: Data Allocation Challenge
-- DELIVERABLES:
--   C.1 running balance theo từng giao dịch      → query 1
--   C.2 closing balance cuối mỗi tháng           → REUSE B.4 (b4_monthly_closing_balance.csv)
--   C.3 min / avg / max của running balance      → query 2 (+2b summary)
--   C.4 data cần provision theo tháng, 3 options → query 3
-- RULES / ASSUMPTIONS:
--   [P-10]  April 2020 cắt cụt (→ 28/04): peak tháng 4 (Option 3) chỉ
--           phủ 28 ngày → đọc thận trọng.
--   [C-NEG] Balance ÂM → "data allocation âm" vô nghĩa. Báo CẢ HAI biến thể:
--           raw (cho phép âm, để xem hệ số bù trừ) và floored
--           GREATEST(x, 0) = khuyến nghị chính.
--   [C-TIE] Bảng KHÔNG có transaction_id → thứ tự các giao dịch CÙNG ngày
--           là tùy ý; ảnh hưởng giá trị trung gian trong ngày của running
--           balance, KHÔNG ảnh hưởng closing cuối tháng. Đã tài liệu hóa.
-- ============================================================

-- ============================================================
-- C.1. Running customer balance (impact của từng transaction)
-- Frame ROWS: mỗi dòng giao dịch nhận balance SAU chính nó.
-- ============================================================
SELECT
    customer_id,
    txn_date,
    txn_type,
    txn_amount,
    SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount
             ELSE -txn_amount END)
        OVER (PARTITION BY customer_id
              ORDER BY txn_date
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_balance
FROM data_bank.customer_transactions
ORDER BY customer_id, txn_date;
-- Export: outputs/tables/analysis/c1_running_balance.csv  

-- ============================================================
-- C.2. Customer balance at the end of each month
-- IDENTICAL với B.4 → reuse outputs/tables/analysis/b4_monthly_closing_balance.csv
-- (không chạy lại; giữ DRY — logic closing nằm ở 04_analysis_b...)
-- ============================================================

-- ============================================================
-- C.3. Min / avg / max của running balance theo customer
-- ============================================================
WITH running_txn AS (
    
)
SELECT
    customer_id,
    MIN(running_balance)                      AS min_running_balance,
    ROUND(AVG(running_balance)::numeric, 2)   AS avg_running_balance,
    MAX(running_balance)                      AS max_running_balance
FROM running_txn
GROUP BY customer_id
ORDER BY customer_id;
-- Export: outputs/tables/analysis/c3_running_stats.csv

-- C.3b. Summary (dùng cho report)
WITH running_txn AS (
    SELECT
        customer_id,
        SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount
                 ELSE -txn_amount END)
            OVER (PARTITION BY customer_id
                  ORDER BY txn_date
                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_balance
    FROM data_bank.customer_transactions
),
stats AS (
    SELECT customer_id,
           MIN(running_balance) AS min_rb,
           AVG(running_balance) AS avg_rb,
           MAX(running_balance) AS max_rb
    FROM running_txn
    GROUP BY customer_id
)
SELECT
    ROUND(AVG(min_rb)::numeric, 2) AS avg_of_min,
    ROUND(AVG(avg_rb)::numeric, 2) AS avg_of_avg,
    ROUND(AVG(max_rb)::numeric, 2) AS avg_of_max,
    MIN(min_rb)                    AS overall_min,
    MAX(max_rb)                    AS overall_max,
    COUNT(*) FILTER (WHERE min_rb < 0) AS customers_ever_negative,
    COUNT(*) FILTER (WHERE max_rb < 0) AS customers_always_negative
FROM stats;
-- Export: outputs/tables/analysis/c3b_running_stats_summary.csv

-- ============================================================
-- C.4. Data required per option, monthly basis
--   Option 1 = closing balance THÁNG TRƯỚC (allocation cố định cả tháng)
--   Option 2 = trung bình balance của 30 NGÀY TRƯỚC tháng đó
--              (daily balance carry-forward: ngày không giao dịch giữ nguyên)
--   Option 3 = real-time → provision phải phủ ĐỈNH nhu cầu trong tháng
--              = SUM theo customer của MAX(daily balance trong tháng)
--   January: Opt1/Opt2 không có dữ liệu quá khứ → NULL (không bịa số).
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
month_starts AS (
    SELECT DISTINCT DATE_TRUNC('month', txn_date)::date AS month_start
    FROM data_bank.customer_transactions
),
month_ends AS (
    SELECT DISTINCT
        TO_CHAR(DATE_TRUNC('month', txn_date), 'YYYY-MM') AS txn_month,
        (DATE_TRUNC('month', txn_date) + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end_date
    FROM data_bank.customer_transactions
),
closing AS (
    SELECT c.customer_id, me.txn_month,
           (SELECT r.balance FROM running_daily r
            WHERE r.customer_id = c.customer_id AND r.txn_date <= me.month_end_date
            ORDER BY r.txn_date DESC LIMIT 1) AS closing_balance
    FROM customers c CROSS JOIN month_ends me
),
-- OPTION 1: allocation tháng M = closing tháng M-1
closing_lag AS (
    SELECT customer_id, txn_month,
           LAG(closing_balance) OVER (PARTITION BY customer_id ORDER BY txn_month) AS prev_closing
    FROM closing
),
opt1 AS (
    SELECT txn_month,
           SUM(prev_closing)             AS opt1_raw,
           SUM(GREATEST(prev_closing,0)) AS opt1_floored
    FROM closing_lag
    WHERE prev_closing IS NOT NULL
    GROUP BY txn_month
),
-- Daily balance spine (carry-forward) cho Opt2 & Opt3
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
-- OPTION 2: avg balance của 30 ngày trước tháng M
opt2_win AS (
    SELECT ms.month_start, db.customer_id, AVG(db.balance) AS avg_bal
    FROM daily_balance db
    JOIN month_starts ms
      ON db.d BETWEEN (ms.month_start - INTERVAL '30 days')::date -- "30 days" per problem statement, not calendar month
                  AND (ms.month_start - INTERVAL '1 day')::date
    GROUP BY ms.month_start, db.customer_id
),
opt2 AS (
    SELECT TO_CHAR(month_start, 'YYYY-MM') AS txn_month,
           ROUND(SUM(avg_bal), 2)             AS opt2_raw,
           ROUND(SUM(GREATEST(avg_bal, 0)), 2) AS opt2_floored
    FROM opt2_win
    GROUP BY month_start
),
-- OPTION 3: peak nhu cầu trong tháng (real-time)
opt3_win AS (
    SELECT DATE_TRUNC('month', d)::date AS m, customer_id, MAX(balance) AS max_bal
    FROM daily_balance
    GROUP BY 1, 2
),
opt3 AS (
    SELECT TO_CHAR(m, 'YYYY-MM') AS txn_month,
           SUM(max_bal)             AS opt3_raw,
           SUM(GREATEST(max_bal,0)) AS opt3_floored
    FROM opt3_win
    GROUP BY m
)
SELECT
    COALESCE(o1.txn_month, o2.txn_month, o3.txn_month) AS txn_month,
    o1.opt1_raw,  o1.opt1_floored,
    o2.opt2_raw,  o2.opt2_floored,
    o3.opt3_raw,  o3.opt3_floored
FROM opt1 o1
FULL JOIN opt2 o2 ON o1.txn_month = o2.txn_month
FULL JOIN opt3 o3 ON COALESCE(o1.txn_month, o2.txn_month) = o3.txn_month
ORDER BY 1;
-- Export: outputs/tables/analysis/c4_monthly_data_required.csv  (kỳ vọng 4 dòng: Jan opt3-only + Feb–Apr)


