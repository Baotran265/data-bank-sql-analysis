-- ============================================================
-- PROJECT: DATA BANK - DATA CLEANING
-- FILE: 02_data_cleaning.sql
-- PURPOSE: hiện thực hóa & tài liệu hóa các quyết định làm sạch
--          từ Data Profiling Report (01).
-- TRIẾT LÝ: "keep & flag" — không xóa dòng nào trừ khi chứng minh
--           được là có hại; mọi quyết định đều được tái kiểm chứng
--           để pipeline reproducible.
-- ============================================================

-- [C-1] Exact duplicates (profiling §3): 0 → KEEP ALL
SELECT COUNT(*) AS duplicate_row_groups   -- kỳ vọng: 0
FROM (
    SELECT 1
    FROM data_bank.customer_transactions
    GROUP BY customer_id, txn_date, txn_type, txn_amount
    HAVING COUNT(*) > 1
) d;

SELECT COUNT(*) AS duplicate_node_groups  -- kỳ vọng: 0
FROM (
    SELECT 1
    FROM data_bank.customer_nodes
    GROUP BY customer_id, node_id, start_date, end_date
    HAVING COUNT(*) > 1
) d;

-- [C-2] NULLs (profiling §3): 0 → không cần imputation
SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer,
    COUNT(*) FILTER (WHERE txn_date    IS NULL) AS null_date,
    COUNT(*) FILTER (WHERE txn_type    IS NULL) AS null_type,
    COUNT(*) FILTER (WHERE txn_amount  IS NULL) AS null_amount
FROM data_bank.customer_transactions;    -- kỳ vọng: 0 / 0 / 0 / 0

-- [C-3] txn_type validity (P-8): không cần recoding
SELECT COUNT(*) AS invalid_txn_type       -- kỳ vọng: 0
FROM data_bank.customer_transactions
WHERE txn_type NOT IN ('deposit', 'withdrawal', 'purchase');

-- [C-4] Zero-value deposit (P-9): đúng 1 dòng → KEEP & FLAG
SELECT COUNT(*) AS zero_value_deposits    -- kỳ vọng: 1
FROM data_bank.customer_transactions
WHERE txn_type = 'deposit' AND txn_amount = 0;

-- [C-5] Sentinel end_date (R1/R3): KHÔNG xóa — đây là cờ "allocation
-- đang mở", sẽ được xử lý ở tầng phân tích (04, 05), không phải tầng làm sạch
SELECT COUNT(*) AS open_allocations       -- kỳ vọng: 500
FROM data_bank.customer_nodes
WHERE end_date = '9999-12-31';

-- [C-6] Hiện thực "keep & flag": view giao dịch kèm cờ zero-deposit
DROP VIEW IF EXISTS data_bank.v_transactions_flagged CASCADE;
CREATE VIEW data_bank.v_transactions_flagged AS
SELECT
    t.*,
    CASE WHEN t.txn_type = 'deposit' AND t.txn_amount = 0
         THEN 1 ELSE 0 END AS is_zero_deposit
FROM data_bank.customer_transactions t;