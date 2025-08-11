-- PostgreSQL Comprehensive Monitoring Dashboard
-- Complete monitoring solution combining simple monitoring and advanced dashboard features
-- All queries tested and verified to work with PostgreSQL 17

-- ========================================
-- SYSTEM OVERVIEW & HEALTH CHECK
-- ========================================

-- Database overview with health indicators
SELECT 
    'System Overview' as section,
    'Database Name' as metric,
    current_database() as value,
    'Current database being monitored' as description
UNION ALL
SELECT 
    'System Overview',
    'Database Size',
    pg_size_pretty(pg_database_size(current_database())),
    'Total database size including indexes'
UNION ALL
SELECT 
    'System Overview',
    'PostgreSQL Version',
    split_part(version(), ' ', 2),
    'PostgreSQL server version'
UNION ALL
SELECT 
    'System Overview',
    'Active Connections',
    COUNT(*)::text,
    'Currently active database connections'
FROM pg_stat_activity WHERE state = 'active'
UNION ALL
SELECT 
    'System Overview',
    'Buffer Cache Hit Ratio',
    ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2)::text || '%',
    'Percentage of reads served from cache (should be >95%)'
FROM pg_stat_database WHERE datname = current_database();

-- Overall health summary with status indicators
WITH health_metrics AS (
    SELECT 
        -- Cache hit ratio
        ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) as cache_hit_ratio,
        -- Connection count
        (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
        (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') as max_connections,
        -- Dead tuples
        (SELECT COUNT(*) FROM pg_stat_user_tables WHERE n_dead_tup > n_live_tup * 0.1) as tables_needing_vacuum
    FROM pg_stat_database 
    WHERE datname = current_database()
)
SELECT 
    'Health Summary' as section,
    'Cache Performance' as metric,
    cache_hit_ratio::text || '%' as value,
    CASE 
        WHEN cache_hit_ratio >= 95 THEN 'EXCELLENT'
        WHEN cache_hit_ratio >= 90 THEN 'GOOD'
        WHEN cache_hit_ratio >= 80 THEN 'FAIR'
        ELSE 'POOR - Needs attention'
    END as status
FROM health_metrics
UNION ALL
SELECT 
    'Health Summary',
    'Connection Usage',
    active_connections::text || '/' || max_connections::text,
    CASE 
        WHEN active_connections::numeric / max_connections < 0.7 THEN 'GOOD'
        WHEN active_connections::numeric / max_connections < 0.9 THEN 'FAIR'
        ELSE 'HIGH - Monitor closely'
    END
FROM health_metrics
UNION ALL
SELECT 
    'Health Summary',
    'Maintenance Status',
    tables_needing_vacuum::text || ' tables need vacuum',
    CASE 
        WHEN tables_needing_vacuum = 0 THEN 'GOOD'
        WHEN tables_needing_vacuum < 3 THEN 'FAIR'
        ELSE 'NEEDS ATTENTION'
    END
FROM health_metrics;

-- ========================================
-- TABLE INFORMATION & PERFORMANCE
-- ========================================

-- Table sizes and access patterns
SELECT 
    'Table Information' as section,
    schemaname || '.' || tablename as table_name,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size('public.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size('public.'||tablename) - 
                   pg_relation_size('public.'||tablename)) as index_size,
    CASE 
        WHEN pg_total_relation_size('public.'||tablename) > 100*1024*1024 THEN 'LARGE'
        WHEN pg_total_relation_size('public.'||tablename) > 10*1024*1024 THEN 'MEDIUM'
        ELSE 'SMALL'
    END as size_category
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size('public.'||tablename) DESC;

-- Table access patterns and performance metrics
SELECT 
    'Table Performance' as section,
    schemaname || '.' || relname as table_name,
    seq_scan as sequential_scans,
    seq_tup_read as seq_tuples_read,
    idx_scan as index_scans,
    idx_tup_fetch as idx_tuples_fetched,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    CASE 
        WHEN seq_scan + idx_scan = 0 THEN 0
        ELSE ROUND(idx_scan::numeric / (seq_scan + idx_scan) * 100, 2)
    END as index_usage_percent,
    CASE 
        WHEN seq_scan > idx_scan AND seq_scan > 1000 THEN 'Review indexes'
        WHEN seq_scan + idx_scan = 0 THEN 'No activity'
        ELSE 'OK'
    END as recommendation
FROM pg_stat_user_tables
ORDER BY seq_scan + idx_scan DESC;

-- ========================================
-- INDEX USAGE & EFFICIENCY
-- ========================================

-- Index usage statistics with recommendations
SELECT 
    'Index Usage' as section,
    schemaname || '.' || relname as table_name,
    indexrelname as index_name,
    idx_scan as times_used,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    CASE 
        WHEN idx_scan = 0 THEN 'UNUSED - Consider dropping'
        WHEN idx_scan < 100 THEN 'LOW USAGE - Investigate'
        WHEN idx_scan < 1000 THEN 'MODERATE USAGE'
        ELSE 'ACTIVE'
    END as usage_status
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- ========================================
-- CONNECTION MONITORING
-- ========================================

-- Connection states summary
SELECT 
    'Connection States' as section,
    COALESCE(state, 'unknown') as connection_state,
    COUNT(*) as connection_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (now() - backend_start))), 2) as avg_connection_age_seconds,
    ROUND(AVG(EXTRACT(EPOCH FROM (now() - state_change))), 2) as avg_state_duration_seconds
