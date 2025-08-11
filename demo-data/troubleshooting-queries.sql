-- PostgreSQL Troubleshooting Queries
-- Diagnostic queries for common performance and operational issues

-- ========================================
-- SLOW QUERY DIAGNOSTICS
-- ========================================

-- Find queries with high execution time
-- (Requires pg_stat_statements extension)
SELECT 
    'Slow Query Analysis' as category,
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND(max_exec_time::numeric, 2) as max_time_ms,
    ROUND(stddev_exec_time::numeric, 2) as stddev_time_ms,
    rows as total_rows,
    ROUND(rows::numeric / calls, 2) as avg_rows_per_call,
    LEFT(query, 150) as query_sample
FROM pg_stat_statements 
WHERE mean_exec_time > 100  -- Queries averaging more than 100ms
ORDER BY total_exec_time DESC 
LIMIT 20;

-- Queries with high buffer usage
SELECT 
    'High I/O Queries' as category,
    calls,
    shared_blks_hit + shared_blks_read as total_buffers,
    ROUND((shared_blks_hit + shared_blks_read)::numeric / calls, 2) as avg_buffers_per_call,
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) as hit_ratio,
    temp_blks_read + temp_blks_written as temp_buffers,
    LEFT(query, 150) as query_sample
FROM pg_stat_statements 
WHERE shared_blks_hit + shared_blks_read > 1000
ORDER BY total_buffers DESC 
LIMIT 15;

-- ========================================
-- CONNECTION ISSUES DIAGNOSTICS
-- ========================================

-- Connection states analysis
SELECT 
    'Connection Analysis' as category,
    state,
    COUNT(*) as connection_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (now() - backend_start))), 2) as avg_connection_age_seconds,
    ROUND(AVG(EXTRACT(EPOCH FROM (now() - state_change))), 2) as avg_state_duration_seconds,
    array_agg(DISTINCT application_name) as applications
FROM pg_stat_activity 
WHERE pid != pg_backend_pid()
GROUP BY state
ORDER BY connection_count DESC;

-- Idle in transaction connections (potential problem)
SELECT 
    'Idle in Transaction' as category,
    pid,
    usename,
    application_name,
    client_addr,
    backend_start,
    state_change,
    EXTRACT(EPOCH FROM (now() - state_change))::int as idle_duration_seconds,
    LEFT(query, 100) as last_query
FROM pg_stat_activity 
WHERE state = 'idle in transaction'
  AND EXTRACT(EPOCH FROM (now() - state_change)) > 300  -- Idle for more than 5 minutes
ORDER BY state_change;

-- Connection limit analysis
WITH connection_stats AS (
    SELECT 
        COUNT(*) as current_connections,
        (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') as max_connections
    FROM pg_stat_activity
)
SELECT 
    'Connection Limits' as category,
    current_connections,
    max_connections,
    ROUND(current_connections::numeric / max_connections * 100, 2) as usage_percent,
    CASE 
        WHEN current_connections::numeric / max_connections > 0.8 THEN 'WARNING: High usage'
        WHEN current_connections::numeric / max_connections > 0.9 THEN 'CRITICAL: Very high usage'
        ELSE 'OK'
    END as status
FROM connection_stats;

-- ========================================
-- LOCK CONTENTION DIAGNOSTICS
-- ========================================

-- Current lock waits
SELECT 
    'Lock Waits' as category,
    waiting.pid as waiting_pid,
    waiting.usename as waiting_user,
    waiting.query as waiting_query,
    other.pid as blocking_pid,
    other.usename as blocking_user,
    other.query as blocking_query,
    EXTRACT(EPOCH FROM (now() - waiting.query_start))::int as wait_duration_seconds
FROM pg_stat_activity waiting
JOIN pg_stat_activity other ON (waiting.wait_event = 'Lock' AND other.state = 'active')
WHERE waiting.wait_event_type = 'Lock'
  AND waiting.pid != other.pid
ORDER BY wait_duration_seconds DESC;

-- Lock types and counts
SELECT 
    'Lock Types' as category,
    locktype,
    mode,
    COUNT(*) as lock_count,
    COUNT(*) FILTER (WHERE granted = false) as waiting_count,
    COUNT(*) FILTER (WHERE granted = true) as granted_count
FROM pg_locks 
GROUP BY locktype, mode
HAVING COUNT(*) > 1
ORDER BY lock_count DESC;

-- ========================================
-- MEMORY USAGE DIAGNOSTICS
-- ========================================

-- Temporary file usage (indicates work_mem pressure)
SELECT 
    'Temporary Files' as category,
    datname,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) as temp_size,
    CASE 
        WHEN temp_files > 0 THEN 'Consider increasing work_mem'
        ELSE 'OK'
    END as recommendation
