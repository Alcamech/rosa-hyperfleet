#!/usr/bin/env bash
#
# Configure AWS profiles from a pre-built config file in CI credentials.
#
# In CI (Prow), credentials are mounted under CREDS_DIR (default:
# /var/run/rosa-credentials/). This script expects an "aws_config" file
# containing named AWS CLI profiles. It sets AWS_CONFIG_FILE so all
# downstream consumers (aws.py, e2e-tests.sh, load tests) pick them up.
#
# Usage:
#   source ci/setup-aws-profiles.sh

set -euo pipefail

# Stable STS RoleSessionName for assume-role profiles in e2e (ZOA Access operator
# attribution across subprocesses). AWS SDK/CLI apply this when assuming roles from
# aws_config; it overrides per-profile role_session_name when set (see AWS CLI env
# var docs). Override with AWS_CI_ROLE_SESSION_NAME for ad-hoc runs.
export AWS_ROLE_SESSION_NAME="${AWS_CI_ROLE_SESSION_NAME:-seaplane-e2e}"

CREDS_DIR="${CREDS_DIR:-/var/run/rosa-credentials}"

# Already configured (e.g. local dev container mount) — skip path setup only.
if [[ -n "${AWS_CONFIG_FILE:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

if [[ ! -r "${CREDS_DIR}/aws_config" ]]; then
  echo "Error: ${CREDS_DIR}/aws_config not found or not readable" >&2
  return 1 2>/dev/null || exit 1
fi

export AWS_CONFIG_FILE="${CREDS_DIR}/aws_config"
echo "AWS profiles configured (config: ${AWS_CONFIG_FILE})"
