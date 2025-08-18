# PostgreSQL 17 Parameter Tuning Demo

A comprehensive Docker-based PostgreSQL 17 environment for mastering database parameter tuning. Perfect for database administrators, developers, and interview preparation.

## 🚀 Quick Start

```bash
git clone https://github.com/RajeshMadiwale/pgday-2025_paratune.git
cd  pgday-2025_paratune
```


### macOS / Linux
```bash
# One-command setup
make quick-start

# Connect and start learning
make connect
\i /demo-data/step-by-step-tutorial.sql
```

### Windows (PowerShell/CMD)
```powershell
# Option 1: Use PowerShell script
.\quick-start.ps1

# Option 2: Manual commands
docker-compose up -d
timeout /t 30
docker exec -it pg-tuning-demo psql -U demo_user -d tuning_demo

# Option 3: Use batch file (CMD)
quick-start.bat

# In psql, start tutorial
\i /demo-data/step-by-step-tutorial.sql
```

### Prerequisites
- Docker and Docker Compose
- 2GB+ RAM available
- Basic PostgreSQL knowledge

## 📊 Demo Environment

### Sample Data
| Table | Records | Use Case |
|-------|---------|----------|
| `performance_test` | 1,000,000 | Query optimization |
| `user_orders` | 2,000,000 | JOIN performance |
| `sales_data` | 1,000,000 | Partition pruning |
| `documents` | 200,000 | Full-text search |
| `user_profiles` | 100,000 | JSONB optimization |
| `employee_salaries` | 50,000 | Window functions |

### Pre-configured Parameters
```sql
shared_buffers = 256MB          -- Buffer cache
work_mem = 4MB                  -- Sort/group memory
effective_cache_size = 1GB      -- OS cache estimate
random_page_cost = 1.1          -- SSD optimized
log_min_duration_statement = 100ms  -- Slow query logging
```

## 🎯 Learning Path

### 1. Foundation (Beginner)
```sql
-- Start here
\i /demo-data/step-by-step-tutorial.sql
```
- Memory architecture basics
- EXPLAIN ANALYZE interpretation
- Basic parameter tuning
- Index usage analysis

### 2. Core Tuning (Intermediate)
```sql
-- Parameter tuning scenarios
\i /demo-data/parameter-tuning-scenarios.sql
```
- work_mem optimization
- shared_buffers effectiveness
- Connection management
- Performance monitoring

### 3. Advanced Optimization (Expert)
```sql
-- Advanced scenarios
\i /demo-data/advanced-tuning-queries.sql
```
- Partition pruning
- JSONB performance
- Full-text search tuning
- Complex query analysis

### 4. Production Monitoring
```sql
-- Monitoring and analysis
\i /demo-data/monitoring-dashboard.sql
```
- pg_stat_statements mastery
- Buffer cache analysis
- Performance troubleshooting

## 🔧 Commands

| Command | Purpose |
|---------|---------|
| `make quick-start` | Complete setup with validation |
| `make connect` | Connect to database |
| `make work-mem` | Comprehensive work_mem tuning |
| `make validate` | Test all use cases |
| `make perf-test` | Performance validation |
| `make monitor` | Real-time monitoring |
| `make benchmark` | Performance benchmarks |
| `make pgbadger` | Log analysis report |
| `make enable-stats` | Enable query analysis |
| `make clean` | Complete cleanup |

## 📈 Key Tuning Scenarios

### Memory Tuning
```sql
-- Test work_mem impact
SET work_mem = '1MB';   -- May cause external sorts
SET work_mem = '32MB';  -- Should eliminate external sorts

-- Monitor buffer cache
SELECT ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) || '%' 
FROM pg_stat_database WHERE datname = current_database();
```

### Query Optimization
```sql
-- Analyze query performance
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM performance_test WHERE id = 50000;

-- Check index usage
SELECT schemaname, tablename, seq_scan, idx_scan 
FROM pg_stat_user_tables ORDER BY seq_scan DESC;
```

