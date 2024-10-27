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
        
        # Using Standard_B2s for 4GB RAM and 2 vCPUs
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B2s" | 
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
