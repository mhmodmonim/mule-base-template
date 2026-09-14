#!/usr/bin/env bash
# =============================================================================
#  Fail fast, with a readable message, when required configuration is missing.
# =============================================================================
#  Usage: require-env.sh NAME [NAME...]
#
#  Values are never printed. An Azure DevOps macro that did not resolve (the
#  literal text "$(NAME)", left behind when a variable group is not linked)
#  counts as missing, as does an empty GitHub secret (e.g. on a fork PR).
# =============================================================================
set -euo pipefail

error() {
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"
	elif [[ -n "${TF_BUILD:-}" ]]; then echo "##vso[task.logissue type=error]$*"
	else echo "ERROR: $*" >&2
	fi
}

missing=()
for name in "$@"; do
	value="${!name:-}"
	if [[ -z "$value" || "$value" == '$('*')' ]]; then
		missing+=("$name")
	fi
done

if (( ${#missing[@]} > 0 )); then
	error "Missing required configuration: ${missing[*]}"
	echo "See GitHub-Actions-README.md or Azure-DevOps-README.md for where each value is defined." >&2
	exit 1
fi

echo "Required configuration present: $*"
