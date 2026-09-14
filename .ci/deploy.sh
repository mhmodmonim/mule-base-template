#!/usr/bin/env bash
# =============================================================================
#  Deploy the application to one environment with mule-maven-plugin.
# =============================================================================
#  Usage: deploy.sh <dev|test|uat|prod>
#
#  Environment:
#    MVN_FLAGS          Maven flags, must include -s .ci/maven-settings.xml
#    DEPLOY_ATTEMPTS    attempts before giving up (default 2, as retry(2) in
#                       the Jenkinsfile)
#    plus the credentials read by .ci/maven-settings.xml.
#
#  The application name, Anypoint environment and sizing all come from the
#  matching profile in pom.xml - there is exactly one place to change them.
# =============================================================================
set -euo pipefail

error() {
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"
	elif [[ -n "${TF_BUILD:-}" ]]; then echo "##vso[task.logissue type=error]$*"
	else echo "ERROR: $*" >&2
	fi
}

warn() {
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::warning::$*"
	elif [[ -n "${TF_BUILD:-}" ]]; then echo "##vso[task.logissue type=warning]$*"
	else echo "WARNING: $*" >&2
	fi
}

env_name="${1:-}"
case "$env_name" in
	dev | test | uat | prod) ;;
	*)
		error "Usage: deploy.sh <dev|test|uat|prod> (got '${env_name}')"
		exit 2
		;;
esac

# AES accepts 16, 24 or 32 character keys. Anything else deploys "successfully"
# and then fails at startup when the secure properties cannot be decrypted.
key_length="${#MULE_ENC_KEY}"
case "$key_length" in
	16 | 24 | 32) ;;
	*) warn "MULE_ENC_KEY is ${key_length} characters; AES keys are 16, 24 or 32. Secure properties will not decrypt." ;;
esac

# Optional values: an unset one would otherwise reach Runtime Manager as the
# literal "${env.API_ID}" (Maven) or "$(API_ID)" (Azure DevOps).
for name in API_ID PLATFORM_CLIENT_ID PLATFORM_CLIENT_SECRET; do
	value="${!name:-}"
	if [[ -z "$value" || "$value" == '$('*')' ]]; then
		export "$name=__NOT_SET__"
	fi
done

attempts="${DEPLOY_ATTEMPTS:-2}"
for ((attempt = 1; attempt <= attempts; attempt++)); do
	echo "Deploying to ${env_name} (attempt ${attempt}/${attempts})"
	# -DmuleDeploy deploys rather than only publishing; -DskipMunitTests keeps
	# the deploy lifecycle from re-running the suite that already passed.
	# shellcheck disable=SC2086 # MVN_FLAGS is intentionally word-split.
	if mvn ${MVN_FLAGS:-} deploy -P"$env_name" -DmuleDeploy -DskipMunitTests; then
		echo "Deployed to ${env_name}"
		exit 0
	fi
	if ((attempt < attempts)); then
		warn "Deployment attempt ${attempt} to ${env_name} failed; retrying in 30s"
		sleep 30
	fi
done

error "Deployment to ${env_name} failed after ${attempts} attempts"
exit 1