FROM pg_stat_activity 
WHERE pid != pg_backend_pid()
GROUP BY state
ORDER BY connection_count DESC;

-- Current active connections and queries
SELECT 
    'Current Activity' as section,
    pid,
    usename as username,
    application_name,
    client_addr,
    state,
    query_start,
    EXTRACT(EPOCH FROM (now() - query_start))::int as query_duration_seconds,
    wait_event_type,
    wait_event,
    LEFT(query, 80) as current_query
FROM pg_stat_activity 
WHERE state != 'idle' 
  AND pid != pg_backend_pid()
ORDER BY query_start DESC NULLS LAST;

-- Long-running connections (over 5 minutes)
SELECT 
    'Long Running Connections' as section,
    pid,
    usename,
    application_name,
    state,
    EXTRACT(EPOCH FROM (now() - backend_start))::int as connection_age_seconds,
    EXTRACT(EPOCH FROM (now() - query_start))::int as query_age_seconds,
    LEFT(query, 80) as current_query,
    CASE 
        WHEN EXTRACT(EPOCH FROM (now() - backend_start)) > 3600 THEN 'Very long connection'
        WHEN EXTRACT(EPOCH FROM (now() - backend_start)) > 1800 THEN 'Long connection'
        ELSE 'Moderate duration'
    END as duration_category
FROM pg_stat_activity 
WHERE state = 'active' 
  AND backend_start < now() - interval '5 minutes'
  AND pid != pg_backend_pid()
ORDER BY backend_start;

-- ========================================
-- MEMORY & I/O MONITORING
-- ========================================

-- Buffer cache detailed statistics
SELECT 
    'Buffer Cache Details' as section,
    'Shared Buffers Hit Ratio' as metric,
    ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2)::text || '%' as value,
    CASE 
        WHEN ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) >= 95 THEN 'Excellent'
        WHEN ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) >= 90 THEN 'Good'
        ELSE 'Needs improvement'
    END as assessment
FROM pg_stat_database
UNION ALL
SELECT 
    'Buffer Cache Details',
    'Total Blocks Read',
    sum(blks_read)::text,
    'Physical disk reads'
FROM pg_stat_database
UNION ALL
SELECT 
    'Buffer Cache Details',
    'Total Blocks Hit',
    sum(blks_hit)::text,
    'Cache hits (memory reads)'
FROM pg_stat_database;

