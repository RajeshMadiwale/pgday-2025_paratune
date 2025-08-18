-- PostgreSQL Parameter Tuning Scenarios
-- Step-by-step exercises for different tuning parameters
-- 
-- This file contains practical scenarios for tuning key PostgreSQL parameters:
-- 1. work_mem - Memory for sorting and grouping operations
-- 2. shared_buffers - Database buffer cache
-- 3. effective_cache_size - OS cache size estimate
-- 4. random_page_cost - Storage speed setting
--
-- Usage: \i /demo-data/parameter-tuning-scenarios.sql

-- ========================================
-- SCENARIO 1: work_mem Tuning
-- ========================================

-- Before tuning: Check current work_mem
SHOW work_mem;

\echo '=== WORK_MEM TUNING DEMONSTRATION ==='
\echo 'Testing with different work_mem values to show external sort behavior'
\echo ''

-- Step 1: Test with very low work_mem (should cause external sorts)
\echo '--- TEST 1: Low work_mem (1MB) - Expect external sorts ---'
SET work_mem = '1MB';
SHOW work_mem;

\timing on
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    pt.name,
    pt.email,
    STRING_AGG(uo.order_date::text, ',' ORDER BY uo.amount DESC) as order_dates,
    COUNT(*) as order_count,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) as rank
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 1 AND 5000
GROUP BY pt.id, pt.name, pt.email
ORDER BY pt.name, COUNT(*) DESC;
\timing off

-- Step 2: Test with medium work_mem
\echo ''
\echo '--- TEST 2: Medium work_mem (8MB) - Should reduce external sorts ---'
SET work_mem = '8MB';
SHOW work_mem;

\timing on
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    pt.name,
    pt.email,
    STRING_AGG(uo.order_date::text, ',' ORDER BY uo.amount DESC) as order_dates,
    COUNT(*) as order_count,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) as rank
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 1 AND 5000
GROUP BY pt.id, pt.name, pt.email
ORDER BY pt.name, COUNT(*) DESC;
\timing off

-- Step 3: Test with high work_mem (should eliminate external sorts)
\echo ''
\echo '--- TEST 3: High work_mem (32MB) - Should eliminate external sorts ---'
SET work_mem = '32MB';
SHOW work_mem;

\timing on
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT 
    pt.name,
    pt.email,
    STRING_AGG(uo.order_date::text, ',' ORDER BY uo.amount DESC) as order_dates,
    COUNT(*) as order_count,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) as rank
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 1 AND 5000
GROUP BY pt.id, pt.name, pt.email
ORDER BY pt.name, COUNT(*) DESC;
\timing off

-- Step 4: Complex aggregation query that definitely needs more work_mem
\echo ''
\echo '--- TEST 4: Complex aggregation with different work_mem values ---'

-- Low work_mem test
SET work_mem = '2MB';
\echo 'Complex query with work_mem = 2MB:'
\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    department,
    position,
    COUNT(*) as employee_count,
    AVG(salary) as avg_salary,
    STDDEV(salary) as salary_stddev,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) as median_salary,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) as q1_salary,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) as q3_salary
FROM employee_salaries
GROUP BY department, position
HAVING COUNT(*) > 10
ORDER BY department, avg_salary DESC;
\timing off

-- High work_mem test
SET work_mem = '16MB';
\echo ''
\echo 'Same query with work_mem = 16MB:'
\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    department,
    position,
    COUNT(*) as employee_count,
    AVG(salary) as avg_salary,
    STDDEV(salary) as salary_stddev,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) as median_salary,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) as q1_salary,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) as q3_salary
FROM employee_salaries
GROUP BY department, position
HAVING COUNT(*) > 10
ORDER BY department, avg_salary DESC;
\timing off

-- Step 5: Monitor temp file usage (indicates work_mem pressure)
\echo ''
\echo '--- TEMP FILE USAGE MONITORING ---'
SELECT 
    datname,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) as temp_size_readable
FROM pg_stat_database 
WHERE datname = current_database();

-- Reset to session default
RESET work_mem;

\echo ''
\echo '=== WORK_MEM TUNING KEY POINTS ==='
\echo '1. Look for "external merge" or "external sort" in EXPLAIN output'
\echo '2. Monitor temp_files and temp_bytes in pg_stat_database'
\echo '3. Higher work_mem reduces disk I/O but uses more memory'
\echo '4. Set per-session for specific queries, not globally'
\echo '5. Consider max_connections * work_mem for total memory impact'

-- ========================================
-- SCENARIO 2: shared_buffers Impact
-- ========================================

-- shared_buffers is PostgreSQL's main buffer cache
-- Current setting (check postgresql.conf): shared_buffers = 256MB
-- This scenario demonstrates buffer cache effectiveness

