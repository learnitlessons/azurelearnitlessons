# Script to configure pagefile, install ADDS role, and promote domain controllers using Azure CLI

# Set secure password
$password = "YourSecurePassword123!"

# Function to run command on VM and check for errors
function Run-AzVMCommand {
    param (
        [string]$resourceGroup,
        [string]$vmName,
        [string]$script
    )
    
    $script = $script -replace '"', '\"'
    $result = az vm run-command invoke --command-id RunPowerShellScript --name $vmName -g $resourceGroup --scripts "$script"
    $output = $result | ConvertFrom-Json
    
    if ($output.value.message -match "Error") {
        Write-Host "Error occurred while executing command on $vmName"
        Write-Host $output.value.message
        exit 1
    }
    
    Write-Host "Command executed successfully on $vmName"
}

# Function to configure pagefile and restart VM
function Configure-PagefileAndRestart {
    param (
        [string]$resourceGroup,
        [string]$vmName
    )

    $script = @"
    # Configure pagefile to be automatically managed
    $computerSystem = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges
    $computerSystem.AutomaticManagedPagefile = $true
    $computerSystem.Put()

    # Restart the computer
    Restart-Computer -Force
"@

    Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
    
    Write-Host "Waiting for $vmName to restart (5 minutes)..."
    Start-Sleep -Seconds 300
}

# Configure pagefile and restart lon-dc1
Configure-PagefileAndRestart -resourceGroup 'rg-lit-ADLab-ukw' -vmName 'lon-dc1'

# Promote lon-dc1 as first DC in learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
Install-ADDSForest -CreateDnsDelegation:`$false -DatabasePath 'C:\Windows\NTDS' -DomainMode 'WinThreshold' -DomainName 'learnitlessons.com' -DomainNetbiosName 'LEARNITLESSONS' -ForestMode 'WinThreshold' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-ukw' -vmName 'lon-dc1' -script $script
