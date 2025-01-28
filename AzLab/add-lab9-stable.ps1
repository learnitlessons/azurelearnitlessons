# Azure AD Multi-Region Deployment Script

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
    #added this
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
        Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
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

# Function to remove resources in a specific region
function Remove-RegionResources {
    param (
        [string]$resourceGroup
    )

    Write-Host "Removing all resources in resource group: $resourceGroup"
    try {
        Remove-AzResourceGroup -Name $resourceGroup -Force -ErrorAction Stop
        Write-Host "Resources removed successfully."
    }
    catch {
        Write-Host "Error occurred while removing resources in $resourceGroup"
        Write-Host $_.Exception.Message
    }
}

# Function to remove a specific VM
function Remove-VM {
    param (
        [string]$resourceGroup,
        [string]$vmName
    )

    Write-Host "Removing VM: $vmName from resource group: $resourceGroup"
    try {
        # Remove the VM
        Remove-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Force

        # Remove the OS disk
        $osDiskName = "$vmName`_OsDisk"
        Remove-AzDisk -ResourceGroupName $resourceGroup -DiskName $osDiskName -Force

        # Remove the NIC
        $nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like "$vmName*" }
        if ($nic) {
            Remove-AzNetworkInterface -ResourceGroupName $resourceGroup -Name $nic.Name -Force
        }

        # Remove the Public IP
        $pip = Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like "$vmName*" }
        if ($pip) {
            Remove-AzPublicIpAddress -ResourceGroupName $resourceGroup -Name $pip.Name -Force
        }

        Write-Host "VM $vmName and associated resources removed successfully."
    }
    catch {
        Write-Host "Error occurred while removing VM $vmName"
        Write-Host $_.Exception.Message
    }
}

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
            return $result
        } else {
            Write-Host "Error occurred while executing command on $vmName"
            Write-Host $result.Value[0].Message
            return $result
        }
    }
    catch {
        Write-Host "Error occurred while executing command on $vmName"
        Write-Host $_.Exception.Message
        return $null
    }
}

# Function to install ADDS role and promote DC
function Install-ADDSAndPromoteDC {
    param (
        [string]$resourceGroup,
        [string]$vmName,
        [string]$domainName,
        [string]$parentDomainName,
        [bool]$isFirstDC,
        [string]$netbiosName,
        [string]$firstDCIP
    )

    # Configure DNS to point to the first DC
    $script = @"
    `$adapter = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' -and `$_.InterfaceDescription -like '*Hyper-V*' }
    if (`$adapter) {
        Set-DnsClientServerAddress -InterfaceIndex `$adapter.InterfaceIndex -ServerAddresses $firstDCIP
        Write-Output "DNS server set to $firstDCIP for adapter `$(`$adapter.Name)"
    } else {
        Write-Output "No suitable network adapter found"
    }
    ipconfig /flushdns
    Get-DnsClientServerAddress -AddressFamily IPv4 | Format-Table -AutoSize
"@
    $result = Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
    if ($result -eq $null -or $result.Status -ne "Succeeded") {
        Write-Host "Failed to configure DNS on $vmName. Skipping DC promotion."
        return $false
    }

    # Verify DNS configuration
    $script = @"
    nslookup $domainName
    Test-NetConnection -ComputerName $domainName