-- Step 1: Reset statistics to get clean measurements
SELECT pg_stat_reset();

-- Warm up the database connection
SELECT 1;

-- Step 2: Cold cache test - first run will read from disk
\echo ''
\echo 'COLD CACHE TEST (first run - expect disk reads):'
\echo 'Look for "read=" in BUFFERS output (indicates disk I/O)'
\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    pt.name,
    pt.email,
    COUNT(uo.order_id) as order_count,
    SUM(uo.amount) as total_amount
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 100 AND 1000
GROUP BY pt.id, pt.name, pt.email
ORDER BY total_amount DESC
LIMIT 100;
\timing off

-- Check buffer statistics after cold run
SELECT 
    'After Cold Cache' as test_phase,
    sum(blks_read) as disk_reads,
    sum(blks_hit) as buffer_hits,
    CASE 
        WHEN sum(blks_hit) + sum(blks_read) > 0 
        THEN ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2)
        ELSE 0 
    END as hit_ratio_pct
FROM pg_stat_database 
WHERE datname = current_database();

-- Step 3: Warm cache test - second run should hit buffer cache
\echo ''
\echo 'WARM CACHE TEST (second run - expect buffer hits):'
\echo 'Look for "hit=" in BUFFERS output (indicates cache usage)'
\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    pt.name,
    pt.email,
    COUNT(uo.order_id) as order_count,
    SUM(uo.amount) as total_amount
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 100 AND 1000
GROUP BY pt.id, pt.name, pt.email
ORDER BY total_amount DESC
LIMIT 100;
\timing off

-- Check buffer statistics after warm run
SELECT 
    'After Warm Cache' as test_phase,
    sum(blks_read) as disk_reads,
    sum(blks_hit) as buffer_hits,
    CASE 
        WHEN sum(blks_hit) + sum(blks_read) > 0 
        THEN ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2)
        ELSE 0 
    END as hit_ratio_pct
FROM pg_stat_database 
WHERE datname = current_database();

-- Step 4: Test with different query to show cache persistence
\echo ''
\echo 'CACHE PERSISTENCE TEST (different query on same tables):'
\timing on
SELECT COUNT(*) as total_users, 
       AVG(random_number) as avg_random
FROM performance_test 
WHERE random_number BETWEEN 150 AND 1500;
\timing off

-- Step 4a: Force cache pressure test
\echo ''
\echo 'CACHE PRESSURE TEST (large scan to test shared_buffers limits):'
\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    COUNT(*) as total_orders,
    AVG(amount) as avg_amount,
    MIN(order_date) as earliest_order,
    MAX(order_date) as latest_order
FROM user_orders
WHERE amount > 100;
\timing off

-- Step 5: Buffer cache analysis by table
SELECT 
    schemaname,
    relname,
    heap_blks_read,
    heap_blks_hit,
    CASE 
        WHEN heap_blks_hit + heap_blks_read > 0 
        THEN ROUND(100.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 2)
        ELSE 0 
    END as table_hit_ratio_pct,
    idx_blks_read,
    idx_blks_hit,
    CASE 
        WHEN idx_blks_hit + idx_blks_read > 0 
        THEN ROUND(100.0 * idx_blks_hit / (idx_blks_hit + idx_blks_read), 2)
        ELSE 0 
    END as index_hit_ratio_pct
FROM pg_statio_user_tables
WHERE heap_blks_read + heap_blks_hit > 0
ORDER BY heap_blks_read + heap_blks_hit DESC;

-- Exercise: Understanding shared_buffers impact
-- 1. Low shared_buffers (64MB): More disk I/O, lower hit ratios
-- 2. Optimal shared_buffers (256MB): Good balance, high hit ratios  
-- 3. High shared_buffers (1GB): Diminishing returns, may hurt other processes

-- Key metrics to watch:
-- - Hit ratio should be >90% for frequently accessed data
-- - 'read' operations in EXPLAIN BUFFERS indicate disk I/O
-- - 'hit' operations indicate successful buffer cache usage

-- ========================================
-- SCENARIO 3: effective_cache_size Impact
-- ========================================

-- effective_cache_size tells the planner how much memory is available for caching
-- It affects index vs sequential scan decisions
-- Current setting: effective_cache_size = 1GB

\echo ''
\echo '=== EFFECTIVE_CACHE_SIZE DEMONSTRATION ==='
\echo 'Testing how effective_cache_size affects query planning decisions'
\echo ''

-- Show current setting
SHOW effective_cache_size;

-- Test query that can use index or sequential scan
\echo '--- TEST 1: Low effective_cache_size (128MB) - May favor seq scans ---'
SET effective_cache_size = '128MB';
SHOW effective_cache_size;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    d.title,
    d.category,
    d.author_id,
    up.profile_data->>'firstName' as author_name,
    up.profile_data->>'age' as age
