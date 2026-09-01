-- ============================================================
-- PROJECT: DATA BANK - ANALYSIS PART B
-- FILE: 04_analysis_b_customer_transactions.sql
-- TOPIC: Customer Transactions
-- RULES (from profiling report):
--   [P-8] txn_type hợp lệ: deposit / withdrawal / purchase
--   [P-9] 1 zero-value deposit được keep & flag; nó góp 0 vào
--         tổng tiền → không cần điều chỉnh trong tính balance
--   [P-10] April 2020 bị cắt cụt (kết thúc 2020-04-28) → các
--          metric theo tháng của April không so sánh được với
--          các tháng đủ ngày
-- ============================================================

-- ============================================================
-- B.1. Unique count and total amount for each transaction type
-- Interpretation: "unique count" là mơ hồ, nên trả CẢ HAI:
-- số giao dịch (txn_count) VÀ số khách duy nhất (unique_customer_count).
-- ============================================================
SELECT
    txn_type,
    COUNT(*)                       AS txn_count,
    COUNT(DISTINCT customer_id)    AS unique_customer_count,
    SUM(txn_amount)                AS total_amount
FROM data_bank.customer_transactions
GROUP BY txn_type
ORDER BY txn_type;
-- Export: outputs/tables/analysis/b1_txn_type_summary.csv

-- ============================================================
-- B.2. Average total historical deposit counts and amounts
-- Logic: với MỖI customer, tính tổng số lần deposit + tổng tiền
-- deposit (toàn lịch sử); rồi lấy trung bình các tổng đó.
-- Note: profiling §9 cho thấy 100% customers có deposit, nên
-- "trung bình trên người có deposit" = "trung bình trên tất cả".
-- ============================================================
WITH per_customer AS (
    SELECT
        customer_id,
        COUNT(*)      AS deposit_count,
        SUM(txn_amount) AS deposit_amount
    FROM data_bank.customer_transactions
    WHERE txn_type = 'deposit'
    GROUP BY customer_id
)
SELECT
    ROUND(AVG(deposit_count)::numeric, 2)  AS avg_deposit_count_per_customer,
    ROUND(AVG(deposit_amount)::numeric, 2) AS avg_deposit_amount_per_customer
FROM per_customer;
-- Export: outputs/tables/analysis/b2_avg_deposits.csv

-- ============================================================
-- B.3. Customers with >1 deposit AND (>=1 purchase OR >=1 withdrawal)
-- in a single month
-- ============================================================
WITH monthly AS (
    SELECT
        customer_id,
        TO_CHAR(DATE_TRUNC('month', txn_date), 'YYYY-MM') AS txn_month,
        COUNT(*) FILTER (WHERE txn_type = 'deposit')    AS deposit_count,
        COUNT(*) FILTER (WHERE txn_type = 'purchase')   AS purchase_count,
        COUNT(*) FILTER (WHERE txn_type = 'withdrawal') AS withdrawal_count
    FROM data_bank.customer_transactions
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
)
SELECT
    txn_month,
    COUNT(*) AS qualifying_customers
FROM monthly
WHERE deposit_count > 1
  AND (purchase_count >= 1 OR withdrawal_count >= 1)
GROUP BY txn_month
ORDER BY txn_month;
-- Export: outputs/tables/analysis/b3_monthly_qualifying_customers.csv