"@
    $result = Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
    if ($result -eq $null -or $result.Status -ne "Succeeded") {
        Write-Host "DNS verification failed on $vmName. Skipping DC promotion."
        return $false
    }

    # Install ADDS role
    $script = "Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools"
    $result = Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
    if ($result -eq $null -or $result.Status -ne "Succeeded") {
        Write-Host "Failed to install ADDS role on $vmName. Skipping DC promotion."
        return $false
    }

    # Promote DC
    $retryCount = 0
    $maxRetries = 3
    $retryDelay = 300 # 5 minutes

    while ($retryCount -lt $maxRetries) {
        if ($isFirstDC) {
            if ([string]::IsNullOrEmpty($parentDomainName)) {
                # First DC in forest
                $script = @"
                Import-Module ADDSDeployment
                `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
                `$params = @{
                    CreateDnsDelegation = `$false
                    DatabasePath = 'C:\Windows\NTDS'
                    DomainMode = 'WinThreshold'
                    DomainName = '$domainName'
                    DomainNetbiosName = '$netbiosName'
                    ForestMode = 'WinThreshold'
                    InstallDns = `$true
                    LogPath = 'C:\Windows\NTDS'
                    NoRebootOnCompletion = `$false
                    SysvolPath = 'C:\Windows\SYSVOL'
                    Force = `$true
                    SafeModeAdministratorPassword = `$securePassword
                }
                Install-ADDSForest @params -ErrorAction Stop
"@
            } else {
                # First DC in child domain
                $script = @"
                Import-Module ADDSDeployment
                `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
                `$username = '$user@$parentDomainName'
                `$cred = New-Object System.Management.Automation.PSCredential (`$username, `$securePassword)
                `$params = @{
                    NewDomainName = '$domainName'
                    ParentDomainName = '$parentDomainName'
                    DomainMode = 'WinThreshold'
                    DomainType = 'ChildDomain'
                    InstallDns = `$true
                    CreateDnsDelegation = `$true
                    DatabasePath = 'C:\Windows\NTDS'
                    LogPath = 'C:\Windows\NTDS'
                    SysvolPath = 'C:\Windows\SYSVOL'
                    NewDomainNetbiosName = '$netbiosName'
                    Credential = `$cred
                    SafeModeAdministratorPassword = `$securePassword
                    NoRebootOnCompletion = `$false
                    Force = `$true
                }
                Install-ADDSDomain @params -ErrorAction Stop
"@
            }
        } else {
            # Additional DC
            $script = @"
            Import-Module ADDSDeployment
            `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
            `$username = '$user@$domainName'
            `$cred = New-Object System.Management.Automation.PSCredential (`$username, `$securePassword)
            Install-ADDSDomainController ``
                -NoGlobalCatalog:`$false ``
                -CreateDnsDelegation:`$false ``
                -Credential `$cred ``
                -CriticalReplicationOnly:`$false ``
                -DatabasePath 'C:\Windows\NTDS' ``
                -DomainName '$domainName' ``
                -InstallDns:`$true ``
                -LogPath 'C:\Windows\NTDS' ``
                -NoRebootOnCompletion:`$false ``
                -SysvolPath 'C:\Windows\SYSVOL' ``
                -Force:`$true ``
                -SafeModeAdministratorPassword `$securePassword
"@
        }

        $result = Run-AzVMCommand -resourceGroup $resourceGroup -vmName $vmName -script $script
        if ($result -ne $null -and $result.Status -eq "Succeeded") {
            Write-Host "ADDS installation and DC promotion completed successfully on $vmName"
            return $true
        } else {
            Write-Host "Failed to promote $vmName to a domain controller. Attempt $($retryCount + 1) of $maxRetries."
            if ($result -ne $null) {
                Write-Host "Error message: $($result.Value[0].Message)"
            }
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "Waiting $($retryDelay / 60) minutes before retrying..."
                Start-Sleep -Seconds $retryDelay
            }
        }
    }

    Write-Host "Failed to promote $vmName to a domain controller after $maxRetries attempts."
    return $false
}

# Function to install ADDS for a region
function Install-ADDSForRegion {
    param (
        [hashtable]$region,
        [bool]$installBothDCs = $true
    )
    
    $vm1Choice = if ($installBothDCs) { "Y" } else {
        Read-Host "Install ADDS on $($region.vm1)? (Y/N)"
    }
    
    if ($vm1Choice -eq "Y") {
        $parentDomainName = if ($region.name -eq "UK West") { "" } else { "learnitlessons.com" }
        $success = Install-ADDSAndPromoteDC -resourceGroup $region.resourceGroup -vmName $region.vm1 `
                                            -domainName $region.domainName -parentDomainName $parentDomainName `
                                            -isFirstDC $true -netbiosName $region.netbiosName -firstDCIP $region.vm1StaticIP
        if ($success) {
            Write-Host "Waiting 15 minutes for AD replication and DNS propagation..."
            Start-Sleep -Seconds 900
        } else {
            Write-Host "Failed to promote $($region.vm1). Skipping second DC installation."
            return
        }
    }

    $vm2Choice = if ($installBothDCs) { "Y" } else {
        Read-Host "Install ADDS on $($region.vm2)? (Y/N)"
    }
    
    if ($vm2Choice -eq "Y") {
        $success = Install-ADDSAndPromoteDC -resourceGroup $region.resourceGroup -vmName $region.vm2 `
                                            -domainName $region.domainName -isFirstDC $false -netbiosName $region.netbiosName `
                                            -firstDCIP $region.vm1StaticIP
        if ($success) {
            Write-Host "$($region.vm2) successfully promoted to a domain controller."
        } else {
            Write-Host "Failed to promote $($region.vm2) to a domain controller."
        }
    }
}

