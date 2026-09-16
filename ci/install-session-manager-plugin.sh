#!/usr/bin/env bash
# Install or locate AWS session-manager-plugin (SSM port-forward for ephemeral bastion).
# Used by ci/Containerfile (system install) and ci/alertmanager-forward.sh (user cache).
#
# Usage:
#   source ci/install-session-manager-plugin.sh
#   ensure_session_manager_plugin_on_path   # runtime (non-root safe)
#   install_session_manager_plugin_system   # build-time only (root + dnf)

set -euo pipefail

if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

_SSM_PLUGIN_SEARCH_DIRS=(
  /usr/local/sessionmanagerplugin/bin
  /usr/bin
  /usr/local/bin
)

_ssm_user_install_dir() {
  local base="${SESSION_MANAGER_PLUGIN_CACHE:-${REPO_ROOT:-}/ci/.cache/session-manager-plugin}"
  echo "${base}/bin"
}

_session_manager_plugin_on_path() {
  command -v session-manager-plugin >/dev/null 2>&1 && return 0
  local dir
  for dir in "${_SSM_PLUGIN_SEARCH_DIRS[@]}" "$(_ssm_user_install_dir)"; do
    if [[ -n "${dir}" && -x "${dir}/session-manager-plugin" ]]; then
      export PATH="${dir}:${PATH}"
      return 0
    fi
  done
  return 1
}

_ssm_download_rpm() {
  local dest="$1"
  local arch sm_arch
  arch=$(uname -m)
  case "${arch}" in
    x86_64) sm_arch=64bit ;;
    aarch64) sm_arch=arm64 ;;
    *)
      echo "ERROR: unsupported architecture for session-manager-plugin: ${arch}" >&2
      return 1
      ;;
  esac
  curl -fsSL --retry 3 --retry-delay 2 --max-time 300 \
    "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_${sm_arch}/session-manager-plugin.rpm" \
    -o "${dest}"
}

_ssm_extract_rpm_to_dir() {
  local rpm="$1"
  local dest_dir="$2"
  if ! command -v rpm2cpio >/dev/null 2>&1 || ! command -v cpio >/dev/null 2>&1; then
    echo "ERROR: rpm2cpio and cpio required to extract session-manager-plugin RPM" >&2
    return 1
  fi
  mkdir -p "${dest_dir}"
  (cd "${dest_dir}" && rpm2cpio "${rpm}" | cpio -idmv 2>/dev/null)
  local plugin
  plugin=$(find "${dest_dir}" -type f -name session-manager-plugin 2>/dev/null | head -1)
  if [[ -z "${plugin}" ]]; then
    echo "ERROR: session-manager-plugin binary not found in RPM" >&2
    return 1
  fi
  chmod +x "${plugin}"
  local bindir
  bindir="$(dirname "${plugin}")"
  mkdir -p "${dest_dir}/bin"
  ln -sf "${plugin}" "${dest_dir}/bin/session-manager-plugin"
  export PATH="${dest_dir}/bin:${bindir}:${PATH}"
}

# Non-root safe: extract RPM into ci/.cache (or SESSION_MANAGER_PLUGIN_CACHE).
ensure_session_manager_plugin_on_path() {
  if _session_manager_plugin_on_path; then
    return 0
  fi

  echo "=== Installing session-manager-plugin (user cache) ==="
  local tmp_dir rpm
  tmp_dir=$(mktemp -d)
  rpm="${tmp_dir}/session-manager-plugin.rpm"
  _ssm_download_rpm "${rpm}"

  local cache_root="${SESSION_MANAGER_PLUGIN_CACHE:-${REPO_ROOT:-}/ci/.cache/session-manager-plugin}"
  mkdir -p "${cache_root}"
  _ssm_extract_rpm_to_dir "${rpm}" "${cache_root}"
  rm -rf "${tmp_dir}"

  if _session_manager_plugin_on_path; then
    session-manager-plugin --version
    return 0
  fi
  echo "ERROR: session-manager-plugin install failed" >&2
  return 1
}

# Containerfile / root image build only.
install_session_manager_plugin_system() {
  if command -v session-manager-plugin >/dev/null 2>&1; then
    return 0
  fi
  local tmp_dir rpm
  tmp_dir=$(mktemp -d)
  rpm="${tmp_dir}/session-manager-plugin.rpm"
  _ssm_download_rpm "${rpm}"
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: install_session_manager_plugin_system requires root" >&2
    return 1
  fi
  local pkg_mgr=dnf
  command -v dnf >/dev/null 2>&1 || pkg_mgr=yum
  "${pkg_mgr}" install -y "${rpm}"
  rm -rf "${tmp_dir}"
  ln -sf /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/bin/session-manager-plugin
  export PATH="/usr/local/sessionmanagerplugin/bin:${PATH}"
  session-manager-plugin --version
}
