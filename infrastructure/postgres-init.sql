-- SAGE PostgreSQL initialisation script
-- Runs once on first container start

CREATE DATABASE sage;
CREATE USER sage WITH ENCRYPTED PASSWORD 'sage_dev_password';
GRANT ALL PRIVILEGES ON DATABASE sage TO sage;

-- Connect to sage db and set up schema ownership
\c sage
GRANT ALL ON SCHEMA public TO sage;
