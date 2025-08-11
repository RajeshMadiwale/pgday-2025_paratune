-- PostgreSQL Tuning Step-by-Step Tutorial
-- Practical exercises that work with the demo data

-- ========================================
-- STEP 1: Understanding Your Data
-- ========================================

-- First, let's see what tables we have
\dt

-- Check table sizes
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) as size,
    (SELECT COUNT(*) FROM performance_test WHERE tablename = 'performance_test') as row_count_sample
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY pg_total_relation_size('public.'||tablename) DESC;

-- ========================================
-- STEP 2: Basic Query Performance Analysis
-- ========================================

-- Let's start with a simple query and analyze it
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM performance_test WHERE id = 50000;

-- Now try a query that will do a sequential scan
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM performance_test WHERE name LIKE 'User 5%';

-- Check if we have indexes
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE schemaname = 'public' 
  AND tablename = 'performance_test';

-- ========================================
-- STEP 3: work_mem Tuning Exercise
-- ========================================

-- Check current work_mem setting
SHOW work_mem;

-- Query that will use memory for sorting
-- First, let's see the current performance
\timing on

SELECT 
    LEFT(name, 10) as name_prefix,
    COUNT(*) as count,
    AVG(random_number) as avg_random
FROM performance_test
GROUP BY LEFT(name, 10)
ORDER BY count DESC, avg_random DESC;

\timing off

-- Now let's try with different work_mem values
-- Try with low work_mem (may cause external sorts)
SET work_mem = '1MB';
SHOW work_mem;

\timing on
SELECT 
    LEFT(name, 10) as name_prefix,
    COUNT(*) as count,
    AVG(random_number) as avg_random
FROM performance_test
GROUP BY LEFT(name, 10)
ORDER BY count DESC, avg_random DESC;
\timing off

-- Try with higher work_mem
SET work_mem = '16MB';
SHOW work_mem;

\timing on
SELECT 
    LEFT(name, 10) as name_prefix,
    COUNT(*) as count,
    AVG(random_number) as avg_random
FROM performance_test
GROUP BY LEFT(name, 10)
ORDER BY count DESC, avg_random DESC;
\timing off

-- Reset to default
RESET work_mem;

-- ========================================
-- STEP 4: Index Usage Analysis
-- ========================================

-- Query using index (should be fast)
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM performance_test WHERE id BETWEEN 1000 AND 1100;

-- Query that might not use index efficiently
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM performance_test WHERE random_number BETWEEN 100 AND 200;

-- Let's see index usage statistics
SELECT 
    schemaname,
    relname,
    indexrelname,
    idx_scan as times_used,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- ========================================
-- STEP 5: JOIN Performance Testing
-- ========================================

-- Simple JOIN test
\timing on
SELECT 
    pt.name,
    COUNT(uo.order_id) as order_count,
    COALESCE(SUM(uo.amount), 0) as total_amount
FROM performance_test pt
LEFT JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.id BETWEEN 1 AND 1000
GROUP BY pt.id, pt.name
ORDER BY total_amount DESC
LIMIT 20;
\timing off

-- Analyze the JOIN strategy
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    pt.name,
    COUNT(uo.order_id) as order_count
FROM performance_test pt
LEFT JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.id BETWEEN 1 AND 1000
GROUP BY pt.id, pt.name
LIMIT 20;

-- ========================================
-- STEP 6: Buffer Cache Analysis
-- ========================================

-- Check buffer cache hit ratio
SELECT 
    'Buffer Cache Hit Ratio' as metric,
    ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) || '%' as value
FROM pg_stat_database 
WHERE datname = current_database();

-- Run a query multiple times to see caching effect
-- First run (cold cache)
\timing on
SELECT COUNT(*) FROM performance_test WHERE random_number < 500;
\timing off

-- Second run (should be faster due to caching)
\timing on
SELECT COUNT(*) FROM performance_test WHERE random_number < 500;
\timing off

