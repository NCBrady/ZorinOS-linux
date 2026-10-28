#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# Microsoft Intune Portal Installer - Zorin OS adaptation
#
# Adapted from microsoft/shell-intune-samples (Linux/Intune Installer/installer.sh).
# Installs Microsoft Intune Portal and its dependencies (including Microsoft Edge)
# on Zorin OS by mapping it to the Ubuntu release it is built on.
#
# Supported distributions:
#   - Zorin OS 17 (Ubuntu 22.04 base), Zorin OS 18 (Ubuntu 24.04 base)
#   - Ubuntu 22.04, 24.04, 26.04
#
# Usage:
#   ./zorin-intune-installer.sh [OPTIONS]
#
# Options:
#   --insiders-fast        Use the insiders-fast channel instead of prod
#   --local-package <path> Install from a local .deb file instead of the repo
#   --verbose              Show detailed output to the terminal (in addition to the log)
#   -h, --help             Show this help message
#

set -eu${DEBUG:+x}o pipefail

# Handle --help before elevating to root
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        sed -n '/^# Usage:/,/^[^#]/p' "$0" | head -n -1 | sed 's/^# \?//'
        exit 0
    fi
done

# Elevate to root if not already running as root (before arg parsing so $@ is intact)
if [[ $EUID -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

# --- Defaults ---
CHANNEL="prod"
LOCAL_PACKAGE=""
VERBOSE=false
# Use the invoking user's home directory, not root's
USER_HOME="${SUDO_USER:+$(eval echo ~"$SUDO_USER")}"
LOG_FILE="${USER_HOME:-$HOME}/intune-installer.log"

# --- Functions ---

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | head -n -1 | sed 's/^# \?//'
    exit 0
}

log() {
    echo "$1" >&7
}

die() {
    # Write to original stdout (fd 7) if available, otherwise stderr
    if { true >&7; } 2>/dev/null; then
        echo "Error: $1" >&7
    fi
    echo "Error: $1" >&2
    exit 1
}

detect_arch() {
    local arch
    arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)       echo "$arch" ;;
    esac
}

# Remove duplicate Edge repo files that Edge's postinst script may create.
# We maintain a single microsoft-edge.list — any others are duplicates.
cleanup_edge_repo_duplicates() {
    local sources_dir="/etc/apt/sources.list.d"
    for f in "$sources_dir"/microsoft-edge-*.list; do
        [ -f "$f" ] || continue
        rm -f "$f"
    done
}