FROM documents d
JOIN user_profiles up ON d.author_id = up.user_id
WHERE d.category IN ('Technical', 'Business', 'Science')
  AND up.profile_data->>'age'::int BETWEEN 25 AND 45
ORDER BY d.created_at DESC
LIMIT 100;
\timing off

\echo ''
\echo '--- TEST 2: Medium effective_cache_size (1GB) - Balanced decisions ---'
SET effective_cache_size = '1GB';
SHOW effective_cache_size;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    d.title,
    d.category,
    d.author_id,
    up.profile_data->>'firstName' as author_name,
    up.profile_data->>'age' as age
FROM documents d
JOIN user_profiles up ON d.author_id = up.user_id
WHERE d.category IN ('Technical', 'Business', 'Science')
  AND up.profile_data->>'age'::int BETWEEN 25 AND 45
ORDER BY d.created_at DESC
LIMIT 100;
\timing off

\echo ''
\echo '--- TEST 3: High effective_cache_size (4GB) - May favor index scans ---'
SET effective_cache_size = '4GB';
SHOW effective_cache_size;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    d.title,
    d.category,
    d.author_id,
    up.profile_data->>'firstName' as author_name,
    up.profile_data->>'age' as age
FROM documents d
JOIN user_profiles up ON d.author_id = up.user_id
WHERE d.category IN ('Technical', 'Business', 'Science')
  AND up.profile_data->>'age'::int BETWEEN 25 AND 45
ORDER BY d.created_at DESC
LIMIT 100;
\timing off

-- Reset to default
SET effective_cache_size = '1GB';

\echo ''
\echo '=== EFFECTIVE_CACHE_SIZE KEY POINTS ==='
\echo '1. Higher values favor index scans over sequential scans'
\echo '2. Should be set to ~75% of total system RAM'
\echo '3. Only affects planning, not actual memory usage'
\echo '4. Look for "Seq Scan" vs "Index Scan" in EXPLAIN output'

-- ========================================
-- SCENARIO 4: random_page_cost Tuning
-- ========================================

-- random_page_cost affects the planner's cost estimation for random I/O
-- Lower values favor index scans, higher values favor sequential scans
-- Current setting: random_page_cost = 1.1 (SSD optimized)

\echo ''
\echo '=== RANDOM_PAGE_COST DEMONSTRATION ==='
\echo 'Testing how random_page_cost affects index vs sequential scan decisions'
\echo ''

-- Show current setting
SHOW random_page_cost;

-- Query that can benefit from index or sequential scan
\echo '--- TEST 1: High random_page_cost (4.0) - HDD setting, favors seq scans ---'
SET random_page_cost = 4.0;
SHOW random_page_cost;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    sd.sale_id,
    sd.customer_id,
    sd.total_amount,
    sd.sale_date,
    pt.name as customer_name
FROM sales_data sd
JOIN performance_test pt ON sd.customer_id = pt.id
WHERE sd.customer_id IN (
    SELECT id 
    FROM performance_test 
    WHERE random_number BETWEEN 500 AND 800
)
AND sd.total_amount > 500
ORDER BY sd.sale_date DESC
LIMIT 200;
\timing off

\echo ''
\echo '--- TEST 2: Medium random_page_cost (1.1) - SSD setting, balanced ---'
SET random_page_cost = 1.1;
SHOW random_page_cost;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    sd.sale_id,
    sd.customer_id,
    sd.total_amount,
    sd.sale_date,
    pt.name as customer_name
FROM sales_data sd
JOIN performance_test pt ON sd.customer_id = pt.id
WHERE sd.customer_id IN (
    SELECT id 
    FROM performance_test 
    WHERE random_number BETWEEN 500 AND 800
)
AND sd.total_amount > 500
ORDER BY sd.sale_date DESC
LIMIT 200;
\timing off

\echo ''
\echo '--- TEST 3: Low random_page_cost (1.0) - Very fast storage, favors index scans ---'
SET random_page_cost = 1.0;
SHOW random_page_cost;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    sd.sale_id,
    sd.customer_id,
    sd.total_amount,
    sd.sale_date,
    pt.name as customer_name
FROM sales_data sd
JOIN performance_test pt ON sd.customer_id = pt.id
WHERE sd.customer_id IN (
    SELECT id 
    FROM performance_test 
    WHERE random_number BETWEEN 500 AND 800
)
AND sd.total_amount > 500
ORDER BY sd.sale_date DESC
LIMIT 200;
\timing off

-- Reset to SSD default
SET random_page_cost = 1.1;

