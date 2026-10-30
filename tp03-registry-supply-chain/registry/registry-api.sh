#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=registry-common.sh
source "${SCRIPT_DIR}/registry-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  registry-api.sh catalog
  registry-api.sh tags REPOSITORY
  registry-api.sh digest REPOSITORY TAG
  registry-api.sh delete REPOSITORY sha256:DIGEST

Set REGISTRY_NETRC and, for a private CA, REGISTRY_CA_CERT.
EOF
}

main() {
  local action="${1:-}"

  case "$action" in
    catalog)
      [[ $# -eq 1 ]] || { usage; exit 2; }
      registry_common_init
      registry_api_curl "${REGISTRY_URL}/v2/_catalog?n=10000" |
        jq -r '.repositories[]?'
      ;;
    tags)
      [[ $# -eq 2 ]] || { usage; exit 2; }
      registry_common_init
      registry_api_validate_repo "$2"
      registry_api_curl "${REGISTRY_URL}/v2/$2/tags/list?n=10000" |
        jq -r '.tags[]?'
      ;;
    digest)
      [[ $# -eq 3 ]] || { usage; exit 2; }
      registry_common_init
      registry_api_get_digest "$2" "$3"
      ;;
    delete)
      [[ $# -eq 3 ]] || { usage; exit 2; }
      registry_common_init
      registry_api_delete_digest "$2" "$3"
      printf 'Deleted manifest %s@%s. Run garbage collection while the registry is stopped to reclaim blobs.\n' "$2" "$3"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
