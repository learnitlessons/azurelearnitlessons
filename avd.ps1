# Variables for the deployment
$SubscriptionId = (Get-AzContext).Subscription.Id
$ResourceGroup = "rg-avd-prod5"
$Location = "uksouth"
$WorkspaceName = "ws-avd-prod5"
$HostPoolName = "hp-avd-prod5"
$AppGroupName = "ag-desktop-prod5"
$VNetName = "vnet-avd-prod5"
$SubnetName = "snet-avd-prod5"
$NSGName = "nsg-avd-prod5"
$VMPrefix = "vm-avd5"
$UserName = "jdoe@learnitlessonscoutlook.onmicrosoft.com"

# Network settings
$VNetAddressPrefix = "10.0.0.0/16"
$SubnetAddressPrefix = "10.0.1.0/24"

# VM settings
$VMSize = "Standard_D2s_v5"
$VMCount = 1
$AdminUsername = "localadmin"
$AdminPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# Create Resource Group
Write-Host "Creating Resource Group..." -ForegroundColor Green
New-AzResourceGroup -Name $ResourceGroup -Location $Location -Force

# Create NSG with required rules
Write-Host "Creating Network Security Group..." -ForegroundColor Green
$nsgRules = @(
    @{
        Name = 'Allow-RDP'
        Protocol = 'Tcp'
        Direction = 'Inbound'
        Priority = 100
        SourceAddressPrefix = 'Internet'
        SourcePortRange = '*'
        DestinationAddressPrefix = '*'
        DestinationPortRange = '3389'
        Access = 'Allow'
    },
    @{
        Name = 'Allow-HTTP'
        Protocol = 'Tcp'
        Direction = 'Inbound'
        Priority = 110
        SourceAddressPrefix = 'Internet'
        SourcePortRange = '*'
        DestinationAddressPrefix = '*'
        DestinationPortRange = '80'
        Access = 'Allow'
    },
    @{
        Name = 'Allow-HTTPS'
        Protocol = 'Tcp'
        Direction = 'Inbound'
        Priority = 120
        SourceAddressPrefix = 'Internet'
        SourcePortRange = '*'
        DestinationAddressPrefix = '*'
        DestinationPortRange = '443'
        Access = 'Allow'
    },
    @{
        Name = 'Allow-SSH'
        Protocol = 'Tcp'
        Direction = 'Inbound'
        Priority = 130
        SourceAddressPrefix = 'Internet'
        SourcePortRange = '*'
        DestinationAddressPrefix = '*'
        DestinationPortRange = '22'
        Access = 'Allow'
    }
)

$nsgRuleConfig = @()
foreach ($rule in $nsgRules) {
    $nsgRuleConfig += New-AzNetworkSecurityRuleConfig @rule
}

$nsg = New-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $ResourceGroup `
    -Location $Location -SecurityRules $nsgRuleConfig

# Create Virtual Network and Subnet
Write-Host "Creating VNet and Subnet..." -ForegroundColor Green
$subnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix -NetworkSecurityGroup $nsg
$vnet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Location $Location `
    -Name $VNetName -AddressPrefix $VNetAddressPrefix -Subnet $subnet -Force

# Get updated subnet reference
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet

# Create Host Pool
Write-Host "Creating Host Pool..." -ForegroundColor Green
$HostPool = New-AzWvdHostPool -ResourceGroupName $ResourceGroup `
    -Name $HostPoolName `
    -Location $Location `
    -HostPoolType Pooled `
    -LoadBalancerType BreadthFirst `
    -PreferredAppGroupType Desktop `
    -ValidationEnvironment:$false `
    -MaxSessionLimit 2 `
    -StartVMOnConnect:$true

