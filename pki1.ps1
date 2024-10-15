# Azure PKI Lab Setup Script

#================================
# 1. BASIC SETTINGS
#================================
$location = "uksouth"
$resourceGroup = "rg-lit-PKILab"
$addressPrefix = "10.0.0.0/16"
$subnetPrefix = "10.0.0.0/24"
$domainName = "learnitlessons.com"
$netbiosName = "LIT"

#================================
# 2. PREDEFINED CREDENTIALS
#================================
$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with a secure password
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($user, $securePass)

#================================
# 3. VM CONFIGURATIONS
#================================
$vmConfigs = @(
    @{
        name = "lit-dc1"
        size = "Standard_B1s"
        staticIP = "10.0.0.4"
        role = "DC"
    },
    @{
        name = "lit-ca1"
        size = "Standard_B1s"
        staticIP = "10.0.0.5"
        role = "CA"
    },
    @{
        name = "lit-ca2"
        size = "Standard_B1s"
        staticIP = "10.0.0.6"
        role = "CA"
    },
    @{
        name = "lit-rca"
        size = "Standard_B1s"
        staticIP = "10.0.0.7"
        role = "RCA"
    },
    @{
        name = "lit-client"
        size = "Standard_B1s"
        staticIP = "10.0.0.8"
        role = "Client"
    }
)

#================================
# 4. FUNCTION: CREATE VM
#================================
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

