#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUTH_DIR="${SCRIPT_DIR}/auth"
AUTH_FILE="${AUTH_DIR}/htpasswd"

if ! command -v htpasswd >/dev/null 2>&1; then
  printf 'Error: htpasswd is required (for example, install apache2-utils/httpd-tools).\n' >&2
  exit 1
fi

if [[ -e "$AUTH_FILE" ]]; then
  printf 'Error: %s already exists; remove it explicitly to rotate credentials.\n' "$AUTH_FILE" >&2
  exit 1
fi

mkdir -p "$AUTH_DIR"
umask 077
htpasswd -B -c "$AUTH_FILE" ci
htpasswd -B "$AUTH_FILE" dev
chmod 600 "$AUTH_FILE"

printf 'Bcrypt credentials created in %s. The passwords were not written to the command line.\n' "$AUTH_FILE"
