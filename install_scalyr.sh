#!/usr/bin/env bash
# install_scalyr.sh — Install scalyr-agent-2-aio with config from GitHub (avoids install-time API key validation)

set -euo pipefail
# ===== INPUT CHECK =====
if [ $# -lt 1 ]; then
    echo "[ERROR] Missing required argument: API_KEY"
    echo "Usage: $0 <API_KEY> [SCALYR_SERVER]"
    exit 1
fi

API_KEY="$1"
SCALYR_SERVER="${2:-https://xdr.eu1.sentinelone.net}"   # optional override, defaults to 

# ===== PREP =====
echo "[INFO] Updating apt cache and ensuring curl and gpg are available..."
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg python3 python3-dev libpython3.11

# ===== CLEANUP EXISTING INSTALLATION =====
echo "[INFO] Cleaning up any existing Scalyr installations..."
sudo apt-get remove -y scalyr-agent-2-aio scalyr-agent-2 || true
sudo apt-get autoremove -y || true

# ===== GPG KEY SETUP =====
echo "[INFO] Setting up Scalyr GPG key..."
# Remove existing key file if it exists
sudo rm -f /usr/share/keyrings/scalyr.gpg

curl "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x84ac559b5fb5463885ce0841f70ceedb4ad7b6c6" | sudo gpg -o /usr/share/keyrings/scalyr.gpg --dearmor

echo "[INFO] Verifying GPG key fingerprint..."
GPG_FINGERPRINT=$(gpg --show-keys /usr/share/keyrings/scalyr.gpg 2>/dev/null | grep -A1 "pub" | tail -1 | tr -d ' ')
EXPECTED_FINGERPRINT="84AC559B5FB5463885CE0841F70CEEDB4AD7B6C6"

if [ "$GPG_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ]; then
    echo "[INFO] GPG key fingerprint verified successfully: $GPG_FINGERPRINT"
else
    echo "[ERROR] GPG key fingerprint mismatch!"
    echo "Expected: $EXPECTED_FINGERPRINT"
    echo "Got:      $GPG_FINGERPRINT"
    echo "Aborting installation for security reasons."
    exit 1
fi

# ===== ADD SCALYR REPOSITORY =====
echo "[INFO] Adding Scalyr repository to apt sources..."
echo "deb [signed-by=/usr/share/keyrings/scalyr.gpg] https://scalyr-repo.s3.amazonaws.com/stable/apt scalyr main" | sudo tee /etc/apt/sources.list.d/scalyr.list

echo "[INFO] Updating apt cache with new repository..."
sudo apt-get update

# ===== INSTALL SCALYR AIO =====
echo "[INFO] Installing scalyr-agent-2-aio..."
sudo apt-get install -y scalyr-agent-2-aio

# ===== FIX PERMISSIONS =====
echo "[INFO] Setting up proper permissions for Scalyr agent..."
sudo mkdir -p /var/log/scalyr-agent-2
sudo mkdir -p /var/lib/scalyr-agent-2

# Check if scalyr-agent user exists, if not create it
if ! id "scalyr-agent" &>/dev/null; then
    echo "[INFO] Creating scalyr-agent user..."
    sudo useradd --system --no-create-home --shell /bin/false scalyr-agent
fi

# Set ownership and permissions for both log and data directories
sudo chown scalyr-agent:scalyr-agent /var/log/scalyr-agent-2
sudo chown scalyr-agent:scalyr-agent /var/lib/scalyr-agent-2
sudo chmod 755 /var/log/scalyr-agent-2
sudo chmod 755 /var/lib/scalyr-agent-2

# Detect the non-root user running the script
RUN_USER=$(logname 2>/dev/null || echo "$USER")

# Add user to scalyr-agent group if needed
sudo usermod -a -G scalyr-agent "$RUN_USER"

# ===== CONFIG =====
CONFIG_URL="https://raw.githubusercontent.com/cyber-sec-eng-claranet/Scalyr/refs/heads/Linux/agent.json"
CONFIG_PATH="/etc/scalyr-agent-2/agent.json"

echo "[INFO] Downloading agent.json from GitHub..."
sudo curl -fsSL "$CONFIG_URL" -o "$CONFIG_PATH"

echo "[INFO] Replacing API_KEY placeholder with provided key..."
sudo sed -i "s/API_KEY_PLACEHOLDER/${API_KEY}/g" "$CONFIG_PATH"

echo "[INFO] Replacing SCALYR_SERVER placeholder with provided server..."
sudo sed -i "s#SCALYR_SERVER_PLACEHOLDER#${SCALYR_SERVER}#g" "$CONFIG_PATH"

echo "[INFO] Setting proper ownership and permissions for agent.json..."
sudo chown scalyr-agent:scalyr-agent "$CONFIG_PATH"
sudo chmod 600 "$CONFIG_PATH"

# ===== RESTART AGENT =====
echo "[INFO] Restarting Scalyr Agent..."
sudo scalyr-agent-2 stop || true
sudo scalyr-agent-2 start

echo "[INFO] Installation complete!"