#================================
# 5. FUNCTION: INSTALL ADDS
#================================
function Install-ADDS {
    param (
        [string]$vmName
    )

    $script = @"
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    `$securePass = ConvertTo-SecureString "$pass" -AsPlainText -Force
    Install-ADDSForest ``
        -CreateDnsDelegation:`$false ``
        -DatabasePath "C:\Windows\NTDS" ``
        -DomainMode "WinThreshold" ``
        -DomainName "$domainName" ``
        -DomainNetbiosName "$netbiosName" ``
        -ForestMode "WinThreshold" ``
        -InstallDns:`$true ``
        -LogPath "C:\Windows\NTDS" ``
        -NoRebootOnCompletion:`$false ``
        -SysvolPath "C:\Windows\SYSVOL" ``
        -SafeModeAdministratorPassword `$securePass ``
        -Force:`$true
"@

    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

#================================
# 6. FUNCTION: CREATE OUs AND USERS
#================================
function Create-OUsAndUsers {
    param (
        [string]$vmName
    )

    $script = @"
    # Create OUs
    New-ADOrganizationalUnit -Name "LIT_Computers" -Path "DC=learnitlessons,DC=com"
    New-ADOrganizationalUnit -Name "LIT_Users" -Path "DC=learnitlessons,DC=com"

    # Create users
    `$users = @(
        @{Name="John Doe"; Username="jdoe"; Department="IT"},
        @{Name="Jane Smith"; Username="jsmith"; Department="HR"},
        @{Name="Bob Johnson"; Username="bjohnson"; Department="Finance"},
        @{Name="Alice Brown"; Username="abrown"; Department="Marketing"},
        @{Name="Charlie Wilson"; Username="cwilson"; Department="Sales"}
    )

    foreach (`$user in `$users) {
        New-ADUser -Name `$user.Name ``
                   -SamAccountName `$user.Username ``
                   -UserPrincipalName "`$(`$user.Username)@$domainName" ``
                   -Path "OU=LIT_Users,DC=learnitlessons,DC=com" ``
                   -AccountPassword (ConvertTo-SecureString "$pass" -AsPlainText -Force) ``
                   -Department `$user.Department ``
                   -Enabled `$true

        Write-Output "Created user: `$(`$user.Name)"
    }

    # Create groups
    `$groups = @("IT", "HR", "Finance", "Marketing", "Sales")
    foreach (`$group in `$groups) {
        New-ADGroup -Name `$group -GroupScope Global -Path "OU=LIT_Users,DC=learnitlessons,DC=com"
        Write-Output "Created group: `$group"
    }

    # Add users to their respective groups
    foreach (`$user in `$users) {
        Add-ADGroupMember -Identity `$user.Department -Members `$user.Username
        Write-Output "Added `$(`$user.Name) to `$(`$user.Department) group"
    }
"@

    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

#================================
# 7. FUNCTION: CONFIGURE DNS
#================================
function Configure-DNS {
    param (
        [string]$vmName,
        [string]$dnsIP
    )

    $script = @"
    `$adapters = Get-NetAdapter | Where-Object {`$_.Status -eq "Up"}
    foreach (`$adapter in `$adapters) {
        Set-DnsClientServerAddress -InterfaceIndex `$adapter.InterfaceIndex -ServerAddresses "$dnsIP"
    }
    ipconfig /flushdns
    Write-Output "DNS configuration set to $dnsIP"
    Get-DnsClientServerAddress -AddressFamily IPv4 | Format-Table -AutoSize
"@

    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

#================================
# 8. FUNCTION: VERIFY DNS CONFIGURATION
#================================
function Verify-DNSConfiguration {
    param (
        [string]$vmName,
        [string]$expectedDNS
    )

    $script = @"
    `$dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {`$_.ServerAddresses -contains "$expectedDNS"}
    if (`$dnsServers) {
        Write-Output "DNS is correctly configured to $expectedDNS"
        return `$true
    } else {
        Write-Output "DNS is not correctly configured. Current configuration:"
        Get-DnsClientServerAddress -AddressFamily IPv4 | Format-Table -AutoSize
        return `$false
    }
"@

    $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
    return $result.Value[0].Message -match "DNS is correctly configured"
}

#================================
# 9. FUNCTION: JOIN DOMAIN
#================================
function Join-Domain {
    param (
        [string]$vmName
    )

    $script = @"
    `$securePass = ConvertTo-SecureString "$pass" -AsPlainText -Force
    `$cred = New-Object System.Management.Automation.PSCredential ("$domainName\$user", `$securePass)
    Add-Computer -DomainName $domainName -Credential `$cred -Restart -Force
"@

    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}
# Azure PKI Lab Setup Script



#================================
# 10. MAIN SCRIPT
#================================

# Function to create virtual network with retry logic
function Create-VirtualNetworkWithRetry {
    $retryCount = 0
    $maxRetries = 5
    $retryDelay = 30

    while ($retryCount -lt $maxRetries) {
        try {
            $vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroup -Location $location -Name "vnet-pkilab" -AddressPrefix $addressPrefix
            $subnetConfig = Add-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix $subnetPrefix -VirtualNetwork $vnet
            $vnet = $vnet | Set-AzVirtualNetwork

            # Verify the virtual network was created successfully
            $createdVnet = Get-AzVirtualNetwork -Name "vnet-pkilab" -ResourceGroupName $resourceGroup -ErrorAction Stop
            if ($createdVnet) {
                Write-Host "Virtual network created and verified successfully."
                return $createdVnet
            } else {
                throw "Virtual network not found after creation attempt."
            }
        }
        catch {
            Write-Host "Failed to create or verify virtual network. Error: $_"
            Write-Host "Retrying in $retryDelay seconds..."
            Start-Sleep -Seconds $retryDelay
            $retryCount++
        }
    }

    throw "Failed to create virtual network after $maxRetries attempts."
}

# Create resource group
New-AzResourceGroup -Name $resourceGroup -Location $location -Force

# Create virtual network with retry
try {
    $vnet = Create-VirtualNetworkWithRetry
    Write-Host "Virtual network created successfully."
}
catch {
    Write-Host "Failed to create virtual network. Exiting script."
    return
}

# Verify subnet configuration
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "default" -VirtualNetwork $vnet
if (-not $subnet) {
    Write-Host "Subnet 'default' not found in the virtual network. Creating subnet..."
    $subnet = Add-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix $subnetPrefix -VirtualNetwork $vnet
    $vnet = $vnet | Set-AzVirtualNetwork
    $subnet = Get-AzVirtualNetworkSubnetConfig -Name "default" -VirtualNetwork $vnet
}

if (-not $subnet) {
    Write-Host "Failed to create or retrieve subnet. Exiting script."
    return
}

# Create VMs
foreach ($vm in $vmConfigs) {
    try {
        Write-Host "Creating VM $($vm.name)..."
        Create-VM -vmName $vm.name -vmSize $vm.size -staticIP $vm.staticIP -role $vm.role
        Write-Host "VM $($vm.name) created successfully."
    }
    catch {
        Write-Host "Failed to create VM $($vm.name). Error: $_"
    }
}

# Install ADDS and promote to DC
try {
    Install-ADDS -vmName "lit-dc1"
    Write-Host "ADDS installed and promoted to DC successfully."
}
catch {
    Write-Host "Failed to install ADDS and promote to DC. Error: $_"
    return
}

# Wait for DC to be ready (you might need to adjust the wait time)
Write-Host "Waiting for DC to be ready..."
Start-Sleep -Seconds 300

# Create OUs and users
try {
    Write-Host "Creating OUs, users, and groups..."
    Create-OUsAndUsers -vmName "lit-dc1"
    Write-Host "OUs, users, and groups created successfully."
}
catch {
    Write-Host "Failed to create OUs and users. Error: $_"
}

# Configure DNS on all VMs
foreach ($vm in $vmConfigs) {
    if ($vm.name -ne "lit-dc1") {
        try {
            Write-Host "Configuring DNS for $($vm.name)..."
            Configure-DNS -vmName $vm.name -dnsIP $vmConfigs[0].staticIP
            Write-Host "DNS configured successfully for $($vm.name)."
        }
        catch {
            Write-Host "Failed to configure DNS for $($vm.name). Error: $_"
        }
    }
}

# Verify DNS configuration and join domain for CA1, CA2, and Client
$vmsToJoin = @("lit-ca1", "lit-ca2", "lit-client")
foreach ($vmName in $vmsToJoin) {
    $dnsConfigured = $false
    $retryCount = 0
    $maxRetries = 3

    while (-not $dnsConfigured -and $retryCount -lt $maxRetries) {
        try {
            Write-Host "Verifying DNS configuration for $vmName..."
            $dnsConfigured = Verify-DNSConfiguration -vmName $vmName -expectedDNS $vmConfigs[0].staticIP
            
            if (-not $dnsConfigured) {
                Write-Host "DNS not correctly configured for $vmName. Retrying configuration..."
                Configure-DNS -vmName $vmName -dnsIP $vmConfigs[0].staticIP
                Start-Sleep -Seconds 30
                $retryCount++
            }
        }
        catch {
            Write-Host "Error verifying or configuring DNS for $vmName. Retrying..."
            $retryCount++
            Start-Sleep -Seconds 30
        }
    }

    if ($dnsConfigured) {
        try {
            Write-Host "Joining $vmName to domain..."
            Join-Domain -vmName $vmName
            Write-Host "$vmName joined to domain successfully."
        }
        catch {
            Write-Host "Failed to join $vmName to domain. Error: $_"
        }
    } else {
        Write-Host "Failed to configure DNS correctly for $vmName after $maxRetries attempts. Skipping domain join."
    }
}

# Configure DNS for RCA (standalone)
try {
    Write-Host "Configuring DNS for lit-rca..."
    Configure-DNS -vmName "lit-rca" -dnsIP $vmConfigs[0].staticIP
    Write-Host "DNS configured successfully for lit-rca."
}
catch {
    Write-Host "Failed to configure DNS for lit-rca. Error: $_"
}

Write-Host "PKI Lab setup completed. Remember to configure the CA and RCA roles manually on the respective VMs."