\echo ''
\echo '=== RANDOM_PAGE_COST KEY POINTS ==='
\echo '1. HDD (4.0): High cost for random I/O, favors sequential scans'
\echo '2. SSD (1.1): Lower random I/O cost, more likely to use indexes'
\echo '3. NVMe (1.0): Very low random I/O cost, strongly favors indexes'
\echo '4. Look for plan changes: "Seq Scan" vs "Index Scan" vs "Bitmap Scan"'

-- ========================================
-- SCENARIO 5: maintenance_work_mem for Operations
-- ========================================

-- maintenance_work_mem affects VACUUM, CREATE INDEX, and other maintenance operations
-- Higher values speed up these operations significantly

\echo ''
\echo '=== MAINTENANCE_WORK_MEM DEMONSTRATION ==='
\echo 'Testing index creation speed with different maintenance_work_mem values'
\echo ''

-- Show current setting
SHOW maintenance_work_mem;

-- Create test table with substantial data
DROP TABLE IF EXISTS maintenance_test;
CREATE TABLE maintenance_test AS 
SELECT 
    generate_series(1, 100000) as id,
    'Name_' || generate_series(1, 100000) as name,
    random() * 10000 as value,
    md5(generate_series(1, 100000)::text) as hash_value
FROM generate_series(1, 100000);

\echo '--- TEST 1: Low maintenance_work_mem (4MB) - Slower index creation ---'
SET maintenance_work_mem = '4MB';
SHOW maintenance_work_mem;

\timing on
CREATE INDEX idx_maintenance_low ON maintenance_test(name, value);
\timing off
DROP INDEX idx_maintenance_low;

\echo ''
\echo '--- TEST 2: High maintenance_work_mem (64MB) - Faster index creation ---'
SET maintenance_work_mem = '64MB';
SHOW maintenance_work_mem;

\timing on
CREATE INDEX idx_maintenance_high ON maintenance_test(name, value);
\timing off

-- Test VACUUM performance
\echo ''
\echo '--- VACUUM Performance Test ---'
-- Generate some dead tuples
UPDATE maintenance_test SET value = value + 1 WHERE id % 3 = 0;
DELETE FROM maintenance_test WHERE id % 10 = 0;

SET maintenance_work_mem = '4MB';
\echo 'VACUUM with maintenance_work_mem = 4MB:'
\timing on
VACUUM maintenance_test;
\timing off

-- Create more dead tuples
UPDATE maintenance_test SET value = value + 1 WHERE id % 4 = 0;
DELETE FROM maintenance_test WHERE id % 15 = 0;

SET maintenance_work_mem = '64MB';
\echo 'VACUUM with maintenance_work_mem = 64MB:'
\timing on
VACUUM maintenance_test;
\timing off

-- Cleanup
DROP TABLE maintenance_test;
RESET maintenance_work_mem;

\echo ''
\echo '=== MAINTENANCE_WORK_MEM KEY POINTS ==='
\echo '1. Higher values significantly speed up CREATE INDEX operations'
\echo '2. Improves VACUUM performance on tables with many dead tuples'
\echo '3. Safe to set high (256MB-1GB) as it only affects maintenance operations'
\echo '4. Watch timing differences - should see 2-5x improvement'

-- ========================================
-- SCENARIO 6: checkpoint_completion_target Impact
-- ========================================

-- checkpoint_completion_target spreads checkpoint I/O over time
-- Current setting affects write performance and I/O spikes

\echo ''
\echo '=== CHECKPOINT_COMPLETION_TARGET DEMONSTRATION ==='
\echo 'Monitoring checkpoint behavior during write-heavy workload'
\echo ''

-- Show current checkpoint settings
SELECT name, setting, unit FROM pg_settings 
WHERE name IN ('checkpoint_completion_target', 'max_wal_size', 'checkpoint_timeout');

-- Reset checkpoint statistics
SELECT pg_stat_reset_shared('checkpointer');

-- Baseline checkpoint stats
SELECT 
    'Before Write Load' as phase,
    num_timed,
    num_requested,
    write_time,
    sync_time
FROM pg_stat_checkpointer;

\echo ''
\echo '--- Generating write-heavy workload ---'
\timing on

-- Create write activity to trigger checkpoints
DROP TABLE IF EXISTS checkpoint_test;
CREATE TABLE checkpoint_test AS SELECT 1 as dummy;

DO $$
DECLARE
    i INTEGER;
BEGIN
    FOR i IN 1..5000 LOOP
        INSERT INTO checkpoint_test 
        SELECT 
            generate_series(1, 100),
            'Data batch ' || i,
            random() * 1000,
            now()
        FROM generate_series(1, 100);
        
        -- Force some updates to generate WAL
        UPDATE checkpoint_test 
        SET dummy = dummy + 1 
        WHERE random() < 0.1;
        
        -- Commit every 500 operations
        IF i % 500 = 0 THEN
            PERFORM pg_sleep(0.1);
        END IF;
    END LOOP;
