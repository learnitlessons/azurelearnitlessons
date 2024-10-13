# Function to run command on VM and check for errors
function Run-AzVMCommand {
    param (
        [string]$resourceGroup,
        [string]$vmName,
        [string]$script
    )
    
    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script -ErrorAction Stop
        
        if ($result.Status -eq "Succeeded") {
            Write-Host "Command executed successfully on $vmName"
            Write-Host $result.Value[0].Message
        } else {
            Write-Host "Error occurred while executing command on $vmName"
            Write-Host $result.Value[0].Message
            return $false
        }
    }
    catch {
        Write-Host "Error occurred while executing command on $vmName"
        Write-Host $_.Exception.Message
        return $false
    }
    
    return $true
}

# Function to install ADDS role and promote DC
function Install-ADDSAndPromoteDC {
    param (
        [string]$resourceGroup,
        [string]$vmName,
        [string]$domainName,
        [string]$parentDomainName,
        [bool]$isFirstDC,
        [string]$netbiosName
    )

    # Install ADDS role
    $script = "Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools"
    $success = Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
    if (-not $success) {
        Write-Host "Failed to install ADDS role on $vmName. Skipping DC promotion."
        return
    }

    # Promote DC
    if ($isFirstDC) {
        if ([string]::IsNullOrEmpty($parentDomainName)) {
            # First DC in forest
            $script = @"
            Import-Module ADDSDeployment
            `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
            Install-ADDSForest -CreateDnsDelegation:`$false -DatabasePath 'C:\Windows\NTDS' -DomainMode 'WinThreshold' -DomainName '$domainName' -DomainNetbiosName '$netbiosName' -ForestMode 'WinThreshold' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
        } else {
            # First DC in child domain
            $script = @"
            Import-Module ADDSDeployment
            `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
            `$username = 'LIT\$user'
            `$cred = New-Object System.Management.Automation.PSCredential (`$username, `$securePassword)
            Install-ADDSDomain -NoGlobalCatalog:`$false -CreateDnsDelegation:`$true -Credential `$cred -DatabasePath 'C:\Windows\NTDS' -DomainMode 'WinThreshold' -DomainType 'ChildDomain' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NewDomainName '$domainName' -NewDomainNetbiosName '$netbiosName' -ParentDomainName '$parentDomainName' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
        }
    } else {
        # Additional DC
        $script = @"
        Import-Module ADDSDeployment
        `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
        `$username = 'LIT\$user'
        `$cred = New-Object System.Management.Automation.PSCredential (`$username, `$securePassword)
        Install-ADDSDomainController -NoGlobalCatalog:`$false -CreateDnsDelegation:`$false -Credential `$cred -CriticalReplicationOnly:`$false -DatabasePath 'C:\Windows\NTDS' -DomainName '$domainName' -InstallDns:`$true -LogPath 'C:\Windows\NTDS' -NoRebootOnCompletion:`$false -SysvolPath 'C:\Windows\SYSVOL' -Force:`$true -SafeModeAdministratorPassword `$securePassword
"@
    }

    $success = Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
    if ($success) {
        Write-Host "ADDS installation and DC promotion completed successfully on $vmName"
    } else {
        Write-Host "Failed to promote $vmName to a domain controller"
    }
}

# ... [The rest of the script remains unchanged] ...

# Main script
$regions = @(
    @{
        name = "UK West"
        location = "ukwest"
        resourceGroup = "rg-lit-ADLab-ukw"
        addressPrefix = "10.0.0.0/16"
        vm1 = "lon-dc1"
        vm2 = "lon-dc2"
        vm1StaticIP = "10.0.0.4"
        vm2StaticIP = "10.0.0.5"
        domainName = "learnitlessons.com"
        netbiosName = "LIT"
    },
    @{
        name = "West Europe"
        location = "westeurope"
        resourceGroup = "rg-lit-ADLab-weu"
        addressPrefix = "10.1.0.0/16"
        vm1 = "ams-dc1"
        vm2 = "ams-dc2"
        vm1StaticIP = "10.1.0.4"
        vm2StaticIP = "10.1.0.5"
        domainName = "ams.learnitlessons.com"
        netbiosName = "AMS"
    },
    @{
        name = "Central India"
        location = "centralindia"
        resourceGroup = "rg-lit-ADLab-cin"
        addressPrefix = "10.2.0.0/16"
        vm1 = "mum-dc1"
        vm2 = "mum-dc2"
        vm1StaticIP = "10.2.0.4"
        vm2StaticIP = "10.2.0.5"
        domainName = "mum.learnitlessons.com"
        netbiosName = "MUM"
    }
)

do {
    Write-Host "`nSelect an action:"
    Write-Host "1. Create VMs with Static IPs"
    Write-Host "2. Remove Resources"
    Write-Host "3. Install ADDS and Promote DCs"
    Write-Host "4. Exit"

    $action = Read-Host "Enter your choice (1-4)"

    switch ($action) {
        "1" {
            do {
                Write-Host "`nSelect the region(s) you want to create VMs in:"
                for ($i = 0; $i -lt $regions.Count; $i++) {
                    Write-Host "$($i+1). $($regions[$i].name)"
                }
                Write-Host "4. All regions"
                Write-Host "5. Back to main menu"

                $choice = Read-Host "Enter your choice (1-5)"

                switch ($choice) {
                    "1" { 
                        Create-RegionVMs -location $regions[0].location -resourceGroup $regions[0].resourceGroup `
                                         -addressPrefix $regions[0].addressPrefix -vm1Name $regions[0].vm1 -vm2Name $regions[0].vm2 `
                                         -vm1StaticIP $regions[0].vm1StaticIP -vm2StaticIP $regions[0].vm2StaticIP
                    }
                    "2" { 
                        Create-RegionVMs -location $regions[1].location -resourceGroup $regions[1].resourceGroup `
                                         -addressPrefix $regions[1].addressPrefix -vm1Name $regions[1].vm1 -vm2Name $regions[1].vm2 `
                                         -vm1StaticIP $regions[1].vm1StaticIP -vm2StaticIP $regions[1].vm2StaticIP
                    }
                    "3" { 
                        Create-RegionVMs -location $regions[2].location -resourceGroup $regions[2].resourceGroup `
                                         -addressPrefix $regions[2].addressPrefix -vm1Name $regions[2].vm1 -vm2Name $regions[2].vm2 `
                                         -vm1StaticIP $regions[2].vm1StaticIP -vm2StaticIP $regions[2].vm2StaticIP
                    }
                    "4" { 
                        foreach ($region in $regions) {
                            Create-RegionVMs -location $region.location -resourceGroup $region.resourceGroup `
                                             -addressPrefix $region.addressPrefix -vm1Name $region.vm1 -vm2Name $region.vm2 `
                                             -vm1StaticIP $region.vm1StaticIP -vm2StaticIP $region.vm2StaticIP
                        }
                    }
                    "5" { break }
                    default { Write-Host "Invalid choice. Please try again." }
                }
            } while ($choice -ne "5")
        }
        "2" {
            do {
                Write-Host "`nSelect the region(s) where you want to remove resources:"
                for ($i = 0; $i -lt $regions.Count; $i++) {
                    Write-Host "$($i+1). $($regions[$i].name)"
                }
                Write-Host "4. All regions"
                Write-Host "5. Back to main menu"

                $choice = Read-Host "Enter your choice (1-5)"

                switch ($choice) {
                    "1" { Remove-RegionResources -resourceGroup $regions[0].resourceGroup }
                    "2" { Remove-RegionResources -resourceGroup $regions[1].resourceGroup }
                    "3" { Remove-RegionResources -resourceGroup $regions[2].resourceGroup }
                    "4" { 
                        foreach ($region in $regions) {
                            Remove-RegionResources -resourceGroup $region.resourceGroup
                        }
                    }
                    "5" { break }
                    default { Write-Host "Invalid choice. Please try again." }
                }

                if ($choice -ne "5") {
                    Write-Host "Resource removal completed."
                    Read-Host "Press Enter to continue..."
                }
            } while ($choice -ne "5")
        }
        "3" {
            do {
                Write-Host "`nSelect the region to install ADDS and promote DCs:"
                for ($i = 0; $i -lt $regions.Count; $i++) {
                    Write-Host "$($i+1). $($regions[$i].name)"
                }
                Write-Host "4. All regions"
                Write-Host "5. Back to main menu"

                $choice = Read-Host "Enter your choice (1-5)"

                switch ($choice) {
                    "1" { 
                        Install-ADDSAndPromoteDC -resourceGroup $regions[0].resourceGroup -vmName $regions[0].vm1 -domainName $regions[0].domainName -isFirstDC $true -netbiosName $regions[0].netbiosName
                        Install-ADDSAndPromoteDC -resourceGroup $regions[0].resourceGroup -vmName $regions[0].vm2 -domainName $regions[0].domainName -isFirstDC $false
                    }
                    "2" { 
                        Install-ADDSAndPromoteDC -resourceGroup $regions[1].resourceGroup -vmName $regions[1].vm1 -domainName $regions[1].domainName -parentDomainName "learnitlessons.com" -isFirstDC $true -netbiosName $regions[1].netbiosName
                        Install-ADDSAndPromoteDC -resourceGroup $regions[1].resourceGroup -vmName $regions[1].vm2 -domainName $regions[1].domainName -isFirstDC $false
                    }
                    "3" { 
                        Install-ADDSAndPromoteDC -resourceGroup $regions[2].resourceGroup -vmName $regions[2].vm1 -domainName $regions[2].domainName -parentDomainName "learnitlessons.com" -isFirstDC $true -netbiosName $regions[2].netbiosName
                        Install-ADDSAndPromoteDC -resourceGroup $regions[2].resourceGroup -vmName $regions[2].vm2 -domainName $regions[2].domainName -isFirstDC $false
                    }
                    "4" { 
                        foreach ($region in $regions) {
                            if ($region.name -eq "UK West") {
                                Install-ADDSAndPromoteDC -resourceGroup $region.resourceGroup -vmName $region.vm1 -domainName $region.domainName -isFirstDC $true -netbiosName $region.netbiosName
                            } else {
                                Install-ADDSAndPromoteDC -resourceGroup $region.resourceGroup -vmName $region.vm1 -domainName $region.domainName -parentDomainName "learnitlessons.com" -isFirstDC $true -netbiosName $region.netbiosName
                            }
                            Install-ADDSAndPromoteDC -resourceGroup $region.resourceGroup -vmName $region.vm2 -domainName $region.domainName -isFirstDC $false
                        }
                    }
                    "5" { break }
                    default { Write-Host "Invalid choice. Please try again." }
                }
            } while ($choice -ne "5")
        }
        "4" { break }
        default { Write-Host "Invalid choice. Please try again." }
    }
} while ($action -ne "4")

Write-Host "Script execution completed."
Write-Host "Remember to update DNS settings within each VM's operating system if necessary."
