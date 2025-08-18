-- ========================================
-- DEDICATED work_mem TUNING SCENARIOS
-- ========================================
-- This script provides comprehensive work_mem tuning demonstrations
-- Usage: \i /demo-data/work-mem-tuning.sql

\echo '🔧 WORK_MEM TUNING COMPREHENSIVE DEMO'
\echo '===================================='
\echo ''

-- Show current configuration
\echo '--- CURRENT CONFIGURATION ---'
SELECT name, setting, unit, context FROM pg_settings 
WHERE name IN ('work_mem', 'temp_buffers', 'shared_buffers');

-- Reset statistics for clean measurement
SELECT pg_stat_reset();

-- ========================================
-- SCENARIO 1: Large Sort Operations
-- ========================================

\echo ''
\echo '=== SCENARIO 1: Large Sort Operations ==='

-- Create a temporary large dataset for sorting
CREATE TEMP TABLE large_sort_test AS
SELECT 
    generate_series as id,
    md5(random()::text) as random_text,
    random() * 1000000 as random_number,
    CURRENT_TIMESTAMP - (random() * interval '365 days') as random_date
FROM generate_series(1, 100000);

\echo ''
\echo '--- Test 1A: Sort with work_mem = 1MB (expect external sort) ---'
SET work_mem = '1MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT * FROM large_sort_test 
ORDER BY random_text, random_number;

\echo ''
\echo '--- Test 1B: Sort with work_mem = 16MB (should be in-memory) ---'
SET work_mem = '16MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT * FROM large_sort_test 
ORDER BY random_text, random_number;

-- ========================================
-- SCENARIO 2: Hash Joins
-- ========================================

\echo ''
\echo '=== SCENARIO 2: Hash Join Operations ==='

\echo ''
\echo '--- Test 2A: Hash join with work_mem = 2MB ---'
SET work_mem = '2MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    pt.name,
    pt.email,
    COUNT(uo.order_id) as order_count,
    SUM(uo.amount) as total_spent
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 1 AND 5000
GROUP BY pt.id, pt.name, pt.email
ORDER BY total_spent DESC
LIMIT 1000;

\echo ''
\echo '--- Test 2B: Hash join with work_mem = 32MB ---'
SET work_mem = '32MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    pt.name,
    pt.email,
    COUNT(uo.order_id) as order_count,
    SUM(uo.amount) as total_spent
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 1 AND 5000
GROUP BY pt.id, pt.name, pt.email
ORDER BY total_spent DESC
LIMIT 1000;

-- ========================================
-- SCENARIO 3: Window Functions
-- ========================================

\echo ''
\echo '=== SCENARIO 3: Window Function Operations ==='

\echo ''
\echo '--- Test 3A: Window functions with work_mem = 4MB ---'
SET work_mem = '4MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    department,
    position,
    salary,
    ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) as dept_rank,
    PERCENT_RANK() OVER (PARTITION BY department ORDER BY salary) as salary_percentile,
    LAG(salary, 1) OVER (PARTITION BY department ORDER BY hire_date) as prev_salary,
    AVG(salary) OVER (PARTITION BY department) as dept_avg_salary
FROM employee_salaries
ORDER BY department, salary DESC;

\echo ''
\echo '--- Test 3B: Window functions with work_mem = 24MB ---'
SET work_mem = '24MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    department,
    position,
    salary,
    ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) as dept_rank,
    PERCENT_RANK() OVER (PARTITION BY department ORDER BY salary) as salary_percentile,
    LAG(salary, 1) OVER (PARTITION BY department ORDER BY hire_date) as prev_salary,
    AVG(salary) OVER (PARTITION BY department) as dept_avg_salary
FROM employee_salaries
ORDER BY department, salary DESC;

-- ========================================
-- SCENARIO 4: Complex Aggregations
-- ========================================

\echo ''
\echo '=== SCENARIO 4: Complex Aggregation Operations ==='

\echo ''
\echo '--- Test 4A: Complex aggregation with work_mem = 2MB ---'
SET work_mem = '2MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    EXTRACT(YEAR FROM uo.order_date) as order_year,
    EXTRACT(MONTH FROM uo.order_date) as order_month,
    pt.random_number / 100 as customer_segment,
    COUNT(*) as order_count,
    SUM(uo.amount) as total_revenue,
    AVG(uo.amount) as avg_order_value,
    STDDEV(uo.amount) as revenue_stddev,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY uo.amount) as median_order,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY uo.amount) as p95_order
