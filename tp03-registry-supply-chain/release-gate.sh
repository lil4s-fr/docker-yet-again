#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  release-gate.sh IMAGE [--push REGISTRY_IMAGE]

The local image must have non-empty OCI version, revision, and source labels,
a non-root user, and a HEALTHCHECK. Syft and Trivy are required for SBOM and
security checks. When --push is supplied, cosign and COSIGN_KEY are also required.
EOF
}

fail() {
  printf 'release gate: %s\n' "$*" >&2
  exit 1
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage
  exit 2
fi

IMAGE="$1"
shift
PUSH_IMAGE=""
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == "--push" && -n "$2" ]] || {
    usage
    exit 2
  }
  PUSH_IMAGE="$2"
fi

for tool in docker jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required."
done

if ! config_json="$(docker image inspect --format='{{json .Config}}' "$IMAGE")"; then
  fail "could not inspect local image: $IMAGE"
fi

for label in \
  org.opencontainers.image.version \
  org.opencontainers.image.revision \
  org.opencontainers.image.source; do
  if ! jq -e --arg label "$label" \
    '.Labels[$label] | select(type == "string" and length > 0)' \
    <<<"$config_json" >/dev/null; then
    fail "image is missing required OCI label: $label"
  fi
done

image_user="$(jq -r '.User // ""' <<<"$config_json")"
image_uid="${image_user%%:*}"
case "$image_uid" in
  ""|root)
    fail "image runs as root (Config.User=${image_user:-unset})"
    ;;
esac
if [[ "$image_uid" =~ ^0+$ ]]; then
  fail "image runs as root (Config.User=$image_user)"
fi

if ! jq -e \
  '(.Healthcheck.Test // []) as $test | (($test | length) > 0 and $test[0] != "NONE")' \
  <<<"$config_json" >/dev/null; then
  fail "image has no active HEALTHCHECK"
fi

for tool in syft trivy; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required."
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
vuln_report="${tmp_dir}/vulnerabilities.json"
secret_report="${tmp_dir}/secrets.json"
sbom_path="${SBOM_PATH:-sbom.json}"

if ! trivy image --exit-code 0 --scanners vuln --severity HIGH,CRITICAL \
  --ignore-unfixed --format json --output "$vuln_report" "$IMAGE"; then
  fail "Trivy vulnerability scan failed for $IMAGE"
fi

fixable_count="$(jq \
  '[.Results[]?.Vulnerabilities[]? | select((.Severity == "HIGH" or .Severity == "CRITICAL") and ((.FixedVersion // "") != ""))] | length' \
  "$vuln_report")" || fail "could not parse Trivy vulnerability report"
if (( fixable_count > 0 )); then
  jq -r \
    '.Results[]?.Vulnerabilities[]? | select((.Severity == "HIGH" or .Severity == "CRITICAL") and ((.FixedVersion // "") != "")) | "\(.VulnerabilityID) \(.Severity) \(.PkgName) fixed in \(.FixedVersion)"' \
    "$vuln_report" >&2
  fail "$fixable_count fixable HIGH/CRITICAL vulnerabilities found"
fi

if ! trivy image --exit-code 0 --scanners secret --format json \
  --output "$secret_report" "$IMAGE"; then
  fail "Trivy secret scan failed for $IMAGE"
fi

secret_count="$(jq '[.Results[]?.Secrets[]?] | length' "$secret_report")" ||
  fail "could not parse Trivy secret report"
if (( secret_count > 0 )); then
  fail "$secret_count secret finding(s) detected; details withheld to avoid printing secret values"
fi

if ! syft "$IMAGE" --output spdx-json >"$sbom_path"; then
  fail "Syft could not generate the SBOM for $IMAGE"
fi
jq -e '.spdxVersion != null and (.packages | type == "array")' "$sbom_path" >/dev/null ||
  fail "Syft output is not valid SPDX JSON"
printf 'Release gate passed for %s. SBOM written to %s.\n' "$IMAGE" "$sbom_path"

if [[ -n "$PUSH_IMAGE" ]]; then
  command -v cosign >/dev/null 2>&1 || fail "cosign is required when --push is used."
  COSIGN_KEY="${COSIGN_KEY:-cosign.key}"
  [[ -r "$COSIGN_KEY" ]] || fail "COSIGN_KEY is not readable: $COSIGN_KEY"

  docker tag "$IMAGE" "$PUSH_IMAGE" || fail "could not tag $IMAGE as $PUSH_IMAGE"
  docker push "$PUSH_IMAGE" || fail "could not push $PUSH_IMAGE"
  cosign sign --key "$COSIGN_KEY" "$PUSH_IMAGE" ||
    fail "cosign signing failed for $PUSH_IMAGE"
  cosign attest --key "$COSIGN_KEY" --type spdxjson \
    --predicate "$sbom_path" "$PUSH_IMAGE" ||
    fail "cosign SBOM attestation failed for $PUSH_IMAGE"
  printf 'Pushed, signed, and attested %s.\n' "$PUSH_IMAGE"
else
  printf 'No --push target supplied; image was validated locally only.\n'
fi
