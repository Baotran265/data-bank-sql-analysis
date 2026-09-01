-- ============================================================
-- PROJECT: DATA BANK - DATA PROFILING
-- AUTHOR: Nguyen Thi Bao Tran
-- DATE: 2026-08-29
-- DESCRIPTION: Initial data profiling to check data volume, 
--              data types, and data quality.
-- ============================================================

-- ============================================================
-- STEP 1: CHECK DATA VOLUME (ROW COUNT)
-- Objective: Verify the total number of records in each table 
--            to ensure data has been imported correctly.
-- ============================================================

SELECT 'regions'                            AS table_name, COUNT(*) AS row_count
FROM data_bank.regions
UNION ALL
SELECT 'customer_nodes',                     COUNT(*)
FROM data_bank.customer_nodes
UNION ALL
SELECT 'customer_transactions',              COUNT(*)
FROM data_bank.customer_transactions
UNION ALL
SELECT 'unique_customers (in nodes)',        COUNT(DISTINCT customer_id)
FROM data_bank.customer_nodes
UNION ALL
SELECT 'unique_customers (in transactions)', COUNT(DISTINCT customer_id)
FROM data_bank.customer_transactions
ORDER BY table_name;
-- Export: outputs/tables/profiling/row_counts.csv            (3 dòng row count)
--      +  outputs/tables/profiling/unique_customer_counts.csv (2 dòng unique customers)

-- ============================================================
-- STEP 2: CHECK DATA TYPES
-- Objective: Verify that each column has the correct data type
-- as per the database design specification.
-- ============================================================

SELECT 
    table_schema,
    table_name,
    column_name,
    data_type,
    character_maximum_length,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'data_bank'
ORDER BY 
    table_name, 
    ordinal_position;
-- Export: outputs/tables/profiling/column_data_types.csv

-- ============================================================
-- STEP 3: CHECK MISSING VALUES (NULL & EMPTY STRINGS)
-- Objective: Identify columns with NULL or empty values that 
-- may impact analysis integrity.
-- ============================================================

-- 3.1 Table: regions
SELECT 
    'regions' AS table_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN region_id IS NULL THEN 1 ELSE 0 END) AS null_region_id,
    SUM(CASE WHEN region_name IS NULL OR TRIM(region_name) = '' THEN 1 ELSE 0 END) AS null_or_empty_region_name
FROM data_bank.regions;

-- 3.2 Table: customer_nodes
SELECT 
    'customer_nodes' AS table_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN region_id IS NULL THEN 1 ELSE 0 END) AS null_region_id,
    SUM(CASE WHEN node_id IS NULL THEN 1 ELSE 0 END) AS null_node_id,
    SUM(CASE WHEN start_date IS NULL THEN 1 ELSE 0 END) AS null_start_date,
    SUM(CASE WHEN end_date IS NULL THEN 1 ELSE 0 END) AS null_end_date
FROM data_bank.customer_nodes;

-- 3.3 Table: customer_transactions
SELECT 
    'customer_transactions' AS table_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN txn_date IS NULL THEN 1 ELSE 0 END) AS null_txn_date,
    SUM(CASE WHEN txn_type IS NULL OR TRIM(txn_type) = '' THEN 1 ELSE 0 END) AS null_or_empty_txn_type,
    SUM(CASE WHEN txn_amount IS NULL THEN 1 ELSE 0 END) AS null_txn_amount
FROM data_bank.customer_transactions;    
-- Export: outputs/tables/profiling/missing_values.csv (gộp kết quả 3.1–3.3)

-- ============================================================
-- STEP 4: CHECK DUPLICATES
-- ============================================================

-- 4.1. CHECK EXACT DUPLICATES IN customer_nodes
-- Objective: Find rows where ALL columns are identical
-- (same customer, region, node, start_date, end_date)

SELECT 
    customer_id,
    region_id,
    node_id,
    start_date,
    end_date,
    COUNT(*) AS duplicate_count
FROM data_bank.customer_nodes
GROUP BY 
    customer_id,
    region_id,
    node_id,
    start_date,
    end_date
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- 4.2. CHECK EXACT DUPLICATES IN customer_transactions

