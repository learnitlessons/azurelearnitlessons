#================================
# 1. BASIC SETTINGS
#================================

$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with a secure password
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force
$resourceGroup = "rg-lit-PKILab"
$locationUKSouth = "uksouth"
$locationUKWest = "ukwest"
$addressPrefixUKSouth = "10.0.0.0/16"
$addressPrefixUKWest = "10.1.0.0/16"
$domainName = "learnitlessons.com"
$netbiosName = "LIT"

#================================
# 2. FUNCTION DEFINITIONS
#================================

# Function to create a VM with static IP
function Create-VMWithStaticIP {
    param (
        [string]$vmName,
        [string]$staticIP,
        [string]$vmSize,
        [string]$publisher,
        [string]$offer,
        [string]$skus,
        [string]$location,
        [string]$vnetName
    )

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroup -Name $vnetName
    $pip = New-AzPublicIpAddress -Name "$vmName-pip" -ResourceGroupName $resourceGroup -Location $location -AllocationMethod Static -Sku Standard
    $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress $staticIP
    $nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
    Set-AzNetworkInterface -NetworkInterface $nic
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $location -Name "$vmName-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
    $nic.NetworkSecurityGroup = $nsg
    Set-AzNetworkInterface -NetworkInterface $nic
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize | 
        Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential (New-Object PSCredential($user, $securePass)) | 
        Set-AzVMSourceImage -PublisherName $publisher -Offer $offer -Skus $skus -Version "latest" | 
        Add-AzVMNetworkInterface -Id $nic.Id | 
        Set-AzVMBootDiagnostic -Disable |
        Set-AzVMOSDisk -CreateOption FromImage -StorageAccountType StandardSSD_LRS
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig

    # Configure pagefile
    $script = @"
    `$computerSystem = Get-WmiObject -Class Win32_ComputerSystem -EnableAllPrivileges
    if (-not `$computerSystem.AutomaticManagedPagefile) {
        `$computerSystem.AutomaticManagedPagefile = `$true
        `$computerSystem.Put()
    }
    Restart-Computer -Force
"@
    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

# Function to install ADDS and promote DC
function Install-ADDSAndPromoteDC {
    param (
        [string]$vmName
    )

    $script = @"
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
    Install-ADDSForest ``
        -CreateDnsDelegation:`$false ``
        -DatabasePath 'C:\Windows\NTDS' ``
        -DomainMode 'WinThreshold' ``
        -DomainName '$domainName' ``
        -DomainNetbiosName '$netbiosName' ``
        -ForestMode 'WinThreshold' ``
        -InstallDns:`$true ``
        -LogPath 'C:\Windows\NTDS' ``
        -NoRebootOnCompletion:`$false ``
        -SysvolPath 'C:\Windows\SYSVOL' ``
        -Force:`$true ``
        -SafeModeAdministratorPassword `$securePassword
"@
    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

# Function to join a VM to the domain
function Join-Domain {
    param (
        [string]$vmName
    )

    $script = @"
    `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
    `$credential = New-Object System.Management.Automation.PSCredential ('$domainName\$user', `$securePassword)
    Add-Computer -DomainName $domainName -Credential `$credential -Restart -Force
"@
    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

#================================
# 3. MAIN DEPLOYMENT
#================================

# Create Resource Group
New-AzResourceGroup -Name $resourceGroup -Location $locationUKSouth -Force

# Create Virtual Networks
$vnetUKSouth = New-AzVirtualNetwork -ResourceGroupName $resourceGroup -Location $locationUKSouth -Name "vnet-pkilab-uksouth" -AddressPrefix $addressPrefixUKSouth -Subnet (New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix ($addressPrefixUKSouth -replace '0/16', '0/24'))
$vnetUKWest = New-AzVirtualNetwork -ResourceGroupName $resourceGroup -Location $locationUKWest -Name "vnet-pkilab-ukwest" -AddressPrefix $addressPrefixUKWest -Subnet (New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix ($addressPrefixUKWest -replace '0/16', '0/24'))

# Set up VNet peering
$peering1 = Add-AzVirtualNetworkPeering -Name "UKSouthToUKWest" -VirtualNetwork $vnetUKSouth -RemoteVirtualNetworkId $vnetUKWest.Id -AllowForwardedTraffic
$peering2 = Add-AzVirtualNetworkPeering -Name "UKWestToUKSouth" -VirtualNetwork $vnetUKWest -RemoteVirtualNetworkId $vnetUKSouth.Id -AllowForwardedTraffic

# Create VMs
Create-VMWithStaticIP -vmName "lit-dc" -staticIP "10.0.0.4" -vmSize "Standard_B2s" -publisher "MicrosoftWindowsServer" -offer "WindowsServer" -skus "2022-datacenter-azure-edition" -location $locationUKSouth -vnetName "vnet-pkilab-uksouth"
Create-VMWithStaticIP -vmName "lit-rca" -staticIP "10.1.0.4" -vmSize "Standard_B2s" -publisher "MicrosoftWindowsServer" -offer "WindowsServer" -skus "2022-datacenter-azure-edition" -location $locationUKWest -vnetName "vnet-pkilab-ukwest"
Create-VMWithStaticIP -vmName "lit-ca1" -staticIP "10.0.0.5" -vmSize "Standard_B2s" -publisher "MicrosoftWindowsServer" -offer "WindowsServer" -skus "2022-datacenter-azure-edition" -location $locationUKSouth -vnetName "vnet-pkilab-uksouth"
Create-VMWithStaticIP -vmName "lit-ca2" -staticIP "10.0.0.6" -vmSize "Standard_B2s" -publisher "MicrosoftWindowsServer" -offer "WindowsServer" -skus "2022-datacenter-azure-edition" -location $locationUKSouth -vnetName "vnet-pkilab-uksouth"
Create-VMWithStaticIP -vmName "lit-win10" -staticIP "10.0.0.7" -vmSize "Standard_B2s" -publisher "MicrosoftWindowsDesktop" -offer "Windows-10" -skus "win10-21h2-pro" -location $locationUKSouth -vnetName "vnet-pkilab-uksouth"

# Install ADDS and promote DC
Install-ADDSAndPromoteDC -vmName "lit-dc"

# Wait for AD to be ready
Start-Sleep -Seconds 300

# Join other VMs to the domain (except RCA)
Join-Domain -vmName "lit-ca1"
Join-Domain -vmName "lit-ca2"
Join-Domain -vmName "lit-win10"

# Configure DNS for RCA to use DC
$rcaNic = Get-AzNetworkInterface -ResourceGroupName $resourceGroup -Name "lit-rca-nic"
$rcaNic.DnsSettings.DnsServers.Add("10.0.0.4")
Set-AzNetworkInterface -NetworkInterface $rcaNic

#================================
# 4. OUTPUT CONNECTION INFO
#================================

Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | ForEach-Object { 
    Write-Output "VM: $($_.Name.Replace('-pip','')) Public IP: $($_.IpAddress) RDP: mstsc /v:$($_.IpAddress) /u:$user" 
}

Write-Host "Script execution completed."
Write-Host "Remember to configure PKI roles on the appropriate VMs after deployment."
Write-Host "Note: The RCA (lit-rca) is not domain-joined but can communicate with the domain through VNet peering."
