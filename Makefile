# PostgreSQL Tuning Demo - Makefile
# Convenient commands for managing the demo environment

.PHONY: help start stop test clean connect logs status benchmark

# Default target
help:
	@echo "PostgreSQL Tuning Demo - Available Commands:"
	@echo ""
	@echo "  make start      - Start the demo environment"
	@echo "  make test       - Test the setup and verify everything works"
	@echo "  make connect    - Connect to the database"
	@echo "  make logs       - Show container logs"
	@echo "  make status     - Show container status"
	@echo "  make benchmark  - Run performance benchmarks"
	@echo "  make monitor    - Run comprehensive monitoring dashboard"
	@echo "  make pgbadger   - Generate pgBadger log analysis report"
	@echo "  make enable-stats - Enable pg_stat_statements for query analysis"
	@echo "  make validate   - Validate all use cases and functionality"
	@echo "  make perf-test  - Run detailed performance validation"
	@echo "  make stop       - Stop the demo environment"
	@echo "  make clean      - Stop and remove everything (including data)"
	@echo ""
	@echo "Quick start: make start && make test && make connect"

# Start the demo environment
start:
	@echo "🚀 Starting PostgreSQL Tuning Demo..."
	docker-compose up -d
	@echo "✅ Demo started! Run 'make test' to verify setup."

# Test the setup
test:
	@echo "🧪 Testing demo setup..."
	./test-setup.sh

# Connect to the database
connect:
	@echo "🔗 Connecting to PostgreSQL..."
	@echo "💡 Tip: Run '\\i /demo-data/step-by-step-tutorial.sql' to start the tutorial"
	docker exec -it pg-tuning-demo psql -U demo_user -d tuning_demo

# Show container logs
logs:
	@echo "📋 Container logs:"
	docker logs pg-tuning-demo --tail 50 -f

# Show container status
status:
	@echo "📊 Container status:"
	docker ps | grep pg-tuning-demo || echo "Container not running"
	@echo ""
	@echo "📈 Resource usage:"
	docker stats pg-tuning-demo --no-stream || echo "Container not running"

# Run performance benchmarks
benchmark:
	@echo "⚡ Running performance benchmarks..."
	docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "\\i /demo-data/performance-benchmarks.sql"

# Stop the demo environment
stop:
	@echo "🛑 Stopping PostgreSQL Tuning Demo..."
	docker-compose down
	@echo "✅ Demo stopped."

# Clean everything (including data)
clean:
	@echo "🧹 Cleaning up everything..."
	docker-compose down -v
	docker system prune -f
	@echo "✅ Cleanup complete."

# Quick setup for new users
quick-start: start
	@echo "⏳ Waiting for PostgreSQL to be ready..."
	@sleep 15
	@make test
	@echo ""
	@echo "🎉 Quick start complete! Run 'make connect' to begin."

# Development helpers
rebuild:
	@echo "🔨 Rebuilding containers..."
	docker-compose down
	docker-compose build --no-cache
	docker-compose up -d

# Show database info
info:
	@echo "📊 Database Information:"
	@echo "======================="
	docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "SELECT version();"
	@echo ""
	docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "SELECT tablename, pg_size_pretty(pg_total_relation_size('public.'||tablename)) as size FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size('public.'||tablename) DESC;"

# Run comprehensive monitoring dashboard
monitor:
	@echo "📊 Running comprehensive monitoring dashboard..."
	docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "\\i /demo-data/monitoring-dashboard.sql"

# Generate pgBadger log analysis report
pgbadger:
	@echo "📈 Generating pgBadger log analysis report..."
	@echo "1. Running sample workload to generate log data..."
	docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "\\i /demo-data/log-analysis-pgbadger.sql"
	@echo "2. Analyzing logs with pgBadger..."
	docker exec pg-tuning-demo bash -c "pgbadger /var/log/postgresql/postgresql-*.log -o /pgbadger-reports/report.html"
	@echo "3. Copying report to local directory..."
	docker cp pg-tuning-demo:/pgbadger-reports/report.html ./pgbadger-report.html
	@echo "✅ pgBadger report generated: pgbadger-report.html"
	@echo "💡 Open the report in your browser to view detailed log analysis"

# Enable pg_stat_statements extension
enable-stats:
	@echo "🔧 Enabling pg_stat_statements extension..."
	@echo "1. Stopping container..."
	docker-compose down
	@echo "2. Updating postgresql.conf..."
	sed -i '' "s/shared_preload_libraries = ''/shared_preload_libraries = 'pg_stat_statements'/" postgresql.conf
	sed -i '' "s/# pg_stat_statements.track = all/pg_stat_statements.track = all/" postgresql.conf
	sed -i '' "s/# pg_stat_statements.max = 10000/pg_stat_statements.max = 10000/" postgresql.conf
	@echo "3. Rebuilding and starting container..."
	docker-compose up -d --build
	@echo "4. Waiting for PostgreSQL to be ready..."
	@sleep 20
	@echo "5. Creating extension..."
	docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
	@echo "✅ pg_stat_statements enabled! You can now analyze query performance."
	@echo "💡 Try: SELECT query, calls, total_exec_time FROM pg_stat_statements LIMIT 5;"

# Validate all use cases and functionality
validate:
	@echo "🧪 Validating all PostgreSQL tuning use cases..."
	./validate-use-cases.sh

# Run detailed performance validation
perf-test:
	@echo "⚡ Running detailed performance validation..."
	@echo "This will test all tuning scenarios with timing measurements..."
	docker exec pg-tuning-demo psql -U demo_user -d tuning_demo -c "\\i /demo-data/performance-validation.sql"