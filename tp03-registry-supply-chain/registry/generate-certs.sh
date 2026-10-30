#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${CERT_DIR:-${SCRIPT_DIR}/certs}"

if ! command -v openssl >/dev/null 2>&1; then
  printf 'Error: openssl is required.\n' >&2
  exit 1
fi

mkdir -p "$CERT_DIR"
for file in registry-ca.key registry-ca.crt registry-ca.srl registry.key registry.crt; do
  if [[ -e "${CERT_DIR}/${file}" ]]; then
    printf 'Error: %s already exists; move it aside before generating a new CA.\n' "${CERT_DIR}/${file}" >&2
    exit 1
  fi
done

umask 077
tmp_dir="$(mktemp -d "${CERT_DIR}/.certs.XXXXXX")"
trap 'rm -rf -- "$tmp_dir"' EXIT

openssl genrsa -out "${tmp_dir}/registry-ca.key" 4096
openssl req -x509 -new -sha256 -days 3650 \
  -key "${tmp_dir}/registry-ca.key" \
  -subj "/CN=Shop SAS local registry CA" \
  -out "${tmp_dir}/registry-ca.crt"

openssl genrsa -out "${tmp_dir}/registry.key" 2048
openssl req -new \
  -key "${tmp_dir}/registry.key" \
  -subj "/CN=registry.local" \
  -out "${tmp_dir}/registry.csr"

cat >"${tmp_dir}/registry.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:registry.local,DNS:registry,IP:127.0.0.1
EOF

openssl x509 -req -sha256 -days 825 \
  -in "${tmp_dir}/registry.csr" \
  -CA "${tmp_dir}/registry-ca.crt" \
  -CAkey "${tmp_dir}/registry-ca.key" \
  -CAcreateserial \
  -extfile "${tmp_dir}/registry.ext" \
  -out "${tmp_dir}/registry.crt"

chmod 600 "${tmp_dir}/registry-ca.key" "${tmp_dir}/registry.key"
chmod 644 "${tmp_dir}/registry-ca.crt" "${tmp_dir}/registry.crt"
mv "${tmp_dir}/registry-ca.key" "$CERT_DIR/registry-ca.key"
mv "${tmp_dir}/registry-ca.crt" "$CERT_DIR/registry-ca.crt"
mv "${tmp_dir}/registry-ca.srl" "$CERT_DIR/registry-ca.srl"
mv "${tmp_dir}/registry.key" "$CERT_DIR/registry.key"
mv "${tmp_dir}/registry.crt" "$CERT_DIR/registry.crt"

printf 'Certificates created in %s\n' "$CERT_DIR"
printf 'The CA private key is not mounted into the registry container.\n'