END $$;

\timing off

-- Check checkpoint activity after load
SELECT 
    'After Write Load' as phase,
    num_timed,
    num_requested,
    write_time,
    sync_time,
    CASE 
        WHEN num_requested > num_timed 
        THEN 'Many forced checkpoints - consider increasing max_wal_size'
        ELSE 'Normal checkpoint behavior'
    END as analysis
FROM pg_stat_checkpointer;

-- Show current WAL usage
SELECT 
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')) as wal_generated,
    pg_size_pretty(pg_database_size(current_database())) as db_size;

-- Cleanup
DROP TABLE checkpoint_test;

\echo ''
\echo '=== CHECKPOINT_COMPLETION_TARGET KEY POINTS ==='
\echo '1. Lower values (0.5): Faster checkpoints, more I/O spikes'
\echo '2. Higher values (0.9): Slower checkpoints, smoother I/O'
\echo '3. Monitor num_requested vs num_timed ratio'
\echo '4. High forced checkpoints indicate need for larger max_wal_size'

-- ========================================
-- SCENARIO 7: Connection Management Impact
-- ========================================

-- max_connections affects memory usage and connection overhead
-- Each connection uses work_mem + maintenance_work_mem + connection overhead

\echo ''
\echo '=== CONNECTION MANAGEMENT DEMONSTRATION ==='
\echo 'Understanding connection limits and memory impact'
\echo ''

-- Show current connection settings
SELECT name, setting, unit FROM pg_settings 
WHERE name IN ('max_connections', 'superuser_reserved_connections');

-- Calculate theoretical memory usage
SELECT 
    'Memory Calculation' as analysis,
    current_setting('max_connections')::int as max_connections,
    current_setting('work_mem') as work_mem_per_conn,
    current_setting('maintenance_work_mem') as maint_work_mem,
    pg_size_pretty(
        current_setting('max_connections')::bigint * 
        (pg_size_bytes(current_setting('work_mem')) + 
         pg_size_bytes(current_setting('maintenance_work_mem')) +
         1048576)  -- ~1MB connection overhead
    ) as theoretical_max_memory;

