#!/usr/bin/env bash
# =============================================================================
# Install-Scalyr.sh
# Installs the Scalyr Agent (AIO) directly via apt/yum, applies a specified
# config, and injects an API key.
#
# Usage:
#   sudo bash Install-Scalyr.sh --api-token "YOUR_API_KEY" --config-file "Agent1.json"
#
# One-liner:
#   curl -sO https://raw.githubusercontent.com/charleshewish/Scalyr/refs/heads/Linux/Install-Scalyr.sh && sudo bash Install-Scalyr.sh --api-token "YOUR_API_KEY" --config-file "Agent1.json"
# =============================================================================

set -euo pipefail

# ─── CONFIGURATION ────────────────────────────────────────────────────────────
GITHUB_RAW_BASE="https://raw.githubusercontent.com/charleshewish/Scalyr/refs/heads/Linux"
AGENT_CONFIG_PATH="/etc/scalyr-agent-2/agent.json"
API_PLACEHOLDER="API_KEY_PLACEHOLDER"
TEMP_DIR=$(mktemp -d)
SCALYR_GPG_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF70CEEDB4AD7B6C6"
# ──────────────────────────────────────────────────────────────────────────────

# ─── COLOURS ──────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

step()    { echo -e "${CYAN}[*] $1${NC}"; }
success() { echo -e "${GREEN}[+] $1${NC}"; }
error()   { echo -e "${RED}[!] $1${NC}" >&2; exit 1; }
# ──────────────────────────────────────────────────────────────────────────────

# ─── ARGUMENT PARSING ─────────────────────────────────────────────────────────
API_TOKEN=""
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-token)   API_TOKEN="$2";   shift 2 ;;
        --config-file) CONFIG_FILE="$2"; shift 2 ;;
        *) error "Unknown argument: $1. Usage: $0 --api-token TOKEN --config-file Agent1.json" ;;
    esac
done

[[ -z "$API_TOKEN" ]]   && error "--api-token is required."
[[ -z "$CONFIG_FILE" ]] && error "--config-file is required."
# ──────────────────────────────────────────────────────────────────────────────

# ─── ROOT CHECK ───────────────────────────────────────────────────────────────
[[ "$EUID" -ne 0 ]] && error "This script must be run as root. Use: sudo bash $0"
# ──────────────────────────────────────────────────────────────────────────────

# ─── DETECT PACKAGE MANAGER ───────────────────────────────────────────────────
step "Detecting Linux distribution..."
if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
    success "Detected Debian/Ubuntu (apt)"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
    success "Detected RHEL/CentOS (dnf)"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
    success "Detected RHEL/CentOS (yum)"
else
    error "Unsupported distribution. Could not find apt, yum, or dnf."
fi
# ──────────────────────────────────────────────────────────────────────────────

# ─── STEP 1: INSTALL PREREQUISITES ───────────────────────────────────────────
step "Installing prerequisites (gnupg, curl)..."
case "$PKG_MANAGER" in
    apt) apt-get install -y gnupg curl ;;
    yum) yum install -y gnupg curl ;;
    dnf) dnf install -y gnupg curl ;;
esac
success "Prerequisites installed."
# ──────────────────────────────────────────────────────────────────────────────

# ─── STEP 2: CLEAN UP ANY BROKEN EXISTING INSTALLATION ──────────────────────
step "Checking for existing Scalyr packages..."
if dpkg -l scalyr-agent-2 2>/dev/null | grep -qE '^[iuph]'; then
    step "Found existing scalyr-agent-2 install, removing before installing AIO..."
    dpkg --remove --force-remove-reinstreq scalyr-agent-2 2>/dev/null || true
    apt-get purge -y scalyr-agent-2 2>/dev/null || true
    apt-get install -f -y 2>/dev/null || true
    success "Existing package removed."
else
    success "No conflicting packages found."
fi
# ──────────────────────────────────────────────────────────────────────────────

# ─── STEP 3: ADD SCALYR REPO AND INSTALL AIO PACKAGE DIRECTLY ────────────────
step "Installing Scalyr Agent (AIO)..."