### Advanced Features
```sql
-- JSONB optimization
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM user_profiles WHERE profile_data->>'age' = '25';

-- Full-text search
EXPLAIN (ANALYZE, BUFFERS) 
SELECT title FROM documents 
WHERE search_vector @@ to_tsquery('postgresql & performance');

-- Partition pruning
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM sales_data WHERE sale_date BETWEEN '2024-01-01' AND '2024-01-31';
```

## 🔍 Performance Monitoring

### Real-time Metrics
```bash
make monitor  # Comprehensive dashboard
```

### Query Analysis
```bash
make enable-stats  # Enable pg_stat_statements
```

### Log Analysis
```bash
make pgbadger  # Generate detailed report
```

### Key Metrics
- **Buffer Hit Ratio**: >95% (excellent), >90% (good)
- **Index Usage**: High for frequently queried tables
- **Connection Usage**: <80% of max_connections
- **Query Performance**: Track slow queries >100ms

## 🎓 Interview Preparation

### Common Questions & Demos

**"How would you tune a slow query?"**
```sql
-- 1. Analyze the query
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
-- 2. Check index usage
-- 3. Adjust work_mem if needed
-- 4. Measure improvement
```

**"Explain PostgreSQL memory management"**
- shared_buffers: Database cache
- work_mem: Query operations
- effective_cache_size: OS cache estimate

**"How do you monitor performance?"**
- pg_stat_statements for query analysis
- Buffer cache hit ratios
- Real-time connection monitoring

## 🚨 Troubleshooting

### Common Issues
```bash
# Container won't start
make clean && make quick-start

# pg_stat_statements error
make enable-stats

# Performance issues
# Ensure Docker has 2GB+ RAM
```

### Diagnostic Queries
```sql
-- Find slow queries
SELECT pid, query_start, query FROM pg_stat_activity 
WHERE state = 'active' AND query_start < now() - interval '30 seconds';

-- Check blocking queries
SELECT blocked.pid, blocking.pid, blocked.query 
FROM pg_stat_activity blocked 
JOIN pg_locks blocked_locks ON blocked.pid = blocked_locks.pid
JOIN pg_locks blocking_locks ON blocking_locks.transactionid = blocked_locks.transactionid
JOIN pg_stat_activity blocking ON blocking.pid = blocking_locks.pid
WHERE blocked.pid != blocking.pid;
```

## 📚 Connection Info

| Parameter | Value |
|-----------|-------|
| **Host** | localhost |
| **Port** | 5432 |
| **Database** | tuning_demo |
| **Username** | demo_user |
| **Password** | demo_pass |

## ✅ Validation

```bash
# Verify everything works
./final-check.sh

# Complete testing
make validate
make perf-test
```


## Support
Tell people where they can go to for help. It can be any combination of an issue tracker, a chat room, an email address, etc.

## Roadmap
If you have ideas for releases in the future, it is a good idea to list them in the README.

## Contributing
State if you are open to contributions and what your requirements are for accepting them.

For people who want to make changes to your project, it's helpful to have some documentation on how to get started. Perhaps there is a script that they should run or some environment variables that they need to set. Make these steps explicit. These instructions could also be useful to your future self.

You can also document commands to lint the code or run tests. These steps help to ensure high code quality and reduce the likelihood that the changes inadvertently break something. Having instructions for running tests is especially helpful if it requires external setup, such as starting a Selenium server for testing in a browser.

## Authors and acknowledgment
Show your appreciation to those who have contributed to the project.

1. __Rajesh Madiwale__

## License
For open source projects, say how it is licensed.

## Project status

If you have run out of energy or time for your project, put a note at the top of the README saying that development has slowed down or stopped completely. Someone may choose to fork your project or volunteer to step in as a maintainer or owner, allowing your project to keep going. You can also make an explicit request for maintainers.


This PostgreSQL 17 tuning demo is complete and validated for professional use across all platforms.

