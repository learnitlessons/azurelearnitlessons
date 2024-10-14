# Azure AD Multi-Region VM Creation Script

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

    # Function to create a VM with static IP and Basic SSD
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

        # Create a configuration for the OS disk with Basic SSD
        $osDiskConfig = New-AzDiskConfig -Location $location -CreateOption FromImage -SkuName StandardSSD_LRS

        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B1s" | 
            Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential (New-Object PSCredential($user, $securePass)) | 
            Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | 
            Add-AzVMNetworkInterface -Id $nic.Id | 
            Set-AzVMOSDisk -DiskSizeInGB 128 -CreateOption FromImage -StorageAccountType StandardSSD_LRS |
            Set-AzVMBootDiagnostic -Disable

        New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig
    }

    # Create VMs
    Create-VMWithStaticIP -vmName $vm1Name -staticIP $vm1StaticIP
    Create-VMWithStaticIP -vmName $vm2Name -staticIP $vm2StaticIP

    # Output connection information
    Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | ForEach-Object { 
        Write-Output "VM: $($_.Name.Replace('-pip','')) Public IP: $($_.IpAddress) RDP: mstsc /v:$($_.IpAddress) /u:$user" 
    }
}

# Region definitions
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
    }
)

# Main script
do {
    Write-Host "`nSelect the region(s) you want to create VMs in:"
    for ($i = 0; $i -lt $regions.Count; $i++) {
        Write-Host "$($i+1). $($regions[$i].name)"
    }
    Write-Host "4. All regions"
    Write-Host "5. Exit"

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

Write-Host "Script execution completed."
