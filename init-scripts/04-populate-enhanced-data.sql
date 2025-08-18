-- Enhanced data population script for PostgreSQL tuning demo
-- Automatically loads during Docker initialization
-- Significantly increases data volume for better performance testing

\echo 'Loading enhanced dataset - this may take a few minutes...'

-- Increase performance_test table to 1M records
INSERT INTO performance_test (name, email, data, random_number)
SELECT 
    'User ' || (100000 + generate_series),
    'user' || (100000 + generate_series) || '@example.com',
    jsonb_build_object(
        'age', (random() * 80 + 18)::int, 
        'city', 'City ' || (random() * 500)::int,
        'country', CASE (random() * 10)::int
            WHEN 0 THEN 'USA' WHEN 1 THEN 'Canada' WHEN 2 THEN 'UK'
            WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'Japan'
            WHEN 6 THEN 'Australia' WHEN 7 THEN 'Brazil' WHEN 8 THEN 'India'
            ELSE 'Mexico'
        END,
        'score', (random() * 1000)::int
    ),
    (random() * 10000)::int
FROM generate_series(1, 900000);

-- Increase user_orders to 2M records
INSERT INTO user_orders (user_id, amount, status, order_date)
SELECT 
    (random() * 1000000 + 1)::int,
    (random() * 5000 + 10)::decimal(10,2),
    CASE (random() * 4)::int
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        WHEN 2 THEN 'cancelled'
        ELSE 'shipped'
    END,
    CURRENT_TIMESTAMP - (random() * interval '2 years')
FROM generate_series(1, 1500000);

-- Add more partitions and data to sales_data
CREATE TABLE sales_data_2024_04 PARTITION OF sales_data
    FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');
CREATE TABLE sales_data_2024_05 PARTITION OF sales_data
    FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
CREATE TABLE sales_data_2024_06 PARTITION OF sales_data
    FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');

-- Increase sales_data to 1M records
INSERT INTO sales_data (sale_date, customer_id, product_id, quantity, unit_price, total_amount, region, sales_rep_id)
SELECT 
    '2024-01-01'::date + (random() * 180)::int,
    (random() * 50000 + 1)::int,
    (random() * 5000 + 1)::int,
    (random() * 20 + 1)::int,
    (random() * 500 + 5)::decimal(10,2),
    0,
    CASE (random() * 6)::int
        WHEN 0 THEN 'North America'
        WHEN 1 THEN 'South America'
        WHEN 2 THEN 'Europe'
        WHEN 3 THEN 'Asia'
        WHEN 4 THEN 'Africa'
        ELSE 'Oceania'
    END,
    (random() * 200 + 1)::int
FROM generate_series(1, 800000);

UPDATE sales_data SET total_amount = quantity * unit_price WHERE total_amount = 0;

-- Increase documents to 200K records
INSERT INTO documents (title, content, category, author_id, tags)
SELECT 
    'Document ' || (50000 + generate_series) || ': ' || 
    CASE (random() * 8)::int
        WHEN 0 THEN 'Advanced Technical Manual'
        WHEN 1 THEN 'Comprehensive User Guide'
        WHEN 2 THEN 'Complete API Documentation'
        WHEN 3 THEN 'Step-by-Step Tutorial'
        WHEN 4 THEN 'Reference Guide'
        WHEN 5 THEN 'Best Practices Guide'
        WHEN 6 THEN 'Troubleshooting Manual'
        ELSE 'Implementation Guide'
    END,
    'This comprehensive document ' || (50000 + generate_series) || ' covers ' ||
    CASE (random() * 6)::int
        WHEN 0 THEN 'advanced database optimization techniques and performance tuning strategies'
        WHEN 1 THEN 'modern application development frameworks and architectural patterns'
        WHEN 2 THEN 'enterprise system administration and infrastructure monitoring'
        WHEN 3 THEN 'cloud computing platforms and containerization technologies'
        WHEN 4 THEN 'data analytics and machine learning implementation'
        ELSE 'cybersecurity protocols and compliance requirements'
    END || '. ' ||
    'The document provides extensive explanations, code examples, and real-world scenarios for ' ||
    'experienced developers, system administrators, and technical architects who need to implement ' ||
    'complex solutions in production environments. It includes performance benchmarks, ' ||
    'troubleshooting guides, and optimization recommendations.',
    CASE (random() * 6)::int
        WHEN 0 THEN 'Technical'
        WHEN 1 THEN 'Tutorial'
        WHEN 2 THEN 'Reference'
        WHEN 3 THEN 'Guide'
        WHEN 4 THEN 'Manual'
        ELSE 'Documentation'
    END,
    (random() * 100 + 1)::int,
    ARRAY[
        CASE (random() * 6)::int
            WHEN 0 THEN 'postgresql' WHEN 1 THEN 'performance' WHEN 2 THEN 'database'
            WHEN 3 THEN 'optimization' WHEN 4 THEN 'monitoring' ELSE 'tuning'
        END,
        CASE (random() * 6)::int
            WHEN 0 THEN 'advanced' WHEN 1 THEN 'enterprise' WHEN 2 THEN 'production'
            WHEN 3 THEN 'scalability' WHEN 4 THEN 'architecture' ELSE 'implementation'
        END,
        CASE (random() * 4)::int
            WHEN 0 THEN 'cloud' WHEN 1 THEN 'security' WHEN 2 THEN 'analytics' ELSE 'devops'
        END
    ]
