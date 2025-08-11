FROM postgres:17

# Install additional tools for demos including pgBadger
RUN apt-get update && apt-get install -y \
    postgresql-contrib \
    vim \
    htop \
    wget \
    curl \
    perl \
    && rm -rf /var/lib/apt/lists/*

# Install pgBadger by downloading the script directly
RUN curl -L https://raw.githubusercontent.com/darold/pgbadger/master/pgbadger -o /usr/local/bin/pgbadger \
    && chmod +x /usr/local/bin/pgbadger

# Create directory for pgBadger reports
RUN mkdir -p /var/log/postgresql /pgbadger-reports

# Copy custom configuration and demo files
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY init-scripts/ /docker-entrypoint-initdb.d/
COPY demo-data/ /demo-data/

# Set environment variables
ENV POSTGRES_DB=tuning_demo
ENV POSTGRES_USER=demo_user
ENV POSTGRES_PASSWORD=demo_pass

# Expose PostgreSQL port
EXPOSE 5432

# Use custom config
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]