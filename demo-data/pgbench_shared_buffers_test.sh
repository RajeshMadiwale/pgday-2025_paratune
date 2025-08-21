#!/bin/bash

# pgbench Shared Buffers Testing Scenarios
# Tests different shared_buffers values with pgbench workloads

DB_NAME=${1:-postgres}
USERNAME=${2:-$(whoami)}
SCALE_FACTOR=${3:-100}  # Default 100 = ~15MB database

echo "🚀 pgbench Shared Buffers Testing"
echo "================================="
echo "Database: $DB_NAME"
echo "User: $USERNAME"
echo "Scale Factor: $SCALE_FACTOR"
echo ""

# Check PostgreSQL connection
if ! psql -d "$DB_NAME" -U "$USERNAME" -c "SELECT version();" > /dev/null 2>&1; then
    echo "❌ Cannot connect to PostgreSQL"
    exit 1
fi

echo "✅ PostgreSQL connection successful"

# Create results directory
mkdir -p pgbench_results

# Get current shared_buffers setting
CURRENT_SHARED_BUFFERS=$(psql -d "$DB_NAME" -U "$USERNAME" -t -c "SELECT setting FROM pg_settings WHERE name = 'shared_buffers';")
echo "📊 Current shared_buffers: ${CURRENT_SHARED_BUFFERS} (8kB blocks)"

# Initialize pgbench database
echo ""
echo "🔧 Initializing pgbench database (scale factor: $SCALE_FACTOR)..."
pgbench -i -s $SCALE_FACTOR -d "$DB_NAME" -U "$USERNAME" > pgbench_results/init.log 2>&1

if [ $? -eq 0 ]; then
    echo "✅ pgbench database initialized"
else
    echo "❌ Failed to initialize pgbench database"
    exit 1
fi

# Get database size
DB_SIZE=$(psql -d "$DB_NAME" -U "$USERNAME" -t -c "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));")
echo "📏 Database size: $DB_SIZE"

# Test scenarios with different shared_buffers values
# Note: These require PostgreSQL restart to take effect

echo ""
echo "🧪 Testing Scenarios (Current shared_buffers: ${CURRENT_SHARED_BUFFERS})"
echo ""

# Scenario 1: Read-Heavy Workload (SELECT only)
echo "📖 Scenario 1: Read-Heavy Workload"
echo "   Testing buffer cache efficiency with SELECT-only queries"

{
    echo "-- Read-Heavy Workload Test"
    echo "-- Current shared_buffers: ${CURRENT_SHARED_BUFFERS}"
    echo "-- Database size: $DB_SIZE"
    echo ""
    
    # Reset statistics
    psql -d "$DB_NAME" -U "$USERNAME" -c "SELECT pg_stat_reset();"
    
    # Run read-heavy test
    pgbench -c 10 -j 2 -T 60 -S -d "$DB_NAME" -U "$USERNAME"
    
    echo ""
    echo "-- Buffer statistics after read-heavy test:"
    psql -d "$DB_NAME" -U "$USERNAME" -c "
    SELECT 
        'Buffer Hit Ratio' as metric,
        ROUND((sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0)) * 100, 2) || '%' as value
    FROM pg_statio_user_tables 
    WHERE schemaname = 'public';
    
    SELECT 
        'Total Blocks Read' as metric,
        sum(heap_blks_read) as value
    FROM pg_statio_user_tables 
    WHERE schemaname = 'public';
    
    SELECT 
        'Total Blocks Hit' as metric,
        sum(heap_blks_hit) as value
    FROM pg_statio_user_tables 
    WHERE schemaname = 'public';
    "
    
} > pgbench_results/read_heavy_current_sb.log 2>&1

# Scenario 2: Write-Heavy Workload (TPC-B)
echo "✍️  Scenario 2: Write-Heavy Workload (TPC-B)"
echo "   Testing buffer cache with mixed read/write operations"