-- ============================================================
-- B.4. Closing balance for each customer at the end of each month
-- Logic:
--   1) net theo ngày: deposit +, withdrawal/purchase -
--   2) running balance theo customer
--   3) closing = balance tại giao dịch CUỐI CÙNG trước/sát cuối tháng
--      (carry-forward tự động: tháng không giao dịch vẫn có balance)
-- ============================================================
WITH daily_net AS (
    SELECT
        customer_id,
        txn_date,
        SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount
                 ELSE -txn_amount END) AS net_amount
    FROM data_bank.customer_transactions
    GROUP BY customer_id, txn_date
),
running AS (
    SELECT
        customer_id,
        txn_date,
        SUM(net_amount) OVER (
            PARTITION BY customer_id
            ORDER BY txn_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS balance
    FROM daily_net
),
month_ends AS (
    SELECT DISTINCT
        DATE_TRUNC('month', txn_date) AS txn_month,
        (DATE_TRUNC('month', txn_date) + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end_date
    FROM data_bank.customer_transactions
),
customers AS (
    SELECT DISTINCT customer_id
    FROM data_bank.customer_transactions
)
SELECT
    c.customer_id,
    TO_CHAR(me.txn_month, 'YYYY-MM') AS txn_month,
    (
        SELECT r.balance
        FROM running r
        WHERE r.customer_id = c.customer_id
          AND r.txn_date <= me.month_end_date
        ORDER BY r.txn_date DESC
        LIMIT 1
    ) AS closing_balance
FROM customers c
CROSS JOIN month_ends me
ORDER BY c.customer_id, me.txn_month;
-- Export: outputs/tables/analysis/b4_monthly_closing_balance.csv  (kỳ vọng 500 x 4 = 2,000 dòng)

-- B.4b. Summary closing balance theo tháng (dùng cho report)
WITH daily_net AS (
    SELECT customer_id, txn_date,
           SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END) AS net_amount
    FROM data_bank.customer_transactions
    GROUP BY customer_id, txn_date
),
running AS (
    SELECT customer_id, txn_date,
           SUM(net_amount) OVER (PARTITION BY customer_id ORDER BY txn_date) AS balance
    FROM daily_net
),
month_ends AS (
    SELECT DISTINCT
        DATE_TRUNC('month', txn_date) AS txn_month,
        (DATE_TRUNC('month', txn_date) + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end_date
    FROM data_bank.customer_transactions
),
customers AS (
    SELECT DISTINCT customer_id FROM data_bank.customer_transactions
),
closing AS (
    SELECT c.customer_id,
           TO_CHAR(me.txn_month, 'YYYY-MM') AS txn_month,
           (SELECT r.balance FROM running r
            WHERE r.customer_id = c.customer_id AND r.txn_date <= me.month_end_date
            ORDER BY r.txn_date DESC LIMIT 1) AS closing_balance
    FROM customers c CROSS JOIN month_ends me
)
SELECT
    txn_month,
    COUNT(*)                                AS customers,
    ROUND(AVG(closing_balance)::numeric, 2) AS avg_closing_balance,
    MIN(closing_balance)                    AS min_closing_balance,
    MAX(closing_balance)                    AS max_closing_balance,
    COUNT(*) FILTER (WHERE closing_balance < 0) AS customers_negative_balance
FROM closing
GROUP BY txn_month
ORDER BY txn_month;
-- Export: outputs/tables/analysis/b4b_closing_balance_summary.csv

-- ============================================================
-- B.5. % customers who increase their closing balance by >5%
-- Interpretation (ghi rõ trong report): so sánh closing balance
-- tháng này vs tháng trước (month-over-month); một customer được
-- tính nếu CÓ ÍT NHẤT 1 tháng tăng >5%.
-- Guard: chỉ xét khi prev_closing > 0 (tăng % trên nền âm/0 là vô nghĩa).
-- ============================================================
WITH daily_net AS (
    SELECT customer_id, txn_date,
           SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END) AS net_amount
    FROM data_bank.customer_transactions
    GROUP BY customer_id, txn_date
),
running AS (
    SELECT customer_id, txn_date,
           SUM(net_amount) OVER (PARTITION BY customer_id ORDER BY txn_date) AS balance
    FROM daily_net
),
month_ends AS (
    SELECT DISTINCT
        DATE_TRUNC('month', txn_date) AS txn_month,
        (DATE_TRUNC('month', txn_date) + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end_date
    FROM data_bank.customer_transactions
),
customers AS (
    SELECT DISTINCT customer_id FROM data_bank.customer_transactions
),
closing AS (
    SELECT c.customer_id,
           TO_CHAR(me.txn_month, 'YYYY-MM') AS txn_month,
           (SELECT r.balance FROM running r
            WHERE r.customer_id = c.customer_id AND r.txn_date <= me.month_end_date
            ORDER BY r.txn_date DESC LIMIT 1) AS closing_balance
    FROM customers c CROSS JOIN month_ends me
),
lagged AS (
    SELECT
        customer_id,
        txn_month,
        closing_balance,
        LAG(closing_balance) OVER (PARTITION BY customer_id ORDER BY txn_month) AS prev_closing
    FROM closing
)
SELECT
    ROUND(
        100.0 * COUNT(DISTINCT CASE
                    WHEN prev_closing > 0 AND closing_balance > 1.05 * prev_closing
                    THEN customer_id END)
        / COUNT(DISTINCT customer_id),
    2) AS pct_customers_increased_over_5pct
FROM lagged;
-- Export: outputs/tables/analysis/b5_pct_increase_over_5pct.csv

-- B.5b. Breakdown theo tháng (dùng cho report)
WITH daily_net AS (
    SELECT customer_id, txn_date,
           SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END) AS net_amount
    FROM data_bank.customer_transactions
    GROUP BY customer_id, txn_date
),
running AS (
    SELECT customer_id, txn_date,
           SUM(net_amount) OVER (PARTITION BY customer_id ORDER BY txn_date) AS balance
    FROM daily_net
),
month_ends AS (
    SELECT DISTINCT
        DATE_TRUNC('month', txn_date) AS txn_month,
        (DATE_TRUNC('month', txn_date) + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end_date
    FROM data_bank.customer_transactions
),
customers AS (
    SELECT DISTINCT customer_id FROM data_bank.customer_transactions
),
closing AS (
    SELECT c.customer_id,
           TO_CHAR(me.txn_month, 'YYYY-MM') AS txn_month,
           (SELECT r.balance FROM running r
            WHERE r.customer_id = c.customer_id AND r.txn_date <= me.month_end_date
            ORDER BY r.txn_date DESC LIMIT 1) AS closing_balance
    FROM customers c CROSS JOIN month_ends me
),
lagged AS (
    SELECT customer_id, txn_month, closing_balance,
           LAG(closing_balance) OVER (PARTITION BY customer_id ORDER BY txn_month) AS prev_closing
    FROM closing
)
SELECT
    txn_month,
    COUNT(DISTINCT CASE WHEN prev_closing > 0 AND closing_balance > 1.05 * prev_closing
                        THEN customer_id END) AS customers_up_over_5pct
FROM lagged
WHERE prev_closing IS NOT NULL
GROUP BY txn_month
ORDER BY txn_month;
-- Export: outputs/tables/analysis/b5b_monthly_increase_breakdown.csv