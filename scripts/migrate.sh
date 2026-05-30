#!/bin/bash
set -euo pipefail

ENV_FILE=/opt/deploy/.env
SECRETS_FILE=/opt/deploy/configs/secrets.ini
ALEMBIC_FILE=/opt/deploy/configs/alembic.ini

python3 - <<'PY'
import re
from pathlib import Path

env = {}
for line in Path("/opt/deploy/.env").read_text().splitlines():
    if "=" in line and not line.strip().startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()

user = env.get("MYSQL_USER", "closet")
password = env.get("MYSQL_PASSWORD", "")
database = env.get("MYSQL_DATABASE", "closet_management")
url = f"mysql+pymysql://{user}:{password}@db:3306/{database}?charset=utf8mb4"

template = Path("/opt/deploy/configs/alembic.ini.example")

text = template.read_text()
text = re.sub(r"^sqlalchemy\.url\s*=.*$", f"sqlalchemy.url = {url}", text, flags=re.M)
Path("/opt/deploy/configs/alembic.ini").write_text(text)
print("ALEMBIC_INI_OK")
PY

docker compose -f /opt/deploy/docker-compose.yml cp "$ALEMBIC_FILE" backend:/opt/deploy/backend/alembic.ini
docker compose -f /opt/deploy/docker-compose.yml exec -T backend sh -c "cd /opt/deploy/backend && python -m alembic upgrade head"
echo "MIGRATION_OK"
