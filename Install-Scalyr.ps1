#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and installs the Scalyr Agent, applies a specified config, and injects an API key.

.PARAMETER ApiToken
    The Scalyr API key to inject into the config file.

.PARAMETER ConfigFile
    The name of the agent config file to download from GitHub (e.g. Agent1.json).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cyber-sec-eng-claranet/Scalyr/refs/heads/Windows/Install-Scalyr.ps1'))) -ApiToken 'YOUR_API_KEY' -ConfigFile 'CONFIG_NAME.json'"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ApiToken,

    [Parameter(Mandatory = $true)]
    [string]$ConfigFile
)

$ErrorActionPreference = "Stop"

# ─── CONFIGURATION ────────────────────────────────────────────────────────────
$MsiUrl         = "https://app.scalyr.com/scalyr-repo/stable/latest/ScalyrAgentInstaller-2.2.21.msi"
$GitHubRawBase  = "https://raw.githubusercontent.com/cyber-sec-eng-claranet/Scalyr/refs/heads/Windows"
$AgentConfigDir = "C:\Program Files (x86)\Scalyr\config"
$AgentConfigDst = Join-Path $AgentConfigDir "agent.json"
$TempDir        = $env:TEMP
$MsiPath        = Join-Path $TempDir "ScalyrAgentInstaller.msi"
$TempConfigPath = Join-Path $TempDir $ConfigFile
$ApiPlaceholder = "API_KEY_PLACEHOLDER"
# ──────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

# Step 1: Download the MSI
Write-Step "Downloading Scalyr Agent MSI from: $MsiUrl"
Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing
Write-Success "MSI downloaded to: $MsiPath"

# Step 2: Install the MSI silently
Write-Step "Installing Scalyr Agent..."
$installArgs = "/i `"$MsiPath`" /qn /norestart /l*v `"$TempDir\scalyr_install.log`""
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "MSI installation failed with exit code: $($process.ExitCode). Check log at $TempDir\scalyr_install.log"
}
Write-Success "Scalyr Agent installed successfully."

# Step 3: Download the specified agent config from GitHub
$ConfigUrl = "$GitHubRawBase/$ConfigFile"
Write-Step "Downloading config '$ConfigFile' from: $ConfigUrl"
Invoke-WebRequest -Uri $ConfigUrl -OutFile $TempConfigPath -UseBasicParsing
Write-Success "Config downloaded to: $TempConfigPath"

# Step 4: Inject the API key into the config
Write-Step "Injecting API key into config..."
$configContent = Get-Content -Path $TempConfigPath -Raw
if ($configContent -notmatch [regex]::Escape($ApiPlaceholder)) {
    throw "Placeholder '$ApiPlaceholder' not found in $ConfigFile. Verify the config template is correct."
}
$configContent = $configContent -replace [regex]::Escape($ApiPlaceholder), $ApiToken
[System.IO.File]::WriteAllText($TempConfigPath, $configContent, [System.Text.UTF8Encoding]::new($false))
Write-Success "API key injected successfully."

# Step 5: Replace the default agent.json with the downloaded config
Write-Step "Replacing agent.json at: $AgentConfigDst"
if (-not (Test-Path $AgentConfigDir)) {
    throw "Scalyr config directory not found at '$AgentConfigDir'. Installation may have failed or used a different path."
}
Copy-Item -Path $TempConfigPath -Destination $AgentConfigDst -Force

# Verify the file is fully written and the API key is present before proceeding
Write-Step "Verifying agent.json was written correctly..."
$retries = 0
do {
    Start-Sleep -Seconds 2
    $written = Get-Content -Path $AgentConfigDst -Raw -ErrorAction SilentlyContinue
    $retries++
    if ($retries -gt 10) { throw "Timed out waiting for agent.json to be written correctly." }
} until ($written -match [regex]::Escape($ApiToken))

Write-Success "agent.json replaced and verified successfully."

# Step 6: Start the Scalyr Agent service
Write-Step "Starting Scalyr Agent service..."

$serviceName = "ScalyrAgentService"
$agentBin    = "C:\Program Files (x86)\Scalyr\bin\ScalyrAgentService.exe"

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -eq $service) {
    # Fallback: start directly via binary if service entry is missing
    if (Test-Path $agentBin) {
        Write-Step "Service entry not found, starting via binary: $agentBin"
        Start-Process -FilePath $agentBin -ArgumentList "start" -Wait -NoNewWindow
        Write-Success "Scalyr Agent started via binary."
    } else {
        throw "Service '$serviceName' not found and binary not present at '$agentBin'. Check install log at $TempDir\scalyr_install.log"
    }
} else {
    Write-Step "Found service: '$serviceName' (Current state: $($service.Status))"
    if ($service.Status -eq "Running") {
        Restart-Service -Name $serviceName -Force
        Write-Success "Scalyr Agent service restarted."
    } else {
        Start-Service -Name $serviceName
        Write-Success "Scalyr Agent service started."
    }
}

Write-Success "Scalyr Agent installation and configuration complete."
