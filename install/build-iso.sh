#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
build="$here/build"
iso="${1:?usage: $0 <proxmox-ve.iso>}"
iso="$(realpath "$iso")"

mkdir -p "$build"

if [[ ! -f "$build/answer.toml" || "${RENDER:-}" == 1 ]]; then
    read -rsp "root password for sarten: " pw; echo
    read -rsp "again: " pw2; echo
    [[ "$pw" == "$pw2" ]] || { echo "passwords differ" >&2; exit 1; }
    hash="$(openssl passwd -6 -stdin <<<"$pw")"
    keys="$(sops decrypt --extract '["ssh_keys"]["asynthe"]' --output-type json \
        "$here/../ansible/group_vars/all.sops.yaml")"
    answer="$(<"$here/answer.toml.in")"
    answer="${answer//@ROOT_PASSWORD_HASH@/"$hash"}"
    answer="${answer//@ROOT_SSH_KEYS@/"$keys"}"
    printf '%s\n' "$answer" > "$build/answer.toml"
    chmod 600 "$build/answer.toml"
fi

if command -v proxmox-auto-install-assistant >/dev/null; then
    proxmox-auto-install-assistant validate-answer "$build/answer.toml"
    proxmox-auto-install-assistant prepare-iso "$iso" \
        --fetch-from iso \
        --answer-file "$build/answer.toml" \
        --output "$build/sarten-auto.iso"
    echo "wrote $build/sarten-auto.iso"
    exit 0
fi

runtime="$(command -v podman || command -v docker || true)"
[[ -n "$runtime" ]] || {
    echo "need proxmox-auto-install-assistant, podman or docker" >&2
    exit 1
}

"$runtime" run --rm -i \
    -v "$here:/work/install" \
    -v "$iso:/work/source.iso:ro" \
    -e RENDER=0 \
    docker.io/library/debian:trixie bash -euc '
        apt-get update -qq
        apt-get install -qq -y curl ca-certificates >/dev/null
        curl -fsSL -o /usr/share/keyrings/proxmox-archive-keyring.gpg \
            https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg
        echo "deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
            > /etc/apt/sources.list.d/pve.list
        apt-get update -qq
        apt-get install -qq -y proxmox-auto-install-assistant xorriso >/dev/null
        /work/install/build-iso.sh /work/source.iso
    '