# Function to create route tables and routes
function Create-RouteTables {
    param (
        [array]$regions
    )

    foreach ($region in $regions) {
        $routeTableName = "rt-" + ($region.name -replace '\s', '-')
        Write-Host "Creating route table: $routeTableName"
        
        try {
            $routeTable = New-AzRouteTable -Name $routeTableName -ResourceGroupName $region.resourceGroup -Location $region.location -Force

            foreach ($otherRegion in $regions) {
                if ($otherRegion.name -ne $region.name) {
                    $routeName = "route-to-" + ($otherRegion.name -replace '\s', '-')
                    Write-Host "Adding route: $routeName"
                    
                    Add-AzRouteConfig -Name $routeName `
                                      -AddressPrefix $otherRegion.addressPrefix `
                                      -NextHopType VirtualAppliance `
                                      -NextHopIpAddress $otherRegion.vm1StaticIP `
                                      -RouteTable $routeTable
                }
            }

            $routeTable | Set-AzRouteTable

            Write-Host "Associating route table with subnet"
            $vnet = Get-AzVirtualNetwork -ResourceGroupName $region.resourceGroup -Name "vnet-$($region.location)"
            $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name "default"
            
            Set-AzVirtualNetworkSubnetConfig -Name "default" `
                                             -VirtualNetwork $vnet `
                                             -AddressPrefix $subnet.AddressPrefix `
                                             -RouteTable $routeTable | Set-AzVirtualNetwork
            
            Write-Host "Route table created and associated successfully for $($region.name)"
        }
        catch {
            Write-Host "Error creating route table for $($region.name): $_"
        }
    }
}

# Function to create VNet peering between regions
function Create-VNetPeering {
    param (
        [array]$regions
    )

    for ($i = 0; $i -lt $regions.Count; $i++) {
        for ($j = $i + 1; $j -lt $regions.Count; $j++) {
            $region1 = $regions[$i]
            $region2 = $regions[$j]

            Write-Host "Creating VNet peering between $($region1.name) and $($region2.name)"

            # Get virtual networks
            $vnet1 = Get-AzVirtualNetwork -ResourceGroupName $region1.resourceGroup -Name "vnet-$($region1.location)"
            $vnet2 = Get-AzVirtualNetwork -ResourceGroupName $region2.resourceGroup -Name "vnet-$($region2.location)"

            # Create peering from vnet1 to vnet2
            $peering1Name = "$($region1.name)-to-$($region2.name)" -replace '\s', '-'
            Add-AzVirtualNetworkPeering -Name $peering1Name `
                                        -VirtualNetwork $vnet1 `
                                        -RemoteVirtualNetworkId $vnet2.Id `
                                        -AllowForwardedTraffic

            # Create peering from vnet2 to vnet1
            $peering2Name = "$($region2.name)-to-$($region1.name)" -replace '\s', '-'
            Add-AzVirtualNetworkPeering -Name $peering2Name `
                                        -VirtualNetwork $vnet2 `
                                        -RemoteVirtualNetworkId $vnet1.Id `
                                        -AllowForwardedTraffic

            Write-Host "VNet peering created successfully between $($region1.name) and $($region2.name)"
        }
    }
}

# Function to check VNet peering status
function Check-VNetPeeringStatus {
    param (
        [array]$regions
    )

    foreach ($region in $regions) {
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $region.resourceGroup -Name "vnet-$($region.location)"
        $peerings = Get-AzVirtualNetworkPeering -VirtualNetwork $vnet

        Write-Host "Peering status for $($region.name):"
        foreach ($peering in $peerings) {
            Write-Host "  $($peering.Name): $($peering.PeeringState)"
        }
    }
}

# Function to update NSG rules
function Update-NSGRules {
    param (
        [array]$regions
    )

    foreach ($region in $regions) {
        $vms = @($region.vm1, $region.vm2)
        foreach ($vm in $vms) {
            $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $region.resourceGroup -Name "$vm-nsg"
            
            # Check if ICMP rule exists
            $icmpRule = $nsg.SecurityRules | Where-Object { $_.Name -eq "AllowICMP" }
            if (-not $icmpRule) {
                # Add ICMP rule if it doesn't exist
                $nsg | Add-AzNetworkSecurityRuleConfig -Name "AllowICMP" -Description "Allow ICMP" -Access Allow -Protocol ICMP -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange *
                $nsg | Set-AzNetworkSecurityGroup
                Write-Host "Added ICMP rule to NSG for $vm"
            } else {
                Write-Host "ICMP rule already exists in NSG for $vm"
            }
        }
    }
}

# Function to update Windows Firewall
function Update-WindowsFirewall {
    param (
        [array]$regions
    )

    $script = @"
    New-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Protocol ICMPv4
    New-NetFirewallRule -DisplayName "Allow ICMPv4-Out" -Protocol ICMPv4 -Direction Outbound
    Write-Output "ICMP rules added to Windows Firewall"
"@

    foreach ($region in $regions) {
        $vms = @($region.vm1, $region.vm2)
        foreach ($vm in $vms) {
            Write-Host "Updating Windows Firewall rules on $vm"
            $result = Run-AzVMCommand -ResourceGroupName $region.resourceGroup -VMName $vm -CommandId 'RunPowerShellScript' -ScriptString $script
            if ($result.Status -eq "Succeeded") {
                Write-Host $result.Value[0].Message
            } else {
                Write-Host "Failed to update Windows Firewall rules on $vm"
            }
        }
    }
}

# Function to enable IP forwarding
function Enable-IPForwarding {
    param (
        [array]$regions
    )

    foreach ($region in $regions) {
        $vms = @($region.vm1, $region.vm2)
        foreach ($vm in $vms) {
            $nic = Get-AzNetworkInterface -ResourceGroupName $region.resourceGroup -Name "$vm-nic"
            if ($nic.EnableIPForwarding -eq $false) {
                $nic.EnableIPForwarding = $true
                Set-AzNetworkInterface -NetworkInterface $nic
                Write-Host "Enabled IP forwarding on NIC for $vm"
            } else {
                Write-Host "IP forwarding already enabled on NIC for $vm"
            }
        }
    }
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
    Write-Host "4. Create Route Tables"
    Write-Host "5. Create VNet Peering and Configure Network"
    Write-Host "6. Exit"

    $action = Read-Host "Enter your choice (1-6)"

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
                Write-Host "`nSelect the resource removal option:"
                Write-Host "1. Remove entire region"
                Write-Host "2. Remove specific VM"
                Write-Host "3. Back to main menu"

                $removalChoice = Read-Host "Enter your choice (1-3)"

                switch ($removalChoice) {
                    "1" {
                        Write-Host "`nSelect the region(s) where you want to remove resources:"
                        for ($i = 0; $i -lt $regions.Count; $i++) {
                            Write-Host "$($i+1). $($regions[$i].name)"
                        }
                        Write-Host "4. All regions"
                        Write-Host "5. Back to previous menu"

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
                    }
                    "2" {
                        Write-Host "`nSelect the VM you want to remove:"
                        $vmList = @()
                        for ($i = 0; $i -lt $regions.Count; $i++) {
                            $vmList += [PSCustomObject]@{
                                Index = ($vmList.Count + 1)
                                VM = $regions[$i].vm1
                                ResourceGroup = $regions[$i].resourceGroup
                            }
                            $vmList += [PSCustomObject]@{
                                Index = ($vmList.Count + 1)
                                VM = $regions[$i].vm2
                                ResourceGroup = $regions[$i].resourceGroup
                            }
                            Write-Host "$($vmList[-2].Index). $($regions[$i].vm1) ($($regions[$i].name))"
                            Write-Host "$($vmList[-1].Index). $($regions[$i].vm2) ($($regions[$i].name))"
                        }
                        Write-Host "$($vmList.Count + 1). Back to previous menu"

                        $vmChoice = Read-Host "Enter your choice (1-$($vmList.Count + 1))"

                        if ($vmChoice -eq $($vmList.Count + 1)) {
                            break
                        }
                        elseif ($vmChoice -in 1..$vmList.Count) {
                            $selectedVM = $vmList[$vmChoice - 1]
                            Remove-VM -resourceGroup $selectedVM.ResourceGroup -vmName $selectedVM.VM
                        }
                        else {
                            Write-Host "Invalid choice. Please try again."
                        }
                    }
                    "3" { break }
                    default { Write-Host "Invalid choice. Please try again." }
                }

                if ($removalChoice -ne "3") {
                    Write-Host "Resource removal completed."
                    Read-Host "Press Enter to continue..."
                }
            } while ($removalChoice -ne "3")
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
        "6" { break }
        default { Write-Host "Invalid choice. Please try again." }
    }
} while ($action -ne "6")

Write-Host "Script execution completed."
Write-Host "Remember to update DNS settings within each VM's operating system if necessary."