FROM generate_series(1, 150000);

UPDATE documents SET search_vector = to_tsvector('english', title || ' ' || content) 
WHERE search_vector IS NULL;

-- Increase user_profiles to 100K records
INSERT INTO user_profiles (user_id, profile_data, preferences, metadata)
SELECT 
    pt.id,
    jsonb_build_object(
        'firstName', 'User',
        'lastName', pt.id::text,
        'age', (random() * 70 + 16)::int,
        'address', jsonb_build_object(
            'street', (random() * 9999 + 1)::int || ' ' || 
                CASE (random() * 5)::int
                    WHEN 0 THEN 'Main St' WHEN 1 THEN 'Oak Ave' WHEN 2 THEN 'Pine Rd'
                    WHEN 3 THEN 'Elm Dr' ELSE 'Maple Ln'
                END,
            'city', 'City ' || (random() * 1000 + 1)::int,
            'state', CASE (random() * 10)::int
                WHEN 0 THEN 'CA' WHEN 1 THEN 'NY' WHEN 2 THEN 'TX' WHEN 3 THEN 'FL'
                WHEN 4 THEN 'IL' WHEN 5 THEN 'PA' WHEN 6 THEN 'OH' WHEN 7 THEN 'GA'
                WHEN 8 THEN 'NC' ELSE 'MI'
            END,
            'zipCode', (random() * 99999 + 10000)::text
        ),
        'skills', ARRAY[
            CASE (random() * 8)::int
                WHEN 0 THEN 'postgresql' WHEN 1 THEN 'python' WHEN 2 THEN 'javascript'
                WHEN 3 THEN 'java' WHEN 4 THEN 'react' WHEN 5 THEN 'nodejs'
                WHEN 6 THEN 'docker' ELSE 'kubernetes'
            END,
            CASE (random() * 8)::int
                WHEN 0 THEN 'aws' WHEN 1 THEN 'azure' WHEN 2 THEN 'gcp'
                WHEN 3 THEN 'terraform' WHEN 4 THEN 'ansible' WHEN 5 THEN 'jenkins'
                WHEN 6 THEN 'git' ELSE 'linux'
            END
        ],
        'experience', (random() * 20 + 1)::int,
        'salary', (random() * 150000 + 50000)::int,
        'department', CASE (random() * 5)::int
            WHEN 0 THEN 'Engineering' WHEN 1 THEN 'Sales' WHEN 2 THEN 'Marketing'
            WHEN 3 THEN 'HR' ELSE 'Finance'
        END
    ),
    jsonb_build_object(
        'theme', CASE (random() * 3)::int WHEN 0 THEN 'dark' WHEN 1 THEN 'light' ELSE 'auto' END,
        'notifications', jsonb_build_object(
            'email', random() > 0.3,
            'sms', random() > 0.7,
            'push', random() > 0.5,
            'desktop', random() > 0.6
        ),
        'language', CASE (random() * 6)::int
            WHEN 0 THEN 'en' WHEN 1 THEN 'es' WHEN 2 THEN 'fr'
            WHEN 3 THEN 'de' WHEN 4 THEN 'ja' ELSE 'zh'
        END,
        'timezone', CASE (random() * 8)::int
            WHEN 0 THEN 'UTC' WHEN 1 THEN 'EST' WHEN 2 THEN 'PST' WHEN 3 THEN 'CST'
            WHEN 4 THEN 'MST' WHEN 5 THEN 'GMT' WHEN 6 THEN 'JST' ELSE 'CET'
        END
    ),
    json_build_object(
        'lastLogin', CURRENT_TIMESTAMP - (random() * interval '90 days'),
        'loginCount', (random() * 5000)::int,
        'deviceInfo', json_build_object(
            'browser', CASE (random() * 5)::int
                WHEN 0 THEN 'Chrome' WHEN 1 THEN 'Firefox' WHEN 2 THEN 'Safari'
                WHEN 3 THEN 'Edge' ELSE 'Opera'
            END,
            'os', CASE (random() * 4)::int
                WHEN 0 THEN 'Windows' WHEN 1 THEN 'macOS' WHEN 2 THEN 'Linux' ELSE 'iOS'
            END,
            'mobile', random() > 0.6
        ),
        'sessionData', json_build_object(
            'averageSessionTime', (random() * 3600 + 300)::int,
            'pagesPerSession', (random() * 20 + 1)::int
        )
    )
