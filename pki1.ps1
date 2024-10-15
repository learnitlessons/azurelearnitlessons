# Azure PKI Lab Setup Script

# Basic settings
$location = "ukwest"
$resourceGroup = "rg-lit-PKILab"
$addressPrefix = "10.0.0.0/16"
$subnetPrefix = "10.0.0.0/24"
$domainName = "learnitlessons.com"
$netbiosName = "LIT"

# Predefined credentials
$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with a secure password
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($user, $securePass)

# VM configurations
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

# Function to create VMs
function Create-VM {
    param (
        [string]$vmName,
        [string]$vmSize,
        [string]$staticIP,
        [string]$role
    )

    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $resourceGroup -Location $location -SubnetId $vnet.Subnets[0].Id -PrivateIpAddress $staticIP
    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id

    if ($role -eq "Client") {
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsDesktop" -Offer "Windows-10" -Skus "20h2-pro" -Version "latest"
    } else {
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-Datacenter-Azure-Edition" -Version "latest"
    }

    $vmConfig = Set-AzVMOSDisk -VM $vmConfig -CreateOption FromImage -StorageAccountType StandardSSD_LRS

    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig
}

# Function to install ADDS and promote to DC
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

# Function to create OUs and users
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

# Function to configure DNS
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

# Function to verify DNS configuration
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

# Function to join VM to domain
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



# Create resource group
New-AzResourceGroup -Name $resourceGroup -Location $location

# Create virtual network
$vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroup -Location $location -Name "vnet-pkilab" -AddressPrefix $addressPrefix
Add-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix $subnetPrefix -VirtualNetwork $vnet
$vnet | Set-AzVirtualNetwork

# Create VMs
foreach ($vm in $vmConfigs) {
    Create-VM -vmName $vm.name -vmSize $vm.size -staticIP $vm.staticIP -role $vm.role
}

# Install ADDS and promote to DC
Install-ADDS -vmName "lit-dc1"

# Wait for DC to be ready (you might need to adjust the wait time)
Write-Host "Waiting for DC to be ready..."
Start-Sleep -Seconds 300

# Create OUs and users
Write-Host "Creating OUs, users, and groups..."
Create-OUsAndUsers -vmName "lit-dc1"

# Configure DNS on all VMs
foreach ($vm in $vmConfigs) {
    if ($vm.name -ne "lit-dc1") {
        Write-Host "Configuring DNS for $($vm.name)..."
        Configure-DNS -vmName $vm.name -dnsIP $vmConfigs[0].staticIP
    }
}

# Verify DNS configuration and join domain for CA1, CA2, and Client
$vmsToJoin = @("lit-ca1", "lit-ca2", "lit-client")
foreach ($vmName in $vmsToJoin) {
    $dnsConfigured = $false
    $retryCount = 0
    $maxRetries = 3

    while (-not $dnsConfigured -and $retryCount -lt $maxRetries) {
        Write-Host "Verifying DNS configuration for $vmName..."
        $dnsConfigured = Verify-DNSConfiguration -vmName $vmName -expectedDNS $vmConfigs[0].staticIP
        
        if (-not $dnsConfigured) {
            Write-Host "DNS not correctly configured for $vmName. Retrying configuration..."
            Configure-DNS -vmName $vmName -dnsIP $vmConfigs[0].staticIP
            Start-Sleep -Seconds 30
            $retryCount++
        }
    }

    if ($dnsConfigured) {
        Write-Host "Joining $vmName to domain..."
        Join-Domain -vmName $vmName
    } else {
        Write-Host "Failed to configure DNS correctly for $vmName after $maxRetries attempts. Skipping domain join."
    }
}

# Configure DNS for RCA (standalone)
Write-Host "Configuring DNS for lit-rca..."
Configure-DNS -vmName "lit-rca" -dnsIP $vmConfigs[0].staticIP

Write-Host "PKI Lab setup completed. Remember to configure the CA and RCA roles manually on the respective VMs."
