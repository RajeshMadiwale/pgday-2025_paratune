-- PostgreSQL Performance Benchmarking Queries
-- Use these to measure and compare performance before/after tuning

-- ========================================
-- BENCHMARK 1: SELECT Performance
-- ========================================

-- Simple point lookups (should use index)
\timing on
SELECT * FROM performance_test WHERE id = 50000;
SELECT * FROM performance_test WHERE name = 'User 25000';
SELECT * FROM performance_test WHERE random_number = 500;
\timing off

-- Range queries
\timing on
SELECT COUNT(*) FROM performance_test 
WHERE created_at BETWEEN '2024-01-01' AND '2024-01-31';

SELECT * FROM performance_test 
WHERE random_number BETWEEN 100 AND 200 
ORDER BY created_at DESC 
LIMIT 100;
\timing off

-- ========================================
-- BENCHMARK 2: JOIN Performance
-- ========================================

-- Simple JOIN
\timing on
SELECT pt.name, COUNT(uo.order_id) as order_count
FROM performance_test pt
LEFT JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.id BETWEEN 1000 AND 2000
GROUP BY pt.id, pt.name
ORDER BY order_count DESC;
\timing off

-- Complex multi-table JOIN
\timing on
SELECT 
    pt.name,
    COUNT(DISTINCT uo.order_id) as orders,
    COUNT(DISTINCT sd.id) as sales,
    COALESCE(SUM(uo.amount), 0) as order_total,
    COALESCE(SUM(sd.total_amount), 0) as sales_total
FROM performance_test pt
LEFT JOIN user_orders uo ON pt.id = uo.user_id
LEFT JOIN sales_data sd ON pt.id = sd.customer_id
WHERE pt.random_number BETWEEN 1 AND 100
GROUP BY pt.id, pt.name
HAVING COUNT(DISTINCT uo.order_id) > 0
ORDER BY order_total DESC
LIMIT 50;
\timing off

-- ========================================
-- BENCHMARK 3: Aggregation Performance
-- ========================================

-- Simple aggregations
\timing on
SELECT 
    COUNT(*) as total_users,
    AVG(random_number) as avg_random,
    MIN(created_at) as earliest,
    MAX(created_at) as latest
FROM performance_test;
\timing off

-- Grouped aggregations (tests work_mem)
\timing on
SELECT 
    DATE_TRUNC('day', created_at) as day,
    COUNT(*) as user_count,
    AVG(random_number) as avg_random,
    STDDEV(random_number) as stddev_random,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY random_number) as median_random
FROM performance_test
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY day;
\timing off

-- ========================================
-- BENCHMARK 4: Sorting Performance
-- ========================================

-- Large sort operation (tests work_mem)
\timing on
SELECT * FROM performance_test 
ORDER BY random_number, created_at, name 
LIMIT 10000;
\timing off

-- Sort with grouping
\timing on
SELECT 
    LEFT(name, 10) as name_prefix,
    COUNT(*) as count,
    AVG(random_number) as avg_random
FROM performance_test
GROUP BY LEFT(name, 10)
ORDER BY count DESC, avg_random DESC;
\timing off

-- ========================================
-- BENCHMARK 5: Full-Text Search Performance
-- ========================================

-- Simple text search
\timing on
SELECT id, title, ts_rank(search_vector, query) as rank
FROM documents, to_tsquery('english', 'postgresql') query
WHERE search_vector @@ query
ORDER BY rank DESC
LIMIT 100;
\timing off

-- Complex text search with filters
\timing on
SELECT 
    d.title,
    d.category,
    ts_rank(d.search_vector, query) as rank,
    ts_headline('english', d.content, query) as snippet
FROM documents d, to_tsquery('english', 'database & performance') query
WHERE d.search_vector @@ query
  AND d.category IN ('Technical', 'Tutorial')
  AND d.tags && ARRAY['postgresql']
ORDER BY rank DESC
LIMIT 50;
\timing off

-- ========================================
-- BENCHMARK 6: JSONB Performance
-- ========================================

-- JSONB containment queries
\timing on
SELECT COUNT(*) FROM user_profiles 
WHERE profile_data @> '{"age": 25}';

SELECT COUNT(*) FROM user_profiles 
WHERE profile_data->'address'->>'city' LIKE 'City 1%';
\timing off

-- JSONB aggregations
\timing on
SELECT 
    preferences->>'theme' as theme,
    COUNT(*) as user_count,
    AVG((profile_data->>'age')::int) as avg_age,
    COUNT(DISTINCT profile_data->'address'->>'city') as unique_cities
FROM user_profiles 
WHERE profile_data->>'age' IS NOT NULL
GROUP BY preferences->>'theme'
ORDER BY user_count DESC;
\timing off

-- ========================================
-- BENCHMARK 7: Window Functions Performance
-- ========================================

-- Ranking operations
\timing on
SELECT 
    employee_id,
    department,
    salary,
    RANK() OVER (PARTITION BY department ORDER BY salary DESC) as dept_rank,
    DENSE_RANK() OVER (ORDER BY salary DESC) as overall_rank,
    PERCENT_RANK() OVER (PARTITION BY department ORDER BY salary) as percentile
