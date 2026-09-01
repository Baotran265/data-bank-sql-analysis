-- ============================================================
-- PROJECT: DATA BANK - ANALYSIS PART A
-- FILE: 03_analysis_a_customer_nodes.sql
-- TOPIC: Customer Nodes Exploration
-- RULES (from profiling report §5, §11):
--   [R1] Current node = end_date = '9999-12-31'
--        (đặt trong ON clause của LEFT JOIN — xem A.3)
--   [R2] Unique node = (region_id, node_id) — node_id alone is NOT unique
--   [R3] When computing allocation duration, exclude sentinel rows
--        (allocation still active → end date unknown)
-- ============================================================

-- ============================================================
-- A.1. How many unique nodes are there on the Data Bank system?
-- ============================================================
SELECT
    COUNT(DISTINCT (region_id, node_id)) AS unique_node_count
FROM data_bank.customer_nodes;
-- Export: outputs/tables/analysis/a1_unique_nodes.csv

-- ============================================================
-- A.2. What is the number of nodes per region?
-- ============================================================
SELECT
    r.region_id,
    r.region_name,
    COUNT(DISTINCT n.node_id) AS nodes_per_region
FROM data_bank.regions r
LEFT JOIN data_bank.customer_nodes n
    ON r.region_id = n.region_id
GROUP BY r.region_id, r.region_name
ORDER BY r.region_id;
-- Export: outputs/tables/analysis/a2_nodes_per_region.csv

-- ============================================================
-- A.3. How many customers are allocated to each region?
-- Using current allocation (R1) to avoid double-counting customers
-- who have historically moved between nodes.
-- ============================================================
SELECT
    r.region_id,
    r.region_name,
    COUNT(DISTINCT n.customer_id) AS customers_allocated
FROM data_bank.regions r
LEFT JOIN data_bank.customer_nodes n
    ON  r.region_id = n.region_id
    AND n.end_date = '9999-12-31'   -- [R1] đúng vị trí (ON, không phải WHERE)
GROUP BY r.region_id, r.region_name
ORDER BY r.region_id;
-- Export: outputs/tables/analysis/a3_customers_per_region.csv

-- ============================================================
-- A.4. Average days customers are reallocated to a different node
-- KEY INSIGHT: exclude sentinel rows ('9999-12-31') because the
-- current allocation's end date is unknown → would distort the
-- average if included.
-- ============================================================
WITH allocation_duration AS (
    SELECT
        customer_id,
        start_date,
        end_date,
        end_date - start_date AS duration_days   -- PostgreSQL: date subtraction = integer days
    FROM data_bank.customer_nodes
    WHERE end_date <> '9999-12-31'   -- [R3] only closed allocations
)
SELECT
    ROUND(AVG(duration_days), 2) AS avg_reallocation_days
FROM allocation_duration;
-- Export: outputs/tables/analysis/a4_avg_reallocation.csv

-- ============================================================
-- A.5. Median, 80th and 95th percentile of reallocation days per region
-- Same exclusion logic as A.4.
-- ============================================================
WITH allocation_duration AS (
    SELECT
        region_id,
        end_date - start_date AS duration_days
    FROM data_bank.customer_nodes
    WHERE end_date <> '9999-12-31'   -- [R3]
)
SELECT
    r.region_name,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY a.duration_days)::numeric, 1) AS p50_median,
    ROUND(PERCENTILE_CONT(0.80) WITHIN GROUP (ORDER BY a.duration_days)::numeric, 1) AS p80,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY a.duration_days)::numeric, 1) AS p95,
    COUNT(*)                                                                         AS closed_allocations
FROM allocation_duration a
JOIN data_bank.regions r
    ON a.region_id = r.region_id
GROUP BY r.region_name
ORDER BY r.region_name;
-- Export: outputs/tables/analysis/a5_percentiles_by_region.csv