SELECT 
    customer_id,
    txn_date,
    txn_type,
    txn_amount,
    COUNT(*) AS duplicate_count
FROM data_bank.customer_transactions
GROUP BY 
    customer_id,
    txn_date,
    txn_type,
    txn_amount
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- 4.3. CHECK LOGICAL DUPLICATES IN customer_nodes
-- Objective: Find customers assigned to MULTIPLE nodes 

SELECT 
    customer_id,
    start_date,
    COUNT(*) AS same_start_date_count
FROM data_bank.customer_nodes
GROUP BY 
    customer_id,
    start_date
HAVING COUNT(*) > 1
ORDER BY same_start_date_count DESC;
-- Export: outputs/tables/profiling/duplicates.csv (gộp 4.1–4.3; kỳ vọng 0 dòng)

-- ============================================================
-- STEP 5: LOGICAL INTEGRITY & INVALID VALUES CHECK
-- Objective: Validate temporal logic in customer_nodes table
-- and ensure data consistency for active node allocations.
-- ============================================================

-- 5.1. Check for invalid date ranges (end_date < start_date)
-- Business Meaning: A node allocation cannot end before it starts.
SELECT COUNT(*) AS invalid_date_range_count
FROM data_bank.customer_nodes
WHERE end_date < start_date;

-- 5.2. Check for currently active node allocations
-- Business Meaning: '9999-12-31' is the sentinel value for 'current/active'.
SELECT COUNT(*) AS active_node_allocation_count
FROM data_bank.customer_nodes
WHERE end_date = DATE '9999-12-31';

-- 5.3. Check for customers with multiple active nodes (Data anomaly)
-- Business Meaning: A customer should only be in ONE node at a time.
SELECT 
    customer_id,
    COUNT(*) AS active_node_count
FROM data_bank.customer_nodes
WHERE end_date = DATE '9999-12-31'
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY active_node_count DESC;
-- Export: outputs/tables/profiling/logical_integrity.csv (gộp 5.1–5.3)

-- ============================================================
-- STEP 6: CHECK TEMPORAL OVERLAP IN customer_nodes
-- Objective: Detect if any customer has overlapping node 
-- allocations (start_date < previous end_date)
-- ============================================================

WITH ordered_nodes AS (
    SELECT 
        customer_id,
        start_date,
        end_date,
        LAG(end_date) OVER (
            PARTITION BY customer_id 
            ORDER BY start_date, end_date
        ) AS previous_end_date
    FROM data_bank.customer_nodes
)
SELECT COUNT(*) AS possible_overlap_count
FROM ordered_nodes
WHERE previous_end_date IS NOT NULL
  AND start_date < previous_end_date;
-- Export: outputs/tables/profiling/temporal_overlap.csv

-- ============================================================
-- STEP 7: CHECK REFERENTIAL INTEGRITY
-- Objective: Verify relationships between tables
-- ============================================================

-- 7.1. Customers with transactions but no node allocation
SELECT COUNT(DISTINCT t.customer_id) AS txn_customers_without_node
FROM data_bank.customer_transactions t
LEFT JOIN data_bank.customer_nodes n
    ON t.customer_id = n.customer_id
WHERE n.customer_id IS NULL;

-- 7.2. Customers with node allocation but no transactions
SELECT COUNT(DISTINCT n.customer_id) AS node_customers_without_txn
FROM data_bank.customer_nodes n
LEFT JOIN data_bank.customer_transactions t
    ON n.customer_id = t.customer_id
WHERE t.customer_id IS NULL;

-- 7.3. Nodes with invalid region_id
SELECT COUNT(*) AS nodes_with_invalid_region
FROM data_bank.customer_nodes n
LEFT JOIN data_bank.regions r
    ON n.region_id = r.region_id
WHERE r.region_id IS NULL;
-- Export: outputs/tables/profiling/referential_integrity.csv (gộp 7.1–7.3)

-- ============================================================
-- STEP 8: CHECK txn_type VALUES
-- Objective: Verify txn_type contains only valid values
-- ============================================================

