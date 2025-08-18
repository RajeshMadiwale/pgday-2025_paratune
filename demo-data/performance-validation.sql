-- Performance Validation Script
-- Measures actual performance improvements from parameter tuning

-- ========================================
-- SETUP: Enable timing and clear stats
-- ========================================
\timing on
SELECT pg_stat_reset();

-- ========================================
-- TEST 1: work_mem Impact on Sorting
-- ========================================
\echo '=== Testing work_mem Impact ==='

-- Baseline with low work_mem
SET work_mem = '1MB';
\echo 'Low work_mem (1MB):'
EXPLAIN (ANALYZE, BUFFERS, TIMING) 
SELECT 
    department,
    position,
    COUNT(*) as count,
    AVG(salary) as avg_salary,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) as median
FROM employee_salaries
GROUP BY department, position
ORDER BY department, avg_salary DESC;

-- Optimized with higher work_mem
SET work_mem = '32MB';
\echo 'High work_mem (32MB):'
EXPLAIN (ANALYZE, BUFFERS, TIMING) 
SELECT 
    department,
    position,
    COUNT(*) as count,
    AVG(salary) as avg_salary,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) as median
FROM employee_salaries
GROUP BY department, position
ORDER BY department, avg_salary DESC;

RESET work_mem;

-- ========================================
-- TEST 2: Buffer Cache Effectiveness
-- ========================================
\echo '=== Testing Buffer Cache Performance ==='

-- Cold cache test
SELECT pg_stat_reset();

\echo 'Cold cache - First run:'
SELECT 
    pt.name,
    COUNT(uo.order_id) as orders,
    SUM(uo.amount) as total
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 100 AND 200
GROUP BY pt.id, pt.name
ORDER BY total DESC
LIMIT 50;

\echo 'Warm cache - Second run:'
SELECT 
    pt.name,
    COUNT(uo.order_id) as orders,
    SUM(uo.amount) as total
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 100 AND 200
GROUP BY pt.id, pt.name
ORDER BY total DESC
LIMIT 50;

-- Check cache hit ratio
SELECT 
    'Buffer Cache Hit Ratio: ' || 
    ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) || '%' as metric
FROM pg_stat_database WHERE datname = current_database();

-- ========================================
-- TEST 3: Index Usage Validation
-- ========================================
\echo '=== Testing Index Usage ==='

-- Point lookup (should use index)
\echo 'Point lookup (index expected):'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM performance_test WHERE id = 50000;

-- Range query (may use index or seq scan)
\echo 'Range query on indexed column:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT COUNT(*) FROM performance_test 
WHERE created_at BETWEEN '2024-01-01' AND '2024-01-31';

-- Full table scan (should use seq scan)
\echo 'Large range query (seq scan expected):'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT COUNT(*) FROM performance_test WHERE random_number > 100;

-- ========================================
-- TEST 4: Join Performance Analysis
-- ========================================
\echo '=== Testing Join Performance ==='

-- Small join (nested loop expected)
\echo 'Small selective join:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT pt.name, uo.amount
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.id BETWEEN 1000 AND 1100;

-- Large join (hash join expected)
\echo 'Large join:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT pt.name, COUNT(uo.order_id), AVG(uo.amount)
FROM performance_test pt
LEFT JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 100 AND 300
GROUP BY pt.id, pt.name
LIMIT 100;

-- ========================================
-- TEST 5: Partition Pruning
-- ========================================
\echo '=== Testing Partition Pruning ==='

-- Query targeting specific partition
\echo 'Single partition query:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT COUNT(*), AVG(total_amount)
FROM sales_data 
WHERE sale_date BETWEEN '2024-01-01' AND '2024-01-31';

-- Query spanning multiple partitions
\echo 'Multi-partition query:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT region, COUNT(*), SUM(total_amount)
FROM sales_data 
WHERE sale_date BETWEEN '2024-01-15' AND '2024-02-15'
GROUP BY region;

-- ========================================
-- TEST 6: JSONB Performance
-- ========================================
\echo '=== Testing JSONB Performance ==='

-- JSONB index usage
\echo 'JSONB indexed query:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT COUNT(*) FROM user_profiles 
WHERE profile_data->>'age' = '25';

-- JSONB complex query
\echo 'JSONB complex query:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT 
    profile_data->>'firstName' as name,
    profile_data->'address'->>'city' as city
FROM user_profiles 
WHERE profile_data->'address'->>'city' LIKE 'City 1%'
LIMIT 100;

-- ========================================
-- TEST 7: Full-Text Search
-- ========================================
\echo '=== Testing Full-Text Search ==='

-- GIN index usage
\echo 'Full-text search with GIN index:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT title, ts_rank(search_vector, query) as rank
FROM documents, to_tsquery('postgresql & performance') query
WHERE search_vector @@ query
ORDER BY rank DESC
LIMIT 20;

-- Array search
\echo 'Array search:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT title FROM documents 
WHERE tags @> ARRAY['postgresql'];

-- ========================================
-- TEST 8: Window Functions
-- ========================================
\echo '=== Testing Window Function Performance ==='

\echo 'Window function query:'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT 
    department,
    position,
    salary,
    AVG(salary) OVER (PARTITION BY department) as dept_avg,
    RANK() OVER (PARTITION BY department ORDER BY salary DESC) as dept_rank,
    LAG(salary) OVER (PARTITION BY department ORDER BY hire_date) as prev_salary
FROM employee_salaries
WHERE department IN ('Engineering', 'Sales')
ORDER BY department, salary DESC;

-- ========================================
-- SUMMARY: Performance Metrics
-- ========================================
\echo '=== Performance Summary ==='

-- Table access patterns
SELECT 
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    CASE 
        WHEN seq_scan + idx_scan > 0 
        THEN ROUND(100.0 * idx_scan / (seq_scan + idx_scan), 2) 
        ELSE 0 
    END as index_usage_pct
FROM pg_stat_user_tables
ORDER BY seq_scan + idx_scan DESC;

-- Buffer usage
SELECT 
    'Shared Buffers Hit Ratio: ' || 
    ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) || '%' as buffer_hit_ratio
FROM pg_stat_database 
WHERE datname = current_database();

-- Connection info
SELECT 
    'Active Connections: ' || count(*) as connections
FROM pg_stat_activity 
WHERE state = 'active';

\echo '=== Validation Complete ==='
\echo 'Review EXPLAIN output for:'
\echo '- External merge elimination with higher work_mem'
\echo '- Appropriate index usage vs sequential scans'
\echo '- Efficient join algorithms'
\echo '- Partition pruning effectiveness'
\echo '- GIN index usage for JSONB and full-text search'

\timing off
