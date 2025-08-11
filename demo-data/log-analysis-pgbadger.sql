-- PostgreSQL Log Analysis with pgBadger
-- This file demonstrates log parameter tuning and pgBadger usage for performance analysis

-- ========================================
-- LOG PARAMETER CONFIGURATION
-- ========================================

-- Check current logging configuration
SELECT 
    'Current Logging Configuration' as section,
    name as parameter,
    setting as current_value,
    unit,
    short_desc as description
FROM pg_settings 
WHERE name IN (
    'logging_collector',
    'log_destination',
    'log_directory',
    'log_filename',
    'log_min_duration_statement',
    'log_statement',
    'log_duration',
    'log_line_prefix',
    'log_checkpoints',
    'log_connections',
    'log_lock_waits',
    'log_temp_files',
    'log_autovacuum_min_duration'
)
ORDER BY name;

-- ========================================
-- LOG PARAMETER TUNING SCENARIOS
-- ========================================

-- SCENARIO 1: log_min_duration_statement Tuning
-- This parameter controls which queries are logged based on execution time

-- Check current setting
SHOW log_min_duration_statement;

-- Test different thresholds:
-- SET log_min_duration_statement = '50ms';   -- Log queries > 50ms (detailed analysis)
-- SET log_min_duration_statement = '100ms';  -- Log queries > 100ms (balanced)
-- SET log_min_duration_statement = '500ms';  -- Log queries > 500ms (only slow queries)
-- SET log_min_duration_statement = '0';      -- Log all queries (debugging only)
-- SET log_min_duration_statement = '-1';     -- Disable duration logging (production)

-- SCENARIO 2: log_statement Parameter
-- Controls which SQL statements are logged

-- Current setting
SHOW log_statement;

-- Options to test:
-- SET log_statement = 'none';  -- No statements logged (production)
-- SET log_statement = 'ddl';   -- Only DDL statements (CREATE, ALTER, DROP)
-- SET log_statement = 'mod';   -- DDL + DML statements (INSERT, UPDATE, DELETE)
-- SET log_statement = 'all';   -- All statements (debugging only - high overhead)

-- SCENARIO 3: log_line_prefix Customization
-- Controls the format of log entries for better analysis

SHOW log_line_prefix;

-- Recommended formats:
-- For pgBadger: '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
-- For debugging: '%m [%p] %q%u@%d '
-- For performance: '%t [%p]: [%l-1] '

-- ========================================
-- GENERATE SAMPLE WORKLOAD FOR LOG ANALYSIS
-- ========================================

-- Generate various types of queries to create interesting log data

-- Fast queries (should not be logged with default settings)
SELECT COUNT(*) FROM performance_test WHERE id < 100;
SELECT * FROM performance_test WHERE id = 1;

-- Medium queries (may be logged depending on log_min_duration_statement)
SELECT 
    LEFT(name, 5) as name_prefix,
    COUNT(*) as count,
    AVG(random_number) as avg_random
FROM performance_test 
WHERE random_number BETWEEN 100 AND 200
GROUP BY LEFT(name, 5)
ORDER BY count DESC
LIMIT 20;

-- Slow queries (should be logged)
SELECT 
    pt.name,
    COUNT(uo.order_id) as order_count,
    SUM(uo.amount) as total_amount,
    AVG(uo.amount) as avg_amount
FROM performance_test pt
LEFT JOIN user_orders uo ON pt.id = uo.user_id
WHERE pt.random_number BETWEEN 1 AND 50
GROUP BY pt.id, pt.name
HAVING COUNT(uo.order_id) > 0
ORDER BY total_amount DESC
LIMIT 100;

-- Complex analytical query (definitely should be logged)
WITH user_stats AS (
    SELECT 
        pt.id,
        pt.name,
        COUNT(uo.order_id) as order_count,
        SUM(uo.amount) as total_amount,
        AVG(uo.amount) as avg_amount
    FROM performance_test pt
    LEFT JOIN user_orders uo ON pt.id = uo.user_id
    WHERE pt.random_number BETWEEN 1 AND 100
    GROUP BY pt.id, pt.name
),
ranked_users AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY total_amount DESC NULLS LAST) as rank,
        PERCENT_RANK() OVER (ORDER BY total_amount) as percentile
    FROM user_stats
    WHERE order_count > 0
)
SELECT * FROM ranked_users WHERE rank <= 50;

-- Generate some DDL activity (if log_statement includes DDL)
CREATE TEMP TABLE log_test AS SELECT * FROM performance_test LIMIT 1000;
CREATE INDEX idx_log_test_name ON log_test(name);
DROP TABLE log_test;

-- Generate connection activity
-- (Connections/disconnections will be logged if log_connections = on)

-- ========================================
-- PGBADGER USAGE INSTRUCTIONS
-- ========================================