-- Current connection analysis
SELECT 
    'Current Connections' as category,
    COUNT(*) as total_connections,
    COUNT(*) FILTER (WHERE state = 'active') as active_connections,
    COUNT(*) FILTER (WHERE state = 'idle') as idle_connections,
    COUNT(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction,
    ROUND(COUNT(*)::numeric / current_setting('max_connections')::numeric * 100, 2) as connection_usage_pct
FROM pg_stat_activity;

-- Connection duration analysis
SELECT 
    'Connection Duration Analysis' as category,
    COUNT(*) FILTER (WHERE backend_start > now() - interval '1 minute') as connections_last_1min,
    COUNT(*) FILTER (WHERE backend_start > now() - interval '5 minutes') as connections_last_5min,
    COUNT(*) FILTER (WHERE backend_start > now() - interval '1 hour') as connections_last_1hour,
    AVG(EXTRACT(EPOCH FROM (now() - backend_start))) as avg_connection_age_seconds
FROM pg_stat_activity
WHERE pid != pg_backend_pid();

-- Simulate connection pressure test
\echo ''
\echo '--- Connection Pressure Simulation ---'
\echo 'Testing query performance under different connection scenarios'

-- Test 1: Simple query performance baseline
\timing on
SELECT COUNT(*), AVG(random_number) FROM performance_test WHERE random_number < 1000;
\timing off

-- Test 2: Memory-intensive query (simulates multiple concurrent users)
SET work_mem = '1MB';  -- Simulate resource pressure
\timing on
SELECT 
    name,
    COUNT(*) as order_count,
    STRING_AGG(DISTINCT email, ', ') as emails
FROM performance_test 
WHERE random_number BETWEEN 1 AND 2000
GROUP BY name
ORDER BY COUNT(*) DESC
LIMIT 50;
\timing off

RESET work_mem;

-- Show locks and blocking (connection contention indicators)
SELECT 
    'Lock Analysis' as category,
    COUNT(*) as total_locks,
    COUNT(*) FILTER (WHERE NOT granted) as waiting_locks,
    COUNT(DISTINCT pid) as processes_with_locks
FROM pg_locks;

\echo ''
\echo '=== CONNECTION MANAGEMENT KEY POINTS ==='
\echo '1. Each connection uses work_mem + maintenance_work_mem + ~1MB overhead'
\echo '2. Too many connections can cause memory pressure and context switching'
\echo '3. Monitor connection usage: should stay <80% of max_connections'
\echo '4. Use connection pooling (pgbouncer) for high-connection applications'
\echo '5. Watch for "idle in transaction" connections - they hold locks'

-- ========================================
-- SCENARIO 8: Autovacuum Tuning Impact
-- ========================================

-- Autovacuum parameters control when and how aggressively VACUUM runs
-- Key parameters: autovacuum_vacuum_threshold, autovacuum_vacuum_scale_factor

\echo ''
\echo '=== AUTOVACUUM TUNING DEMONSTRATION ==='
\echo 'Understanding autovacuum triggers and table bloat'
\echo ''

-- Show current autovacuum settings
SELECT name, setting FROM pg_settings 
WHERE name LIKE 'autovacuum%' 
AND name IN ('autovacuum', 'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor', 'autovacuum_analyze_threshold');

-- Create test table and generate activity
DROP TABLE IF EXISTS autovacuum_demo;
CREATE TABLE autovacuum_demo AS 
SELECT 
    generate_series(1, 50000) as id,
    'Original data ' || generate_series(1, 50000) as data,
    random() * 1000 as value
FROM generate_series(1, 50000);

-- Check initial table stats
SELECT 
    'Initial State' as phase,
    schemaname,
    relname,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_dead_tup as dead_tuples,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables 
WHERE relname = 'autovacuum_demo';

-- Generate significant update/delete activity
\echo ''
\echo '--- Generating table bloat (updates and deletes) ---'
\timing on

-- Heavy update activity
UPDATE autovacuum_demo 
SET data = 'Updated data ' || id, 
    value = value + random() * 100
WHERE id % 2 = 0;

-- Delete some rows
DELETE FROM autovacuum_demo WHERE id % 10 = 0;

-- More updates to create dead tuples
UPDATE autovacuum_demo 
SET data = 'Second update ' || id
WHERE id % 3 = 0;

\timing off

-- Check table stats after modifications
SELECT 
    'After Modifications' as phase,
    schemaname,
    relname,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_dead_tup as dead_tuples,
    ROUND(n_dead_tup::numeric / NULLIF(n_tup_ins + n_tup_upd + n_tup_del, 0) * 100, 2) as dead_tuple_pct,
    pg_size_pretty(pg_total_relation_size('autovacuum_demo')) as table_size
FROM pg_stat_user_tables 
WHERE relname = 'autovacuum_demo';

-- Calculate autovacuum threshold
SELECT 
    'Autovacuum Threshold Analysis' as analysis,
    reltuples::bigint as estimated_tuples,
    current_setting('autovacuum_vacuum_threshold')::int as vacuum_threshold,
    current_setting('autovacuum_vacuum_scale_factor')::numeric as scale_factor,
    (current_setting('autovacuum_vacuum_threshold')::int + 
     current_setting('autovacuum_vacuum_scale_factor')::numeric * reltuples)::bigint as autovac_trigger_point,
    (SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'autovacuum_demo') as current_dead_tuples,
    CASE 
        WHEN (SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'autovacuum_demo') > 
             (current_setting('autovacuum_vacuum_threshold')::int + 
              current_setting('autovacuum_vacuum_scale_factor')::numeric * reltuples)
        THEN 'SHOULD TRIGGER AUTOVACUUM'
        ELSE 'Below autovacuum threshold'
    END as autovacuum_status
FROM pg_class 
WHERE relname = 'autovacuum_demo';

-- Manual VACUUM to show the difference
\echo ''
\echo '--- Manual VACUUM to demonstrate cleanup ---'
\timing on
VACUUM ANALYZE autovacuum_demo;
\timing off

-- Check stats after VACUUM
SELECT 
    'After VACUUM' as phase,
    schemaname,
    relname,
    n_dead_tup as dead_tuples,
    pg_size_pretty(pg_total_relation_size('autovacuum_demo')) as table_size,
    last_vacuum
FROM pg_stat_user_tables 
WHERE relname = 'autovacuum_demo';

-- Cleanup
DROP TABLE autovacuum_demo;

\echo ''
\echo '=== AUTOVACUUM KEY POINTS ==='
\echo '1. Autovacuum triggers when dead_tuples > threshold + (scale_factor * total_tuples)'
\echo '2. Default: threshold=50, scale_factor=0.2 (20% of table must be dead)'
\echo '3. High update/delete activity needs more aggressive autovacuum settings'
\echo '4. Monitor n_dead_tup and table bloat regularly'
\echo '5. Consider per-table autovacuum settings for busy tables'

-- ========================================
-- SCENARIO 9: Parallel Query Tuning
-- ========================================

-- Parallel query parameters control when PostgreSQL uses multiple workers
-- Key settings: max_parallel_workers_per_gather, parallel_tuple_cost, parallel_setup_cost

\echo ''
\echo '=== PARALLEL QUERY DEMONSTRATION ==='
\echo 'Testing parallel execution for large aggregations'
\echo ''

-- Show current parallel settings
SELECT name, setting FROM pg_settings 
WHERE name IN (
    'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'parallel_tuple_cost',
    'parallel_setup_cost',
    'min_parallel_table_scan_size'
);

-- Test query that benefits from parallelization
\echo '--- TEST 1: Parallel execution DISABLED ---'
SET max_parallel_workers_per_gather = 0;
SET parallel_tuple_cost = 1.0;
SET parallel_setup_cost = 1000.0;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    EXTRACT(YEAR FROM sale_date) as sale_year,
    EXTRACT(MONTH FROM sale_date) as sale_month,
    region,
    COUNT(*) as sales_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_sale,
    STDDEV(total_amount) as revenue_stddev,
    MIN(total_amount) as min_sale,
    MAX(total_amount) as max_sale
FROM sales_data
WHERE sale_date >= '2024-01-01'
GROUP BY EXTRACT(YEAR FROM sale_date), EXTRACT(MONTH FROM sale_date), region
ORDER BY sale_year, sale_month, total_revenue DESC;
\timing off

\echo ''
\echo '--- TEST 2: Parallel execution ENABLED ---'
SET max_parallel_workers_per_gather = 4;
SET parallel_tuple_cost = 0.1;
SET parallel_setup_cost = 1000.0;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    EXTRACT(YEAR FROM sale_date) as sale_year,
    EXTRACT(MONTH FROM sale_date) as sale_month,
    region,
    COUNT(*) as sales_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_sale,
    STDDEV(total_amount) as revenue_stddev,
    MIN(total_amount) as min_sale,
    MAX(total_amount) as max_sale
FROM sales_data
WHERE sale_date >= '2024-01-01'
GROUP BY EXTRACT(YEAR FROM sale_date), EXTRACT(MONTH FROM sale_date), region
ORDER BY sale_year, sale_month, total_revenue DESC;
\timing off

-- Test parallel-friendly aggregation
\echo ''
\echo '--- TEST 3: Large table scan with parallel aggregation ---'
SET max_parallel_workers_per_gather = 2;
SET parallel_tuple_cost = 0.1;

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    COUNT(*) as total_orders,
    COUNT(DISTINCT customer_id) as unique_customers,
    SUM(amount) as total_amount,
    AVG(amount) as avg_order_value,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) as median_amount,
    COUNT(*) FILTER (WHERE amount > 1000) as large_orders
