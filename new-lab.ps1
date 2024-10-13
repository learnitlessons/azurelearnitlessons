# Basic settings
$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with a secure password
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force

# Function to create VMs in a specific region with static IPs
function Create-RegionVMs {
    param (
        [string]$location,
        [string]$resourceGroup,
        [string]$addressPrefix,
        [string]$vm1Name,
        [string]$vm2Name,
        [string]$vm1StaticIP,
        [string]$vm2StaticIP
    )

    New-AzResourceGroup -Name $resourceGroup -Location $location -ErrorAction SilentlyContinue

    $vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroup -Location $location -Name "vnet-$location" -AddressPrefix $addressPrefix -Subnet (New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix ($addressPrefix -replace '0/16', '0/24'))

    # Create first VM
    $vm = $vm1Name
    $pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $resourceGroup -Location $location -AllocationMethod Static -Sku Standard
    $nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress $vm1StaticIP
    $nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
    Set-AzNetworkInterface -NetworkInterface $nic
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $location -Name "$vm-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
    $nic.NetworkSecurityGroup = $nsg
    Set-AzNetworkInterface -NetworkInterface $nic
    $vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | 
        Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $securePass)) | 
        Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | 
        Add-AzVMNetworkInterface -Id $nic.Id | 
        Set-AzVMBootDiagnostic -Disable
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig

    # Create second VM
    $vm = $vm2Name
    $pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $resourceGroup -Location $location -AllocationMethod Static -Sku Standard
    $nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress $vm2StaticIP
    $nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
    Set-AzNetworkInterface -NetworkInterface $nic
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $location -Name "$vm-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
    $nic.NetworkSecurityGroup = $nsg
    Set-AzNetworkInterface -NetworkInterface $nic
    $vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | 
        Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $securePass)) | 
        Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | 
        Add-AzVMNetworkInterface -Id $nic.Id | 
        Set-AzVMBootDiagnostic -Disable
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig

    # Verify IP configurations
    Write-Host "Verifying IP configurations for $($vm1Name) and $($vm2Name):"
    Get-AzNetworkInterface -Name "$vm1Name-nic" -ResourceGroupName $resourceGroup | Select-Object -ExpandProperty IpConfigurations
    Get-AzNetworkInterface -Name "$vm2Name-nic" -ResourceGroupName $resourceGroup | Select-Object -ExpandProperty IpConfigurations

    # Output connection information
    Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | ForEach-Object { 
        Write-Output "VM: $($_.Name.Replace('-pip','')) Public IP: $($_.IpAddress) RDP: mstsc /v:$($_.IpAddress) /u:$user" 
    }
}

# Function to remove resources in a specific region
function Remove-RegionResources {
    param (
        [string]$resourceGroup
    )

    Write-Host "Removing all resources in resource group: $resourceGroup"
    Remove-AzResourceGroup -Name $resourceGroup -Force
    Write-Host "Resources removed successfully."
}

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

    # Configure pagefile and restart
    Configure-PagefileAndRestart -resourceGroup $resourceGroup -vmName $vmName

    # Install ADDS role
    $script = "Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools"
    Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script

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

    Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script

    Write-Host "Waiting for promotion to complete and DC to restart (10 minutes)..."
    Start-Sleep -Seconds 600
}

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
                    "1" { Create-RegionVMs @regions[0] }
                    "2" { Create-RegionVMs @regions[1] }
                    "3" { Create-RegionVMs @regions[2] }
                    "4" { 
                        foreach ($region in $regions) {
                            Create-RegionVMs @region
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
