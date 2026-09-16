#!/usr/bin/env bash
# Ephemeral CI: tunnel regional Alertmanager to localhost for e2e-cli silence specs.
#
# Pattern (same as scripts/dev/ephemeral-env.sh port-forward):
#   1. Bastion: kubectl port-forward monitoring-alertmanager:9093 on 0.0.0.0
#   2. Test pod: SSM port-forward bastion:9093 -> localhost:9093
#
# Requires: AWS creds with ECS exec + SSM (rrp-rc), session-manager-plugin, kubectl on bastion.
# Sets ALERTMANAGER_URL (Makefile maps to E2E_ALERTMANAGER_URL for ginkgo).

set -euo pipefail

_AM_BASTION_PF_PID=""
_AM_SSM_PID=""
_AM_ECS_CLUSTER=""
_AM_TASK_ID=""
_AM_CLEANUP_REGISTERED=false
_AM_PRIOR_EXIT_TRAP=""

# Locate SSM plugin on PATH; on-demand-e2e `from: src` may not include Containerfile tooling.
ensure_session_manager_plugin() {
  if command -v session-manager-plugin >/dev/null 2>&1; then
    return 0
  fi
  local dir
  for dir in /usr/local/sessionmanagerplugin/bin /usr/bin /usr/local/bin; do
    if [[ -x "${dir}/session-manager-plugin" ]]; then
      export PATH="${dir}:${PATH}"
      return 0
    fi
  done
  if ! command -v dnf >/dev/null 2>&1 && ! command -v yum >/dev/null 2>&1; then
    echo "ERROR: session-manager-plugin not found and no package manager to install it" >&2
    return 1
  fi
  echo "=== Installing session-manager-plugin for Alertmanager tunnel ==="
  local arch sm_arch rpm=/tmp/session-manager-plugin.rpm pkg_mgr=dnf
  command -v dnf >/dev/null 2>&1 || pkg_mgr=yum
  arch=$(uname -m)
  case "${arch}" in
    x86_64) sm_arch=64bit ;;
    aarch64) sm_arch=arm64 ;;
    *)
      echo "ERROR: unsupported architecture for session-manager-plugin: ${arch}" >&2
      return 1
      ;;
  esac
  curl -fsSL --max-time 300 \
    "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_${sm_arch}/session-manager-plugin.rpm" \
    -o "${rpm}"
  "${pkg_mgr}" install -y "${rpm}"
  rm -f "${rpm}"
  ln -sf /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/bin/session-manager-plugin 2>/dev/null || true
  export PATH="/usr/local/sessionmanagerplugin/bin:${PATH}"
  if command -v session-manager-plugin >/dev/null 2>&1; then
    return 0
  fi
  echo "ERROR: session-manager-plugin install failed" >&2
  return 1
}

cleanup_alertmanager_forward() {
  if [[ -n "${_AM_SSM_PID}" ]]; then
    kill "${_AM_SSM_PID}" 2>/dev/null || true
    wait "${_AM_SSM_PID}" 2>/dev/null || true
    _AM_SSM_PID=""
  fi
  if [[ -n "${_AM_BASTION_PF_PID}" ]]; then
    kill "${_AM_BASTION_PF_PID}" 2>/dev/null || true
    wait "${_AM_BASTION_PF_PID}" 2>/dev/null || true
    _AM_BASTION_PF_PID=""
  fi
  if [[ -n "${_AM_ECS_CLUSTER}" && -n "${_AM_TASK_ID}" ]]; then
    aws ecs execute-command --cluster "${_AM_ECS_CLUSTER}" --task "${_AM_TASK_ID}" --container bastion \
      --interactive --command "pkill -f 'port-forward.*monitoring-alertmanager' || true" &>/dev/null || true
  fi
}

_register_am_cleanup_trap() {
  if [[ "${_AM_CLEANUP_REGISTERED}" == "true" ]]; then
    return 0
  fi
  local trap_output
  trap_output="$(trap -p EXIT 2>/dev/null || true)"
  if [[ -n "${trap_output}" ]]; then
    _AM_PRIOR_EXIT_TRAP="${trap_output#trap -- \'}"
    _AM_PRIOR_EXIT_TRAP="${_AM_PRIOR_EXIT_TRAP%\' EXIT}"
  fi
  trap '_am_run_exit_traps' EXIT
  _AM_CLEANUP_REGISTERED=true
}

_am_run_exit_traps() {
  cleanup_alertmanager_forward
  if [[ -n "${_AM_PRIOR_EXIT_TRAP}" ]]; then
    eval "${_AM_PRIOR_EXIT_TRAP}"
  fi
}

# Start bastion + SSM tunnel. Uses CLUSTER_PREFIX (eph-<hash>-) when cluster_id omitted.
start_alertmanager_forward() {
  local cluster_id="${1:-}"
  local local_port="${ALERTMANAGER_LOCAL_PORT:-9093}"
  local remote_port="${ALERTMANAGER_REMOTE_PORT:-9093}"
  local am_url="http://127.0.0.1:${local_port}"

  if [[ -z "${cluster_id}" ]]; then
    [[ -n "${CLUSTER_PREFIX:-}" ]] || {
      echo "ERROR: CLUSTER_PREFIX required to derive ephemeral cluster id" >&2
      return 1
    }
    cluster_id="${CLUSTER_PREFIX}regional"
  fi

  ensure_session_manager_plugin || return 1

  local repo_root script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"
  # shellcheck source=scripts/dev/env-common.sh
  source "${repo_root}/scripts/dev/env-common.sh"

  echo "=== Alertmanager forward: cluster_id=${cluster_id} ==="
  unset task_id
  bastion_run_task "${cluster_id}"
  _AM_ECS_CLUSTER="${ecs_cluster}"
  _AM_TASK_ID="${task_id}"
  _register_am_cleanup_trap
  sleep 12

  aws ecs execute-command --cluster "${ecs_cluster}" --task "${task_id}" --container bastion \
    --interactive --command "pkill -f 'port-forward.*monitoring-alertmanager' || true" &>/dev/null || true
  sleep 2

  echo "=== Bastion kubectl port-forward to Alertmanager ==="
  aws ecs execute-command --cluster "${ecs_cluster}" --task "${task_id}" --container bastion \
    --interactive \
    --command "kubectl port-forward svc/monitoring-alertmanager ${remote_port}:9093 -n monitoring --address 0.0.0.0" &
  _AM_BASTION_PF_PID=$!
  sleep 10

  local runtime_id target
  runtime_id=$(aws ecs describe-tasks --cluster "${ecs_cluster}" --tasks "${task_id}" \
    --query 'tasks[0].containers[?name==`bastion`].runtimeId | [0]' --output text)
  target="ecs:${ecs_cluster}_${task_id}_${runtime_id}"

  echo "=== SSM port-forward localhost:${local_port} -> bastion:${remote_port} ==="
  aws ssm start-session \
    --target "${target}" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"${remote_port}\"],\"localPortNumber\":[\"${local_port}\"]}" &
  _AM_SSM_PID=$!
  sleep 15

  if curl -sf --connect-timeout 5 --max-time 15 "${am_url}/-/healthy" >/dev/null; then
    export ALERTMANAGER_URL="${am_url}"
    export E2E_ALERTMANAGER_URL="${am_url}"
    echo "ALERTMANAGER_FORWARD_OK url=${ALERTMANAGER_URL}"
    return 0
  fi

  echo "ERROR: Alertmanager health check failed at ${am_url}" >&2
  cleanup_alertmanager_forward
  return 1
}
