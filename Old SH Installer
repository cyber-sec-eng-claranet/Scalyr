#!/usr/bin/env bash
# install_scalyr.sh — Securely install scalyr-agent-2-aio with API key and selectable config

set -euo pipefail

# ===== ARGUMENT VALIDATION =====
if [[ $# -ne 2 ]]; then
  echo "Usage: bash install_scalyr.sh <API_KEY> <CONFIG_FILENAME>"
  echo "Example: bash install_scalyr.sh ABC12345 agent.json"
  exit 1
fi

API_KEY="$1"
CONFIG_FILE="$2"

# ===== CONSTANTS =====
REPO_BASE="https://raw.githubusercontent.com/cyber-sec-eng-claranet/Scalyr/refs/heads/Linux"
CONFIG_URL="${REPO_BASE}/${CONFIG_FILE}"
CONFIG_PATH="/etc/scalyr-agent-2/agent.json"

echo "[INFO] Installing Scalyr Agent using config: $CONFIG_FILE"

# ===== DEPENDENCIES =====
echo "[INFO] Updating apt cache and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg python3 python3-dev libpython3.11

# ===== CLEANUP EXISTING INSTALLATION =====
echo "[INFO] Cleaning up existing Scalyr installation..."
sudo apt-get remove -y scalyr-agent-2-aio scalyr-agent-2 || true
sudo apt-get autoremove -y || true

# ===== GPG KEY SETUP =====
echo "[INFO] Setting up verified GPG key..."
sudo rm -f /usr/share/keyrings/scalyr.gpg
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x84ac559b5fb5463885ce0841f70ceedb4ad7b6c6" \
  | sudo gpg -o /usr/share/keyrings/scalyr.gpg --dearmor

EXPECTED_FINGERPRINT="84AC559B5FB5463885CE0841F70CEEDB4AD7B6C6"
GPG_FINGERPRINT=$(gpg --show-keys /usr/share/keyrings/scalyr.gpg 2>/dev/null | grep -A1 "pub" | tail -1 | tr -d ' ')

if [[ "$GPG_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]]; then
  echo "[ERROR] GPG key fingerprint mismatch! Aborting installation."
  exit 1
fi

# ===== REPOSITORY SETUP =====
echo "[INFO] Adding Scalyr APT repository..."
echo "deb [signed-by=/usr/share/keyrings/scalyr.gpg] https://scalyr-repo.s3.amazonaws.com/stable/apt scalyr main" \
  | sudo tee /etc/apt/sources.list.d/scalyr.list

sudo apt-get update -y

# ===== INSTALL SCALYR AIO =====
echo "[INFO] Installing scalyr-agent-2-aio..."
sudo apt-get install -y scalyr-agent-2-aio

# ===== DIRECTORY PREP =====
echo "[INFO] Preparing directories and permissions..."
sudo mkdir -p /var/log/scalyr-agent-2 /var/lib/scalyr-agent-2
if ! id "scalyr-agent" &>/dev/null; then
  sudo useradd --system --no-create-home --shell /bin/false scalyr-agent
fi
sudo chown -R scalyr-agent:scalyr-agent /var/log/scalyr-agent-2 /var/lib/scalyr-agent-2
sudo chmod 755 /var/log/scalyr-agent-2 /var/lib/scalyr-agent-2

# ===== DOWNLOAD CONFIG =====
echo "[INFO] Downloading config: ${CONFIG_FILE}..."
sudo curl -fsSL "$CONFIG_URL" -o "$CONFIG_PATH"

# ===== SUBSTITUTE API KEY SAFELY =====
echo "[INFO] Injecting API key into config..."
sudo sed -i "s|API_KEY_PLACEHOLDER|${API_KEY}|g" "$CONFIG_PATH"

# ===== FIX PERMISSIONS =====
sudo chown scalyr-agent:scalyr-agent "$CONFIG_PATH"
sudo chmod 600 "$CONFIG_PATH"

# ===== RESTART AGENT =====
echo "[INFO] Restarting Scalyr agent..."
sudo scalyr-agent-2 stop || true
sudo scalyr-agent-2 start

echo "[SUCCESS] Installation complete using config '${CONFIG_FILE}'."
echo "[INFO] You can check status with: sudo scalyr-agent-2 status"
