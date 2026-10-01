#!/bin/bash
# SAGE PostgreSQL initialisation
# Runs ONCE, only when the data volume is empty (first start).
# Credentials come from the container environment (.env via compose), never hardcoded.
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  -v sage_user="$POSTGRES_SAGE_USER" \
  -v sage_password="$POSTGRES_SAGE_PASSWORD" <<'EOSQL'
CREATE USER :"sage_user" WITH ENCRYPTED PASSWORD :'sage_password';
CREATE DATABASE sage OWNER :"sage_user";
GRANT ALL PRIVILEGES ON DATABASE sage TO :"sage_user";
EOSQL