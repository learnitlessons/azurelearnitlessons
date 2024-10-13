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
    `$computerSystem = Get-WmiObject -Class Win32_ComputerSystem -EnableAllPrivileges
    if (`$computerSystem.AutomaticManagedPagefile) {
        Write-Host "Pagefile is already automatically managed."
    } else {
        `$computerSystem.AutomaticManagedPagefile = `$true
        `$result = `$computerSystem.Put()
        if (`$result.ReturnValue -eq 0) {
            Write-Host "Pagefile set to be automatically managed."
        } else {
            Write-Host "Failed to set pagefile to automatically managed. Return value: `$(`$result.ReturnValue)"
        }
    }

    # Restart the computer
    Write-Host "Restarting the computer..."
    Restart-Computer -Force
"@

    Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
    
    Write-Host "Waiting for $vmName to restart (5 minutes)..."
    Start-Sleep -Seconds 300
}


# Configure pagefile and restart ams-dc1
Configure-PagefileAndRestart -resourceGroup 'rg-lit-ADLab-weu' -vmName 'ams-dc1'

# Configure DNS on ams-dc1
$script = @"
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '10.0.0.4','10.0.0.5'
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-weu' -vmName 'ams-dc1' -script $script

# Promote ams-dc1 as first DC in ams.learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential ("LIT\shumi", `$securePassword)
Install-ADDSDomain -NoGlobalCatalog:`$false -CreateDnsDelegation:`$true -Credential `$cred -DatabasePath 'C:\Windows\NTDS' -DomainMode 'WinThreshold' -DomainType 'ChildDomain' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NewDomainName 'ams' -NewDomainNetbiosName 'AMS' -ParentDomainName 'learnitlessons.com' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-weu' -vmName 'ams-dc1' -script $script

Write-Host "Waiting for subdomain to be ready (10 minutes)..."
Start-Sleep -Seconds 600

# Configure pagefile and restart ams-dc2
Configure-PagefileAndRestart -resourceGroup 'rg-lit-ADLab-weu' -vmName 'ams-dc2'

# Configure DNS on ams-dc2
$script = @"
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '10.1.0.4'
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-weu' -vmName 'ams-dc2' -script $script

# Promote ams-dc2 as additional DC in ams.learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential ("AMS\shumi", `$securePassword)
Install-ADDSDomainController -NoGlobalCatalog:`$false -CreateDnsDelegation:`$false -Credential `$cred -CriticalReplicationOnly:`$false -DatabasePath 'C:\Windows\NTDS' -DomainName 'ams.learnitlessons.com' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-weu' -vmName 'ams-dc2' -script $script

Write-Host "Waiting for replication (10 minutes)..."
Start-Sleep -Seconds 600

# Configure pagefile and restart mum-dc1
Configure-PagefileAndRestart -resourceGroup 'rg-lit-ADLab-cin' -vmName 'mum-dc1'

# Configure DNS on mum-dc1
$script = @"
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '10.0.0.4','10.0.0.5'
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-cin' -vmName 'mum-dc1' -script $script

# Promote mum-dc1 as first DC in mum.learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential ("LIT\shumi", `$securePassword)
Install-ADDSDomain -NoGlobalCatalog:`$false -CreateDnsDelegation:`$true -Credential `$cred -DatabasePath 'C:\Windows\NTDS' -DomainMode 'WinThreshold' -DomainType 'ChildDomain' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NewDomainName 'mum' -NewDomainNetbiosName 'MUM' -ParentDomainName 'learnitlessons.com' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-cin' -vmName 'mum-dc1' -script $script

Write-Host "Waiting for subdomain to be ready (10 minutes)..."
Start-Sleep -Seconds 600

# Configure pagefile and restart mum-dc2
Configure-PagefileAndRestart -resourceGroup 'rg-lit-ADLab-cin' -vmName 'mum-dc2'

# Configure DNS on mum-dc2
$script = @"
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '10.2.0.4'
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-cin' -vmName 'mum-dc2' -script $script

# Promote mum-dc2 as additional DC in mum.learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential ("MUM\shumi", `$securePassword)
Install-ADDSDomainController -NoGlobalCatalog:`$false -CreateDnsDelegation:`$false -Credential `$cred -CriticalReplicationOnly:`$false -DatabasePath 'C:\Windows\NTDS' -DomainName 'mum.learnitlessons.com' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-cin' -vmName 'mum-dc2' -script $script

Write-Host "Domain Controller promotion process completed. Please check each server to ensure successful promotion and replication."
