-- Demo functions for PostgreSQL tuning demonstrations

-- Function to simulate CPU-intensive operations
CREATE OR REPLACE FUNCTION cpu_intensive_function(iterations INTEGER)
RETURNS INTEGER AS $$
DECLARE
    result INTEGER := 0;
    i INTEGER;
BEGIN
    FOR i IN 1..iterations LOOP
        result := result + i * i;
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to demonstrate memory usage
CREATE OR REPLACE FUNCTION memory_test_function()
RETURNS TABLE(id INTEGER, data TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        generate_series(1, 10000) as id,
        repeat('x', 1000) as data;
END;
$$ LANGUAGE plpgsql;

-- Function to show query statistics
CREATE OR REPLACE FUNCTION show_query_stats()
RETURNS TABLE(
    query TEXT,
    calls BIGINT,
    total_time DOUBLE PRECISION,
    mean_time DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pg_stat_statements.query,
        pg_stat_statements.calls,
        pg_stat_statements.total_exec_time,
        pg_stat_statements.mean_exec_time
    FROM pg_stat_statements
    ORDER BY total_exec_time DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;