# Check if an APT repository is already enrolled by another source file.
# Searches /etc/apt/sources.list, *.list, and *.sources files.
# If a pre-existing enrollment is found, removes our file so the admin's enrollment takes precedence.
# Args: $1 = URL substring to match, $2 = our filename in sources.list.d/
# Returns: 0 if enrolled elsewhere (caller should skip creation), 1 if not
apt_repo_enrolled() {
    local url_pattern="$1"
    local our_file="$2"
    local our_path="/etc/apt/sources.list.d/$our_file"

    # Check /etc/apt/sources.list
    if [ -f /etc/apt/sources.list ] && \
       grep -v '^[[:space:]]*#' /etc/apt/sources.list 2>/dev/null | grep -qF "$url_pattern"; then
        [ -f "$our_path" ] && rm -f "$our_path" || true
        return 0
    fi

    # Check .list files (one-line format), skipping our own
    for f in /etc/apt/sources.list.d/*.list; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "$our_file" ] && continue
        if grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -qF "$url_pattern"; then
            [ -f "$our_path" ] && rm -f "$our_path" || true
            return 0
        fi
    done

    # Check .sources files
    for f in /etc/apt/sources.list.d/*.sources; do
        [ -f "$f" ] || continue
        if grep -i '^URIs:' "$f" 2>/dev/null | grep -qF "$url_pattern" && \
           ! grep -qi "^Enabled:[[:space:]]*no" "$f" 2>/dev/null; then
            [ -f "$our_path" ] && rm -f "$our_path" || true
            return 0
        fi
    done

    return 1
}

# --- Argument Parsing ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        --insiders-fast)
            CHANNEL="insiders-fast"
            shift
            ;;
        --local-package)
            [[ $# -ge 2 ]] || die "--local-package requires a file path argument"
            LOCAL_PACKAGE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            die "Unknown option: $1 (see --help)"
            ;;
    esac
done

if [[ -n "$LOCAL_PACKAGE" && ! -f "$LOCAL_PACKAGE" ]]; then
    die "Local package not found: $LOCAL_PACKAGE"
fi

# --- Pre-flight ---

# Read distro information
. /etc/os-release
DISTRO="$ID"
DISTRO_VERSION="$VERSION_ID"
ARCH=$(detect_arch)

# Zorin sets UBUNTU_CODENAME to its Ubuntu base; map it to the Ubuntu release
# number that packages.microsoft.com uses in its repo path.
case "$DISTRO" in
    zorin)
        CODENAME="${UBUNTU_CODENAME:-}"
        ;;
    ubuntu)
        CODENAME="${VERSION_CODENAME:-}"
        ;;
    *)
        die "$DISTRO is not supported. Supported: Zorin OS 17/18, Ubuntu 22.04/24.04/26.04"
        ;;
esac

case "$CODENAME" in
    jammy)    RELEASE="22.04" ;;
    noble)    RELEASE="24.04" ;;
    resolute) RELEASE="26.04" ;;
    *)        die "$DISTRO $DISTRO_VERSION (Ubuntu base '${CODENAME:-unknown}') is not supported. Zorin OS 17 or 18 is required." ;;
esac

# Print summary
echo "============================================="
echo " Microsoft Intune Portal Installer (Zorin)"
echo "============================================="
echo " Distro:       $DISTRO $DISTRO_VERSION (Ubuntu $RELEASE base, $CODENAME)"
echo " Architecture: $ARCH"
echo " Channel:      $CHANNEL"
if [[ -n "$LOCAL_PACKAGE" ]]; then
    echo " Local package: $LOCAL_PACKAGE"
fi
echo " Log file:     $LOG_FILE"
echo "============================================="
echo ""

# Redirect output to log file, keeping fd 7 for user-facing messages
exec 7>&1
if $VERBOSE; then
    exec &> >(tee -a "$LOG_FILE")
else
    exec &>"$LOG_FILE"
fi

# --- Installation ---

log "Installing prerequisites..."

apt-get update
apt-get -y install curl gpg

# Import Microsoft GPG key (always refresh to pick up key rotations).
# The Edge repo uses the older microsoft.asc key on all versions.
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$HOME/microsoft.gpg"
install -o root -g root -m 644 "$HOME/microsoft.gpg" /usr/share/keyrings/
rm -f "$HOME/microsoft.gpg"

# Ubuntu 26.04+ PMC repos are signed with a newer Microsoft GPG key
if dpkg --compare-versions "$RELEASE" ge "26.04"; then
    MS_GPG_KEYRING="/usr/share/keyrings/microsoft-2025.gpg"
    curl -fsSL https://packages.microsoft.com/keys/microsoft-2025.asc | gpg --dearmor > "$HOME/microsoft-2025.gpg"
    install -o root -g root -m 644 "$HOME/microsoft-2025.gpg" /usr/share/keyrings/
    rm -f "$HOME/microsoft-2025.gpg"
else
    MS_GPG_KEYRING="/usr/share/keyrings/microsoft.gpg"
fi

# Clean up any pre-existing Edge repo files to avoid duplicates
cleanup_edge_repo_duplicates

# Configure repo for portal and dependencies — skip if already enrolled
# For insiders-fast, the URL path stays as "prod" and "insiders-fast" is the apt component
if [[ "$CHANNEL" == "insiders-fast" ]]; then
    APT_COMPONENT="insiders-fast"
else
    APT_COMPONENT="$CODENAME"
fi
if apt_repo_enrolled "packages.microsoft.com/ubuntu/$RELEASE/prod $APT_COMPONENT" "microsoft-$CHANNEL.list"; then
    log "Microsoft $CHANNEL repo already enrolled, skipping."
else
    echo "deb [arch=$ARCH signed-by=$MS_GPG_KEYRING] https://packages.microsoft.com/ubuntu/$RELEASE/prod $APT_COMPONENT main" \
        | tee /etc/apt/sources.list.d/microsoft-$CHANNEL.list > /dev/null
fi

# The Edge repo is signed with the legacy microsoft.asc key on every release,
# so pin it to microsoft.gpg rather than MS_GPG_KEYRING.
if apt_repo_enrolled "packages.microsoft.com/repos/edge" "microsoft-edge.list"; then
    log "Microsoft Edge repo already enrolled, skipping."
else
    echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
        | tee /etc/apt/sources.list.d/microsoft-edge.list > /dev/null
fi

log "Updating package information..."
apt-get update

# Install Edge if not already present
if ! command -v microsoft-edge &>/dev/null; then
    log "Installing Microsoft Edge..."
    apt-get -y install microsoft-edge-stable

    # Edge's postinst may add duplicate repo files — clean them up
    cleanup_edge_repo_duplicates
else
    log "Microsoft Edge is already installed."
fi

# Install Intune Portal
log "Installing Intune Portal..."
if [[ -n "$LOCAL_PACKAGE" ]]; then
    log "Using local package: $LOCAL_PACKAGE"
    apt-get -y --allow-downgrades install "$(readlink -f "$LOCAL_PACKAGE")"
else
    apt-get -y install intune-portal
fi

# --- Done ---
log ""
log "Installation complete. Log file: $LOG_FILE"
