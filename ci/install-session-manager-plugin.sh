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

_ssm_arch_mapping() {
  local arch
  arch=$(uname -m)
  case "${arch}" in
    x86_64) SM_RPM_ARCH=64bit; SM_DEB_ARCH=64bit ;;
    aarch64) SM_RPM_ARCH=arm64; SM_DEB_ARCH=arm64 ;;
    *)
      echo "ERROR: unsupported architecture for session-manager-plugin: ${arch}" >&2
      return 1
      ;;
  esac
}

_ssm_download_rpm() {
  local dest="$1"
  _ssm_arch_mapping || return 1
  curl -fsSL --retry 3 --retry-delay 2 --max-time 300 \
    "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_${SM_RPM_ARCH}/session-manager-plugin.rpm" \
    -o "${dest}"
}

_ssm_download_deb() {
  local dest="$1"
  _ssm_arch_mapping || return 1
  curl -fsSL --retry 3 --retry-delay 2 --max-time 300 \
    "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_${SM_DEB_ARCH}/session-manager-plugin.deb" \
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
  _ssm_finalize_plugin_in_dir "${dest_dir}"
}

_ssm_finalize_plugin_in_dir() {
  local dest_dir="$1"
  local plugin
  plugin=$(find "${dest_dir}" -type f -name session-manager-plugin 2>/dev/null | head -1)
  if [[ -z "${plugin}" ]]; then
    echo "ERROR: session-manager-plugin binary not found after extract" >&2
    return 1
  fi
  chmod +x "${plugin}"
  local bindir
  bindir="$(dirname "${plugin}")"
  mkdir -p "${dest_dir}/bin"
  ln -sf "${plugin}" "${dest_dir}/bin/session-manager-plugin"
  export PATH="${dest_dir}/bin:${bindir}:${PATH}"
}

# Non-root: extract .deb with ar+tar (works when rpm2cpio is not in the `src` CI pod).
_ssm_extract_deb_to_dir() {
  local deb="$1"
  local dest_dir="$2"
  if ! command -v ar >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    return 1
  fi
  mkdir -p "${dest_dir}"
  local work="${dest_dir}/.deb-extract"
  mkdir -p "${work}"
  (cd "${work}" && ar x "${deb}" && tar -xzf data.tar.gz)
  _ssm_finalize_plugin_in_dir "${work}"
}

# Non-root safe: extract RPM into ci/.cache (or SESSION_MANAGER_PLUGIN_CACHE).
ensure_session_manager_plugin_on_path() {
  if _session_manager_plugin_on_path; then
    return 0
  fi

  echo "=== Installing session-manager-plugin (user cache) ==="
  local tmp_dir cache_root
  tmp_dir=$(mktemp -d)
  cache_root="${SESSION_MANAGER_PLUGIN_CACHE:-${REPO_ROOT:-}/ci/.cache/session-manager-plugin}"
  mkdir -p "${cache_root}"

  if command -v rpm2cpio >/dev/null 2>&1 && command -v cpio >/dev/null 2>&1; then
    local rpm="${tmp_dir}/session-manager-plugin.rpm"
    _ssm_download_rpm "${rpm}"
    _ssm_extract_rpm_to_dir "${rpm}" "${cache_root}"
  elif command -v ar >/dev/null 2>&1; then
    local deb="${tmp_dir}/session-manager-plugin.deb"
    _ssm_download_deb "${deb}"
    _ssm_extract_deb_to_dir "${deb}" "${cache_root}" || {
      rm -rf "${tmp_dir}"
      echo "ERROR: failed to extract session-manager-plugin .deb" >&2
      return 1
    }
  else
    rm -rf "${tmp_dir}"
    echo "ERROR: need rpm2cpio+cpio or ar+tar to install session-manager-plugin" >&2
    return 1
  fi
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