FROM pg_stat_database 
WHERE datname = current_database();

-- Memory settings analysis
WITH memory_settings AS (
    SELECT 
        name,
        setting,
        unit,
        CASE 
            WHEN unit = '8kB' THEN setting::bigint * 8 * 1024
            WHEN unit = 'kB' THEN setting::bigint * 1024
            WHEN unit = 'MB' THEN setting::bigint * 1024 * 1024
            WHEN unit = 'GB' THEN setting::bigint * 1024 * 1024 * 1024
            ELSE setting::bigint
        END as bytes_value
    FROM pg_settings 
    WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size')
)
SELECT 
    'Memory Configuration' as category,
    name,
    setting || COALESCE(' ' || unit, '') as current_setting,
    pg_size_pretty(bytes_value) as size_pretty,
    CASE 
        WHEN name = 'shared_buffers' AND bytes_value < 134217728 THEN 'Consider increasing (< 128MB)'
        WHEN name = 'work_mem' AND bytes_value < 4194304 THEN 'Consider increasing (< 4MB)'
        WHEN name = 'maintenance_work_mem' AND bytes_value < 67108864 THEN 'Consider increasing (< 64MB)'
        ELSE 'OK'
    END as recommendation
FROM memory_settings
ORDER BY bytes_value DESC;

-- ========================================
-- INDEX USAGE DIAGNOSTICS
-- ========================================

-- Unused indexes (potential candidates for removal)
SELECT 
    'Unused Indexes' as category,
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    idx_scan as times_used,
    CASE 
        WHEN idx_scan = 0 THEN 'Never used - consider dropping'
        WHEN idx_scan < 10 THEN 'Rarely used - investigate'
        ELSE 'OK'
    END as recommendation
FROM pg_stat_user_indexes 
WHERE idx_scan < 10
ORDER BY pg_relation_size(indexrelid) DESC;

-- Tables with low index usage ratio
SELECT 
    'Index Usage Ratio' as category,
    schemaname,
    relname as table_name,
    seq_scan as sequential_scans,
    idx_scan as index_scans,
    CASE 
        WHEN seq_scan + idx_scan = 0 THEN 0
        ELSE ROUND(idx_scan::numeric / (seq_scan + idx_scan) * 100, 2)
    END as index_usage_percent,
    CASE 
        WHEN seq_scan > idx_scan AND seq_scan > 1000 THEN 'High sequential scan usage - check indexes'
        WHEN seq_scan + idx_scan = 0 THEN 'No activity'
        ELSE 'OK'
    END as recommendation
FROM pg_stat_user_tables
WHERE seq_scan + idx_scan > 0
ORDER BY 
    CASE WHEN seq_scan + idx_scan = 0 THEN 0 
         ELSE idx_scan::numeric / (seq_scan + idx_scan) END;

-- ========================================
-- VACUUM AND MAINTENANCE DIAGNOSTICS
-- ========================================

-- Tables needing vacuum
SELECT 
    'Vacuum Status' as category,
    schemaname,
    relname as table_name,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    CASE 
        WHEN n_live_tup + n_dead_tup = 0 THEN 0
        ELSE ROUND(n_dead_tup::numeric / (n_live_tup + n_dead_tup) * 100, 2)
    END as dead_tuple_percent,
    last_autovacuum,
    CASE 
        WHEN n_dead_tup > n_live_tup * 0.2 THEN 'URGENT: Manual vacuum recommended'
        WHEN n_dead_tup > n_live_tup * 0.1 THEN 'Consider manual vacuum'
        WHEN last_autovacuum < now() - interval '1 day' AND n_dead_tup > 1000 THEN 'Monitor autovacuum settings'
        ELSE 'OK'
    END as recommendation
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC;

-- Autovacuum configuration analysis
SELECT 
    'Autovacuum Config' as category,
    name,
    setting,
    unit,
    short_desc,
    CASE 
        WHEN name = 'autovacuum_vacuum_threshold' AND setting::int < 50 THEN 'Consider increasing threshold'
        WHEN name = 'autovacuum_vacuum_scale_factor' AND setting::float > 0.2 THEN 'Consider decreasing scale factor'
        WHEN name = 'autovacuum_max_workers' AND setting::int < 3 THEN 'Consider increasing workers'
        ELSE 'OK'
    END as recommendation
FROM pg_settings 
WHERE name LIKE 'autovacuum%'
ORDER BY name;