-- Table I/O statistics with hit ratios
SELECT 
    'Table I/O Performance' as section,
    schemaname || '.' || relname as table_name,
    heap_blks_read as table_blocks_read,
    heap_blks_hit as table_blocks_hit,
    CASE 
        WHEN heap_blks_read + heap_blks_hit = 0 THEN 0
        ELSE ROUND(heap_blks_hit::numeric / (heap_blks_read + heap_blks_hit) * 100, 2)
    END as table_hit_ratio_percent,
    idx_blks_read as index_blocks_read,
    idx_blks_hit as index_blocks_hit,
    CASE 
        WHEN idx_blks_read + idx_blks_hit = 0 THEN 0
        ELSE ROUND(idx_blks_hit::numeric / (idx_blks_read + idx_blks_hit) * 100, 2)
    END as index_hit_ratio_percent
FROM pg_statio_user_tables
WHERE heap_blks_read + heap_blks_hit > 0
ORDER BY heap_blks_read DESC
LIMIT 10;

-- ========================================
-- MAINTENANCE & VACUUM MONITORING
-- ========================================

-- Comprehensive vacuum and analyze status
SELECT 
    'Maintenance Status' as section,
    schemaname || '.' || relname as table_name,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    CASE 
        WHEN n_live_tup + n_dead_tup = 0 THEN 0
        ELSE ROUND(n_dead_tup::numeric / (n_live_tup + n_dead_tup) * 100, 2)
    END as dead_tuple_percent,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count,
    last_analyze,
    last_autoanalyze,
    CASE 
        WHEN n_dead_tup > n_live_tup * 0.2 THEN 'URGENT - Manual vacuum recommended'
        WHEN n_dead_tup > n_live_tup * 0.1 THEN 'Consider manual vacuum'
        WHEN last_autovacuum < now() - interval '1 day' AND n_dead_tup > 1000 THEN 'Monitor autovacuum settings'
        ELSE 'OK'
    END as maintenance_recommendation
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- Table bloat estimation with recommendations
SELECT 
    'Table Bloat Analysis' as section,
    schemaname || '.' || relname as table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    CASE 
        WHEN n_live_tup + n_dead_tup = 0 THEN 0
        ELSE ROUND(n_dead_tup::numeric / (n_live_tup + n_dead_tup) * 100, 2)
    END as bloat_percent,
    CASE 
        WHEN last_autovacuum IS NULL THEN 'Never'
        ELSE EXTRACT(EPOCH FROM (now() - last_autovacuum))::int::text || ' seconds ago'
    END as last_autovacuum_age,
    CASE 
        WHEN n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) > 0.3 THEN 'HIGH BLOAT'
        WHEN n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1 THEN 'MODERATE BLOAT'
        ELSE 'LOW BLOAT'
    END as bloat_level
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC;

-- ========================================
-- LOCK MONITORING
-- ========================================

-- Current locks with potential issues
SELECT 
    'Lock Monitoring' as section,
    l.locktype,
    l.mode,
    l.granted,
    a.usename,
    a.application_name,
    a.client_addr,
    EXTRACT(EPOCH FROM (now() - a.query_start))::int as lock_duration_seconds,
    LEFT(a.query, 80) as query_preview,
    CASE 
        WHEN NOT l.granted THEN 'WAITING FOR LOCK'
        WHEN l.mode IN ('ExclusiveLock', 'AccessExclusiveLock') THEN 'EXCLUSIVE LOCK'
        ELSE 'NORMAL'
    END as lock_status
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE NOT l.granted OR l.mode IN ('ExclusiveLock', 'AccessExclusiveLock')
ORDER BY a.query_start;

-- ========================================
-- CONFIGURATION MONITORING
-- ========================================

-- Key configuration parameters with recommendations
SELECT 
    'Configuration Review' as section,
    name as parameter,
    setting as current_value,
    unit,
    context as change_context,
    short_desc as description,
    CASE 
        WHEN name = 'shared_buffers' AND setting::bigint < 134217728 THEN 'Consider increasing (current < 128MB)'
        WHEN name = 'work_mem' AND setting::bigint < 4194304 THEN 'Consider increasing (current < 4MB)'
        WHEN name = 'maintenance_work_mem' AND setting::bigint < 67108864 THEN 'Consider increasing (current < 64MB)'
        WHEN name = 'effective_cache_size' AND setting::bigint < 1073741824 THEN 'Consider increasing (current < 1GB)'
        WHEN name = 'random_page_cost' AND setting::numeric > 2.0 THEN 'Consider decreasing for SSD storage'
        ELSE 'OK'
    END as recommendation
