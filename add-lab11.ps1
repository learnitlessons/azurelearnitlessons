# Azure AD Multi-Region Deployment Script with Member Servers

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

    # Function to create a VM with static IP and configure pagefile
    function Create-VMWithStaticIP {
        param (
            [string]$vmName,
            [string]$staticIP
        )

        $pip = New-AzPublicIpAddress -Name "$vmName-pip" -ResourceGroupName $resourceGroup -Location $location -AllocationMethod Static -Sku Standard
        $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress $staticIP
        $nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
        Set-AzNetworkInterface -NetworkInterface $nic
        $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $location -Name "$vmName-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
        $nic.NetworkSecurityGroup = $nsg
        Set-AzNetworkInterface -NetworkInterface $nic
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B1s" | 
            Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential (New-Object PSCredential($user, $securePass)) | 
            Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | 
            Add-AzVMNetworkInterface -Id $nic.Id | 
            Set-AzVMBootDiagnostic -Disable |
            Set-AzVMOSDisk -CreateOption FromImage -StorageAccountType StandardSSD_LRS
        New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig

        # Configure pagefile
        $script = @"
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
        Restart-Computer -Force
"@
        Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
    }

    # Create VMs
    Create-VMWithStaticIP -vmName $vm1Name -staticIP $vm1StaticIP
    Create-VMWithStaticIP -vmName $vm2Name -staticIP $vm2StaticIP

    # Verify IP configurations
    Write-Host "Verifying IP configurations for $($vm1Name) and $($vm2Name):"
    Get-AzNetworkInterface -Name "$vm1Name-nic" -ResourceGroupName $resourceGroup | Select-Object -ExpandProperty IpConfigurations
    Get-AzNetworkInterface -Name "$vm2Name-nic" -ResourceGroupName $resourceGroup | Select-Object -ExpandProperty IpConfigurations

    # Output connection information
    Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | ForEach-Object { 
        Write-Output "VM: $($_.Name.Replace('-pip','')) Public IP: $($_.IpAddress) RDP: mstsc /v:$($_.IpAddress) /u:$user" 
    }
}

# Function to create a member server
function Create-MemberServer {
    param (
        [string]$location,
        [string]$resourceGroup,
        [string]$vmName,
        [string]$staticIP,
        [string]$domainName,
        [bool]$joinDomain
    )

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroup -Name "vnet-$location"

    $pip = New-AzPublicIpAddress -Name "$vmName-pip" -ResourceGroupName $resourceGroup -Location $location -AllocationMethod Static -Sku Standard
    $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress $staticIP
    $nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
    Set-AzNetworkInterface -NetworkInterface $nic
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $location -Name "$vmName-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
    $nic.NetworkSecurityGroup = $nsg
    Set-AzNetworkInterface -NetworkInterface $nic
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B1s" | 
        Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential (New-Object PSCredential($user, $securePass)) | 
        Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | 
        Add-AzVMNetworkInterface -Id $nic.Id | 
        Set-AzVMBootDiagnostic -Disable |
        Set-AzVMOSDisk -CreateOption FromImage -StorageAccountType StandardSSD_LRS
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig

    if ($joinDomain) {
        $domainUser = "$user@$domainName"
        $domainPassword = ConvertTo-SecureString $pass -AsPlainText -Force
        $domainCred = New-Object System.Management.Automation.PSCredential ($domainUser, $domainPassword)

        Set-AzVMDomainJoin -VMName $vmName -DomainName $domainName -Credential $domainCred -JoinOption 3 -ResourceGroupName $resourceGroup
    }

    # Output connection information
    $publicIP = Get-AzPublicIpAddress -ResourceGroupName $resourceGroup -Name "$vmName-pip"
    Write-Output "Member Server: $vmName Public IP: $($publicIP.IpAddress) RDP: mstsc /v:$($publicIP.IpAddress) /u:$user"
}
# Function to create a member server
function Create-MemberServer {
    param (
        [string]$location,
        [string]$resourceGroup,
        [string]$vmName,
        [string]$staticIP,
        [string]$domainName,
        [bool]$joinDomain
    )

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroup -Name "vnet-$location"

    $pip = New-AzPublicIpAddress -Name "$vmName-pip" -ResourceGroupName $resourceGroup -Location $location -AllocationMethod Static -Sku Standard
    $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress $staticIP
    $nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
    Set-AzNetworkInterface -NetworkInterface $nic
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $location -Name "$vmName-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
    $nic.NetworkSecurityGroup = $nsg
    Set-AzNetworkInterface -NetworkInterface $nic
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B1s" | 
        Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential (New-Object PSCredential($user, $securePass)) | 
        Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | 
        Add-AzVMNetworkInterface -Id $nic.Id | 
        Set-AzVMBootDiagnostic -Disable |
        Set-AzVMOSDisk -CreateOption FromImage -StorageAccountType StandardSSD_LRS
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig

    if ($joinDomain) {
        $domainUser = "$user@$domainName"
        $domainPassword = ConvertTo-SecureString $pass -AsPlainText -Force
        $domainCred = New-Object System.Management.Automation.PSCredential ($domainUser, $domainPassword)

        Set-AzVMDomainJoin -VMName $vmName -DomainName $domainName -Credential $domainCred -JoinOption 3 -ResourceGroupName $resourceGroup
    }

    # Output connection information
    $publicIP = Get-AzPublicIpAddress -ResourceGroupName $resourceGroup -Name "$vmName-pip"
    Write-Output "Member Server: $vmName Public IP: $($publicIP.IpAddress) RDP: mstsc /v:$($publicIP.IpAddress) /u:$user"
}

