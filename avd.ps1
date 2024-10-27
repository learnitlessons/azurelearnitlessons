# Variables for naming
$SubscriptionId = (Get-AzContext).Subscription.Id
$Location = "uksouth"
$ResourceGroup = "rg-avd-prod4"
$WorkspaceName = "ws-avd-prod4"
$HostPoolName = "hp-avd-prod4"
$AppGroupName = "ag-desktop-prod4"
$VNetName = "vnet-avd-prod4"
$SubnetName = "snet-avd-prod4"
$NSGName = "nsg-avd-prod4"
$VMPrefix = "vm-avd4"

# Prerequisites Check
Write-Host "Checking and setting up prerequisites..." -ForegroundColor Green

# 1. Check Azure PowerShell Modules
$requiredModules = @(
    "Az.DesktopVirtualization",
    "Az.Network",
    "Az.Compute",
    "Az.Resources"
)

foreach ($module in $requiredModules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing $module module..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber
    }
}

# 2. Register Required Resource Providers
Write-Host "Registering required resource providers..." -ForegroundColor Green
Register-AzResourceProvider -ProviderNamespace "Microsoft.DesktopVirtualization"
Register-AzResourceProvider -ProviderNamespace "Microsoft.Network"
Register-AzResourceProvider -ProviderNamespace "Microsoft.Compute"

# Wait for registration to complete
do {
    $rp = Get-AzResourceProvider -ProviderNamespace "Microsoft.DesktopVirtualization"
    Write-Host "Waiting for resource provider registration..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
} while ($rp.RegistrationState -ne "Registered")

# Create Resource Group
Write-Host "Creating Resource Group..." -ForegroundColor Green
New-AzResourceGroup -Name $ResourceGroup -Location $Location -Force

# Network Setup
Write-Host "Setting up networking components..." -ForegroundColor Green

# Create NSG with RDP rule
$rdpRule = New-AzNetworkSecurityRuleConfig -Name 'Allow-RDP' -Description 'Allow RDP' `
    -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
    -SourceAddressPrefix Internet -SourcePortRange * `
    -DestinationAddressPrefix * -DestinationPortRange 3389

$nsg = New-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $ResourceGroup `
    -Location $Location -SecurityRules $rdpRule

# Create VNet and Subnet
$subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.1.0/24" -NetworkSecurityGroup $nsg
$vnet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Location $Location `
    -Name $VNetName -AddressPrefix "10.0.0.0/16" -Subnet $subnet

# Create Host Pool
Write-Host "Creating Host Pool..." -ForegroundColor Green
$hostPool = New-AzWvdHostPool -ResourceGroupName $ResourceGroup `
    -Name $HostPoolName `
    -Location $Location `
    -HostPoolType Pooled `
    -LoadBalancerType BreadthFirst `
    -PreferredAppGroupType Desktop `
    -ValidationEnvironment:$false `
    -StartVMOnConnect:$true

# Get Host Pool Registration Token
$Token = New-AzWvdRegistrationInfo -ResourceGroupName $ResourceGroup `
    -HostPoolName $HostPoolName `
    -ExpirationTime $((get-date).ToUniversalTime().AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ'))

# Create Application Group
Write-Host "Creating Application Group..." -ForegroundColor Green
$appGroup = New-AzWvdApplicationGroup -ResourceGroupName $ResourceGroup `
    -Name $AppGroupName `
    -Location $Location `
    -HostPoolArmPath $hostPool.Id `
    -ApplicationGroupType Desktop

# Create Workspace
Write-Host "Creating Workspace..." -ForegroundColor Green
$workspace = New-AzWvdWorkspace -ResourceGroupName $ResourceGroup `
    -Name $WorkspaceName `
    -Location $Location

# Associate Application Group with Workspace
Write-Host "Associating Application Group with Workspace..." -ForegroundColor Green
Register-AzWvdApplicationGroup -ResourceGroupName $ResourceGroup `
    -WorkspaceName $WorkspaceName `
    -ApplicationGroupPath $appGroup.Id

# Create Session Host VM
Write-Host "Creating Session Host VM..." -ForegroundColor Green
$VMSize = "Standard_D2s_v5"
$VMName = "$VMPrefix-1"
$AdminUsername = "localadmin"
$AdminPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# Create public IP
$pipConfig = @{
    Name = "$VMName-pip"
    ResourceGroupName = $ResourceGroup
    Location = $Location
    Sku = "Standard"
    AllocationMethod = "Static"
}
$pip = New-AzPublicIpAddress @pipConfig

# Create NIC
$nicConfig = @{
    Name = "$VMName-nic"
    ResourceGroupName = $ResourceGroup
    Location = $Location
    SubnetId = $vnet.Subnets[0].Id
    PublicIpAddressId = $pip.Id
    NetworkSecurityGroupId = $nsg.Id
}
$nic = New-AzNetworkInterface @nicConfig

# Create VM Configuration
$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $VMName `
    -Credential (New-Object PSCredential ($AdminUsername, $AdminPassword)) `
    -ProvisionVMAgent -EnableAutoUpdate

$vmConfig = Set-AzVMSourceImage -VM $vmConfig `
    -PublisherName 'MicrosoftWindowsDesktop' `
    -Offer 'Windows-10' `
    -Skus 'win10-22h2-avd' `
    -Version latest

$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id -Primary
$vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name "$VMName-OSDisk" -CreateOption FromImage -Windows

# Create the VM
Write-Host "Creating VM $VMName..." -ForegroundColor Green
New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $vmConfig

Write-Host "`nDeployment Complete!" -ForegroundColor Green
Write-Host "`nHost Pool Registration Token: $($Token.Token)" -ForegroundColor Yellow
Write-Host "`nImportant Next Steps:" -ForegroundColor Yellow
Write-Host "1. Install the AVD Agent and Boot Loader on the VM" -ForegroundColor Yellow
Write-Host "2. Register the VM with the Host Pool using the token" -ForegroundColor Yellow
Write-Host "3. Configure user assignments in Microsoft Entra ID" -ForegroundColor Yellow
Write-Host "4. Set up FSLogix profile containers if needed" -ForegroundColor Yellow
Write-Host "5. Test connection at: https://client.wvd.microsoft.com/arm/webclient/index.html" -ForegroundColor Yellow
