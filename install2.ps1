function Install-Scalyr {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,
        [Parameter(Mandatory = $true)]
        [string]$ConfigFile
    )
    $msiUrl       = "https://app.scalyr.com/scalyr-repo/stable/latest/ScalyrAgentInstaller-2.2.18.msi"
    $msiPath      = "$env:TEMP\ScalyrAgentInstaller.msi"
    $configUrl    = "https://raw.githubusercontent.com/cyber-sec-eng-claranet/Scalyr/refs/heads/Windows/$ConfigFile"
    $configPath   = "C:\Program Files (x86)\Scalyr\config\agent.json"
    $serviceName  = "Scalyr Agent Service"
    
    # Check if agent is installed
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "[INFO] Scalyr Agent not detected. Installing..."
        
        # Download MSI
        try {
            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -ErrorAction Stop
            Write-Host "[INFO] MSI downloaded successfully."
        } catch {
            Write-Error "[ERROR] Failed to download MSI: $_"
            return
        }
        
        # Install with better error handling
        Write-Host "[INFO] Starting installation (this may take a few minutes)..."
        $process = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart /L*v `"$env:TEMP\ScalyrInstall.log`"" -Wait -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Error "[ERROR] Installation failed with exit code $($process.ExitCode). Check log: $env:TEMP\ScalyrInstall.log"
            return
        }
        Write-Host "[INFO] Installation completed successfully."
        
        # Wait for service to be registered
        Start-Sleep -Seconds 5
    } else {
        Write-Host "[INFO] Scalyr Agent already installed. Skipping MSI installation."
    }
    
    # Fetch config file from GitHub
    Write-Host "[INFO] Fetching config $ConfigFile from GitHub..."
    try {
        $config = Invoke-WebRequest -Uri $configUrl -ErrorAction Stop | Select-Object -ExpandProperty Content
        $config = $config -replace 'API_KEY_PLACEHOLDER', $ApiKey
        
        Write-Host "[INFO] Overwriting agent.json contents..."
        $config | Set-Content -Path $configPath -Encoding Ascii -Force
    } catch {
        Write-Error "[ERROR] Failed to fetch or write config: $_"
        return
    }
    
    # Restart service
    Write-Host "[INFO] Restarting Scalyr Agent service..."
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Restart-Service $serviceName -ErrorAction SilentlyContinue
        Write-Host "[INFO] $serviceName restarted successfully."
    } else {
        Write-Warning "[WARN] Could not restart $serviceName (service not found)."
    }
    Write-Host "[SUCCESS] Agent is installed and configured with $ConfigFile."
}
