-- Demo database initialization script
-- Creates sample tables and data for PostgreSQL tuning demonstrations

-- Create a large table for performance testing
CREATE TABLE performance_test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data JSONB,
    random_number INTEGER
);

-- Create indexes for demonstration
CREATE INDEX idx_performance_test_name ON performance_test(name);
CREATE INDEX idx_performance_test_created_at ON performance_test(created_at);
CREATE INDEX idx_performance_test_random ON performance_test(random_number);

-- Insert sample data
INSERT INTO performance_test (name, email, data, random_number)
SELECT 
    'User ' || generate_series,
    'user' || generate_series || '@example.com',
    jsonb_build_object('age', (random() * 80 + 18)::int, 'city', 'City ' || (random() * 100)::int),
    (random() * 1000)::int
FROM generate_series(1, 100000);

-- Create a table for join demonstrations
CREATE TABLE user_orders (
    order_id SERIAL PRIMARY KEY,
    user_id INTEGER,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(10,2),
    status VARCHAR(20)
);

-- Insert order data
INSERT INTO user_orders (user_id, amount, status)
SELECT 
    (random() * 100000 + 1)::int,
    (random() * 1000 + 10)::decimal(10,2),
    CASE (random() * 3)::int
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        ELSE 'cancelled'
    END
FROM generate_series(1, 500000);

-- Create indexes for join performance
CREATE INDEX idx_user_orders_user_id ON user_orders(user_id);
CREATE INDEX idx_user_orders_date ON user_orders(order_date);

-- Create a view for complex queries
CREATE VIEW user_order_summary AS
SELECT 
    pt.id,
    pt.name,
    pt.email,
    COUNT(uo.order_id) as total_orders,
    COALESCE(SUM(uo.amount), 0) as total_spent,
    MAX(uo.order_date) as last_order_date
FROM performance_test pt
LEFT JOIN user_orders uo ON pt.id = uo.user_id
GROUP BY pt.id, pt.name, pt.email;