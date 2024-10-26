# Get current context
$context = Get-AzContext
$SubscriptionId = $context.Subscription.Id
Write-Host "Using subscription: $SubscriptionId" -ForegroundColor Green

# Variables
$ResourceGroup = "rg-lit-ukw-AVDLab"
$Location = "ukwest"
$VnetName = "rg-lit-ukw-vnet"
$SubnetName = "default"
$HostPoolName = "rg-lit-ukw-hostpool1"
$WorkspaceName = "rg-lit-ukw-workspace"
$VMName = "lit-avd-pvm-0"
$NICName = "lit-avd-pvm-0-nic"
$AppGroupName = "rg-lit-ukw-hostpool1-DAG"

# VM Credentials
$VMUsername = "shumi"
$VMPasswordText = "YourSecurePassword123!"
$VMPassword = ConvertTo-SecureString $VMPasswordText -AsPlainText -Force
$VMCredential = New-Object System.Management.Automation.PSCredential ($VMUsername, $VMPassword)

Write-Host "Starting AVD deployment in subscription: $SubscriptionId" -ForegroundColor Green

# Create Resource Group
Write-Host "Creating Resource Group..." -ForegroundColor Yellow
New-AzResourceGroup -Name $ResourceGroup -Location $Location

# Create Virtual Network and Subnet
Write-Host "Creating Virtual Network and Subnet..." -ForegroundColor Yellow
$SubnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.0.0/24"
New-AzVirtualNetwork `
    -ResourceGroupName $ResourceGroup `
    -Location $Location `
    -Name $VnetName `
    -AddressPrefix "10.0.0.0/16" `
    -Subnet $SubnetConfig

# Create Host Pool
Write-Host "Creating Host Pool..." -ForegroundColor Yellow
New-AzWvdHostPool `
    -ResourceGroupName $ResourceGroup `
    -Name $HostPoolName `
    -Location $Location `
    -HostPoolType Pooled `
    -LoadBalancerType DepthFirst `
    -PreferredAppGroupType Desktop `
    -MaxSessionLimit 5 `
    -ValidationEnvironment:$false

# Get Host Pool Registration Token
$Token = New-AzWvdRegistrationInfo `
    -ResourceGroupName $ResourceGroup `
    -HostPoolName $HostPoolName `
    -ExpiryTime $((Get-Date).AddHours(2))

# Create Session Host VM
Write-Host "Creating Session Host VM..." -ForegroundColor Yellow
$VMConfig = New-AzVMConfig -VMName $VMName -VMSize "Standard_D4s_v5"
$VMConfig = Set-AzVMOperatingSystem `
    -VM $VMConfig `
    -Windows `
    -ComputerName $VMName `
    -Credential $VMCredential `
    -ProvisionVMAgent

$VMConfig = Set-AzVMSourceImage `
    -VM $VMConfig `
    -PublisherName "MicrosoftWindowsDesktop" `
    -Offer "office-365" `
    -Skus "win11-23h2-avd-m365" `
    -Version "latest"

$Vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroup
$Subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet

$NIC = New-AzNetworkInterface `
    -Name $NICName `
    -ResourceGroupName $ResourceGroup `
    -Location $Location `
    -SubnetId $Subnet.Id

$VMConfig = Add-AzVMNetworkInterface -VM $VMConfig -Id $NIC.Id

New-AzVM `
    -ResourceGroupName $ResourceGroup `
    -Location $Location `
    -VM $VMConfig

# Install AVD Agent and register to Host Pool
Write-Host "Installing AVD Agent and registering to Host Pool..." -ForegroundColor Yellow
$ScriptContent = @"
`$RegistrationToken = '$($Token.Token)'
`$LocalPath = 'C:\AVD'
New-Item -Path `$LocalPath -ItemType Directory -Force
Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv' -OutFile `$LocalPath\Microsoft.RDInfra.RDAgent.Installer-x64.msi
Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', "`$LocalPath\Microsoft.RDInfra.RDAgent.Installer-x64.msi", '/quiet', "REGISTRATIONTOKEN=`$RegistrationToken" -Wait
Invoke-WebRequest -Uri 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH' -OutFile `$LocalPath\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi
Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', "`$LocalPath\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi", '/quiet' -Wait
"@

Invoke-AzVMRunCommand `
    -ResourceGroupName $ResourceGroup `
    -VMName $VMName `
    -CommandId 'RunPowerShellScript' `
    -ScriptString $ScriptContent

# Create Workspace
Write-Host "Creating Workspace..." -ForegroundColor Yellow
New-AzWvdWorkspace `
    -ResourceGroupName $ResourceGroup `
    -Name $WorkspaceName `
    -Location $Location `
    -FriendlyName "LIT AVD Workspace"

# Get the Application Group
Write-Host "Getting Application Group..." -ForegroundColor Yellow
$AppGroup = Get-AzWvdApplicationGroup `
    -ResourceGroupName $ResourceGroup | Select-Object -First 1

# Associate Application Group with Workspace
Write-Host "Associating Application Group with Workspace..." -ForegroundColor Yellow
Register-AzWvdApplicationGroup `
    -ResourceGroupName $ResourceGroup `
    -WorkspaceName $WorkspaceName `
    -ApplicationGroupPath $AppGroup.Id

# Configure Auto-scaling
Write-Host "Configuring Auto-scaling..." -ForegroundColor Yellow
$AutoscaleSettings = @{
    Location = $Location
    Name = "lit-avd-autoscale"
    ResourceGroupName = $ResourceGroup
    TargetResourceId = (Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName).Id
    Profiles = @(
        @{
            Name = "Default"
            Capacity = @{
                Minimum = "1"
                Maximum = "4"
                Default = "1"
            }
            Rules = @(
                @{
                    MetricTrigger = @{
                        MetricName = "TimeOfDay"
                        MetricResourceId = (Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName).Id
                        TimeGrain = "PT1M"
                        Statistic = "Average"
                        TimeWindow = "PT5M"
                        TimeAggregation = "Average"
                        Operator = "GreaterThanOrEqual"
                        Threshold = 9
                    }
                    ScaleAction = @{
                        Direction = "Increase"
                        Type = "ChangeCount"
                        Value = "1"
                        Cooldown = "PT5M"
                    }
                }
            )
        }
    )
}

New-AzAutoscaleSetting @AutoscaleSettings

Write-Host "AVD deployment complete!" -ForegroundColor Green

# Output deployment summary
Write-Host "=== Deployment Summary ===" -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Host Pool: $HostPoolName"
Write-Host "Workspace: $WorkspaceName"
Write-Host "Virtual Network: $VnetName"
Write-Host "VM Name: $VMName"
Write-Host "NIC Name: $NICName"
Write-Host "Application Group: $AppGroupName"
Write-Host "Location: $Location"
Write-Host "Username: $VMUsername"