-- Check table-level cache statistics
SELECT 
    schemaname,
    relname,
    heap_blks_read,
    heap_blks_hit,
    CASE 
        WHEN heap_blks_read + heap_blks_hit = 0 THEN 0
        ELSE ROUND(heap_blks_hit::numeric / (heap_blks_read + heap_blks_hit) * 100, 2)
    END as hit_ratio_percent
FROM pg_statio_user_tables
WHERE heap_blks_read + heap_blks_hit > 0
ORDER BY heap_blks_read + heap_blks_hit DESC;

-- ========================================
-- STEP 7: Configuration Analysis
-- ========================================

-- Check current key configuration parameters
SELECT 
    name,
    setting,
    unit,
    short_desc
FROM pg_settings 
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'random_page_cost',
    'max_connections'
)
ORDER BY name;

-- ========================================
-- STEP 8: Simple Performance Monitoring
-- ========================================

-- Check current database activity
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    LEFT(query, 50) as query_preview
FROM pg_stat_activity 
WHERE state = 'active' 
  AND pid != pg_backend_pid();

-- Check table access patterns
SELECT 
    schemaname,
    relname,
    seq_scan as sequential_scans,
    seq_tup_read as seq_tuples_read,
    idx_scan as index_scans,
    idx_tup_fetch as idx_tuples_fetched,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes
FROM pg_stat_user_tables
ORDER BY seq_scan + idx_scan DESC;

-- ========================================
-- STEP 9: Practical Tuning Exercise
-- ========================================

-- Let's create a scenario where we can see the impact of tuning

-- First, let's create some load and measure it
DO $$
DECLARE
    start_time timestamp;
    end_time timestamp;
    duration interval;
BEGIN
    start_time := clock_timestamp();
    
    -- Simulate some work
    PERFORM COUNT(*) FROM performance_test pt
    JOIN user_orders uo ON pt.id = uo.user_id
    WHERE pt.random_number BETWEEN 1 AND 100;
    
    end_time := clock_timestamp();
    duration := end_time - start_time;
    
    RAISE NOTICE 'Query completed in: %', duration;
END $$;

-- ========================================
-- STEP 10: Summary and Next Steps
-- ========================================

-- Database overview
SELECT 
    'Database Size' as metric,
    pg_size_pretty(pg_database_size(current_database())) as value
UNION ALL
SELECT 
    'Total Tables',
    COUNT(*)::text
FROM pg_tables WHERE schemaname = 'public'
UNION ALL
SELECT 
    'Cache Hit Ratio',
    ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2)::text || '%'
FROM pg_stat_database WHERE datname = current_database();

-- Recommendations based on what we've learned:
SELECT 
    'Tuning Recommendations' as category,
    'Check work_mem for sorting operations' as recommendation
UNION ALL
SELECT 
    'Tuning Recommendations',
    'Monitor buffer cache hit ratios'
UNION ALL
SELECT 
    'Tuning Recommendations',
    'Analyze query plans with EXPLAIN'
UNION ALL
SELECT 
    'Tuning Recommendations',
    'Review index usage patterns'
UNION ALL
SELECT 
    'Tuning Recommendations',
    'Monitor connection and query activity';

-- ========================================
-- BONUS: Interactive Exercises
-- ========================================

-- Try these exercises on your own:

-- Exercise 1: Find the slowest queries
-- Hint: Look at pg_stat_statements if available

-- Exercise 2: Identify unused indexes
-- Hint: Check pg_stat_user_indexes for idx_scan = 0

-- Exercise 3: Find tables that need VACUUM
-- Hint: Look at pg_stat_user_tables for n_dead_tup

-- Exercise 4: Test different JOIN strategies
-- Hint: Use SET enable_nestloop = off; to force different join types

-- Exercise 5: Monitor real-time activity
-- Hint: Query pg_stat_activity repeatedly to see changes