FROM pg_settings 
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'random_page_cost',
    'seq_page_cost',
    'max_connections',
    'checkpoint_completion_target',
    'wal_buffers',
    'autovacuum',
    'log_min_duration_statement'
)
ORDER BY name;

-- ========================================
-- SLOW QUERY ANALYSIS
-- ========================================

-- Check for pg_stat_statements extension and provide detailed guidance
DO $$
DECLARE
    log_setting TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        RAISE NOTICE '✅ pg_stat_statements extension is available and active';
        RAISE NOTICE '';
        RAISE NOTICE '📊 Query slow queries with:';
        RAISE NOTICE 'SELECT query, calls, total_exec_time, mean_exec_time FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;';
        RAISE NOTICE '';
        RAISE NOTICE '🔄 Reset statistics with:';
        RAISE NOTICE 'SELECT pg_stat_statements_reset();';
    ELSE
        RAISE NOTICE '⚠️  pg_stat_statements extension is NOT available';
        RAISE NOTICE '';
        RAISE NOTICE '🔧 To enable query performance tracking:';
        RAISE NOTICE '';
        RAISE NOTICE '1. Quick setup using Make:';
        RAISE NOTICE '   make enable-stats';
        RAISE NOTICE '';
        RAISE NOTICE '2. Manual setup:';
        RAISE NOTICE '   a) Add to postgresql.conf: shared_preload_libraries = ''pg_stat_statements''';
        RAISE NOTICE '   b) Restart PostgreSQL container: docker-compose restart';
        RAISE NOTICE '   c) Create extension: CREATE EXTENSION pg_stat_statements;';
        RAISE NOTICE '';
        RAISE NOTICE '💡 Alternative: Use log_min_duration_statement to log slow queries';
        
        -- Get the current setting using a variable
        SELECT setting INTO log_setting FROM pg_settings WHERE name = 'log_min_duration_statement';
        RAISE NOTICE '   Current setting: %', log_setting;
    END IF;
END $$;

-- ========================================
-- USAGE INSTRUCTIONS & RECOMMENDATIONS
-- ========================================

SELECT 
    'Monitoring Guidelines' as section,
    'Key Metrics to Watch' as category,
    'Buffer cache hit ratio should be >95%' as guideline,
    'Critical for performance' as importance
UNION ALL
SELECT 
    'Monitoring Guidelines',
    'Key Metrics to Watch',
    'Index usage percent should be high for frequently queried tables',
    'Indicates proper indexing strategy'
UNION ALL
SELECT 
    'Monitoring Guidelines',
    'Key Metrics to Watch',
    'Dead tuple percent should be <10% for most tables',
    'Indicates effective autovacuum'
UNION ALL
SELECT 
    'Monitoring Guidelines',
    'Key Metrics to Watch',
    'Connection usage should be <80% of max_connections',
    'Prevents connection exhaustion'
UNION ALL
SELECT 
    'Monitoring Guidelines',
    'Performance Analysis',
    'Use EXPLAIN (ANALYZE, BUFFERS) for slow queries',
    'Essential for query optimization'
UNION ALL
SELECT 
    'Monitoring Guidelines',
    'Performance Analysis',
    'Monitor long-running connections and queries',
    'Identifies potential blocking issues'
UNION ALL
SELECT 
    'Monitoring Guidelines',
    'Maintenance Tasks',
    'Review vacuum and analyze statistics regularly',
    'Ensures optimal query performance'
UNION ALL
SELECT 
    'Monitoring Guidelines',
    'Maintenance Tasks',
    'Monitor table and index sizes for growth trends',
    'Helps with capacity planning';

-- ========================================
-- FINAL SUMMARY
-- ========================================

SELECT 
    'Dashboard Summary' as section,
    'Monitoring Complete' as status,
    'All key metrics have been analyzed' as message,
    'Review recommendations above for optimization opportunities' as next_steps;