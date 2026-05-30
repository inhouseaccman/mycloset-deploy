#!/bin/bash
set -euo pipefail

python3 - <<'PY'
import re
import secrets
from pathlib import Path

env_path = Path("/opt/deploy/.env")
secrets_path = Path("/opt/deploy/configs/secrets.ini")

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
