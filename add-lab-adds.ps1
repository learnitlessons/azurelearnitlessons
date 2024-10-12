# Script to install ADDS role and promote domain controllers using Azure VM Run Command

# Set secure password
$securePassword = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force
$passwordParam = $securePassword | ConvertFrom-SecureString

# Promote lon-dc1 as first DC in learnitlessons.com
$scriptBlock = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString -String '$passwordParam' -AsPlainText -Force
Install-ADDSForest `
    -CreateDnsDelegation:`$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "WinThreshold" `
    -DomainName "learnitlessons.com" `
    -DomainNetbiosName "LEARNITLESSONS" `
    -ForestMode "WinThreshold" `
    -InstallDns:`$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:`$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:`$true `
    -SafeModeAdministratorPassword `$securePassword
"@

Invoke-AzVMRunCommand -ResourceGroupName 'rg-lit-ADLab-ukw' -VMName 'lon-dc1' -CommandId 'RunPowerShellScript' -ScriptString $scriptBlock

# Wait for forest to be ready (adjust time as needed)
Start-Sleep -Seconds 300

# Promote lon-dc2 as additional DC in learnitlessons.com
$scriptBlock = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString -String '$passwordParam' -AsPlainText -Force
Install-ADDSDomainController `
    -NoGlobalCatalog:`$false `
    -CreateDnsDelegation:`$false `
    -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
    -CriticalReplicationOnly:`$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainName "learnitlessons.com" `
    -InstallDns:`$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:`$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:`$true `
    -SafeModeAdministratorPassword `$securePassword
"@

Invoke-AzVMRunCommand -ResourceGroupName 'rg-lit-ADLab-ukw' -VMName 'lon-dc2' -CommandId 'RunPowerShellScript' -ScriptString $scriptBlock

# Wait for replication (adjust time as needed)
Start-Sleep -Seconds 300

# Promote ams-dc1 as first DC in ams.learnitlessons.com
$scriptBlock = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString -String '$passwordParam' -AsPlainText -Force
Install-ADDSDomain `
    -NoGlobalCatalog:`$false `
    -CreateDnsDelegation:`$true `
    -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "WinThreshold" `
    -DomainType "ChildDomain" `
    -InstallDns:`$true `
    -LogPath "C:\Windows\NTDS" `
    -NewDomainName "ams" `
    -NewDomainNetbiosName "AMS" `
    -ParentDomainName "learnitlessons.com" `
    -NoRebootOnCompletion:`$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:`$true `
    -SafeModeAdministratorPassword `$securePassword
"@

Invoke-AzVMRunCommand -ResourceGroupName 'rg-lit-ADLab-weu' -VMName 'ams-dc1' -CommandId 'RunPowerShellScript' -ScriptString $scriptBlock

# Wait for subdomain to be ready (adjust time as needed)
Start-Sleep -Seconds 300

# Promote ams-dc2 as additional DC in ams.learnitlessons.com
$scriptBlock = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString -String '$passwordParam' -AsPlainText -Force
Install-ADDSDomainController `
    -NoGlobalCatalog:`$false `
    -CreateDnsDelegation:`$false `
    -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
    -CriticalReplicationOnly:`$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainName "ams.learnitlessons.com" `
    -InstallDns:`$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:`$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:`$true `
    -SafeModeAdministratorPassword `$securePassword
"@

Invoke-AzVMRunCommand -ResourceGroupName 'rg-lit-ADLab-weu' -VMName 'ams-dc2' -CommandId 'RunPowerShellScript' -ScriptString $scriptBlock

# Wait for replication (adjust time as needed)
Start-Sleep -Seconds 300

# Promote mum-dc1 as first DC in mum.learnitlessons.com
$scriptBlock = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString -String '$passwordParam' -AsPlainText -Force
Install-ADDSDomain `
    -NoGlobalCatalog:`$false `
    -CreateDnsDelegation:`$true `
    -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "WinThreshold" `
    -DomainType "ChildDomain" `
    -InstallDns:`$true `
    -LogPath "C:\Windows\NTDS" `
    -NewDomainName "mum" `
    -NewDomainNetbiosName "MUM" `
    -ParentDomainName "learnitlessons.com" `
    -NoRebootOnCompletion:`$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:`$true `
    -SafeModeAdministratorPassword `$securePassword
"@

Invoke-AzVMRunCommand -ResourceGroupName 'rg-lit-ADLab-cin' -VMName 'mum-dc1' -CommandId 'RunPowerShellScript' -ScriptString $scriptBlock

# Wait for subdomain to be ready (adjust time as needed)
Start-Sleep -Seconds 300

# Promote mum-dc2 as additional DC in mum.learnitlessons.com
$scriptBlock = @"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
`$securePassword = ConvertTo-SecureString -String '$passwordParam' -AsPlainText -Force
Install-ADDSDomainController `
    -NoGlobalCatalog:`$false `
    -CreateDnsDelegation:`$false `
    -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
    -CriticalReplicationOnly:`$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainName "mum.learnitlessons.com" `
    -InstallDns:`$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:`$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:`$true `
    -SafeModeAdministratorPassword `$securePassword
"@

Invoke-AzVMRunCommand -ResourceGroupName 'rg-lit-ADLab-cin' -VMName 'mum-dc2' -CommandId 'RunPowerShellScript' -ScriptString $scriptBlock

Write-Host "Domain Controller promotion process completed. Please check each server to ensure successful promotion and replication."