# Get Host Pool Registration Token
$Token = New-AzWvdRegistrationInfo -ResourceGroupName $ResourceGroup `
    -HostPoolName $HostPoolName `
    -ExpirationTime $((get-date).ToUniversalTime().AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ'))

# Create Application Group
Write-Host "Creating Application Group..." -ForegroundColor Green
$AppGroup = New-AzWvdApplicationGroup -ResourceGroupName $ResourceGroup `
    -Name $AppGroupName `
    -Location $Location `
    -HostPoolArmPath $HostPool.Id `
    -ApplicationGroupType Desktop

# Create Workspace
Write-Host "Creating Workspace..." -ForegroundColor Green
$Workspace = New-AzWvdWorkspace -ResourceGroupName $ResourceGroup `
    -Name $WorkspaceName `
    -Location $Location

# Associate Application Group with Workspace
Write-Host "Associating Application Group with Workspace..." -ForegroundColor Green
Register-AzWvdApplicationGroup -ResourceGroupName $ResourceGroup `
    -WorkspaceName $WorkspaceName `
    -ApplicationGroupPath $AppGroup.Id

# Assign test user to Application Group
Write-Host "Assigning test user to Application Group..." -ForegroundColor Green
$UserObjectId = (Get-AzADUser -UserPrincipalName $UserName).Id
New-AzRoleAssignment -ObjectId $UserObjectId `
    -RoleDefinitionName "Desktop Virtualization User" `
    -ResourceName $AppGroupName `
    -ResourceGroupName $ResourceGroup `
    -ResourceType 'Microsoft.DesktopVirtualization/applicationGroups'

# Add VM User Login Role Assignment
New-AzRoleAssignment -ObjectId $UserObjectId `
    -RoleDefinitionName "Virtual Machine User Login" `
    -ResourceGroupName $ResourceGroup

# Create Session Host VMs
Write-Host "Creating Session Host VMs..." -ForegroundColor Green
for ($i = 1; $i -le $VMCount; $i++) {
    $VMName = "$VMPrefix-$i"
    
    # Create public IP with Static allocation
    $pipConfig = @{
        Name = "$VMName-pip"
        ResourceGroupName = $ResourceGroup
        Location = $Location
        Sku = "Standard"
        AllocationMethod = "Static"
    }
    $pip = New-AzPublicIpAddress @pipConfig

    # Get updated subnet reference
    $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup
    $subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet

    # Create NIC
    $nicName = "$VMName-nic"
    $nic = New-AzNetworkInterface -Name $nicName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -SubnetId $subnet.Id `
        -PublicIpAddressId $pip.Id `
        -NetworkSecurityGroupId $nsg.Id

    # Create VM Config
    $vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize

    # Set OS settings
    $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig `
        -Windows `
        -ComputerName $VMName `
        -Credential (New-Object PSCredential ($AdminUsername, $AdminPassword)) `
        -ProvisionVMAgent `
        -EnableAutoUpdate

    # Set source image
    $vmConfig = Set-AzVMSourceImage -VM $vmConfig `
        -PublisherName 'MicrosoftWindowsDesktop' `
        -Offer 'Windows-10' `
        -Skus 'win10-22h2-avd' `
        -Version latest

    # Add NIC
    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id -Primary

    # Configure boot diagnostics
    $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable

    # Create the VM
    Write-Host "Creating VM $VMName..." -ForegroundColor Green
    New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $vmConfig
}

# Configure RDP Properties for AAD Join
$Properties = "targetisaadjoined:i:1"
Update-AzWvdHostPool -ResourceGroupName $ResourceGroup `
    -Name $HostPoolName `
    -CustomRdpProperty $Properties

Write-Host "`nDeployment Complete!" -ForegroundColor Green
Write-Host "`nHost Pool Registration Token: $($Token.Token)" -ForegroundColor Yellow
Write-Host "`nImportant Next Steps:" -ForegroundColor Yellow
Write-Host "1. Install the AVD Agent on each VM" -ForegroundColor Yellow
Write-Host "2. Register each VM with the Host Pool using the token provided above" -ForegroundColor Yellow
Write-Host "3. Test connection using: https://client.wvd.microsoft.com/arm/webclient/index.html" -ForegroundColor Yellow
Write-Host "4. Update the local admin password in production" -ForegroundColor Yellow
Write-Host "5. Configure any additional security settings as needed" -ForegroundColor Yellow
