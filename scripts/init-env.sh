#!/bin/bash
set -euo pipefail

python3 - <<'PY'
import re
import secrets
from pathlib import Path

env_path = Path("/opt/deploy/.env")
secrets_path = Path("/opt/deploy/configs/secrets.ini")
secrets_path.parent.mkdir(parents=True, exist_ok=True)

DEFAULT_ENV = """FRONTEND_IMAGE=mycloset-frontend:latest
BACKEND_IMAGE=mycloset-backend:latest
NGINX_IMAGE=nginx:1.27-alpine
MYSQL_ROOT_PASSWORD=
MYSQL_DATABASE=closet_management
MYSQL_USER=closet
MYSQL_PASSWORD=
MYSQL_IMAGE=mysql:8.0
"""

DEFAULT_SECRETS = """[database]
dialect=mysql
driver=pymysql
user=closet
password=
host=db
port=3306
database=closet_management
options=charset=utf8mb4

[session]
secret=

[csrf]
secret=
expiration=300
algorithm=HS256

[jwt]
secret=

[google]
client_id=
client_secret=

[app]
prefix=
cors_origins=https://akikaycloset.vip,https://www.akikaycloset.vip

[upload]
dir=/opt/deploy/backend/uploads
allowed_extensions=jpg,jpeg,png,webp,gif,bmp
max_upload_size=10485760
url_prefix=/uploads
"""

if not env_path.exists():
    env_path.write_text(DEFAULT_ENV)
if not secrets_path.exists():
    secrets_path.write_text(DEFAULT_SECRETS)

env_lines = env_path.read_text().splitlines()
secrets_lines = secrets_path.read_text().splitlines()

env = {}
order = []
for line in env_lines:
    if not line.strip() or line.strip().startswith("#"):
        order.append(("raw", line))
        continue
    if "=" in line:
        k, v = line.split("=", 1)
        env[k] = v
        order.append(("kv", k))
    else:
        order.append(("raw", line))

if not env.get("MYSQL_ROOT_PASSWORD"):
    env["MYSQL_ROOT_PASSWORD"] = secrets.token_urlsafe(24)
if not env.get("MYSQL_PASSWORD"):
    env["MYSQL_PASSWORD"] = secrets.token_urlsafe(24)

env["FRONTEND_IMAGE"] = "mycloset-frontend:latest"
env["BACKEND_IMAGE"] = "mycloset-backend:latest"
env["MYSQL_IMAGE"] = "mysql:8.0"
env["NGINX_IMAGE"] = "nginx:1.27-alpine"
env.setdefault("MYSQL_DATABASE", "closet_management")
env.setdefault("MYSQL_USER", "closet")

seen = set()
out_env = []
for kind, item in order:
    if kind == "raw":
        out_env.append(item)
    elif item not in seen:
        out_env.append(f"{item}={env[item]}")
        seen.add(item)
for k, v in env.items():
    if k not in seen:
        out_env.append(f"{k}={v}")
env_path.write_text("\n".join(out_env).strip() + "\n")

section = None
out_secrets = []
for line in secrets_lines:
    if line.strip().startswith("[") and line.strip().endswith("]"):
        section = line.strip()[1:-1]
        out_secrets.append(line)
        continue
    if "=" in line:
        key, val = line.split("=", 1)
        if section == "database" and key == "password":
            val = env["MYSQL_PASSWORD"]
        if section == "database" and key == "host":
            val = "db"
        if key == "secret" and not val:
            val = secrets.token_urlsafe(32)
        out_secrets.append(f"{key}={val}")
    else:
        out_secrets.append(line)

secrets_path.write_text("\n".join(out_secrets).strip() + "\n")
print("INIT_ENV_OK")
PY

chmod 600 /opt/deploy/.env /opt/deploy/configs/secrets.ini
