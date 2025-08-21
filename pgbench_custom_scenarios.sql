-- Custom pgbench Scenarios for Shared Buffers Testing
-- These scenarios stress different aspects of buffer cache

-- Scenario 1: Buffer Cache Thrashing Test
-- Forces cache misses by accessing more data than fits in shared_buffers

\set scale_factor 100
\set random_aid random(1, :scale_factor * 100000)
\set random_bid random(1, :scale_factor)
\set random_tid random(1, :scale_factor * 10)

-- Large table scan that exceeds buffer cache
SELECT COUNT(*), AVG(abalance) 
FROM pgbench_accounts 
WHERE aid BETWEEN :random_aid AND :random_aid + 10000;

-- Scenario 2: Hot Data Access Pattern
-- Repeatedly accesses small subset of data (should stay in cache)

\set hot_aid random(1, 1000)
\set hot_bid random(1, 10)

SELECT * FROM pgbench_accounts WHERE aid = :hot_aid;
SELECT * FROM pgbench_branches WHERE bid = :hot_bid;
UPDATE pgbench_accounts SET abalance = abalance + 1 WHERE aid = :hot_aid;

-- Scenario 3: Index-Heavy Workload
-- Tests buffer cache efficiency for index pages

\set lookup_aid random(1, :scale_factor * 100000)

SELECT aid, abalance FROM pgbench_accounts WHERE aid = :lookup_aid;
SELECT COUNT(*) FROM pgbench_accounts WHERE bid = (SELECT bid FROM pgbench_accounts WHERE aid = :lookup_aid);

-- Scenario 4: Sequential Scan vs Index Scan
-- Tests planner decisions based on buffer cache assumptions

\set range_start random(1, :scale_factor * 50000)
\set range_size random(100, 1000)

-- This should prefer index scan with good buffer cache
SELECT aid, abalance 
FROM pgbench_accounts 
WHERE aid BETWEEN :range_start AND :range_start + :range_size
ORDER BY aid;

-- Scenario 5: Buffer Cache Warming
-- Gradually loads data into buffer cache

\set warm_start random(1, :scale_factor * 10000)

-- First pass - cold cache
SELECT COUNT(*) FROM pgbench_accounts WHERE aid > :warm_start AND aid < :warm_start + 5000;

-- Second pass - warmed cache (same data)
SELECT AVG(abalance) FROM pgbench_accounts WHERE aid > :warm_start AND aid < :warm_start + 5000;
