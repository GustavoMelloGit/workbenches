#!/usr/bin/env bash
# entrypoint.sh
# - On first run: initialize Postgres cluster inside the persistent volume.
# - Then exec supervisor, which keeps sshd + postgres + redis up.
set -euo pipefail

PGDATA=/home/dev/.pgdata
REDIS_DIR=/home/dev/.redis

# --- Postgres: initdb if empty ----------------------------------------------
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[entrypoint] Inicializando cluster Postgres em $PGDATA (primeira execução)..."
  mkdir -p "$PGDATA"
  chown -R dev:dev "$PGDATA"
  chmod 700 "$PGDATA"

  # initdb roda como o usuário dev e cria um superusuário 'dev'
  sudo -u dev /usr/lib/postgresql/16/bin/initdb \
    --pgdata="$PGDATA" \
    --username=dev \
    --auth-local=trust \
    --auth-host=trust \
    --encoding=UTF8 \
    --locale=en_US.UTF-8

  # Permite conexões locais sem senha (é dev local dentro de um container isolado).
  # Se quiser senha, edite pg_hba.conf depois.
  echo "host all all 127.0.0.1/32 trust" >> "$PGDATA/pg_hba.conf"
  echo "host all all ::1/128       trust" >> "$PGDATA/pg_hba.conf"

  # Tuning leve pra dev
  cat >> "$PGDATA/postgresql.conf" <<'EOF'

# workbench tuning
listen_addresses = 'localhost'
port = 5432
EOF

  echo "[entrypoint] Cluster Postgres pronto."
else
  echo "[entrypoint] Cluster Postgres já existe em $PGDATA, reaproveitando."
fi

# --- Redis: ensure data dir exists ------------------------------------------
mkdir -p "$REDIS_DIR"
chown -R dev:dev "$REDIS_DIR"

# --- Postgres runtime socket dir (owned by the package's 'postgres' user by default) ---
mkdir -p /var/run/postgresql
chown dev:dev /var/run/postgresql

# --- Supervisor: orchestrates sshd + postgres + redis -----------------------
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