FROM user_orders
WHERE order_date >= '2024-01-01';
\timing off

-- Reset to defaults
RESET max_parallel_workers_per_gather;
RESET parallel_tuple_cost;
RESET parallel_setup_cost;

\echo ''
\echo '=== PARALLEL QUERY KEY POINTS ==='
\echo '1. Look for "Parallel" nodes in EXPLAIN output (Parallel Seq Scan, Parallel Aggregate)'
\echo '2. Workers Planned vs Workers Launched shows actual parallelization'
\echo '3. Parallel queries work best on large tables with CPU-intensive operations'
\echo '4. Lower parallel_tuple_cost encourages more parallel execution'
\echo '5. Ensure max_parallel_workers_per_gather > 0 and sufficient CPU cores'

-- ========================================
-- SCENARIO 10: Memory Usage Analysis & Optimization
-- ========================================

-- Comprehensive memory analysis and optimization recommendations
-- Tests actual memory pressure and provides tuning guidance

\echo ''
\echo '=== MEMORY USAGE ANALYSIS & OPTIMIZATION ==='
\echo 'Analyzing current memory configuration and usage patterns'
\echo ''

-- Current memory configuration
SELECT 
    'Current Memory Settings' as category,
    name,
    setting,
    unit,
    CASE 
        WHEN unit = '8kB' THEN pg_size_pretty(setting::bigint * 8192)
        WHEN unit = 'kB' THEN pg_size_pretty(setting::bigint * 1024)
        WHEN unit = 'MB' THEN pg_size_pretty(setting::bigint * 1024 * 1024)
        ELSE setting || COALESCE(unit, '')
    END as readable_value
FROM pg_settings 
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'temp_buffers'
)
ORDER BY name;

-- Calculate total theoretical memory usage
WITH memory_calc AS (
    SELECT 
        current_setting('max_connections')::bigint as max_conn,
        pg_size_bytes(current_setting('shared_buffers')) as shared_buf,
        pg_size_bytes(current_setting('work_mem')) as work_mem_bytes,
        pg_size_bytes(current_setting('maintenance_work_mem')) as maint_mem_bytes
)
SELECT 
    'Memory Usage Calculation' as analysis,
    pg_size_pretty(shared_buf) as shared_buffers_size,
    pg_size_pretty(work_mem_bytes * max_conn) as max_work_mem_total,
    pg_size_pretty(shared_buf + (work_mem_bytes * max_conn) + (maint_mem_bytes * 5)) as estimated_max_usage,
    CASE 
        WHEN (shared_buf + (work_mem_bytes * max_conn)) > 8589934592 -- 8GB
        THEN 'WARNING: High memory usage - consider reducing work_mem or max_connections'
        ELSE 'Memory usage appears reasonable'
    END as recommendation
