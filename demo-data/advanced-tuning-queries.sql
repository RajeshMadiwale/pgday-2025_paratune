-- Advanced PostgreSQL Tuning Demo Queries
-- These queries demonstrate complex scenarios and advanced tuning concepts

-- ========================================
-- 1. PARTITION PRUNING AND PERFORMANCE
-- ========================================

-- Query that benefits from partition pruning
EXPLAIN (ANALYZE, BUFFERS) 
SELECT region, SUM(total_amount) as total_sales
FROM sales_data 
WHERE sale_date BETWEEN '2024-02-01' AND '2024-02-28'
GROUP BY region;

-- Query that scans multiple partitions
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, COUNT(*) as purchase_count, SUM(total_amount) as total_spent
FROM sales_data 
WHERE sale_date >= '2024-01-15' AND sale_date <= '2024-03-15'
GROUP BY customer_id
HAVING SUM(total_amount) > 1000
ORDER BY total_spent DESC;

-- ========================================
-- 2. FULL-TEXT SEARCH OPTIMIZATION
-- ========================================

-- Basic full-text search
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, ts_rank(search_vector, query) as rank
FROM documents, to_tsquery('english', 'postgresql & performance') query
WHERE search_vector @@ query
ORDER BY rank DESC
LIMIT 20;

-- Complex full-text search with filters
EXPLAIN (ANALYZE, BUFFERS)
SELECT d.title, d.category, d.tags,
       ts_headline('english', d.content, query) as snippet
FROM documents d, to_tsquery('english', 'database | optimization') query
WHERE d.search_vector @@ query
  AND d.category = 'Technical'
  AND d.tags && ARRAY['postgresql', 'performance']
ORDER BY ts_rank(d.search_vector, query) DESC;

-- ========================================
-- 3. JSONB QUERY OPTIMIZATION
-- ========================================

-- JSONB containment queries
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, profile_data->'firstName' as name, profile_data->'age' as age
FROM user_profiles 
WHERE profile_data @> '{"age": 25}';

-- JSONB path queries
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, profile_data->'address'->>'city' as city
FROM user_profiles 
WHERE profile_data->'address'->>'city' LIKE 'City 1%';

-- JSONB array operations
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, profile_data->'skills' as skills
FROM user_profiles 
WHERE profile_data->'skills' ? 'postgresql';

-- Complex JSONB aggregation
SELECT 
    preferences->>'theme' as theme,
    COUNT(*) as user_count,
    AVG((profile_data->>'age')::int) as avg_age
FROM user_profiles 
WHERE profile_data->>'age' IS NOT NULL
GROUP BY preferences->>'theme';

-- ========================================
-- 4. WINDOW FUNCTIONS AND ANALYTICS
-- ========================================

-- Ranking within departments
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    employee_id,
    department,
    position,
    salary,
    RANK() OVER (PARTITION BY department ORDER BY salary DESC) as dept_rank,
    PERCENT_RANK() OVER (PARTITION BY department ORDER BY salary) as salary_percentile
FROM employee_salaries
WHERE department IN ('Engineering', 'Sales');

-- Running totals and moving averages
SELECT 
    department,
    hire_date,
    salary,
    SUM(salary) OVER (PARTITION BY department ORDER BY hire_date 
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as running_total,
    AVG(salary) OVER (PARTITION BY department ORDER BY hire_date 
                      ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as moving_avg
FROM employee_salaries
ORDER BY department, hire_date;

-- ========================================
-- 5. COMPLEX JOINS AND SUBQUERIES
-- ========================================

-- Multi-table join with aggregations
EXPLAIN (ANALYZE, BUFFERS)
WITH customer_stats AS (
    SELECT 
        pt.id,
        pt.name,
        COUNT(DISTINCT uo.order_id) as order_count,
        SUM(uo.amount) as total_spent,
        COUNT(DISTINCT sd.id) as sales_interactions
    FROM performance_test pt
    LEFT JOIN user_orders uo ON pt.id = uo.user_id
    LEFT JOIN sales_data sd ON pt.id = sd.customer_id
    GROUP BY pt.id, pt.name
),
customer_segments AS (
    SELECT *,
        CASE 
            WHEN total_spent > 5000 THEN 'Premium'
            WHEN total_spent > 1000 THEN 'Standard'
            ELSE 'Basic'
        END as segment
    FROM customer_stats
    WHERE order_count > 0
)
SELECT 
    segment,
    COUNT(*) as customer_count,
    AVG(total_spent) as avg_spent,
    AVG(order_count) as avg_orders
FROM customer_segments
GROUP BY segment
ORDER BY avg_spent DESC;

-- Correlated subquery example
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    es1.employee_id,
    es1.department,
    es1.salary,
    (SELECT COUNT(*) 
     FROM employee_salaries es2 
     WHERE es2.department = es1.department 
       AND es2.salary > es1.salary) as higher_paid_colleagues
FROM employee_salaries es1
WHERE es1.department = 'Engineering'
ORDER BY es1.salary DESC;

-- ========================================
-- 6. RECURSIVE QUERIES (CTE)
-- ========================================

-- Hierarchical data simulation
WITH RECURSIVE org_chart AS (
    -- Base case: top-level managers
    SELECT employee_id, department, position, salary, 1 as level, 
           ARRAY[employee_id] as path
    FROM employee_salaries 
    WHERE position LIKE '%Manager%'
    
    UNION ALL
    
    -- Recursive case: employees under managers
    SELECT es.employee_id, es.department, es.position, es.salary, 
           oc.level + 1, oc.path || es.employee_id
    FROM employee_salaries es
    JOIN org_chart oc ON es.department = oc.department
    WHERE es.position NOT LIKE '%Manager%' 
      AND oc.level < 3
      AND NOT es.employee_id = ANY(oc.path)
)
SELECT department, level, COUNT(*) as employee_count, AVG(salary) as avg_salary
FROM org_chart
GROUP BY department, level
ORDER BY department, level;

-- ========================================
-- 7. PERFORMANCE MONITORING QUERIES
-- ========================================

-- Table and index sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - 
                   pg_relation_size(schemaname||'.'||tablename)) as index_size
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Index usage statistics
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Buffer cache hit ratios by table
SELECT 
    schemaname,
    tablename,
    heap_blks_read,
    heap_blks_hit,
    CASE 
        WHEN heap_blks_hit + heap_blks_read = 0 THEN 0
        ELSE ROUND(heap_blks_hit::numeric / (heap_blks_hit + heap_blks_read) * 100, 2)
    END as hit_ratio_percent
FROM pg_statio_user_tables
WHERE heap_blks_read + heap_blks_hit > 0
ORDER BY hit_ratio_percent ASC;

-- Long-running queries
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    now() - query_start as duration,
    LEFT(query, 100) as query_preview
FROM pg_stat_activity 
WHERE state = 'active' 
  AND query_start < now() - interval '1 minute'
ORDER BY duration DESC;

-- ========================================
-- 8. VACUUM AND MAINTENANCE QUERIES
-- ========================================

-- Table bloat estimation
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_dead_tup as dead_tuples,
    CASE 
        WHEN n_tup_ins + n_tup_upd + n_tup_del = 0 THEN 0
        ELSE ROUND(n_dead_tup::numeric / (n_tup_ins + n_tup_upd + n_tup_del) * 100, 2)
    END as dead_tuple_percent
FROM pg_stat_user_tables
ORDER BY dead_tuple_percent DESC;

-- Autovacuum activity
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count,
    last_analyze,
    last_autoanalyze,
    analyze_count,
    autoanalyze_count
FROM pg_stat_user_tables
ORDER BY last_autovacuum DESC NULLS LAST;