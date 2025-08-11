-- Additional demo tables for advanced PostgreSQL tuning scenarios

-- Table for partitioning demonstrations
CREATE TABLE sales_data (
    id SERIAL,
    sale_date DATE NOT NULL,
    customer_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    unit_price DECIMAL(10,2),
    total_amount DECIMAL(12,2),
    region VARCHAR(50),
    sales_rep_id INTEGER
) PARTITION BY RANGE (sale_date);

-- Create partitions for different months
CREATE TABLE sales_data_2024_01 PARTITION OF sales_data
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE sales_data_2024_02 PARTITION OF sales_data
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE sales_data_2024_03 PARTITION OF sales_data
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');

-- Insert partitioned data
INSERT INTO sales_data (sale_date, customer_id, product_id, quantity, unit_price, total_amount, region, sales_rep_id)
SELECT 
    '2024-01-01'::date + (random() * 89)::int,
    (random() * 10000 + 1)::int,
    (random() * 1000 + 1)::int,
    (random() * 10 + 1)::int,
    (random() * 100 + 10)::decimal(10,2),
    0, -- Will update with trigger
    CASE (random() * 4)::int
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        ELSE 'West'
    END,
    (random() * 50 + 1)::int
FROM generate_series(1, 200000);

-- Update total_amount
UPDATE sales_data SET total_amount = quantity * unit_price;

-- Create indexes on partitioned table
CREATE INDEX idx_sales_data_customer ON sales_data (customer_id);
CREATE INDEX idx_sales_data_product ON sales_data (product_id);
CREATE INDEX idx_sales_data_region ON sales_data (region);

-- Table for full-text search demonstrations
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200),
    content TEXT,
    category VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    author_id INTEGER,
    tags TEXT[],
    search_vector tsvector
);

-- Insert document data
INSERT INTO documents (title, content, category, author_id, tags)
SELECT 
    'Document ' || generate_series || ': ' || 
    CASE (random() * 5)::int
        WHEN 0 THEN 'Technical Manual'
        WHEN 1 THEN 'User Guide'
        WHEN 2 THEN 'API Documentation'
        WHEN 3 THEN 'Tutorial'
        ELSE 'Reference Guide'
    END,
    'This is the content of document ' || generate_series || '. ' ||
    'It contains various technical information about ' ||
    CASE (random() * 3)::int
        WHEN 0 THEN 'database optimization and performance tuning'
        WHEN 1 THEN 'application development and best practices'
        ELSE 'system administration and monitoring'
    END || '. ' ||
    'The document provides detailed explanations and examples for ' ||
    'developers and system administrators who need to understand ' ||
    'complex technical concepts and implementation details.',
    CASE (random() * 4)::int
        WHEN 0 THEN 'Technical'
        WHEN 1 THEN 'Tutorial'
        WHEN 2 THEN 'Reference'
        ELSE 'Guide'
    END,
    (random() * 20 + 1)::int,
    ARRAY[
        CASE (random() * 3)::int
            WHEN 0 THEN 'postgresql'
            WHEN 1 THEN 'performance'
            ELSE 'database'
        END,
        CASE (random() * 3)::int
            WHEN 0 THEN 'tuning'
            WHEN 1 THEN 'optimization'
            ELSE 'monitoring'
        END
    ]
FROM generate_series(1, 50000);

-- Update search vectors
UPDATE documents SET search_vector = to_tsvector('english', title || ' ' || content);

-- Create full-text search index
CREATE INDEX idx_documents_search ON documents USING GIN(search_vector);
CREATE INDEX idx_documents_category ON documents (category);
CREATE INDEX idx_documents_tags ON documents USING GIN(tags);

-- Table for JSON/JSONB demonstrations
CREATE TABLE user_profiles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES performance_test(id),
    profile_data JSONB,
    preferences JSONB,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert JSON data
INSERT INTO user_profiles (user_id, profile_data, preferences, metadata)
SELECT 
    pt.id,
    jsonb_build_object(
        'firstName', 'User',
        'lastName', pt.id::text,
        'age', (random() * 60 + 18)::int,
        'address', jsonb_build_object(
            'street', (random() * 9999 + 1)::int || ' Main St',
            'city', 'City ' || (random() * 100 + 1)::int,
            'zipCode', (random() * 99999 + 10000)::text
        ),
        'skills', ARRAY['postgresql', 'python', 'javascript'],
        'experience', (random() * 15 + 1)::int
    ),
    jsonb_build_object(
        'theme', CASE (random() * 2)::int WHEN 0 THEN 'dark' ELSE 'light' END,
        'notifications', jsonb_build_object(
            'email', random() > 0.5,
            'sms', random() > 0.7,
            'push', random() > 0.3
        ),
        'language', CASE (random() * 3)::int
            WHEN 0 THEN 'en'
            WHEN 1 THEN 'es'
            ELSE 'fr'
        END
    ),
    json_build_object(
        'lastLogin', CURRENT_TIMESTAMP - (random() * interval '30 days'),
        'loginCount', (random() * 1000)::int,
        'deviceInfo', json_build_object(
            'browser', CASE (random() * 3)::int
                WHEN 0 THEN 'Chrome'
                WHEN 1 THEN 'Firefox'
                ELSE 'Safari'
            END,
            'os', CASE (random() * 3)::int
                WHEN 0 THEN 'Windows'
                WHEN 1 THEN 'macOS'
                ELSE 'Linux'
            END
        )
    )
FROM performance_test pt
WHERE pt.id <= 25000;

-- Create JSONB indexes
CREATE INDEX idx_user_profiles_age ON user_profiles USING GIN ((profile_data->'age'));
CREATE INDEX idx_user_profiles_city ON user_profiles USING GIN ((profile_data->'address'->'city'));
CREATE INDEX idx_user_profiles_skills ON user_profiles USING GIN ((profile_data->'skills'));
CREATE INDEX idx_user_profiles_theme ON user_profiles USING GIN ((preferences->'theme'));

-- Table for window function demonstrations
CREATE TABLE employee_salaries (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER,
    department VARCHAR(50),
    position VARCHAR(100),
    salary DECIMAL(10,2),
    hire_date DATE,
    performance_score DECIMAL(3,2)
);

-- Insert employee data
INSERT INTO employee_salaries (employee_id, department, position, salary, hire_date, performance_score)
SELECT 
    generate_series,
    CASE (random() * 5)::int
        WHEN 0 THEN 'Engineering'
        WHEN 1 THEN 'Sales'
        WHEN 2 THEN 'Marketing'
        WHEN 3 THEN 'HR'
        ELSE 'Finance'
    END,
    CASE (random() * 4)::int
        WHEN 0 THEN 'Junior'
        WHEN 1 THEN 'Senior'
        WHEN 2 THEN 'Lead'
        ELSE 'Manager'
    END || ' ' ||
    CASE (random() * 3)::int
        WHEN 0 THEN 'Developer'
        WHEN 1 THEN 'Analyst'
        ELSE 'Specialist'
    END,
    (random() * 100000 + 40000)::decimal(10,2),
    '2020-01-01'::date + (random() * 1460)::int,
    (random() * 2 + 3)::decimal(3,2)
FROM generate_series(1, 10000);

CREATE INDEX idx_employee_salaries_dept ON employee_salaries (department);
CREATE INDEX idx_employee_salaries_position ON employee_salaries (position);
CREATE INDEX idx_employee_salaries_hire_date ON employee_salaries (hire_date);