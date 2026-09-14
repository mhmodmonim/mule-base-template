#!/usr/bin/env bash
# =============================================================================
#  Smoke test a deployed application through /health-check.
# =============================================================================
#  Usage: smoke-test.sh <environment> <base-url>
#     e.g. smoke-test.sh dev https://my-app-dev.uk-e1.cloudhub.io/api
#
#  Passes when GET <base-url>/health-check returns 200 with "status": "UP".
#  A deploy that reports success but leaves the app unhealthy is the failure
#  mode this catches. With no base URL the test is skipped (not failed), so
#  environments can adopt it one at a time - same as the Jenkinsfile.
#
#  Environment:
#    SMOKE_ATTEMPTS        default 5
#    SMOKE_DELAY_SECONDS   wait before each attempt, default 15
# =============================================================================
set -euo pipefail

error() {
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"
	elif [[ -n "${TF_BUILD:-}" ]]; then echo "##vso[task.logissue type=error]$*"
	else echo "ERROR: $*" >&2
	fi
}

env_name="${1:?usage: smoke-test.sh <environment> <base-url>}"
base_url="${2:-}"

# Azure DevOps leaves an undefined $(APP_BASE_URL) macro as literal text.
if [[ -z "$base_url" || "$base_url" == '$('*')' ]]; then
	echo "No APP_BASE_URL configured for ${env_name} - skipping smoke test."
	exit 0
fi

url="${base_url%/}/health-check"
attempts="${SMOKE_ATTEMPTS:-5}"
delay="${SMOKE_DELAY_SECONDS:-15}"
body="$(mktemp)"
trap 'rm -f "$body"' EXIT

for ((attempt = 1; attempt <= attempts; attempt++)); do
	sleep "$delay"
	status="$(curl -sS -o "$body" -w '%{http_code}' --max-time 30 "$url")" || true
	echo "Attempt ${attempt}/${attempts}: GET ${url} -> HTTP ${status:-000}"
	cat "$body" 2>/dev/null || true
	echo
	if [[ "$status" == "200" ]] && grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"' "$body"; then
		echo "Smoke test passed for ${env_name}"
		exit 0
	fi
done

error "Smoke test failed for ${env_name}: ${url} did not return 200 with status UP"
exit 1
