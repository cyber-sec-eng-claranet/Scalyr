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
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath
        Start-Process msiexec.exe -ArgumentList '/i', "`"$msiPath`"", '/qn' -Wait
    } else {
        Write-Host "[INFO] Scalyr Agent already installed. Skipping MSI installation."
    }

   # Fetch config file from GitHub
    Write-Host "[INFO] Fetching config $ConfigFile from GitHub..."
    $config = Invoke-WebRequest -Uri $configUrl | Select-Object -ExpandProperty Content
    $config = $config -replace 'API_KEY_PLACEHOLDER', $ApiKey


Write-Host "[INFO] Overwriting agent.json contents without replacing the file..."
$config | Set-Content -Path $configPath -Encoding Ascii


    # Restart service
    Write-Host "[INFO] Restarting Scalyr Agent service..."
    if (-not $service) { $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue }
    if ($service) {
        Restart-Service $serviceName
        Write-Host "[INFO] $serviceName restarted successfully."
    } else {
        Write-Warning "[WARN] Could not restart $serviceName (service not found)."
    }

    Write-Host "[SUCCESS] Agent is installed and configured with $ConfigFile."
}
