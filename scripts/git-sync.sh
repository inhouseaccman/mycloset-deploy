#!/bin/bash
# 從 git 同步；reset --hard 確保無 local changes（保留 gitignore runtime 檔）。
# 用法：git-sync.sh <repo_url> <target_dir> [branch]
set -euo pipefail

REPO_URL="${1:?repo url}"
TARGET_DIR="${2:?target dir}"
BRANCH="${3:-${GIT_BRANCH:-master}}"

if [ -f "$HOME/.git-credentials" ] && ! git config --global --get-regexp '^url\..*\.insteadof$' https://github.com/ >/dev/null 2>&1; then
  python3 - <<'PY'
from pathlib import Path
import subprocess
cred = Path.home().joinpath(".git-credentials").read_text().splitlines()[0].strip()
base = cred.rstrip("/") + "/"
subprocess.run(["git", "config", "--global", f"url.{base}.insteadOf", "https://github.com/"], check=True)
PY
fi

mkdir -p "$(dirname "$TARGET_DIR")"
if [ -d "$TARGET_DIR/.git" ]; then
  git -C "$TARGET_DIR" fetch origin "$BRANCH"
  git -C "$TARGET_DIR" reset --hard "origin/$BRANCH"
  git -C "$TARGET_DIR" clean -fd
else
  git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

[ -z "$(git -C "$TARGET_DIR" status --porcelain)" ] || {
  echo "git-sync: dirty tree: $TARGET_DIR" >&2
  exit 1
}
echo "git-sync OK: $(git -C "$TARGET_DIR" rev-parse --short HEAD) $TARGET_DIR"
