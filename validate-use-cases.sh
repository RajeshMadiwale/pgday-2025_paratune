#!/bin/bash

# PostgreSQL Tuning Demo - Use Case Validation Script
# Tests all major tuning scenarios and validates expected behavior

set -e

echo "🧪 Validating PostgreSQL Tuning Use Cases"
echo "=========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}✅ $message${NC}" ;;
        "error") echo -e "${RED}❌ $message${NC}" ;;
        "warning") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "info") echo -e "${BLUE}ℹ️  $message${NC}" ;;
    esac
}

# Test database connection
test_connection() {
    print_status "info" "Testing database connection..."
    if docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "SELECT version();" > /dev/null 2>&1; then
        print_status "success" "Database connection successful"
        return 0
    else
        print_status "error" "Cannot connect to database"
        return 1
    fi
}

# Test data integrity
test_data_integrity() {
    print_status "info" "Validating demo data..."
    
    local tables=("performance_test" "user_orders" "sales_data" "documents" "user_profiles" "employee_salaries")
    local expected_counts=(100000 500000 200000 50000 25000 10000)
    
    for i in "${!tables[@]}"; do
        local table="${tables[$i]}"
        local expected="${expected_counts[$i]}"
        local actual=$(docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -t -c "SELECT COUNT(*) FROM $table;" | tr -d ' ')
        
        if [ "$actual" -ge "$expected" ]; then
            print_status "success" "$table: $actual rows (expected: $expected+)"
        else
            print_status "error" "$table: $actual rows (expected: $expected+)"
        fi
    done
}

# Test memory tuning scenarios
test_memory_tuning() {
    print_status "info" "Testing memory tuning scenarios..."
    
    # Test work_mem impact on sorting
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    SET work_mem = '1MB';
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT department, AVG(salary) 
    FROM employee_salaries 
    GROUP BY department 
    ORDER BY AVG(salary) DESC;
    " > /tmp/low_work_mem.out 2>&1
    
    if grep -q "external merge" /tmp/low_work_mem.out; then
        print_status "success" "Low work_mem causes external merge (expected)"
    else
        print_status "warning" "No external merge detected with low work_mem"
    fi
    
    # Test higher work_mem
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    SET work_mem = '32MB';
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT department, AVG(salary) 
    FROM employee_salaries 
    GROUP BY department 
    ORDER BY AVG(salary) DESC;
    " > /tmp/high_work_mem.out 2>&1
    
    if ! grep -q "external merge" /tmp/high_work_mem.out; then
        print_status "success" "High work_mem eliminates external merge"
    else
        print_status "warning" "External merge still present with high work_mem"
    fi
}

# Test index usage scenarios
test_index_usage() {
    print_status "info" "Testing index usage scenarios..."
    
    # Test index scan
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT * FROM performance_test WHERE id = 50000;
    " > /tmp/index_scan.out 2>&1
    
    if grep -q "Index Scan" /tmp/index_scan.out; then
        print_status "success" "Primary key lookup uses index scan"
    else
        print_status "error" "Primary key lookup not using index"
    fi
    
    # Test sequential scan
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT COUNT(*) FROM performance_test WHERE random_number > 500;
    " > /tmp/seq_scan.out 2>&1
    
    if grep -q "Seq Scan" /tmp/seq_scan.out; then
        print_status "success" "Large range query uses sequential scan"
    else
        print_status "warning" "Expected sequential scan not detected"
    fi
}

# Test join performance
test_join_performance() {
    print_status "info" "Testing join performance scenarios..."
    
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT pt.name, COUNT(uo.order_id) 
    FROM performance_test pt 
    LEFT JOIN user_orders uo ON pt.id = uo.user_id 
    WHERE pt.id BETWEEN 1000 AND 2000 
    GROUP BY pt.id, pt.name;
    " > /tmp/join_test.out 2>&1
    
    if grep -q "Hash Join\|Nested Loop\|Merge Join" /tmp/join_test.out; then
        print_status "success" "Join query uses appropriate join algorithm"
    else
        print_status "error" "No join algorithm detected"
    fi
}

# Test partition pruning
test_partition_pruning() {
    print_status "info" "Testing partition pruning..."
    
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT * FROM sales_data 
    WHERE sale_date BETWEEN '2024-01-01' AND '2024-01-31';
    " > /tmp/partition_test.out 2>&1
    
    if grep -q "Partitions removed" /tmp/partition_test.out; then
        print_status "success" "Partition pruning working correctly"
    else
        print_status "warning" "Partition pruning not detected"
    fi
}

# Test JSONB performance
test_jsonb_performance() {
    print_status "info" "Testing JSONB query performance..."
    
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT * FROM user_profiles 
    WHERE profile_data->>'age' = '25';
    " > /tmp/jsonb_test.out 2>&1
    
    if grep -q "Index\|Bitmap" /tmp/jsonb_test.out; then
        print_status "success" "JSONB query uses index"
    else
        print_status "warning" "JSONB query may not be using optimal index"
    fi
}

# Test full-text search
test_fulltext_search() {
    print_status "info" "Testing full-text search performance..."
    
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT title FROM documents 
    WHERE search_vector @@ to_tsquery('postgresql & performance');
    " > /tmp/fts_test.out 2>&1
    
    if grep -q "GIN" /tmp/fts_test.out; then
        print_status "success" "Full-text search uses GIN index"
    else
        print_status "warning" "Full-text search may not be using GIN index"
    fi
}

# Test monitoring queries
test_monitoring() {
    print_status "info" "Testing monitoring capabilities..."
    
    # Test buffer cache hit ratio
    docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "
    SELECT ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) as hit_ratio
    FROM pg_stat_database WHERE datname = current_database();
    " > /tmp/cache_hit.out 2>&1
    
    if [ $? -eq 0 ]; then
        print_status "success" "Buffer cache monitoring working"
    else
        print_status "warning" "Buffer cache monitoring may need more queries to generate stats"
    fi
}

# Main test execution
main() {
    echo "Starting comprehensive use case validation..."
    echo
    
    test_connection || exit 1
    test_data_integrity
    test_memory_tuning
    test_index_usage
    test_join_performance
    test_partition_pruning
    test_jsonb_performance
    test_fulltext_search
    test_monitoring
    
    echo
    print_status "info" "Validation complete! Check individual test results above."
    echo "📊 Run 'make benchmark' for performance measurements"
    echo "🔍 Run 'make monitor' for real-time monitoring"
}

main "$@"
