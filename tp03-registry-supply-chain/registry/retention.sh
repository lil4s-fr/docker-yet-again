#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=registry-common.sh
source "${SCRIPT_DIR}/registry-common.sh"

TMP_DIR=""

cleanup() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat >&2 <<'EOF'
Usage:
  retention.sh [--apply] REPOSITORY KEEP_COUNT

Without --apply, only print the deletion plan. Set REGISTRY_URL, REGISTRY_NETRC,
and optionally REGISTRY_CA_CERT to configure access.
EOF
}

config_created() {
  local repo="$1"
  local config_digest="$2"
  local config_json

  config_json="$(registry_api_curl "${REGISTRY_URL}/v2/${repo}/blobs/${config_digest}")" ||
    registry_common_die "could not read image config ${config_digest}"
  jq -r '.created // empty' <<<"$config_json"
}

manifest_created() {
  local repo="$1"
  local digest="$2"
  local manifest_json
  local config_digest
  local child_digests
  local child_digest
  local child_json
  local child_config
  local created
  local latest_created=""

  manifest_json="$(registry_api_curl \
    -H "Accept: ${REGISTRY_MANIFEST_ACCEPT}" \
    "${REGISTRY_URL}/v2/${repo}/manifests/${digest}")" ||
    registry_common_die "could not read manifest ${digest}"

  config_digest="$(jq -r '.config.digest // empty' <<<"$manifest_json")"
  if [[ -n "$config_digest" ]]; then
    created="$(config_created "$repo" "$config_digest")"
    printf '%s\n' "${created:-0000-01-01T00:00:00Z}"
    return
  fi

  child_digests="$(jq -r '.manifests[]?.digest // empty' <<<"$manifest_json")"
  while IFS= read -r child_digest; do
    [[ -n "$child_digest" ]] || continue
    child_json="$(registry_api_curl \
      -H "Accept: ${REGISTRY_MANIFEST_ACCEPT}" \
      "${REGISTRY_URL}/v2/${repo}/manifests/${child_digest}")" ||
      registry_common_die "could not read platform manifest ${child_digest}"
    child_config="$(jq -r '.config.digest // empty' <<<"$child_json")"
    [[ -n "$child_config" ]] || continue
    created="$(config_created "$repo" "$child_config")"
    if [[ -n "$created" && "$created" > "$latest_created" ]]; then
      latest_created="$created"
    fi
  done <<<"$child_digests"

  printf '%s\n' "${latest_created:-0000-01-01T00:00:00Z}"
}

main() {
  local apply=0
  local repo
  local keep_count
  local tags_json
  local tags
  local tag
  local digest
  local created
  local tab
  local kept_digests
  local processed_digests
  local stale_count=0

  if [[ "${1:-}" == "--apply" ]]; then
    apply=1
    shift
  fi
  [[ $# -eq 2 ]] || { usage; exit 2; }
  repo="$1"
  keep_count="$2"
  registry_api_validate_repo "$repo"
  [[ "$keep_count" =~ ^[1-9][0-9]{0,4}$ ]] && (( keep_count <= 10000 )) ||
    registry_common_die "KEEP_COUNT must be an integer between 1 and 10000"

  registry_common_init
  TMP_DIR="$(mktemp -d)"
  local records="${TMP_DIR}/records.tsv"
  local sorted="${TMP_DIR}/sorted.tsv"
  local kept="${TMP_DIR}/kept.tsv"
  local stale="${TMP_DIR}/stale.tsv"
  kept_digests="${TMP_DIR}/kept-digests.txt"
  processed_digests="${TMP_DIR}/processed-digests.txt"
  : >"$records"
  : >"$processed_digests"

  tags_json="$(registry_api_curl "${REGISTRY_URL}/v2/${repo}/tags/list?n=10000")" ||
    registry_common_die "could not list tags for ${repo}"
  tags="$(jq -r '.tags[]? // empty' <<<"$tags_json")"
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    digest="$(registry_api_get_digest "$repo" "$tag")"
    created="$(manifest_created "$repo" "$digest")"
    printf '%s\t%s\t%s\n' "$created" "$digest" "$tag" >>"$records"
  done <<<"$tags"

  if [[ ! -s "$records" ]]; then
    printf 'No tags found for %s.\n' "$repo"
    return
  fi

  tab="$(printf '\t')"
  LC_ALL=C sort -t "$tab" -k1,1r -k2,2 -k3,3 "$records" >"$sorted"
  head -n "$keep_count" "$sorted" >"$kept"
  tail -n "+$((keep_count + 1))" "$sorted" >"$stale"
  cut -f2 "$kept" | sort -u >"$kept_digests"

  while IFS="$tab" read -r created digest tag; do
    [[ -n "$digest" ]] || continue
    if grep -Fqx "$digest" "$kept_digests"; then
      printf 'Keep %s:%s (digest %s is also referenced by a retained tag).\n' "$repo" "$tag" "$digest"
      continue
    fi
    if grep -Fqx "$digest" "$processed_digests"; then
      continue
    fi
    printf '%s\n' "$digest" >>"$processed_digests"
    stale_count=$((stale_count + 1))
    if (( apply )); then
      registry_api_delete_digest "$repo" "$digest"
      printf 'Deleted %s:%s (digest %s).\n' "$repo" "$tag" "$digest"
    else
      printf 'Would delete %s:%s (digest %s).\n' "$repo" "$tag" "$digest"
    fi
  done <"$stale"

  if (( stale_count == 0 )); then
    printf 'No unreferenced old digests to delete for %s.\n' "$repo"
  elif (( ! apply )); then
    printf 'Dry run only. Re-run with --apply to delete these manifests.\n'
  else
    printf 'Manifest deletion is complete. Stop the registry and run garbage collection to reclaim blobs.\n'
  fi
}

main "$@"
