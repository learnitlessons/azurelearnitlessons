# Function to create VMs
function Create-VM {
    param (
        [string]$vmName,
        [string]$vmSize,
        [string]$staticIP,
        [string]$role
    )

    $subnet = Get-AzVirtualNetworkSubnetConfig -Name "default" -VirtualNetwork $vnet
    $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $subnet.Id -PrivateIpAddress $staticIP

    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id

    if ($role -eq "Client") {
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsDesktop" -Offer "Windows-10" -Skus "20h2-pro" -Version "latest"
    } else {
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-Datacenter-Azure-Edition" -Version "latest"
    }

    $vmConfig = Set-AzVMOSDisk -VM $vmConfig -CreateOption FromImage -StorageAccountType StandardSSD_LRS
    
    # Disable boot diagnostics
    $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable

    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig
}
