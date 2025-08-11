-- PostgreSQL Query Analysis with pg_stat_statements
-- This file demonstrates how to use pg_stat_statements for query performance analysis

-- ========================================
-- CHECK EXTENSION STATUS
-- ========================================

-- Check if pg_stat_statements is available
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') 
        THEN '✅ pg_stat_statements is ENABLED'
        ELSE '❌ pg_stat_statements is NOT ENABLED'
    END as extension_status;

-- If not enabled, show how to enable it
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        RAISE NOTICE '';
        RAISE NOTICE '🔧 To enable pg_stat_statements:';
        RAISE NOTICE '';
        RAISE NOTICE '1. Quick method (using Make):';
        RAISE NOTICE '   Exit psql and run: make enable-stats';
        RAISE NOTICE '';
        RAISE NOTICE '2. Manual method:';
        RAISE NOTICE '   a) Edit postgresql.conf: shared_preload_libraries = ''pg_stat_statements''';
        RAISE NOTICE '   b) Restart container: docker-compose restart';
        RAISE NOTICE '   c) Create extension: CREATE EXTENSION pg_stat_statements;';
        RAISE NOTICE '';
        RAISE NOTICE '⚠️  Note: shared_preload_libraries requires a PostgreSQL restart!';
        RAISE NOTICE '';
    END IF;
END $$;

-- ========================================
-- QUERY PERFORMANCE ANALYSIS
-- (Only works if pg_stat_statements is enabled)
-- ========================================

-- Top 10 queries by total execution time
SELECT 
    'Top Queries by Total Time' as analysis_type,
    query,
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND((100 * total_exec_time / sum(total_exec_time) OVER())::numeric, 2) as percent_total_time
FROM pg_stat_statements 
WHERE calls > 1
ORDER BY total_exec_time DESC 
LIMIT 10;

-- Top 10 queries by average execution time
SELECT 
    'Top Queries by Average Time' as analysis_type,
    query,
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND(max_exec_time::numeric, 2) as max_time_ms
FROM pg_stat_statements 
WHERE calls > 5
ORDER BY mean_exec_time DESC 
LIMIT 10;

-- Most frequently called queries
SELECT 
    'Most Frequent Queries' as analysis_type,
    query,
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms
FROM pg_stat_statements 
ORDER BY calls DESC 
LIMIT 10;

-- Queries with high I/O (buffer reads)
SELECT 
    'High I/O Queries' as analysis_type,
    query,
    calls,
    shared_blks_hit + shared_blks_read as total_buffers,
    ROUND((shared_blks_hit + shared_blks_read)::numeric / calls, 2) as avg_buffers_per_call,
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) as hit_ratio_percent
FROM pg_stat_statements 
WHERE shared_blks_hit + shared_blks_read > 1000
ORDER BY total_buffers DESC 
LIMIT 10;

-- ========================================
-- GENERATE SAMPLE WORKLOAD
-- ========================================

-- Generate some sample queries to populate pg_stat_statements
-- (Run this section to create data for analysis)

-- Sample SELECT queries
SELECT COUNT(*) FROM performance_test WHERE random_number < 100;
SELECT COUNT(*) FROM performance_test WHERE random_number BETWEEN 100 AND 200;
SELECT COUNT(*) FROM performance_test WHERE random_number > 900;

-- Sample JOIN queries
SELECT COUNT(*) 
FROM performance_test pt 
JOIN user_orders uo ON pt.id = uo.user_id 
WHERE pt.random_number < 50;

-- Sample aggregation queries
SELECT 
    LEFT(name, 5) as name_prefix,
    COUNT(*) as count,
    AVG(random_number) as avg_random
FROM performance_test 
WHERE random_number BETWEEN 200 AND 300
GROUP BY LEFT(name, 5)
ORDER BY count DESC
LIMIT 10;

-- ========================================
-- QUERY ANALYSIS UTILITIES
-- ========================================

-- Function to show query statistics for a specific query pattern
CREATE OR REPLACE FUNCTION analyze_query_pattern(pattern TEXT)
RETURNS TABLE(
    query TEXT,
    calls BIGINT,
    total_time_ms NUMERIC,
    avg_time_ms NUMERIC,
    hit_ratio_percent NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pss.query,
        pss.calls,
        ROUND(pss.total_exec_time::numeric, 2),
        ROUND(pss.mean_exec_time::numeric, 2),
        ROUND(100.0 * pss.shared_blks_hit / NULLIF(pss.shared_blks_hit + pss.shared_blks_read, 0), 2)
    FROM pg_stat_statements pss
    WHERE pss.query ILIKE '%' || pattern || '%'
    ORDER BY pss.total_exec_time DESC;
END;
$$ LANGUAGE plpgsql;

-- Example usage of the analysis function
-- SELECT * FROM analyze_query_pattern('performance_test');

-- ========================================
-- MAINTENANCE COMMANDS
-- ========================================

-- Reset pg_stat_statements (clears all collected statistics)
-- Uncomment the line below to reset statistics
-- SELECT pg_stat_statements_reset();

-- Show pg_stat_statements configuration
SELECT 
    name,
    setting,
    unit,
    short_desc
FROM pg_settings 
WHERE name LIKE 'pg_stat_statements%'
ORDER BY name;

-- ========================================
-- USAGE INSTRUCTIONS
-- ========================================

SELECT 
    'Query Analysis Instructions' as section,
    'How to use pg_stat_statements:' as instruction,
    '1. Enable the extension (see above if not enabled)' as step
UNION ALL
SELECT 
    'Query Analysis Instructions',
    '',
    '2. Run queries to generate statistics'
UNION ALL
SELECT 
    'Query Analysis Instructions',
    '',
    '3. Analyze performance using the queries above'
UNION ALL
SELECT 
    'Query Analysis Instructions',
    '',
    '4. Use EXPLAIN ANALYZE for detailed query plans'
UNION ALL
SELECT 
    'Query Analysis Instructions',
    '',
    '5. Reset statistics periodically with pg_stat_statements_reset()'
UNION ALL
SELECT 
    'Query Analysis Instructions',
    'Key metrics to monitor:',
    '- total_exec_time: Total time spent in query'
UNION ALL
SELECT 
    'Query Analysis Instructions',
    '',
    '- mean_exec_time: Average time per execution'
UNION ALL
SELECT 
    'Query Analysis Instructions',
    '',
    '- calls: Number of times query was executed'
UNION ALL
SELECT 
    'Query Analysis Instructions',
    '',
    '- shared_blks_hit/read: Buffer cache efficiency';