# ... (rest of the functions remain the same)





# ... (previous code remains the same)

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
    Write-Host "4. Create Route Tables"
    Write-Host "5. Create VNet Peering and Configure Network"
    Write-Host "6. Add Member Server"
    Write-Host "7. Exit"

    $action = Read-Host "Enter your choice (1-7)"

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
            # ... (code for removing resources, same as before)
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
                    "1" { Install-ADDSForRegion -region $regions[0] -installBothDCs $false }
                    "2" { Install-ADDSForRegion -region $regions[1] -installBothDCs $false }
                    "3" { Install-ADDSForRegion -region $regions[2] -installBothDCs $false }
                    "4" { 
                        foreach ($region in $regions) {
                            Install-ADDSForRegion -region $region
                        }
                    }
                    "5" { break }
                    default { Write-Host "Invalid choice. Please try again." }
                }

                if ($choice -ne "5") {
                    Write-Host "ADDS installation and DC promotion completed."
                    Read-Host "Press Enter to continue..."
                }
            } while ($choice -ne "5")
        }
        "4" {
            Write-Host "Creating route tables for all regions..."
            Create-RouteTables -regions $regions
            Write-Host "Route tables created successfully."
            Read-Host "Press Enter to continue..."
        }
        "5" {
            Write-Host "Creating VNet peering between all regions..."
            Create-VNetPeering -regions $regions
            Write-Host "VNet peering created successfully."
            
            Write-Host "Checking VNet peering status..."
            Check-VNetPeeringStatus -regions $regions
            
            Write-Host "Updating NSG rules..."
            Update-NSGRules -regions $regions
            
            Write-Host "Updating Windows Firewall rules..."
            Update-WindowsFirewall -regions $regions
            
            Write-Host "Enabling IP forwarding..."
            Enable-IPForwarding -regions $regions
            
            Read-Host "Press Enter to continue..."
        }
        "6" {
            do {
                Write-Host "`nSelect the region to add a member server:"
                for ($i = 0; $i -lt $regions.Count; $i++) {
                    Write-Host "$($i+1). $($regions[$i].name)"
                }
                Write-Host "$($regions.Count + 1). Back to main menu"

                $choice = Read-Host "Enter your choice (1-$($regions.Count + 1))"

                if ($choice -in 1..$regions.Count) {
                    $selectedRegion = $regions[$choice - 1]
                    $serverName = Read-Host "Enter the name for the member server"
                    $serverIP = Read-Host "Enter the static IP for the member server"
                    $joinDomain = (Read-Host "Join the server to the domain? (Y/N)").ToLower() -eq 'y'

                    Create-MemberServer -location $selectedRegion.location `
                                        -resourceGroup $selectedRegion.resourceGroup `
                                        -vmName $serverName `
                                        -staticIP $serverIP `
                                        -domainName $selectedRegion.domainName `
                                        -joinDomain $joinDomain

                    Write-Host "Member server creation completed."
                    Read-Host "Press Enter to continue..."
                }
                elseif ($choice -eq ($regions.Count + 1).ToString()) {
                    break
                }
                else {
                    Write-Host "Invalid choice. Please try again."
                }
            } while ($true)
        }
        "7" { break }
        default { Write-Host "Invalid choice. Please try again." }
    }
} while ($action -ne "7")

Write-Host "Script execution completed."
Write-Host "Remember to update DNS settings within each VM's operating system if necessary."
