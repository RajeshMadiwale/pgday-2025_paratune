# PostgreSQL 17 Parameter Tuning Demo

A comprehensive Docker-based PostgreSQL 17 environment designed for learning and practicing database parameter tuning. Perfect for database administrators, developers, and candidates preparing for PostgreSQL performance optimization interviews.

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose installed
- Minimum 2GB RAM available
- Basic PostgreSQL knowledge recommended

### Installation & Setup
```bash
# Recommended: One-command setup
make quick-start

# Alternative: Manual setup
docker-compose up -d
./test-setup.sh
make connect
```

### Connection Information
| Parameter | Value |
|-----------|-------|
| **Host** | localhost |
| **Port** | 5432 |
| **Database** | tuning_demo |
| **Username** | demo_user |

## 📊 Demo Environment

### Sample Data Overview
Our demo includes realistic datasets designed to demonstrate various PostgreSQL performance scenarios:

| Table | Records | Size | Use Case |
|-------|---------|------|----------|
| `performance_test` | 100,000 | 21 MB | Basic query optimization |
| `user_orders` | 500,000 | 52 MB | JOIN performance analysis |
| `sales_data` | 200,000 | Partitioned | Partition pruning demos |
| `documents` | 50,000 | 69 MB | Full-text search optimization |
| `user_profiles` | 25,000 | JSONB | NoSQL-style query tuning |
| `employee_salaries` | 10,000 | Analytics | Window function performance |

### Pre-configured Parameters
The environment comes optimized for learning with carefully chosen parameter values:

```sql
shared_buffers = 256MB          -- Shared memory buffer pool
work_mem = 4MB                  -- Memory for sorting/grouping
effective_cache_size = 1GB      -- OS cache size estimate
maintenance_work_mem = 64MB     -- Memory for maintenance operations
random_page_cost = 1.1          -- SSD-optimized cost setting
log_min_duration_statement = 100ms  -- Log slow queries
```

## 🎯 Learning Path

### Phase 1: Foundation (Beginner)
**Start Here**: Interactive Tutorial ⭐
```sql
\i /demo-data/step-by-step-tutorial.sql
```

**Learning Objectives**:
- Understand PostgreSQL memory architecture
- Learn to read and interpret `EXPLAIN ANALYZE` output
- Practice basic parameter tuning (work_mem, shared_buffers)
- Master index usage analysis

**Key Skills Developed**:
- Query performance analysis
- Memory tuning fundamentals
- Buffer cache optimization
- Index effectiveness evaluation

### Phase 2: Core Tuning (Intermediate)
**Files**: `tuning-queries.sql`, `monitoring-dashboard.sql`

**Learning Objectives**:
- Advanced parameter optimization
- Real-time performance monitoring
- Connection management
- Maintenance scheduling

**Practical Exercises**:
```sql
-- Memory impact testing
SET work_mem = '1MB';   -- Observe external sorts
SET work_mem = '32MB';  -- Compare performance

-- Cache effectiveness analysis
SELECT ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) || '%' 
FROM pg_stat_database WHERE datname = current_database();
```

### Phase 3: Advanced Optimization (Advanced)
**Files**: `advanced-tuning-queries.sql`, `performance-benchmarks.sql`

**Learning Objectives**:
- Partition pruning optimization
- Full-text search tuning
- JSONB performance optimization
- Complex query analysis

**Advanced Scenarios**:
- Multi-table JOIN optimization
- Window function performance
- Recursive query tuning
- Parallel execution configuration

### Phase 4: Production Readiness (Expert)
**Files**: `query-analysis.sql`, `log-analysis-pgbadger.sql`, `troubleshooting-queries.sql`

**Learning Objectives**:
- Production monitoring strategies
- Log analysis and pgBadger reporting
- Performance troubleshooting
- Capacity planning

**Professional Skills**:
- pg_stat_statements mastery
- pgBadger report interpretation
- Lock contention resolution
- Autovacuum optimization

## 🔧 Command Reference

### Essential Make Commands
| Command | Purpose | Usage |
|---------|---------|-------|
| `make quick-start` | Complete setup with testing | First-time setup |
| `make connect` | Connect to database | Daily usage |
| `make monitor` | Run monitoring dashboard | Health checks |
| `make benchmark` | Performance testing | Before/after comparisons |
| `make pgbadger` | Generate log analysis report | Weekly analysis |
| `make enable-stats` | Enable pg_stat_statements | Query analysis setup |
| `make clean` | Complete cleanup | Environment reset |

### Critical SQL Commands
```sql
-- Configuration Analysis
SHOW work_mem;
SHOW shared_buffers;
SHOW effective_cache_size;

-- Performance Analysis
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM table_name WHERE condition;

-- Health Monitoring
SELECT schemaname, tablename, seq_scan, idx_scan 
FROM pg_stat_user_tables ORDER BY seq_scan DESC;

-- Memory Tuning
SET work_mem = '16MB';
-- Execute your query
RESET work_mem;
```

## 📈 Parameter Tuning Guide

### Memory Parameters

#### work_mem - Query Operation Memory
**Purpose**: Memory allocated for sorting, grouping, and hash operations
**Testing Approach**:
```sql
-- Test with different values
SET work_mem = '1MB';   -- May cause external sorts
SET work_mem = '8MB';   -- Balanced setting
SET work_mem = '32MB';  -- High memory, faster operations
```
**Success Indicators**: Elimination of "external merge" in EXPLAIN output

#### shared_buffers - Database Cache
**Purpose**: PostgreSQL's shared memory buffer pool
**Testing Method**: Monitor cache hit ratios with repeated queries
**Target Metric**: >95% cache hit ratio for optimal performance