{
    echo "-- Write-Heavy Workload Test (TPC-B)"
    echo "-- Current shared_buffers: ${CURRENT_SHARED_BUFFERS}"
    echo ""
    
    # Reset statistics
    psql -d "$DB_NAME" -U "$USERNAME" -c "SELECT pg_stat_reset();"
    
    # Run standard TPC-B test
    pgbench -c 10 -j 2 -T 60 -d "$DB_NAME" -U "$USERNAME"
    
    echo ""
    echo "-- Buffer statistics after write-heavy test:"
    psql -d "$DB_NAME" -U "$USERNAME" -c "
    SELECT 
        'Buffer Hit Ratio' as metric,
        ROUND((sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0)) * 100, 2) || '%' as value
    FROM pg_statio_user_tables 
    WHERE schemaname = 'public';
    
    SELECT relname, heap_blks_read, heap_blks_hit, idx_blks_read, idx_blks_hit
    FROM pg_statio_user_tables 
    WHERE schemaname = 'public'
    ORDER BY heap_blks_read + heap_blks_hit DESC;
    "
    
} > pgbench_results/write_heavy_current_sb.log 2>&1

# Scenario 3: High Concurrency Test
echo "🔄 Scenario 3: High Concurrency Test"
echo "   Testing buffer contention with many concurrent connections"

{
    echo "-- High Concurrency Test"
    echo "-- Current shared_buffers: ${CURRENT_SHARED_BUFFERS}"
    echo ""
    
    # Reset statistics
    psql -d "$DB_NAME" -U "$USERNAME" -c "SELECT pg_stat_reset();"
    
    # Run high concurrency test
    pgbench -c 50 -j 4 -T 30 -d "$DB_NAME" -U "$USERNAME"
    
    echo ""
    echo "-- Buffer and lock statistics:"
    psql -d "$DB_NAME" -U "$USERNAME" -c "
    SELECT 
        'Buffer Hit Ratio' as metric,
        ROUND((sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0)) * 100, 2) || '%' as value
    FROM pg_statio_user_tables 
    WHERE schemaname = 'public';
    
    SELECT 'Lock Waits' as metric, COUNT(*) as value 
    FROM pg_locks WHERE NOT granted;
    "
    
} > pgbench_results/high_concurrency_current_sb.log 2>&1

# Scenario 4: Buffer Cache Analysis
echo "🔍 Scenario 4: Buffer Cache Analysis"
echo "   Analyzing current buffer cache contents and efficiency"

{
    echo "-- Buffer Cache Analysis"
    echo "-- Current shared_buffers: ${CURRENT_SHARED_BUFFERS}"
    echo ""
    
    # Analyze buffer cache (requires pg_buffercache extension)
    psql -d "$DB_NAME" -U "$USERNAME" -c "
    -- Check if pg_buffercache is available
    SELECT 'pg_buffercache extension' as check, 
           CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_buffercache') 
                THEN 'Available' 
                ELSE 'Not installed' 
           END as status;
    
    -- Buffer cache usage by relation (if extension available)
    DO \$\$
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_buffercache') THEN
            RAISE NOTICE 'Buffer cache contents:';
        ELSE
            RAISE NOTICE 'Install pg_buffercache extension for detailed buffer analysis';
        END IF;
    END
    \$\$;
    
    -- Table and index sizes
    SELECT 
        schemaname,
        relname as table_name,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size,
        pg_size_pretty(pg_relation_size(schemaname||'.'||relname)) as table_size,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname) - pg_relation_size(schemaname||'.'||relname)) as index_size
    FROM pg_stat_user_tables 
    WHERE schemaname = 'public'
    ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC;
    
    -- Current buffer pool statistics
    SELECT 
        'Shared Buffers Size' as metric,
        pg_size_pretty(setting::bigint * 8192) as value
    FROM pg_settings WHERE name = 'shared_buffers'
    UNION ALL
    SELECT 
        'Database Size',
        pg_size_pretty(pg_database_size('$DB_NAME'));
    "
    
} > pgbench_results/buffer_analysis.log 2>&1

# Generate recommendations
echo ""
echo "📋 Generating Shared Buffers Recommendations..."

