-- PostgreSQL Parameter Tuning Scenarios
-- Step-by-step exercises for different tuning parameters

-- ========================================
-- SCENARIO 1: work_mem Tuning
-- ========================================

-- Before tuning: Check current work_mem
SHOW work_mem;

-- Query that will benefit from increased work_mem (sorting/grouping)
-- This query should show "external merge" in EXPLAIN ANALYZE if work_mem is too low
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    department,
    position,
    COUNT(*) as employee_count,
    AVG(salary) as avg_salary,
    STDDEV(salary) as salary_stddev,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) as median_salary
FROM employee_salaries
GROUP BY department, position
ORDER BY department, avg_salary DESC;

-- Exercise: Try these work_mem values and compare performance:
-- SET work_mem = '1MB';  -- Low (may cause external sorts)
-- SET work_mem = '8MB';  -- Medium
-- SET work_mem = '32MB'; -- High (should eliminate external sorts)

-- Reset to session default
RESET work_mem;

-- ========================================
-- SCENARIO 2: shared_buffers Impact
-- ========================================

-- Query to test buffer cache effectiveness
-- Run multiple times to see caching effects
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    pt.name,
    pt.email,
    COUNT(uo.order_id) as order_count,
    SUM(uo.amount) as total_amount
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 100 AND 200
GROUP BY pt.id, pt.name, pt.email
ORDER BY total_amount DESC
LIMIT 100;

-- Check buffer hit ratio after running the query
SELECT 
    'Shared Buffers Hit Ratio' as metric,
    ROUND(
        100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2
    ) as percentage
FROM pg_stat_database;

-- ========================================
-- SCENARIO 3: effective_cache_size Impact
-- ========================================

-- Query that benefits from proper effective_cache_size setting
-- This affects the query planner's decisions about index usage
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    d.title,
    d.category,
    d.author_id,
    up.profile_data->>'firstName' as author_name
FROM documents d
JOIN user_profiles up ON d.author_id = up.user_id
WHERE d.category = 'Technical'
  AND up.profile_data->>'age' > '30'
ORDER BY d.created_at DESC
LIMIT 50;

-- Compare with different effective_cache_size values:
-- SET effective_cache_size = '128MB';  -- Low
-- SET effective_cache_size = '1GB';    -- Medium (current)
-- SET effective_cache_size = '4GB';    -- High

-- ========================================
-- SCENARIO 4: random_page_cost Tuning
-- ========================================

-- Query that involves random I/O patterns
-- Lower random_page_cost favors index scans over sequential scans
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM sales_data
WHERE customer_id IN (
    SELECT id 
    FROM performance_test 
    WHERE random_number BETWEEN 500 AND 600
)
ORDER BY sale_date;

-- Test with different random_page_cost values:
-- SET random_page_cost = 4.0;   -- Traditional HDD setting
-- SET random_page_cost = 1.1;   -- SSD setting (current)
-- SET random_page_cost = 1.0;   -- Very fast storage

-- ========================================
-- SCENARIO 5: maintenance_work_mem for Operations
-- ========================================

-- Create a test table for maintenance operations
CREATE TEMP TABLE maintenance_test AS 
SELECT * FROM performance_test WHERE random_number < 500;

-- Check current maintenance_work_mem
SHOW maintenance_work_mem;

-- Create an index (benefits from higher maintenance_work_mem)
-- Monitor the time this takes
\timing on
CREATE INDEX idx_maintenance_test_name ON maintenance_test(name);
\timing off

-- Vacuum operation (also benefits from maintenance_work_mem)
\timing on
VACUUM ANALYZE maintenance_test;
\timing off

-- Exercise: Try different maintenance_work_mem values:
-- SET maintenance_work_mem = '16MB';  -- Low
-- SET maintenance_work_mem = '64MB';  -- Medium (current)
-- SET maintenance_work_mem = '256MB'; -- High

-- ========================================
-- SCENARIO 6: checkpoint_completion_target
-- ========================================

-- Generate write-heavy workload to test checkpoint behavior
-- This simulates the impact of checkpoint_completion_target

DO $$
DECLARE
    i INTEGER;
