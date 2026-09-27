# vim: set ft=make :
# These are recipes that are generic and should be available in bluefin, aurora,
# bluefin-lts, and dakota

# Toggle LUKS auto-unlock via TPM2
[group('System')]
toggle-tpm2:
    @/usr/bin/luks-tpm2-autounlock

# Run the Hive contributor worker in an isolated podman container
[group('System')]
contribute:
    #!/usr/bin/bash
    set -euo pipefail

    IMAGE="${HIVE_CONTRIBUTE_IMAGE:-ghcr.io/projectbluefin/contribute:stable}"
    HUB="${HIVE_CONTRIBUTE_HUB:-wss://hosted-projectbluefin-knuckle-gjvq.hive.hivecommons.dev/api/contribute/ws}"
    MEMORY="${HIVE_CONTRIBUTE_MEMORY:-4g}"
    CPUS="${HIVE_CONTRIBUTE_CPUS:-2}"
    REGISTRATION="${HIVE_CONTRIBUTE_REGISTRATION:-${HOME}/.config/hive/contributor.env}"
    STATE_VOLUME="hive-contribute-$(printf '%s' "${HUB}" | sha256sum | cut -c1-8)"

    if ! command -v podman &>/dev/null; then
        echo "contribute: podman is required to run the Hive contributor appliance." >&2
        exit 127
    fi

    # Two-tier isolation: prefer a hardware-isolated krun microVM, warn and fall
    # back to a standard rootless podman container when it is unavailable. This
    # is a per-image capability check, never a hard requirement — an unusable
    # image must still be able to run the worker, only with a weaker boundary.
    RUNTIME_ARGS=()
    if podman --runtime=krun info &>/dev/null && [[ -r /dev/kvm && -w /dev/kvm ]]; then
        RUNTIME_ARGS+=(--runtime=krun)
        echo "contribute: using the krun KVM microVM runtime (hardware isolation)."
    else
        echo "contribute: WARNING — krun/gVisor hardware isolation is not available on this image; running with the standard podman container boundary only." >&2
    fi

    if [[ ! -f "${REGISTRATION}" ]]; then
        echo "contribute: no Hive registration at ${REGISTRATION}." >&2
        echo "contribute: register this machine first — see https://github.com/projectbluefin/contribute#configuration" >&2
        exit 1
    fi

    GH_TOKEN_VALUE="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -z "${GH_TOKEN_VALUE}" ]] && command -v gh &>/dev/null; then
        GH_TOKEN_VALUE="$(gh auth token --hostname github.com 2>/dev/null || true)"
    fi

    ARGS=(
        podman run "${RUNTIME_ARGS[@]}" --rm --interactive --tty
        --userns "keep-id:uid=65532,gid=65532"
        --volume "${STATE_VOLUME}:/home/hive:rw"
        --volume "${REGISTRATION}:/home/hive/.config/hive/contributor.env:ro,z"
        --env "HIVE_HUB=${HUB}"
        --env "TERM=${TERM:-xterm-256color}"
        --env "COLORTERM=${COLORTERM:-truecolor}"
    )

    # Enforced resource ceiling — never optional. --memory-swap pinned to
    # --memory keeps a runaway worker from spilling into host swap.
    ARGS+=(--memory "${MEMORY}" --memory-swap "${MEMORY}" --cpus "${CPUS}")

    [[ -n "${GH_TOKEN_VALUE}" ]] && ARGS+=(--env "GH_TOKEN=${GH_TOKEN_VALUE}")

    ARGS+=("${IMAGE}")

    echo "contribute: hive ${HUB}"
    exec "${ARGS[@]}"

# Factory reset this device (experimental)
[group('System')]
powerwash:
    #!/usr/bin/bash
    FIRST_CONFIRMATION=$(gum choose --header='Warning: This is an experimental feature that will reset this device to its factory state.' "No" "Yes - wipe this machine")
    if [[ "$FIRST_CONFIRMATION" != "Yes - wipe this machine" ]]; then
        echo "Powerwash cancelled."
        exit 0
    fi
    SECOND_CONFIRMATION=$(gum choose --header='Are you sure?' "No" "Yes - wipe this machine")
    if [[ "$SECOND_CONFIRMATION" != "Yes - wipe this machine" ]]; then
        echo "Powerwash cancelled."
        exit 0
    fi
    sudo bootc install reset --experimental
