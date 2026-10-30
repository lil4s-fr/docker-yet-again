REGISTRY_URL="${REGISTRY_URL:-https://registry.local:5000}"
REGISTRY_NETRC="${REGISTRY_NETRC:-${HOME}/.netrc}"
REGISTRY_CA_CERT="${REGISTRY_CA_CERT:-}"
REGISTRY_MANIFEST_ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
CURL_ARGS=()

registry_common_die() {
  printf 'registry: %s\n' "$*" >&2
  exit 1
}

registry_common_init() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

  for tool in curl jq awk; do
    command -v "$tool" >/dev/null 2>&1 || registry_common_die "$tool is required."
  done
  [[ "$REGISTRY_URL" == https://* ]] || registry_common_die "REGISTRY_URL must use https."
  [[ -r "$REGISTRY_NETRC" ]] || registry_common_die "REGISTRY_NETRC is not readable: $REGISTRY_NETRC"
  REGISTRY_URL="${REGISTRY_URL%/}"

  if [[ -z "$REGISTRY_CA_CERT" && -r "${script_dir}/certs/registry-ca.crt" ]]; then
    REGISTRY_CA_CERT="${script_dir}/certs/registry-ca.crt"
  fi

  CURL_ARGS=(--fail --silent --show-error --netrc-file "$REGISTRY_NETRC")
  if [[ -n "$REGISTRY_CA_CERT" ]]; then
    [[ -r "$REGISTRY_CA_CERT" ]] || registry_common_die "REGISTRY_CA_CERT is not readable: $REGISTRY_CA_CERT"
    CURL_ARGS+=(--cacert "$REGISTRY_CA_CERT")
  fi
}

registry_api_curl() {
  curl "${CURL_ARGS[@]}" "$@"
}

registry_api_validate_repo() {
  local repo="$1"
  [[ "$repo" =~ ^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$ ]] ||
    registry_common_die "invalid repository name: $repo"
}

registry_api_validate_tag() {
  local tag="$1"
  [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] ||
    registry_common_die "invalid tag: $tag"
}

registry_api_validate_digest() {
  local digest="$1"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] ||
    registry_common_die "invalid sha256 digest: $digest"
}

registry_api_get_digest() {
  local repo="$1"
  local tag="$2"
  local headers
  local digest

  registry_api_validate_repo "$repo"
  registry_api_validate_tag "$tag"
  headers="$(registry_api_curl --head \
    -H "Accept: ${REGISTRY_MANIFEST_ACCEPT}" \
    "${REGISTRY_URL}/v2/${repo}/manifests/${tag}")" ||
    registry_common_die "could not read manifest headers for ${repo}:${tag}"
  digest="$(printf '%s\n' "$headers" | awk 'tolower($1) == "docker-content-digest:" { gsub(/\r/, "", $2); print $2; exit }')"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] ||
    registry_common_die "Docker-Content-Digest is missing or invalid for ${repo}:${tag}"
  printf '%s\n' "$digest"
}

registry_api_delete_digest() {
  local repo="$1"
  local digest="$2"
  local status

  registry_api_validate_repo "$repo"
  registry_api_validate_digest "$digest"
  status="$(registry_api_curl -X DELETE -o /dev/null -w '%{http_code}' \
    "${REGISTRY_URL}/v2/${repo}/manifests/${digest}")" ||
    registry_common_die "could not delete ${repo}@${digest}"
  [[ "$status" == "202" ]] ||
    registry_common_die "registry returned HTTP ${status} while deleting ${repo}@${digest}"
}
