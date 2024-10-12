# Script to install ADDS role and promote domain controllers

# Set secure password
$securePassword = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force

# Promote lon-dc1 as first DC in learnitlessons.com
$session = New-PSSession -ComputerName lon-dc1
Invoke-Command -Session $session -ScriptBlock {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    Install-ADDSForest `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainMode "WinThreshold" `
        -DomainName "learnitlessons.com" `
        -DomainNetbiosName "LEARNITLESSONS" `
        -ForestMode "WinThreshold" `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $using:securePassword
}
Remove-PSSession $session

# Wait for forest to be ready (adjust time as needed)
Start-Sleep -Seconds 300

# Promote lon-dc2 as additional DC in learnitlessons.com
$session = New-PSSession -ComputerName lon-dc2
Invoke-Command -Session $session -ScriptBlock {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    Install-ADDSDomainController `
        -NoGlobalCatalog:$false `
        -CreateDnsDelegation:$false `
        -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
        -CriticalReplicationOnly:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainName "learnitlessons.com" `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $using:securePassword
}
Remove-PSSession $session

# Wait for replication (adjust time as needed)
Start-Sleep -Seconds 300

# Promote ams-dc1 as first DC in ams.learnitlessons.com
$session = New-PSSession -ComputerName ams-dc1
Invoke-Command -Session $session -ScriptBlock {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    Install-ADDSDomain `
        -NoGlobalCatalog:$false `
        -CreateDnsDelegation:$true `
        -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainMode "WinThreshold" `
        -DomainType "ChildDomain" `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NewDomainName "ams" `
        -NewDomainNetbiosName "AMS" `
        -ParentDomainName "learnitlessons.com" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $using:securePassword
}
Remove-PSSession $session

# Wait for subdomain to be ready (adjust time as needed)
Start-Sleep -Seconds 300

# Promote ams-dc2 as additional DC in ams.learnitlessons.com
$session = New-PSSession -ComputerName ams-dc2
Invoke-Command -Session $session -ScriptBlock {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    Install-ADDSDomainController `
        -NoGlobalCatalog:$false `
        -CreateDnsDelegation:$false `
        -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
        -CriticalReplicationOnly:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainName "ams.learnitlessons.com" `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $using:securePassword
}
Remove-PSSession $session

# Wait for replication (adjust time as needed)
Start-Sleep -Seconds 300

# Promote mum-dc1 as first DC in mum.learnitlessons.com
$session = New-PSSession -ComputerName mum-dc1
Invoke-Command -Session $session -ScriptBlock {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    Install-ADDSDomain `
        -NoGlobalCatalog:$false `
        -CreateDnsDelegation:$true `
        -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainMode "WinThreshold" `
        -DomainType "ChildDomain" `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NewDomainName "mum" `
        -NewDomainNetbiosName "MUM" `
        -ParentDomainName "learnitlessons.com" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $using:securePassword
}
Remove-PSSession $session

# Wait for subdomain to be ready (adjust time as needed)
Start-Sleep -Seconds 300

# Promote mum-dc2 as additional DC in mum.learnitlessons.com
$session = New-PSSession -ComputerName mum-dc2
Invoke-Command -Session $session -ScriptBlock {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    Install-ADDSDomainController `
        -NoGlobalCatalog:$false `
        -CreateDnsDelegation:$false `
        -Credential (Get-Credential -Message "Enter Domain Admin Credentials") `
        -CriticalReplicationOnly:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainName "mum.learnitlessons.com" `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $using:securePassword
}
Remove-PSSession $session

Write-Host "Domain Controller promotion process completed. Please check each server to ensure successful promotion and replication."
