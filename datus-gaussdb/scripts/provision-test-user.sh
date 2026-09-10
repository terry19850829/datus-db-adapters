#!/usr/bin/env bash
# Run synchronously in /docker-entrypoint-initdb.d, before the image stops its
# temporary server. A failure must stop initialization instead of being hidden
# in a background process.
set -euo pipefail

DB_USER=${GAUSSDB_USER:-datus}
DB_PASSWORD=${GAUSSDB_PASSWORD:-Datus@123}
PROVISIONED_MARKER="$PGDATA/.datus-test-provisioned"
rm -f "$PROVISIONED_MARKER"

role_exists=$(gsql -d postgres -v ON_ERROR_STOP=1 -v test_user="$DB_USER" -tA <<'SQL'
SELECT 1 FROM pg_roles WHERE rolname = :'test_user';
SQL
)
if [ -z "$role_exists" ]; then
    gsql -d postgres -v ON_ERROR_STOP=1 -v test_user="$DB_USER" -v test_password="$DB_PASSWORD" <<'SQL'
CREATE USER :"test_user" WITH LOGIN PASSWORD :'test_password';
SQL
fi

# Always grant privileges, including when an earlier attempt created the role
# but did not finish granting. openGauss does not grant CREATE on public to
# ordinary users by default.
gsql -d postgres -v ON_ERROR_STOP=1 -v test_user="$DB_USER" <<'SQL'
GRANT ALL PRIVILEGES TO :"test_user";
GRANT ALL ON SCHEMA public TO :"test_user";
SQL

# Keep the image's earlier MD5 rule for the psycopg2 compatibility path.
hba_user=${DB_USER//\"/\"\"}
hba_rule="host all \"$hba_user\" 0.0.0.0/0 sha256"
if ! grep -Fxq "$hba_rule" "$PGDATA/pg_hba.conf"; then
    printf '%s\n' "$hba_rule" >> "$PGDATA/pg_hba.conf"
fi
# The image's final start loads these settings; do not restart from an init hook.
gs_guc set -D "$PGDATA" -c "listen_addresses='*'"

touch "$PROVISIONED_MARKER"
echo "gaussdb: provisioned test user '$DB_USER'"