if [[ "$PKG_MANAGER" == "apt" ]]; then
    # Add Scalyr GPG key
    curl -s "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF70CEEDB4AD7B6C6" \
        | gpg --dearmor -o /usr/share/keyrings/scalyr-archive-keyring.gpg \
        || error "Failed to add Scalyr GPG key."

    # Add Scalyr apt repo
    echo "deb [signed-by=/usr/share/keyrings/scalyr-archive-keyring.gpg] https://scalyr-repo.s3.amazonaws.com/stable/apt scalyr main" \
        > /etc/apt/sources.list.d/scalyr.list

    apt-get update -qq
    # Install AIO package directly - bypasses system Python entirely
    apt-get install -y scalyr-agent-2-aio \
        || error "Failed to install scalyr-agent-2-aio. Check apt output above."

elif [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
    # Add Scalyr RPM GPG key
    rpm --import https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF70CEEDB4AD7B6C6 2>/dev/null || true

    # Add Scalyr yum repo
    cat > /etc/yum.repos.d/scalyr.repo << 'EOF'
[scalyr]
name=Scalyr packages
baseurl=https://scalyr-repo.s3.amazonaws.com/stable/yum
enabled=1
gpgcheck=1
gpgkey=https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF70CEEDB4AD7B6C6
EOF

    if [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf install -y scalyr-agent-2-aio \
            || error "Failed to install scalyr-agent-2-aio."
    else
        yum install -y scalyr-agent-2-aio \
            || error "Failed to install scalyr-agent-2-aio."
    fi
fi

success "Scalyr Agent (AIO) installed successfully."
# ──────────────────────────────────────────────────────────────────────────────

# ─── STEP 4: DOWNLOAD CONFIG FROM GITHUB ─────────────────────────────────────
CONFIG_URL="$GITHUB_RAW_BASE/$CONFIG_FILE"
TEMP_CONFIG="$TEMP_DIR/$CONFIG_FILE"

step "Downloading config '$CONFIG_FILE' from: $CONFIG_URL"
curl -sf "$CONFIG_URL" -o "$TEMP_CONFIG" \
    || error "Failed to download '$CONFIG_FILE' from GitHub. Check the filename and repo."
success "Config downloaded."
# ──────────────────────────────────────────────────────────────────────────────

# ─── STEP 6: INJECT API KEY ───────────────────────────────────────────────────
step "Injecting API key into config..."
if ! grep -q "$API_PLACEHOLDER" "$TEMP_CONFIG"; then
    error "Placeholder '$API_PLACEHOLDER' not found in $CONFIG_FILE. Verify the config template."
fi
sed -i '1s/^\xEF\xBB\xBF//' "$TEMP_CONFIG"
sed -i "s|$API_PLACEHOLDER|$API_TOKEN|g" "$TEMP_CONFIG"
success "API key injected."
# ──────────────────────────────────────────────────────────────────────────────

# ─── STEP 7: REPLACE AGENT CONFIG ────────────────────────────────────────────
step "Replacing agent.json at: $AGENT_CONFIG_PATH"
AGENT_CONFIG_DIR=$(dirname "$AGENT_CONFIG_PATH")
[[ ! -d "$AGENT_CONFIG_DIR" ]] && error "Scalyr config directory not found at '$AGENT_CONFIG_DIR'. Installation may have failed."

cp "$TEMP_CONFIG" "$AGENT_CONFIG_PATH" \
    || error "Failed to copy config to $AGENT_CONFIG_PATH."

chown root:root "$AGENT_CONFIG_PATH"
chmod 640 "$AGENT_CONFIG_PATH"
success "agent.json replaced with correct permissions."
# ──────────────────────────────────────────────────────────────────────────────

# ─── STEP 8: START AGENT ──────────────────────────────────────────────────────
step "Starting Scalyr Agent service..."
if command -v systemctl &>/dev/null; then
    systemctl enable scalyr-agent-2 --quiet
    systemctl restart scalyr-agent-2 \
        || error "Failed to start scalyr-agent-2 via systemctl."
    success "Scalyr Agent started via systemctl."
else
    service scalyr-agent-2 restart \
        || error "Failed to start scalyr-agent-2 via service."
    success "Scalyr Agent started via service."
fi
# ──────────────────────────────────────────────────────────────────────────────

# ─── CLEANUP ──────────────────────────────────────────────────────────────────
rm -rf "$TEMP_DIR"
# ──────────────────────────────────────────────────────────────────────────────

success "Scalyr Agent installation and configuration complete."
