# Basic settings
$rg = "rg-lit-ADLab-created-with-powershell"
$vm = "lit-dc-ps"
$loc = "westeurope"
$user = "vitalii"
$pass = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force

# Create resource group
New-AzResourceGroup -Name $rg -Location $loc -Force

# Create VNet and Subnet
$vnetName = "$rg-vnet"
$subnetName = "default"
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix "10.0.0.0/24"
$vnet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $loc -Name $vnetName -AddressPrefix "10.0.0.0/16" -Subnet $subnetConfig -Force
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet

# Create public IP and NIC
$pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $rg -Location $loc -AllocationMethod Static -Sku Standard -Force
$nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $rg -Location $loc -SubnetId $subnet.Id -PublicIpAddressId $pip.Id -Force

# Create NSG rule for RDP
$nsgRuleRDP = New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name "$vm-nsg" -SecurityRules $nsgRuleRDP -Force
$nic.NetworkSecurityGroup = $nsg
Set-AzNetworkInterface -NetworkInterface $nic

# Create VM
$vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | 
Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $pass)) | 
Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | 
Add-AzVMNetworkInterface -Id $nic.Id

# Disable boot diagnostics
$vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable

# Create the VM
New-AzVM -ResourceGroupName $rg -Location $loc -VM $vmConfig

# Output VM details
$newVM = Get-AzVM -ResourceGroupName $rg -Name $vm
$newPIP = Get-AzPublicIpAddress -ResourceGroupName $rg -Name "$vm-pip"
Write-Output "VM: $vm"
Write-Output "User: $user"
Write-Output "Public IP: $($newPIP.IpAddress)"
Write-Output "Connect via RDP using these credentials and the public IP"