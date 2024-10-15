#================================
# 1. BASIC SETTINGS
#================================
$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with a secure password
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force
$resourceGroup = "rg-lit-PKILab"
$domainName = "learnitlessons.com"
$netbiosName = "LIT"

#================================
# 2. VM CONFIGURATIONS
#================================
$vms = @(
    @{
        name = "lit-dc"
        location = "uksouth"
        staticIP = "10.0.0.4"
        role = "DC"
    },
    @{
        name = "lit-rca"
        location = "ukwest"
        staticIP = "10.1.0.4"
        role = "RCA"
    },
    @{
        name = "lit-ca1"
        location = "uksouth"
        staticIP = "10.0.0.5"
        role = "CA"
    },
    @{
        name = "lit-ca2"
        location = "uksouth"
        staticIP = "10.0.0.6"
        role = "CA"
    },
    @{
        name = "lit-win10"
        location = "uksouth"
        staticIP = "10.0.0.7"
        role = "Client"
    }
)

#================================
# 3. FUNCTIONS
#================================

# Function to create a VM
function Create-VM {
    param (
        [hashtable]$vmConfig
    )

    $vnetName = "vnet-$($vmConfig.location)"
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
    if (-not $vnet) {
        $addressPrefix = if ($vmConfig.location -eq "uksouth") { "10.0.0.0/16" } else { "10.1.0.0/16" }
        $vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroup -Location $vmConfig.location -Name $vnetName -AddressPrefix $addressPrefix
        $vnet | Add-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix ($addressPrefix -replace '0/16', '0/24') | Set-AzVirtualNetwork
    }

    $pip = New-AzPublicIpAddress -Name "$($vmConfig.name)-pip" -ResourceGroupName $resourceGroup -Location $vmConfig.location -AllocationMethod Static -Sku Standard
    $nic = New-AzNetworkInterface -Name "$($vmConfig.name)-nic" -ResourceGroupName $resourceGroup -Location $vmConfig.location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress $vmConfig.staticIP
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $vmConfig.location -Name "$($vmConfig.name)-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
    $nic.NetworkSecurityGroup = $nsg
    $nic | Set-AzNetworkInterface

    $vmSize = if ($vmConfig.role -eq "Client") { "Standard_B2s" } else { "Standard_B2ms" }
    $imageOffer = if ($vmConfig.role -eq "Client") { "Windows-10" } else { "WindowsServer" }
    $imageSku = if ($vmConfig.role -eq "Client") { "win10-21h2-pro" } else { "2022-Datacenter" }

    $vmConfig = New-AzVMConfig -VMName $vmConfig.name -VMSize $vmSize | 
        Set-AzVMOperatingSystem -Windows -ComputerName $vmConfig.name -Credential (New-Object PSCredential($user, $securePass)) | 
        Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer $imageOffer -Skus $imageSku -Version "latest" | 
        Add-AzVMNetworkInterface -Id $nic.Id | 
        Set-AzVMBootDiagnostic -Disable

    New-AzVM -ResourceGroupName $resourceGroup -Location $vmConfig.location -VM $vmConfig
}

# Function to configure DNS and join domain
function Configure-VMNetwork {
    param (
        [hashtable]$vmConfig
    )

    $script = @"
    `$adapter = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' }
    Set-DnsClientServerAddress -InterfaceIndex `$adapter.InterfaceIndex -ServerAddresses ("10.0.0.4")
    if ("$($vmConfig.role)" -ne "DC" -and "$($vmConfig.role)" -ne "RCA") {
        `$securePassword = ConvertTo-SecureString "$pass" -AsPlainText -Force
        `$credential = New-Object System.Management.Automation.PSCredential ("$user@$domainName", `$securePassword)
        Add-Computer -DomainName "$domainName" -Credential `$credential -Restart -Force
    }
"@

    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmConfig.name -CommandId 'RunPowerShellScript' -ScriptString $script
}

# Function to install ADDS and promote to DC
function Install-ADDS {
    param (
        [hashtable]$vmConfig
    )

    $script = @"
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    `$securePassword = ConvertTo-SecureString "$pass" -AsPlainText -Force
    Install-ADDSForest -DomainName "$domainName" -DomainNetbiosName "$netbiosName" -InstallDns -Force -SafeModeAdministratorPassword `$securePassword
"@

    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmConfig.name -CommandId 'RunPowerShellScript' -ScriptString $script
}

#================================
# 4. MAIN SCRIPT
#================================

# Create Resource Group
New-AzResourceGroup -Name $resourceGroup -Location "centralindia" -Force

# Create VMs
foreach ($vm in $vms) {
    Write-Host "Creating VM: $($vm.name)"
    Create-VM -vmConfig $vm
}

# Configure DNS and join domain
foreach ($vm in $vms) {
    Write-Host "Configuring network for VM: $($vm.name)"
    Configure-VMNetwork -vmConfig $vm
}

# Install ADDS and promote to DC
$dcVM = $vms | Where-Object { $_.role -eq "DC" }
Write-Host "Installing ADDS on $($dcVM.name)"
Install-ADDS -vmConfig $dcVM

Write-Host "Deployment completed. Please check the Azure portal for the status of your resources."