BEGIN
    FOR i IN 1..1000 LOOP
        INSERT INTO performance_test (name, email, random_number)
        VALUES ('Checkpoint Test ' || i, 'test' || i || '@example.com', i);
        
        UPDATE performance_test 
        SET random_number = random_number + 1 
        WHERE id = (SELECT id FROM performance_test ORDER BY random() LIMIT 1);
        
        -- Commit every 100 operations
        IF i % 100 = 0 THEN
            COMMIT;
        END IF;
    END LOOP;
END $$;

-- Monitor checkpoint activity
SELECT 
    'Checkpoint Analysis' as category,
    num_timed as checkpoints_timed,
    num_requested as checkpoints_requested,
    ROUND(num_requested::numeric / NULLIF(num_timed + num_requested, 0) * 100, 2) as forced_checkpoint_percent,
    write_time as checkpoint_write_time,
    sync_time as checkpoint_sync_time,
    CASE 
        WHEN num_requested > num_timed THEN 'Too many forced checkpoints - increase max_wal_size'
        WHEN write_time > sync_time * 10 THEN 'Slow checkpoint writes - check I/O'
        ELSE 'OK'
    END as recommendation
FROM pg_stat_checkpointer;

-- ========================================
-- SCENARIO 7: Connection Pooling Impact
-- ========================================

-- Simulate multiple concurrent connections
-- This query helps understand max_connections impact

SELECT 
    state,
    COUNT(*) as connection_count,
    AVG(EXTRACT(EPOCH FROM (now() - query_start))) as avg_duration_seconds
FROM pg_stat_activity 
WHERE pid != pg_backend_pid()
GROUP BY state;

-- Query to show connection usage over time
SELECT 
    datname,
    usename,
    application_name,
    state,
    backend_start,
    query_start,
    state_change
FROM pg_stat_activity
ORDER BY backend_start;

-- ========================================
-- SCENARIO 8: Autovacuum Tuning
-- ========================================

-- Create a table with high update activity for autovacuum testing
CREATE TEMP TABLE autovacuum_test AS 
SELECT * FROM performance_test LIMIT 10000;

-- Generate update activity
UPDATE autovacuum_test SET random_number = random_number + 1;
UPDATE autovacuum_test SET name = name || ' updated' WHERE id % 2 = 0;
DELETE FROM autovacuum_test WHERE id % 10 = 0;

-- Check table statistics for autovacuum decisions
SELECT 
    schemaname,
    tablename,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_dead_tup,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables 
WHERE tablename LIKE '%autovacuum_test%';

-- ========================================
-- SCENARIO 9: Parallel Query Tuning
-- ========================================

-- Check current parallel settings
SELECT name, setting FROM pg_settings 
WHERE name IN (
    'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'parallel_tuple_cost',
    'parallel_setup_cost'
);

-- Query that can benefit from parallelization
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    region,
    COUNT(*) as sales_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_sale,
    STDDEV(total_amount) as revenue_stddev
FROM sales_data
WHERE sale_date >= '2024-01-01'
GROUP BY region
ORDER BY total_revenue DESC;

-- Force parallel execution (if supported)
SET max_parallel_workers_per_gather = 4;
SET parallel_tuple_cost = 0.1;
SET parallel_setup_cost = 1000.0;

-- Re-run the query to see parallel execution
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    region,
    COUNT(*) as sales_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_sale
FROM sales_data
WHERE sale_date >= '2024-01-01'
GROUP BY region
ORDER BY total_revenue DESC;

-- ========================================
-- SCENARIO 10: Memory Usage Monitoring
-- ========================================

-- Query to monitor current memory usage
SELECT 
    name,
    setting,
    unit,
    context,
    short_desc
FROM pg_settings 
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'temp_buffers'
)
ORDER BY name;

-- Check current memory allocation
SELECT 
    pg_size_pretty(pg_database_size(current_database())) as database_size,
    pg_size_pretty(sum(pg_total_relation_size(oid))) as total_table_size
FROM pg_class 
WHERE relkind = 'r';

-- Monitor temporary file usage (indicates work_mem pressure)
SELECT 
    datname,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) as temp_size
FROM pg_stat_database 
WHERE datname = current_database();