FROM employee_salaries
ORDER BY department, dept_rank;
\timing off

-- Running calculations
\timing on
SELECT 
    department,
    hire_date,
    salary,
    SUM(salary) OVER (PARTITION BY department ORDER BY hire_date 
                      ROWS UNBOUNDED PRECEDING) as running_total,
    AVG(salary) OVER (PARTITION BY department ORDER BY hire_date 
                      ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as moving_avg,
    LAG(salary, 1) OVER (PARTITION BY department ORDER BY hire_date) as prev_salary
FROM employee_salaries
ORDER BY department, hire_date;
\timing off

-- ========================================
-- BENCHMARK 8: Subquery Performance
-- ========================================

-- Correlated subquery
\timing on
SELECT 
    pt.id,
    pt.name,
    (SELECT COUNT(*) FROM user_orders uo WHERE uo.user_id = pt.id) as order_count,
    (SELECT MAX(uo.amount) FROM user_orders uo WHERE uo.user_id = pt.id) as max_order
FROM performance_test pt
WHERE pt.random_number BETWEEN 1 AND 100
ORDER BY order_count DESC;
\timing off

-- EXISTS vs IN comparison
\timing on
-- Using EXISTS
SELECT COUNT(*) FROM performance_test pt
WHERE EXISTS (
    SELECT 1 FROM user_orders uo 
    WHERE uo.user_id = pt.id AND uo.amount > 500
);

-- Using IN
SELECT COUNT(*) FROM performance_test pt
WHERE pt.id IN (
    SELECT DISTINCT uo.user_id FROM user_orders uo 
    WHERE uo.amount > 500
);
\timing off

-- ========================================
-- BENCHMARK 9: Partition Performance
-- ========================================

-- Query single partition
\timing on
SELECT region, COUNT(*), SUM(total_amount)
FROM sales_data 
WHERE sale_date BETWEEN '2024-02-01' AND '2024-02-28'
GROUP BY region;
\timing off

-- Query multiple partitions
\timing on
SELECT 
    DATE_TRUNC('month', sale_date) as month,
    region,
    COUNT(*) as sales_count,
    SUM(total_amount) as total_revenue
FROM sales_data 
WHERE sale_date BETWEEN '2024-01-15' AND '2024-03-15'
GROUP BY DATE_TRUNC('month', sale_date), region
ORDER BY month, total_revenue DESC;
\timing off

-- ========================================
-- BENCHMARK 10: Concurrent Load Test
-- ========================================

-- Function to simulate concurrent workload
CREATE OR REPLACE FUNCTION benchmark_concurrent_load()
RETURNS TABLE(operation TEXT, duration INTERVAL) AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    -- Test 1: Multiple SELECT operations
    start_time := clock_timestamp();
    PERFORM COUNT(*) FROM performance_test WHERE random_number < 100;
    PERFORM COUNT(*) FROM user_orders WHERE amount > 100;
    PERFORM COUNT(*) FROM sales_data WHERE region = 'North';
    end_time := clock_timestamp();
    
    operation := 'Multiple SELECTs';
    duration := end_time - start_time;
    RETURN NEXT;
    
    -- Test 2: Mixed read/write operations
    start_time := clock_timestamp();
    INSERT INTO performance_test (name, email, random_number) 
    VALUES ('Benchmark User', 'bench@test.com', 999);
    
    UPDATE performance_test SET random_number = 1000 
    WHERE name = 'Benchmark User';
    
    SELECT COUNT(*) FROM performance_test WHERE random_number = 1000;
    
    DELETE FROM performance_test WHERE name = 'Benchmark User';
    end_time := clock_timestamp();
    
    operation := 'Mixed Operations';
    duration := end_time - start_time;
    RETURN NEXT;
    
    -- Test 3: Complex analytical query
    start_time := clock_timestamp();
    PERFORM 
        pt.name,
        COUNT(DISTINCT uo.order_id) as orders,
        AVG(uo.amount) as avg_amount,
        RANK() OVER (ORDER BY COUNT(uo.order_id) DESC) as rank
    FROM performance_test pt
    LEFT JOIN user_orders uo ON pt.id = uo.user_id
    WHERE pt.random_number BETWEEN 1 AND 50
    GROUP BY pt.id, pt.name
    HAVING COUNT(uo.order_id) > 0
    ORDER BY orders DESC
    LIMIT 20;
    end_time := clock_timestamp();
    
    operation := 'Analytical Query';
    duration := end_time - start_time;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- Run the benchmark
SELECT * FROM benchmark_concurrent_load();

-- ========================================
-- PERFORMANCE SUMMARY QUERIES
-- ========================================

-- Overall database statistics
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
    'Total Indexes',
    COUNT(*)::text
FROM pg_indexes WHERE schemaname = 'public'
UNION ALL
SELECT 
    'Cache Hit Ratio',
    ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2)::text || '%'
FROM pg_stat_database WHERE datname = current_database();

-- Top 5 largest tables
SELECT 
    'Top Tables by Size' as category,
    tablename,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size('public.'||tablename) DESC
LIMIT 5;