#### effective_cache_size - OS Cache Estimate
**Purpose**: Helps query planner make optimal decisions
**Impact**: Influences index vs sequential scan choices
**Tuning Range**: 50% to 75% of total system memory

### I/O Parameters

#### random_page_cost - Storage Speed Setting
**Purpose**: Cost estimate for random page access
**Values**:
- `4.0` - Traditional HDD
- `1.1` - SSD (current setting)
- `1.0` - Very fast NVMe storage

#### checkpoint_completion_target - I/O Smoothing
**Purpose**: Spread checkpoint I/O over time
**Monitoring**: Check `pg_stat_checkpointer` for forced vs timed checkpoints
**Target**: More timed checkpoints, fewer forced ones

### Logging Parameters

#### log_min_duration_statement - Slow Query Logging
**Purpose**: Log queries exceeding specified duration
**Recommended Values**:
- `50ms` - Detailed analysis (development)
- `100ms` - Balanced (current setting)
- `500ms` - Production (minimal overhead)
- `-1` - Disabled

#### log_statement - Statement Logging
**Options**:
- `none` - No statement logging (production)
- `ddl` - Schema changes only
- `mod` - Data modifications
- `all` - All statements (debugging only)

## 🔍 Monitoring & Analysis

### Real-time Monitoring
```sql
-- System health overview
\i /demo-data/monitoring-dashboard.sql

-- Key metrics to watch
Buffer Cache Hit Ratio: >95% (Excellent), >90% (Good)
Index Usage Ratio: High for frequently queried tables
Dead Tuple Percentage: <10% for most tables
Connection Usage: <80% of max_connections
```

### Performance Analysis Tools

#### pg_stat_statements (Query Analysis)
```bash
# Enable extension
make enable-stats

# Analyze slow queries
SELECT query, calls, total_exec_time, mean_exec_time 
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
```

#### pgBadger (Log Analysis)
```bash
# Generate comprehensive report
make pgbadger

# View report
open pgbadger-report.html
```

**pgBadger Report Sections**:
- Query performance analysis
- Connection pattern analysis
- Error frequency analysis
- Resource usage patterns
- Time-based activity trends

## 🚨 Troubleshooting

### Common Issues & Solutions

#### pg_stat_statements Extension Error
**Error**: `pg_stat_statements must be loaded via "shared_preload_libraries"`
**Solution**: `make enable-stats`

#### Container Startup Issues
```bash
# Check container status
docker logs pg-tuning-demo

# Verify setup
./test-setup.sh

# Complete restart
make clean && make quick-start
```

#### Performance Issues
- Ensure Docker has adequate memory (2GB+)
- Check port 5432 availability
- Verify disk space for Docker volumes

### Diagnostic Queries
```sql
-- Identify slow queries
SELECT pid, usename, state, query_start, 
       EXTRACT(EPOCH FROM (now() - query_start)) as duration_seconds,
       LEFT(query, 100) as query_preview
FROM pg_stat_activity 
WHERE state = 'active' AND query_start < now() - interval '30 seconds';

-- Find blocking queries
SELECT blocked.pid as blocked_pid, blocking.pid as blocking_pid,
       blocked.query as blocked_query, blocking.query as blocking_query
FROM pg_stat_activity blocked 
JOIN pg_locks blocked_locks ON blocked.pid = blocked_locks.pid
JOIN pg_locks blocking_locks ON blocking_locks.transactionid = blocked_locks.transactionid
JOIN pg_stat_activity blocking ON blocking.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted AND blocking_locks.granted;
```

## 🧹 Environment Management

### Quick Cleanup
```bash
make clean      # Stop and remove everything
```

### Selective Cleanup
```bash
# Remove only demo containers/images
docker-compose down -v
docker rmi pgtunning_demo-postgres-tuning-demo

# Keep Docker for other projects
docker system prune
```

### Complete Docker Removal
For complete Docker uninstallation, see platform-specific instructions in the detailed cleanup section.

## 🎓 Interview Preparation

### Common PostgreSQL Tuning Questions
1. **"How would you tune a slow query?"**
   - Use `EXPLAIN ANALYZE` for query plan analysis
   - Check index usage and table statistics
   - Consider parameter adjustments (work_mem, etc.)

2. **"Explain PostgreSQL memory management"**
   - shared_buffers for database cache
   - work_mem for query operations
   - maintenance_work_mem for maintenance tasks

3. **"How do you monitor database performance?"**
   - pg_stat_statements for query analysis
   - Buffer cache hit ratios
   - Connection and lock monitoring

4. **"What's your approach to index optimization?"**
   - Analyze query patterns
   - Monitor index usage statistics
   - Remove unused indexes
   - Consider partial and covering indexes

### Practical Demonstration Skills
- Live query optimization using EXPLAIN ANALYZE
- Parameter tuning with measurable results
- Real-time monitoring and alerting setup
- Performance regression analysis

## 📚 Additional Resources

### Official Documentation
- [PostgreSQL 17 Documentation](https://www.postgresql.org/docs/17/)
- [Performance Tuning Guide](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [EXPLAIN Documentation](https://www.postgresql.org/docs/17/sql-explain.html)

### Advanced Topics
- [Query Optimization](https://www.postgresql.org/docs/17/runtime-config-query.html)
- [Monitoring and Statistics](https://www.postgresql.org/docs/17/monitoring.html)
- [pgBadger Documentation](https://pgbadger.darold.net/)

---

## 🚀 Get Started Now

```bash
# Complete setup in 30 seconds
make quick-start

# Connect and begin learning
make connect

# Start with the interactive tutorial
\i /demo-data/step-by-step-tutorial.sql
```

**Ready to master PostgreSQL performance tuning?** This comprehensive environment provides everything you need to become proficient in database optimization! 🎯
