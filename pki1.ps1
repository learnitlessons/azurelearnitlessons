#================================
# 1. BASIC SETTINGS
#================================
$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with a secure password
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force
$resourceGroup = "rg-lit-PKILab"
$location = "centralindia"
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

# Function to create a VM with static IP
function Create-VMWithStaticIP {
    param (
        [string]$vmName,
        [string]$location,
        [string]$staticIP,
        [string]$role
    )

    $vnetName = "vnet-$location"
    $addressPrefix = ($staticIP -replace '\.\d+$', '.0/24')
    
    # Create or get existing VNet
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
    if (-not $vnet) {
        $vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroup -Location $location -Name $vnetName -AddressPrefix $addressPrefix
        $vnet | Set-AzVirtualNetwork
    }

    # Create NIC with static IP
    $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $vnet.Subnets[0].Id -PrivateIpAddress $staticIP

    # Create NSG and allow RDP
    $nsgRuleRDP = New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $location -Name "$vmName-nsg" -SecurityRules $nsgRuleRDP
    $nic.NetworkSecurityGroup = $nsg
    $nic | Set-AzNetworkInterface

    # Create VM
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B2s"
    $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential (New-Object PSCredential($user, $securePass))
    $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
    
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig

    # Configure auto-managed pagefile
    $script = @"
    `$computerSystem = Get-WmiObject -Class Win32_ComputerSystem -EnableAllPrivileges
    `$computerSystem.AutomaticManagedPagefile = `$true
    `$computerSystem.Put()
"@
    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

# Function to install ADDS and promote to DC
function Install-ADDS {
    param (
        [string]$vmName
    )

    $script = @"
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
    Install-ADDSForest -CreateDnsDelegation:`$false -DatabasePath "C:\Windows\NTDS" -DomainMode "WinThreshold" -DomainName "$domainName" -DomainNetbiosName "$netbiosName" -ForestMode "WinThreshold" -InstallDns:`$true -LogPath "C:\Windows\NTDS" -NoRebootOnCompletion:`$false -SysvolPath "C:\Windows\SYSVOL" -Force:`$true -SafeModeAdministratorPassword `$securePassword
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
    `$credential = New-Object System.Management.Automation.PSCredential ("$domainName\$user", `$securePassword)
    Add-Computer -DomainName $domainName -Credential `$credential -Restart -Force
"@
    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

# Function to configure DNS
function Configure-DNS {
    param (
        [string]$vmName,
        [string]$dnsIP
    )

    $script = @"
    `$adapter = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' }
    Set-DnsClientServerAddress -InterfaceIndex `$adapter.ifIndex -ServerAddresses $dnsIP
"@
    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

#================================
# 4. MAIN SCRIPT
#================================

# Create Resource Group
New-AzResourceGroup -Name $resourceGroup -Location $location -Force

# Create VMs
foreach ($vm in $vms) {
    Create-VMWithStaticIP -vmName $vm.name -location $vm.location -staticIP $vm.staticIP -role $vm.role
}

# Install ADDS and promote to DC
Install-ADDS -vmName "lit-dc"

# Configure DNS for all VMs
foreach ($vm in $vms) {
    if ($vm.name -ne "lit-dc") {
        Configure-DNS -vmName $vm.name -dnsIP "10.0.0.4"
    }
}

# Join domain for CA and Win10 VMs
Join-Domain -vmName "lit-ca1"
Join-Domain -vmName "lit-ca2"
Join-Domain -vmName "lit-win10"

Write-Host "PKI Lab setup completed. Remember to configure the Certificate Services roles manually on the CA servers."