FROM user_orders uo
JOIN performance_test pt ON uo.user_id = pt.id
WHERE uo.order_date >= '2023-01-01'
GROUP BY 
    EXTRACT(YEAR FROM uo.order_date),
    EXTRACT(MONTH FROM uo.order_date),
    pt.random_number / 100
HAVING COUNT(*) > 10
ORDER BY order_year, order_month, customer_segment;

\echo ''
\echo '--- Test 4B: Complex aggregation with work_mem = 32MB ---'
SET work_mem = '32MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    EXTRACT(YEAR FROM uo.order_date) as order_year,
    EXTRACT(MONTH FROM uo.order_date) as order_month,
    pt.random_number / 100 as customer_segment,
    COUNT(*) as order_count,
    SUM(uo.amount) as total_revenue,
    AVG(uo.amount) as avg_order_value,
    STDDEV(uo.amount) as revenue_stddev,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY uo.amount) as median_order,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY uo.amount) as p95_order
FROM user_orders uo
JOIN performance_test pt ON uo.user_id = pt.id
WHERE uo.order_date >= '2023-01-01'
GROUP BY 
    EXTRACT(YEAR FROM uo.order_date),
    EXTRACT(MONTH FROM uo.order_date),
    pt.random_number / 100
HAVING COUNT(*) > 10
ORDER BY order_year, order_month, customer_segment;

-- ========================================
-- SCENARIO 5: Monitoring and Analysis
-- ========================================

\echo ''
\echo '=== SCENARIO 5: work_mem Impact Analysis ==='

-- Check temp file usage
\echo ''
\echo '--- Temporary File Usage (indicates work_mem pressure) ---'
SELECT 
    'Current Session' as scope,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) as temp_size_readable,
    CASE 
        WHEN temp_files > 0 THEN 'Consider increasing work_mem'
        ELSE 'work_mem appears sufficient'
    END as recommendation
FROM pg_stat_database 
WHERE datname = current_database();

-- Memory usage recommendations
\echo ''
\echo '--- work_mem Sizing Recommendations ---'
WITH memory_calc AS (
    SELECT 
        current_setting('max_connections')::int as max_conn,
        current_setting('work_mem') as current_work_mem,
        current_setting('shared_buffers') as shared_buffers
)
SELECT 
    'Current work_mem' as setting,
    current_work_mem as value,
    'Per connection memory for sorts/hashes' as description
FROM memory_calc
UNION ALL
SELECT 
    'Max potential work_mem usage',
    pg_size_pretty((max_conn * pg_size_bytes(current_work_mem))::bigint),
    'If all connections use work_mem simultaneously'
FROM memory_calc
UNION ALL
SELECT 
    'Shared buffers',
    shared_buffers,
    'Database buffer cache'
FROM memory_calc;

-- Performance comparison summary
\echo ''
\echo '--- Performance Testing Summary ---'
CREATE TEMP TABLE perf_results AS
SELECT 
    '1MB work_mem' as test_case,
    'Likely external sorts' as expected_behavior,
    'Higher I/O, slower performance' as impact
UNION ALL
SELECT 
    '4-8MB work_mem',
    'Reduced external sorts',
    'Better performance for medium queries'
UNION ALL
SELECT 
    '16-32MB work_mem',
    'Most operations in memory',
    'Best performance, higher memory usage'
UNION ALL
SELECT 
    '64MB+ work_mem',
    'All operations in memory',
    'Diminishing returns, risk of OOM';

SELECT * FROM perf_results;

-- Reset work_mem to default
RESET work_mem;

\echo ''
\echo '=== WORK_MEM TUNING BEST PRACTICES ==='
\echo '1. Start with default (4MB) and monitor temp file usage'
\echo '2. Increase work_mem for sessions running complex queries'
\echo '3. Consider: max_connections × work_mem = total potential memory'
\echo '4. Look for "external merge" or "Disk:" in EXPLAIN output'
\echo '5. Monitor pg_stat_database.temp_files and temp_bytes'
\echo '6. Set per-session: SET work_mem = ''32MB'' for specific queries'
\echo '7. Avoid setting globally too high - risk of out-of-memory'
\echo ''
\echo '🎯 work_mem tuning complete! Use these patterns for production tuning.'