FROM memory_calc;

-- Test memory pressure scenarios
\echo ''
\echo '--- Memory Pressure Test 1: Low work_mem scenario ---'
SET work_mem = '1MB';

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    pt.name,
    COUNT(DISTINCT uo.order_id) as order_count,
    STRING_AGG(DISTINCT uo.order_date::text, ',' ORDER BY uo.order_date::text) as order_dates,
    SUM(uo.amount) as total_spent,
    ROW_NUMBER() OVER (ORDER BY SUM(uo.amount) DESC) as spending_rank
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 1 AND 3000
GROUP BY pt.id, pt.name
ORDER BY total_spent DESC
LIMIT 100;
\timing off

-- Check for temp file usage (indicates memory pressure)
SELECT 
    'Memory Pressure Check' as category,
    datname,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) as temp_size,
    CASE 
        WHEN temp_files > 0 THEN 'Memory pressure detected - consider increasing work_mem'
        ELSE 'No temp file usage - work_mem sufficient'
    END as analysis
FROM pg_stat_database 
WHERE datname = current_database();

\echo ''
\echo '--- Memory Pressure Test 2: Adequate work_mem scenario ---'
SET work_mem = '16MB';

\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    pt.name,
    COUNT(DISTINCT uo.order_id) as order_count,
    STRING_AGG(DISTINCT uo.order_date::text, ',' ORDER BY uo.order_date::text) as order_dates,
    SUM(uo.amount) as total_spent,
    ROW_NUMBER() OVER (ORDER BY SUM(uo.amount) DESC) as spending_rank
FROM performance_test pt
JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 1 AND 3000
GROUP BY pt.id, pt.name
ORDER BY total_spent DESC
LIMIT 100;
\timing off

-- Database size and memory efficiency
SELECT 
    'Database Size Analysis' as category,
    pg_size_pretty(pg_database_size(current_database())) as database_size,
    pg_size_pretty(sum(pg_total_relation_size(oid))) as total_table_size,
    COUNT(*) as table_count
FROM pg_class 
WHERE relkind = 'r';

-- Buffer cache effectiveness
SELECT 
    'Buffer Cache Analysis' as category,
    sum(blks_read) as total_disk_reads,
    sum(blks_hit) as total_buffer_hits,
    CASE 
        WHEN sum(blks_hit) + sum(blks_read) > 0 
        THEN ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2)
        ELSE 0 
    END as hit_ratio_pct,
    CASE 
        WHEN ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) > 95 
        THEN 'Excellent buffer cache performance'
        WHEN ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) > 90 
        THEN 'Good buffer cache performance'
        ELSE 'Consider increasing shared_buffers'
    END as recommendation
FROM pg_stat_database 
WHERE datname = current_database();

-- Reset work_mem
RESET work_mem;

\echo ''
\echo '=== MEMORY OPTIMIZATION RECOMMENDATIONS ==='
\echo '1. shared_buffers: 25% of RAM for dedicated DB server, 15% for mixed workload'
\echo '2. work_mem: Start with 4MB, increase if you see temp file usage'
\echo '3. maintenance_work_mem: 256MB-1GB for faster VACUUM and CREATE INDEX'
\echo '4. effective_cache_size: 50-75% of total system RAM'
\echo '5. Monitor temp_files and buffer hit ratios regularly'
\echo '6. Total memory = shared_buffers + (work_mem × max_connections) + OS overhead'

-- ========================================
-- PARAMETER TUNING SUMMARY
-- ========================================

\echo '=== Parameter Tuning Scenarios Complete ==='
\echo ''
\echo 'Key Takeaways:'
\echo '1. work_mem: Increase to eliminate external sorts (watch for memory usage)'
\echo '2. shared_buffers: Monitor hit ratios >90% for optimal performance'
\echo '3. effective_cache_size: Set to 50-75% of total RAM for better planning'
\echo '4. random_page_cost: Lower for SSDs (1.1) vs HDDs (4.0)'
\echo ''
\echo 'Next Steps:'
\echo '- Run: make monitor (comprehensive monitoring)'
\echo '- Run: make benchmark (performance testing)'
\echo '- Run: make perf-test (detailed validation)'
\echo ''
\echo '🎯 Ready for production parameter tuning!'