-- pgBadger is a PostgreSQL log analyzer that generates detailed HTML reports
-- It's installed in the Docker container and can be used to analyze PostgreSQL logs

-- To generate a pgBadger report, run these commands from outside the container:

/*
# 1. Generate some log data by running queries (done above)

# 2. Run pgBadger to analyze logs
docker exec pg-tuning-demo bash -c "pgbadger /var/log/postgresql/postgresql-*.log -o /pgbadger-reports/report.html"

# 3. Copy the report to your local machine
docker cp pg-tuning-demo:/pgbadger-reports/report.html ./pgbadger-report.html

# 4. Open the report in your browser
open pgbadger-report.html  # macOS
# or
xdg-open pgbadger-report.html  # Linux
# or open manually in browser on Windows
*/

-- ========================================
-- LOG ANALYSIS QUERIES
-- ========================================

-- Since we can't directly query log files from SQL, here are some useful
-- system queries to understand logging behavior:

-- Check if logging collector is running
SELECT 
    'Logging Status' as category,
    CASE 
        WHEN setting = 'on' THEN 'Logging collector is ENABLED'
        ELSE 'Logging collector is DISABLED'
    END as status
FROM pg_settings WHERE name = 'logging_collector';

-- Check log file location and settings
SELECT 
    'Log File Configuration' as category,
    'Log Directory: ' || (SELECT setting FROM pg_settings WHERE name = 'log_directory') as config
UNION ALL
SELECT 
    'Log File Configuration',
    'Log Filename Pattern: ' || (SELECT setting FROM pg_settings WHERE name = 'log_filename')
UNION ALL
SELECT 
    'Log File Configuration',
    'Log Rotation Age: ' || (SELECT setting FROM pg_settings WHERE name = 'log_rotation_age')
UNION ALL
SELECT 
    'Log File Configuration',
    'Log Rotation Size: ' || (SELECT setting FROM pg_settings WHERE name = 'log_rotation_size');

-- Monitor current activity that might generate logs
SELECT 
    'Current Activity for Logging' as category,
    pid,
    usename,
    application_name,
    state,
    EXTRACT(EPOCH FROM (now() - query_start))::int as duration_seconds,
    LEFT(query, 80) as query_preview
FROM pg_stat_activity 
WHERE state = 'active' 
  AND pid != pg_backend_pid()
  AND query_start IS NOT NULL
ORDER BY query_start;

-- ========================================
-- LOG PARAMETER TUNING RECOMMENDATIONS
-- ========================================

SELECT 
    'Log Tuning Recommendations' as category,
    'Parameter' as parameter,
    'Recommendation' as value,
    'Use Case' as use_case
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_min_duration_statement',
    '100ms - 500ms',
    'Production: Balance between detail and performance'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_min_duration_statement',
    '50ms - 100ms',
    'Performance tuning: Detailed analysis'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_min_duration_statement',
    '1s - 5s',
    'Production: Only very slow queries'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_statement',
    'none',
    'Production: Minimal logging overhead'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_statement',
    'ddl',
    'Change tracking: Log schema changes'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_statement',
    'mod',
    'Audit: Log data modifications'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_connections',
    'on',
    'Security: Track connection attempts'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_lock_waits',
    'on',
    'Performance: Identify lock contention'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_temp_files',
    '10MB',
    'Performance: Track large temp file usage'
UNION ALL
SELECT 
    'Log Tuning Recommendations',
    'log_autovacuum_min_duration',
    '0 or 250ms',
    'Maintenance: Monitor vacuum performance';

-- ========================================
-- PGBADGER REPORT INTERPRETATION
-- ========================================

SELECT 
    'pgBadger Report Sections' as category,
    'Section' as section_name,
    'What It Shows' as description
UNION ALL
SELECT 
    'pgBadger Report Sections',
    'Overall Statistics',
    'Total queries, connections, errors, duration'
UNION ALL
SELECT 
    'pgBadger Report Sections',
    'Hourly Statistics',
    'Activity patterns over time'
UNION ALL
SELECT 
    'pgBadger Report Sections',
    'Queries by Duration',
    'Slowest queries and their frequency'
UNION ALL
SELECT 
    'pgBadger Report Sections',
    'Most Frequent Queries',
    'Queries executed most often'
UNION ALL
SELECT 
    'pgBadger Report Sections',
    'Queries by Wait Events',
    'Queries waiting on locks, I/O, etc.'
UNION ALL
SELECT 
    'pgBadger Report Sections',
    'Connections',
    'Connection patterns and errors'
UNION ALL
SELECT 
    'pgBadger Report Sections',
    'Temporary Files',
    'Queries creating large temp files'
UNION ALL
SELECT 
    'pgBadger Report Sections',
    'Checkpoints and Restarts',
    'System maintenance activity';