-- 8.1. List all txn_type values and their counts
SELECT 
    txn_type,
    COUNT(*) AS txn_count
FROM data_bank.customer_transactions
GROUP BY txn_type
ORDER BY txn_count DESC;

-- 8.2. Check for invalid txn_type values
SELECT COUNT(*) AS invalid_txn_type_count
FROM data_bank.customer_transactions
WHERE LOWER(TRIM(txn_type)) NOT IN (
    'deposit',
    'withdrawal',
    'purchase'
);
-- Export: outputs/tables/profiling/txn_type_validation.csv (gộp 8.1–8.2)

-- ============================================================
-- STEP 9: CHECK txn_amount VALUES
-- Objective: Detect negative or zero amounts and analyze distribution
-- ============================================================

-- 9.1. Check for non-positive amounts
SELECT COUNT(*) AS non_positive_amount_count
FROM data_bank.customer_transactions
WHERE txn_amount <= 0;
-- Export: outputs/tables/profiling/non_positive_transactions.csv

-- 9.2. Distribution of txn_amount by txn_type
SELECT 
    txn_type,
    COUNT(*) AS txn_count,
    COUNT(DISTINCT customer_id) AS unique_customer_count,
    MIN(txn_amount) AS min_amount,
    ROUND(AVG(txn_amount)::numeric, 2) AS avg_amount,
    MAX(txn_amount) AS max_amount,
    SUM(txn_amount) AS total_amount,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY txn_amount)::numeric, 2) AS median_amount,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY txn_amount)::numeric, 2) AS p95_amount,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY txn_amount)::numeric, 2) AS p99_amount
FROM data_bank.customer_transactions
GROUP BY txn_type
ORDER BY txn_type;
-- Export: outputs/tables/profiling/txn_amount.csv

-- ============================================================
-- STEP 10: CHECK DATE RANGES
-- Objective: Verify date ranges are within expected period
-- ============================================================

-- 10.1. Date range in customer_transactions
SELECT 
    MIN(txn_date) AS min_txn_date,
    MAX(txn_date) AS max_txn_date,
    COUNT(DISTINCT txn_date) AS distinct_txn_dates
FROM data_bank.customer_transactions;

-- 10.2. Date range in customer_nodes
SELECT 
    MIN(start_date) AS min_start_date,
    MAX(start_date) AS max_start_date,
    MIN(end_date) AS min_end_date,
    MAX(end_date) AS max_end_date
FROM data_bank.customer_nodes;

-- 10.3. Monthly transaction distribution
SELECT 
    DATE_TRUNC('month', txn_date) AS txn_month,
    COUNT(*) AS txn_count,
    COUNT(DISTINCT customer_id) AS unique_customer_count
FROM data_bank.customer_transactions
GROUP BY txn_month
ORDER BY txn_month;
-- Export: outputs/tables/profiling/date_ranges.csv (gộp 10.1–10.3)

-- ============================================================
-- STEP 11: CHECK REGION AND NODE DISTRIBUTION
-- Objective: Analyze region and node allocation patterns
-- ============================================================

-- 11.1. List all regions
SELECT *
FROM data_bank.regions
ORDER BY region_id;

-- 11.2. Number of distinct nodes per region
SELECT 
    region_id,
    COUNT(DISTINCT node_id) AS distinct_node_count
FROM data_bank.customer_nodes
GROUP BY region_id
ORDER BY region_id;

-- 11.3. Number of unique customers per region
SELECT 
    region_id,
    COUNT(DISTINCT customer_id) AS unique_customer_count
FROM data_bank.customer_nodes
GROUP BY region_id
ORDER BY region_id;
-- Export: outputs/tables/profiling/region_node_distribution.csv (gộp 11.1–11.3)

-- 11.4. Check if node_id is unique globally or per region
SELECT 
    COUNT(DISTINCT node_id) AS distinct_node_id_only,
    COUNT(DISTINCT CONCAT(region_id::text, '-', node_id::text)) AS distinct_region_node_pairs
FROM data_bank.customer_nodes;
-- Export: outputs/tables/profiling/node_uniqueness.csv