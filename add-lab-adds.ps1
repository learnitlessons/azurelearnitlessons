# Script to install ADDS role and promote domain controllers using Azure CLI

# Set secure password
$password = "YourSecurePassword123!"

# Function to run command on VM
function Run-AzVMCommand {
    param (
        [string]$resourceGroup,
        [string]$vmName,
        [string]$script
    )
    
    $script = $script -replace '"', '\"'
    az vm run-command invoke --command-id RunPowerShellScript --name $vmName -g $resourceGroup --scripts "$script"
}

# Promote lon-dc1 as first DC in learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
Install-ADDSForest -CreateDnsDelegation:`$false -DatabasePath 'C:\Windows\NTDS' -DomainMode 'WinThreshold' -DomainName 'learnitlessons.com' -DomainNetbiosName 'LEARNITLESSONS' -ForestMode 'WinThreshold' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-ukw' -vmName 'lon-dc1' -script $script

Write-Host "Waiting for forest to be ready (5 minutes)..."
Start-Sleep -Seconds 300

# Promote lon-dc2 as additional DC in learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
Install-ADDSDomainController -NoGlobalCatalog:`$false -CreateDnsDelegation:`$false -CriticalReplicationOnly:`$false -DatabasePath 'C:\Windows\NTDS' -DomainName 'learnitlessons.com' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-ukw' -vmName 'lon-dc2' -script $script

Write-Host "Waiting for replication (5 minutes)..."
Start-Sleep -Seconds 300

# Promote ams-dc1 as first DC in ams.learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
Install-ADDSDomain -NoGlobalCatalog:`$false -CreateDnsDelegation:`$true -DatabasePath 'C:\Windows\NTDS' -DomainMode 'WinThreshold' -DomainType 'ChildDomain' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NewDomainName 'ams' -NewDomainNetbiosName 'AMS' -ParentDomainName 'learnitlessons.com' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-weu' -vmName 'ams-dc1' -script $script

Write-Host "Waiting for subdomain to be ready (5 minutes)..."
Start-Sleep -Seconds 300

# Promote ams-dc2 as additional DC in ams.learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
Install-ADDSDomainController -NoGlobalCatalog:`$false -CreateDnsDelegation:`$false -CriticalReplicationOnly:`$false -DatabasePath 'C:\Windows\NTDS' -DomainName 'ams.learnitlessons.com' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-weu' -vmName 'ams-dc2' -script $script

Write-Host "Waiting for replication (5 minutes)..."
Start-Sleep -Seconds 300

# Promote mum-dc1 as first DC in mum.learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
Install-ADDSDomain -NoGlobalCatalog:`$false -CreateDnsDelegation:`$true -DatabasePath 'C:\Windows\NTDS' -DomainMode 'WinThreshold' -DomainType 'ChildDomain' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NewDomainName 'mum' -NewDomainNetbiosName 'MUM' -ParentDomainName 'learnitlessons.com' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-cin' -vmName 'mum-dc1' -script $script

Write-Host "Waiting for subdomain to be ready (5 minutes)..."
Start-Sleep -Seconds 300

# Promote mum-dc2 as additional DC in mum.learnitlessons.com
$script = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString '$password' -AsPlainText -Force
Install-ADDSDomainController -NoGlobalCatalog:`$false -CreateDnsDelegation:`$false -CriticalReplicationOnly:`$false -DatabasePath 'C:\Windows\NTDS' -DomainName 'mum.learnitlessons.com' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
Run-AzVMCommand -resourceGroup 'rg-lit-ADLab-cin' -vmName 'mum-dc2' -script $script

Write-Host "Domain Controller promotion process completed. Please check each server to ensure successful promotion and replication."