{
    echo "SHARED BUFFERS TUNING RECOMMENDATIONS"
    echo "====================================="
    echo "Generated: $(date)"
    echo ""
    
    # Get system memory info (macOS)
    TOTAL_RAM_GB=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
    echo "System RAM: ${TOTAL_RAM_GB}GB"
    
    # Current setting in MB
    CURRENT_SB_MB=$(psql -d "$DB_NAME" -U "$USERNAME" -t -c "SELECT ROUND(setting::bigint * 8192 / 1024.0 / 1024.0) FROM pg_settings WHERE name = 'shared_buffers';")
    echo "Current shared_buffers: ${CURRENT_SB_MB}MB"
    
    echo ""
    echo "RECOMMENDED SHARED_BUFFERS VALUES TO TEST:"
    echo ""
    
    # Calculate recommendations
    RECOMMENDED_25PCT=$((TOTAL_RAM_GB * 1024 / 4))  # 25% of RAM in MB
    RECOMMENDED_15PCT=$((TOTAL_RAM_GB * 1024 * 15 / 100))  # 15% of RAM in MB
    RECOMMENDED_35PCT=$((TOTAL_RAM_GB * 1024 * 35 / 100))  # 35% of RAM in MB
    
    echo "1. Conservative (15% of RAM): ${RECOMMENDED_15PCT}MB"
    echo "   shared_buffers = ${RECOMMENDED_15PCT}MB"
    echo ""
    
    echo "2. Standard (25% of RAM): ${RECOMMENDED_25PCT}MB"
    echo "   shared_buffers = ${RECOMMENDED_25PCT}MB"
    echo ""
    
    echo "3. Aggressive (35% of RAM): ${RECOMMENDED_35PCT}MB"
    echo "   shared_buffers = ${RECOMMENDED_35PCT}MB"
    echo ""
    
    echo "DATABASE SIZE CONSIDERATIONS:"
    psql -d "$DB_NAME" -U "$USERNAME" -c "
    SELECT 
        'pgbench Database Size' as metric,
        pg_size_pretty(pg_database_size('$DB_NAME')) as value
    UNION ALL
    SELECT 
        'Recommended Min shared_buffers',
        pg_size_pretty(pg_database_size('$DB_NAME') * 2) as value
    UNION ALL
    SELECT 
        'Current shared_buffers',
        pg_size_pretty(setting::bigint * 8192) as value
    FROM pg_settings WHERE name = 'shared_buffers';
    "
    
    echo ""
    echo "TESTING INSTRUCTIONS:"
    echo "1. Edit postgresql.conf:"
    echo "   sudo nano /opt/homebrew/var/postgresql@17/postgresql.conf"
    echo ""
    echo "2. Set shared_buffers value (requires restart):"
    echo "   shared_buffers = 512MB  # Example"
    echo ""
    echo "3. Restart PostgreSQL:"
    echo "   brew services restart postgresql@17"
    echo ""
    echo "4. Re-run this test:"
    echo "   ./pgbench_shared_buffers_test.sh"
    echo ""
    echo "5. Compare buffer hit ratios between runs"
    
} > pgbench_results/recommendations.log 2>&1

echo ""
echo "✅ pgbench Shared Buffers Testing Complete!"
echo ""
echo "📁 Results saved in pgbench_results/:"
echo "   • read_heavy_current_sb.log - Read-only workload results"
echo "   • write_heavy_current_sb.log - TPC-B workload results"  
echo "   • high_concurrency_current_sb.log - High concurrency results"
echo "   • buffer_analysis.log - Buffer cache analysis"
echo "   • recommendations.log - Tuning recommendations"
echo ""
echo "🎯 Key Metrics to Compare:"
echo "   • Buffer Hit Ratio (target: >95% for read workloads)"
echo "   • TPS (Transactions Per Second)"
echo "   • Average latency"
echo "   • Buffer reads vs hits"
echo ""
echo "📊 To compare different shared_buffers values:"
echo "   1. Note current results"
echo "   2. Change shared_buffers in postgresql.conf"
echo "   3. Restart PostgreSQL"
echo "   4. Re-run this script"
echo "   5. Compare buffer hit ratios and TPS"
