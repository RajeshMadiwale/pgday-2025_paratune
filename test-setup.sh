#!/bin/bash

# PostgreSQL Tuning Demo - Setup Test Script
# This script verifies that the demo environment is working correctly

set -e  # Exit on any error

echo "🚀 Testing PostgreSQL Tuning Demo Setup..."
echo "=========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}✅ $message${NC}" ;;
        "error") echo -e "${RED}❌ $message${NC}" ;;
        "warning") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "info") echo -e "${BLUE}ℹ️  $message${NC}" ;;
        *) echo "$message" ;;
    esac
}

# Check if Docker is running
print_status "info" "Checking Docker status..."
if ! docker info > /dev/null 2>&1; then
    print_status "error" "Docker is not running. Please start Docker first."
    exit 1
fi
print_status "success" "Docker is running"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    print_status "error" "docker-compose not found. Please install Docker Compose."
    exit 1
fi

# Start the container
print_status "info" "Starting PostgreSQL container..."
if docker-compose up -d; then
    print_status "success" "Container started successfully"
else
    print_status "error" "Failed to start container"
    exit 1
fi

# Wait for PostgreSQL to be ready with timeout
print_status "info" "Waiting for PostgreSQL to be ready..."
TIMEOUT=60
COUNTER=0
while [ $COUNTER -lt $TIMEOUT ]; do
    if docker exec pg-tuning-demo pg_isready -U demo_user -d tuning_demo > /dev/null 2>&1; then
        break
    fi
    sleep 2
    COUNTER=$((COUNTER + 2))
    if [ $((COUNTER % 10)) -eq 0 ]; then
        print_status "info" "Still waiting... ($COUNTER/$TIMEOUT seconds)"
    fi
done

# Test connection
print_status "info" "Testing database connection..."
if docker exec pg-tuning-demo pg_isready -U demo_user -d tuning_demo > /dev/null 2>&1; then
    print_status "success" "Database connection successful"
else
    print_status "error" "Database connection failed after $TIMEOUT seconds"
    print_status "info" "Container logs (last 20 lines):"
    docker logs pg-tuning-demo --tail 20
    exit 1
fi

# Test PostgreSQL version
PG_VERSION=$(docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -t -c "SELECT version();" | head -1 | tr -d ' ')
print_status "success" "PostgreSQL version: $(echo $PG_VERSION | cut -d' ' -f1-2)"

# Test tables exist
print_status "info" "Checking if demo tables exist..."
TABLE_COUNT=$(docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -t -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';" 2>/dev/null | tr -d ' ' | head -1)

if [ "$TABLE_COUNT" -ge 5 ]; then
    print_status "success" "Found $TABLE_COUNT demo tables"
else
    print_status "error" "Expected at least 5 tables, found $TABLE_COUNT"
    exit 1
fi

# Test sample data with error handling
print_status "info" "Checking sample data..."
PERFORMANCE_TEST_COUNT=$(docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -t -c "SELECT COUNT(*) FROM performance_test;" 2>/dev/null | tr -d ' ' | head -1)
USER_ORDERS_COUNT=$(docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -t -c "SELECT COUNT(*) FROM user_orders;" 2>/dev/null | tr -d ' ' | head -1)

if [ -n "$PERFORMANCE_TEST_COUNT" ] && [ "$PERFORMANCE_TEST_COUNT" -gt 0 ]; then
    print_status "success" "performance_test table: $PERFORMANCE_TEST_COUNT records"
else
    print_status "error" "performance_test table is empty or missing"
    exit 1
fi

if [ -n "$USER_ORDERS_COUNT" ] && [ "$USER_ORDERS_COUNT" -gt 0 ]; then
    print_status "success" "user_orders table: $USER_ORDERS_COUNT records"
else
    print_status "error" "user_orders table is empty or missing"
    exit 1
fi

# Test a simple query
print_status "info" "Testing a sample query..."
if docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "SELECT 'Query test successful' as result, COUNT(*) as total_users FROM performance_test;" > /dev/null 2>&1; then
    print_status "success" "Sample query executed successfully"
else
    print_status "error" "Sample query failed"
    exit 1
fi

# Test monitoring query
print_status "info" "Testing monitoring queries..."
if docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "SELECT schemaname || '.' || relname as table_name, seq_scan FROM pg_stat_user_tables LIMIT 1;" > /dev/null 2>&1; then
    print_status "success" "Monitoring queries work correctly"
else
    print_status "error" "Monitoring queries failed"
    exit 1
fi

# Test checkpoint queries
print_status "info" "Testing troubleshooting queries..."
if docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "SELECT num_timed, num_requested FROM pg_stat_checkpointer;" > /dev/null 2>&1; then
    print_status "success" "Troubleshooting queries work correctly"
else
    print_status "error" "Troubleshooting queries failed"
    exit 1
fi

# Test configuration
print_status "info" "Checking PostgreSQL configuration..."
WORK_MEM=$(docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -t -c "SHOW work_mem;" 2>/dev/null | tr -d ' ' | head -1)
SHARED_BUFFERS=$(docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -t -c "SHOW shared_buffers;" 2>/dev/null | tr -d ' ' | head -1)

if [ -n "$WORK_MEM" ]; then
    print_status "success" "work_mem: $WORK_MEM"
else
    print_status "warning" "Could not retrieve work_mem setting"
fi

if [ -n "$SHARED_BUFFERS" ]; then
    print_status "success" "shared_buffers: $SHARED_BUFFERS"
else
    print_status "warning" "Could not retrieve shared_buffers setting"
fi

# Test demo files exist
print_status "info" "Checking demo files..."
DEMO_FILES=("step-by-step-tutorial.sql" "tuning-queries.sql" "monitoring-dashboard.sql" "performance-benchmarks.sql" "advanced-tuning-queries.sql" "query-analysis.sql" "log-analysis-pgbadger.sql")
for file in "${DEMO_FILES[@]}"; do
    if [ -f "demo-data/$file" ]; then
        print_status "success" "Found demo-data/$file"
    else
        print_status "warning" "Missing demo-data/$file"
    fi
done

# Check container resource usage
print_status "info" "Checking container resources..."
CONTAINER_STATS=$(docker stats pg-tuning-demo --no-stream --format "table {{.MemUsage}}\t{{.CPUPerc}}" | tail -1)
print_status "success" "Container resources: $CONTAINER_STATS"

echo ""
print_status "success" "🎉 Setup test completed successfully!"
echo "=========================================="
echo ""
print_status "info" "📚 Next steps:"
echo "1. Connect to the database:"
echo "   ${BLUE}docker exec -it pg-tuning-demo psql -U demo_user -d tuning_demo${NC}"
echo ""
echo "2. Run the step-by-step tutorial (RECOMMENDED):"
echo "   ${BLUE}\\i /demo-data/step-by-step-tutorial.sql${NC}"
echo ""
echo "3. Or try individual demo files:"
echo "   ${BLUE}\\i /demo-data/monitoring-dashboard.sql${NC}    # Comprehensive monitoring"
echo "   ${BLUE}\\i /demo-data/tuning-queries.sql${NC}          # Basic scenarios"
echo "   ${BLUE}\\i /demo-data/performance-benchmarks.sql${NC}  # Benchmarking"
echo ""
echo "4. Connection details:"
echo "   Host: localhost"
echo "   Port: 5432"
echo "   Database: tuning_demo"
echo "   Username: demo_user"
echo "   Password: demo_pass"
echo ""
print_status "success" "Happy tuning! 🚀"