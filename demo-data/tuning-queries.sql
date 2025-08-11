-- PostgreSQL Tuning Demo Queries
-- Use these queries to demonstrate various performance tuning concepts

-- 1. Basic SELECT with different WHERE clauses
-- Test index usage vs table scan
SELECT * FROM performance_test WHERE name = 'User 1000';
SELECT * FROM performance_test WHERE random_number = 500;
SELECT * FROM performance_test WHERE created_at > '2024-01-01';

-- 2. JOIN performance demonstration
-- Test different join strategies
SELECT pt.name, COUNT(uo.order_id) as order_count
FROM performance_test pt
LEFT JOIN user_orders uo ON pt.id = uo.user_id
GROUP BY pt.id, pt.name
ORDER BY order_count DESC
LIMIT 100;

-- 3. Aggregation queries for work_mem tuning
SELECT 
    DATE_TRUNC('day', created_at) as day,
    COUNT(*) as user_count,
    AVG(random_number) as avg_random
FROM performance_test
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY day;

-- 4. Complex query for shared_buffers demonstration
WITH user_stats AS (
    SELECT 
        pt.id,
        pt.name,
        COUNT(uo.order_id) as order_count,
        SUM(uo.amount) as total_amount
    FROM performance_test pt
    LEFT JOIN user_orders uo ON pt.id = uo.user_id
    GROUP BY pt.id, pt.name
),
ranked_users AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY total_amount DESC) as rank
    FROM user_stats
    WHERE order_count > 0
)
SELECT * FROM ranked_users WHERE rank <= 50;

-- 5. CPU-intensive query for demonstration
SELECT 
    id,
    name,
    cpu_intensive_function(1000) as cpu_result
FROM performance_test
WHERE id <= 100;

-- 6. Memory-intensive query
SELECT * FROM memory_test_function();

-- 7. Query to show current configuration
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'random_page_cost',
    'max_connections'
);

-- 8. Query to show current activity
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    LEFT(query, 50) as query_preview
FROM pg_stat_activity
WHERE state = 'active';

-- 9. Query to show table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;