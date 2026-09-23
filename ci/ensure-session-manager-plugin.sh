#!/usr/bin/env bash
# Ensure session-manager-plugin is on PATH for CI e2e (non-root OpenShift pods).
# Image install: ci/Containerfile. When pipeline:src lacks SSM on PATH, extract the
# Ubuntu .deb into a user-writable directory (no root / dnf).

set -euo pipefail

_ensure_script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

_session_manager_plugin_on_path() {
    command -v session-manager-plugin >/dev/null 2>&1 && return 0
    local dir
    for dir in /usr/local/sessionmanagerplugin/bin /usr/bin /usr/local/bin; do
        if [[ -n "${dir}" && -x "${dir}/session-manager-plugin" ]]; then
            export PATH="${dir}:${PATH}"
            return 0
        fi
    done
    return 1
}

_finalize_plugin_tree() {
    local extract_root="$1"
    local plugin bindir cache_bin
    plugin=$(find "${extract_root}" -type f -name session-manager-plugin 2>/dev/null | head -1)
    if [[ -z "${plugin}" ]]; then
        echo "ERROR: session-manager-plugin binary not found after extract" >&2
        return 1
    fi
    chmod +x "${plugin}"
    bindir="$(dirname "${plugin}")"
    cache_bin="$(dirname "${extract_root}")/bin"
    mkdir -p "${cache_bin}"
    ln -sf "${plugin}" "${cache_bin}/session-manager-plugin"
    export PATH="${cache_bin}:${bindir}:${PATH}"
}

_install_session_manager_plugin_user() {
    echo "=== session-manager-plugin not in image PATH; installing to user cache (non-root) ==="
    local arch ubuntu_arch repo_root script_dir tmp_dir deb cache_root extract_root
    arch=$(uname -m)
    case "${arch}" in
        x86_64) ubuntu_arch=64bit ;;
        aarch64) ubuntu_arch=arm64 ;;
        *)
            echo "ERROR: unsupported architecture for session-manager-plugin: ${arch}" >&2
            return 1
            ;;
    esac

    script_dir="$(_ensure_script_dir)"
    repo_root="${REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
    cache_root="${SESSION_MANAGER_PLUGIN_CACHE:-${TMPDIR:-/tmp}/session-manager-plugin-${UID}}"
    extract_root="${cache_root}/.deb-extract"
    mkdir -p "${cache_root}"
    tmp_dir=$(mktemp -d)
    deb="${tmp_dir}/session-manager-plugin.deb"
    curl -fsSL --retry 3 --retry-delay 2 --max-time 300 \
        "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_${ubuntu_arch}/session-manager-plugin.deb" \
        -o "${deb}"

    if ! command -v python3 >/dev/null 2>&1; then
        rm -rf "${tmp_dir}"
        echo "ERROR: python3 required to extract session-manager-plugin .deb" >&2
        return 1
    fi
    python3 "${repo_root}/ci/extract-deb-data.py" "${deb}" "${extract_root}"
    rm -rf "${tmp_dir}"
    _finalize_plugin_tree "${extract_root}"
}

ensure_session_manager_plugin() {
    if _session_manager_plugin_on_path; then
        return 0
    fi

    _install_session_manager_plugin_user

    if _session_manager_plugin_on_path; then
        session-manager-plugin --version
        return 0
    fi
    echo "ERROR: session-manager-plugin install failed" >&2
    return 1
}