FROM performance_test pt
WHERE pt.id > 25000 AND pt.id <= 100000;

-- Increase employee_salaries to 50K records
INSERT INTO employee_salaries (employee_id, department, position, salary, hire_date, performance_score)
SELECT 
    10000 + generate_series,
    CASE (random() * 8)::int
        WHEN 0 THEN 'Engineering'
        WHEN 1 THEN 'Sales'
        WHEN 2 THEN 'Marketing'
        WHEN 3 THEN 'HR'
        WHEN 4 THEN 'Finance'
        WHEN 5 THEN 'Operations'
        WHEN 6 THEN 'Legal'
        ELSE 'Customer Success'
    END,
    CASE (random() * 5)::int
        WHEN 0 THEN 'Junior'
        WHEN 1 THEN 'Mid-level'
        WHEN 2 THEN 'Senior'
        WHEN 3 THEN 'Lead'
        ELSE 'Principal'
    END || ' ' ||
    CASE (random() * 6)::int
        WHEN 0 THEN 'Developer'
        WHEN 1 THEN 'Analyst'
        WHEN 2 THEN 'Specialist'
        WHEN 3 THEN 'Manager'
        WHEN 4 THEN 'Architect'
        ELSE 'Consultant'
    END,
    (random() * 200000 + 35000)::decimal(10,2),
    '2018-01-01'::date + (random() * 2190)::int,
    (random() * 2 + 2.5)::decimal(3,2)
FROM generate_series(1, 40000);

-- Create additional indexes for better performance testing
CREATE INDEX idx_performance_test_data_age ON performance_test USING GIN ((data->'age'));
CREATE INDEX idx_performance_test_data_country ON performance_test USING GIN ((data->'country'));
CREATE INDEX idx_user_orders_amount ON user_orders (amount);
CREATE INDEX idx_user_orders_status_date ON user_orders (status, order_date);
CREATE INDEX idx_sales_data_total_amount ON sales_data (total_amount);
CREATE INDEX idx_documents_author ON documents (author_id);
CREATE INDEX idx_user_profiles_dept ON user_profiles USING GIN ((profile_data->'department'));
CREATE INDEX idx_employee_salaries_salary ON employee_salaries (salary);

-- Update table statistics
ANALYZE performance_test;
ANALYZE user_orders;
ANALYZE sales_data;
ANALYZE documents;
ANALYZE user_profiles;
ANALYZE employee_salaries;

-- Display final record counts
\echo 'Enhanced dataset loaded successfully!'
SELECT 'performance_test' as table_name, COUNT(*) as record_count FROM performance_test
UNION ALL
SELECT 'user_orders', COUNT(*) FROM user_orders
UNION ALL
SELECT 'sales_data', COUNT(*) FROM sales_data
UNION ALL
SELECT 'documents', COUNT(*) FROM documents
UNION ALL
SELECT 'user_profiles', COUNT(*) FROM user_profiles
UNION ALL
SELECT 'employee_salaries', COUNT(*) FROM employee_salaries
ORDER BY record_count DESC;
