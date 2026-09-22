#!/usr/bin/env bash
# Idempotent session-manager-plugin install — same RPM path as ci/Containerfile.
# CI may reuse a cached pipeline:src image built before the SSM layer; e2e calls
# this once at startup when the binary is not already on PATH.

set -euo pipefail

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

ensure_session_manager_plugin() {
    if _session_manager_plugin_on_path; then
        return 0
    fi

    echo "=== session-manager-plugin not in image PATH; installing from AWS RPM (ci/Containerfile) ==="
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
        -o /tmp/session-manager-plugin.rpm
    dnf install -y /tmp/session-manager-plugin.rpm
    rm -f /tmp/session-manager-plugin.rpm
    chmod -R a+rx /usr/local/sessionmanagerplugin 2>/dev/null || true
    ln -sf /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/bin/session-manager-plugin

    if _session_manager_plugin_on_path; then
        session-manager-plugin --version
        return 0
    fi
    echo "ERROR: session-manager-plugin install failed" >&2
    return 1
}