-- ========================================
-- CHECKPOINT AND WAL DIAGNOSTICS
-- ========================================

-- Checkpoint statistics
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

-- WAL statistics
SELECT 
    'WAL Statistics' as category,
    name,
    setting,
    unit,
    CASE 
        WHEN name = 'max_wal_size' AND setting::bigint < 1073741824 THEN 'Consider increasing (< 1GB)'
        WHEN name = 'wal_buffers' AND setting::int < 2048 THEN 'Consider increasing (< 16MB)'
        WHEN name = 'checkpoint_completion_target' AND setting::float < 0.8 THEN 'Consider increasing to 0.9'
        ELSE 'OK'
    END as recommendation
FROM pg_settings 
WHERE name IN ('max_wal_size', 'min_wal_size', 'wal_buffers', 'checkpoint_completion_target')
ORDER BY name;

-- ========================================
-- QUERY PLAN DIAGNOSTICS
-- ========================================

-- Function to analyze a specific query plan
CREATE OR REPLACE FUNCTION analyze_query_plan(query_text TEXT)
RETURNS TABLE(
    analysis_type TEXT,
    finding TEXT,
    recommendation TEXT
) AS $$
DECLARE
    plan_text TEXT;
BEGIN
    -- Get the query plan
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) ' || query_text INTO plan_text;
    
    -- Basic plan analysis (simplified)
    IF plan_text LIKE '%Seq Scan%' THEN
        analysis_type := 'Scan Type';
        finding := 'Sequential scan detected';
        recommendation := 'Consider adding appropriate indexes';
        RETURN NEXT;
    END IF;
    
    IF plan_text LIKE '%Sort%' AND plan_text LIKE '%external%' THEN
        analysis_type := 'Memory Usage';
        finding := 'External sort detected';
        recommendation := 'Consider increasing work_mem';
        RETURN NEXT;
    END IF;
    
    IF plan_text LIKE '%Nested Loop%' AND plan_text LIKE '%rows=%' THEN
        analysis_type := 'Join Strategy';
        finding := 'Nested loop join with high row count';
        recommendation := 'Consider hash or merge join - check join conditions and statistics';
        RETURN NEXT;
    END IF;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- SYSTEM RESOURCE DIAGNOSTICS
-- ========================================

-- Database size growth analysis
SELECT 
    'Database Growth' as category,
    current_database() as database_name,
    pg_size_pretty(pg_database_size(current_database())) as current_size,
    'Monitor growth trends over time' as recommendation;

-- Top space consumers
SELECT 
    'Space Usage' as category,
    'table' as object_type,
    schemaname || '.' || tablename as object_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - 
                   pg_relation_size(schemaname||'.'||tablename)) as index_size,
    CASE 
        WHEN pg_total_relation_size(schemaname||'.'||tablename) > 1073741824 THEN 'Large table - monitor growth'
        ELSE 'OK'
    END as recommendation
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

-- ========================================
-- TROUBLESHOOTING SUMMARY
-- ========================================

-- Overall system health check
WITH health_check AS (
    SELECT 
        -- Performance indicators
        (SELECT ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) 
         FROM pg_stat_database WHERE datname = current_database()) as cache_hit_ratio,
        
        -- Connection health
        (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
        (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') as max_connections,
        
        -- Maintenance health
        (SELECT COUNT(*) FROM pg_stat_user_tables WHERE n_dead_tup > n_live_tup * 0.1) as tables_needing_vacuum,
        
        -- Lock health
        (SELECT COUNT(*) FROM pg_locks WHERE NOT granted) as waiting_locks
)
SELECT 
    'System Health Summary' as category,
    CASE 
        WHEN cache_hit_ratio >= 95 THEN 'GOOD'
        WHEN cache_hit_ratio >= 90 THEN 'FAIR'
        ELSE 'POOR'
    END as cache_performance,
    
    CASE 
        WHEN active_connections::numeric / max_connections < 0.7 THEN 'GOOD'
        WHEN active_connections::numeric / max_connections < 0.9 THEN 'FAIR'
        ELSE 'HIGH'
    END as connection_usage,
    
    CASE 
        WHEN tables_needing_vacuum = 0 THEN 'GOOD'
        WHEN tables_needing_vacuum < 5 THEN 'FAIR'
        ELSE 'NEEDS_ATTENTION'
    END as maintenance_status,
    
    CASE 
        WHEN waiting_locks = 0 THEN 'GOOD'
        WHEN waiting_locks < 5 THEN 'FAIR'
        ELSE 'CONTENTION'
    END as lock_status,
    
    'Run specific diagnostic queries for detailed analysis' as next_steps
FROM health_check;