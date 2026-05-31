#!/bin/bash
# Windows 本機：Management Tool Release → publish/prd（連線 production API）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANAGEMENT_DIR="${MANAGEMENT_DIR:-$ROOT_DIR/Management}"
OUTPUT_DIR="$MANAGEMENT_DIR/publish/prd"

if [ ! -f "$MANAGEMENT_DIR/Management.csproj" ]; then
  echo "missing $MANAGEMENT_DIR/Management.csproj" >&2
  exit 1
fi

case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW* | MSYS* | CYGWIN*) ;;
  *)
    echo "Management prod build requires Windows (Git Bash / MSYS)" >&2
    exit 1
    ;;
esac

if ! command -v dotnet >/dev/null 2>&1; then
  echo "dotnet SDK not found" >&2
  exit 1
fi

cd "$MANAGEMENT_DIR"
mkdir -p "$OUTPUT_DIR"
dotnet publish Management.csproj -c Release -p:Platform=x64 -o "$OUTPUT_DIR"
echo "MANAGEMENT_OK: $OUTPUT_DIR/Management.exe"
