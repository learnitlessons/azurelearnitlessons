# Login to Azure if needed (not required in Cloud Shell)
# Connect-AzAccount

# Variables for the deployment
$SubscriptionId = (Get-AzContext).Subscription.Id
$ResourceGroup = "rg-avd-prod"
$Location = "eastus"
$WorkspaceName = "ws-avd-prod"
$HostPoolName = "hp-avd-prod"
$AppGroupName = "ag-desktop-prod"
$TestUserUPN = "jdoe@learnitlessonscoutlook.onmicrosoft.com"

# Network settings
$VNetName = "vnet-avd-prod"
$SubnetName = "snet-avd-prod"
$VNetAddressPrefix = "10.0.0.0/16"
$SubnetAddressPrefix = "10.0.1.0/24"

# VM settings
$VMSize = "Standard_D2s_v3"
$VMCount = 1
$VMPrefix = "vm-avd"
$AdminUsername = "localadmin"
# Generate a secure password - change this in production
$AdminPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# Create Resource Group
Write-Host "Creating Resource Group..." -ForegroundColor Green
New-AzResourceGroup -Name $ResourceGroup -Location $Location

# Create Virtual Network and Subnet
Write-Host "Creating VNet and Subnet..." -ForegroundColor Green
$SubnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix
$VNet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Location $Location `
    -Name $VNetName -AddressPrefix $VNetAddressPrefix -Subnet $SubnetConfig

# Create Host Pool
Write-Host "Creating Host Pool..." -ForegroundColor Green
$HostPool = New-AzWvdHostPool -ResourceGroupName $ResourceGroup `
    -Name $HostPoolName `
    -Location $Location `
    -HostPoolType Pooled `
    -LoadBalancerType BreadthFirst `
    -PreferredAppGroupType Desktop `
    -ValidationEnvironment:$false `
    -StartVMOnConnect:$true

# Get Host Pool Registration Token
$RegistrationInfo = New-AzWvdRegistrationInfo -ResourceGroupName $ResourceGroup `
    -HostPoolName $HostPoolName `
    -ExpiryTime $((get-date).ToUniversalTime().AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ'))

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
$WorkspaceId = $Workspace.Id
Register-AzWvdApplicationGroup -ResourceGroupName $ResourceGroup `
    -WorkspaceName $WorkspaceName `
    -ApplicationGroupPath $AppGroup.Id

# Assign test user to Application Group
Write-Host "Assigning test user to Application Group..." -ForegroundColor Green
$UserObjectId = (Get-AzADUser -UserPrincipalName $TestUserUPN).Id
New-AzRoleAssignment -ObjectId $UserObjectId `
    -RoleDefinitionName "Desktop Virtualization User" `
    -ResourceName $AppGroupName `
    -ResourceGroupName $ResourceGroup `
    -ResourceType 'Microsoft.DesktopVirtualization/applicationGroups'

# Create Session Host VMs
Write-Host "Creating Session Host VMs..." -ForegroundColor Green
for ($i = 1; $i -le $VMCount; $i++) {
    $VMName = "$VMPrefix-$i"
    
    # Create NIC
    $NIC = New-AzNetworkInterface -Name "$VMName-nic" `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -SubnetId $VNet.Subnets[0].Id

    # Create VM Config
    $VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    $VMConfig = Set-AzVMOperatingSystem -VM $VMConfig `
        -Windows `
        -ComputerName $VMName `
        -Credential (New-Object PSCredential ($AdminUsername, $AdminPassword))
    $VMConfig = Set-AzVMSourceImage -VM $VMConfig `
        -PublisherName 'MicrosoftWindowsDesktop' `
        -Offer 'windows-10' `
        -Skus '21h1-evd' `
        -Version latest
    $VMConfig = Add-AzVMNetworkInterface -VM $VMConfig -Id $NIC.Id

    # Create VM
    Write-Host "Creating VM $VMName..." -ForegroundColor Green
    New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $VMConfig

    # Install AVD Agent and register with Host Pool
    # Note: In a production environment, you would typically use Custom Script Extension or Azure Automation for this
    Write-Host "Note: You will need to manually install the AVD agent on the VM and register it with the Host Pool using the following token:" -ForegroundColor Yellow
    Write-Host $RegistrationInfo.Token -ForegroundColor Yellow
}

Write-Host "`nDeployment Complete!" -ForegroundColor Green
Write-Host "`nImportant Next Steps:" -ForegroundColor Yellow
Write-Host "1. Install the AVD Agent on each VM" -ForegroundColor Yellow
Write-Host "2. Register each VM with the Host Pool using the token provided" -ForegroundColor Yellow
Write-Host "3. Test connection using: https://client.wvd.microsoft.com/arm/webclient/index.html" -ForegroundColor Yellow
Write-Host "4. Update the local admin password in production" -ForegroundColor Yellow
Write-Host "5. Configure any additional security settings as needed" -ForegroundColor Yellow
