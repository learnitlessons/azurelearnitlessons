# Basic settings
$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with a secure password
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force

# Create Resource Groups
New-AzResourceGroup -Name "rg-lit-ADLab-ukw" -Location "ukwest"
New-AzResourceGroup -Name "rg-lit-ADLab-eus" -Location "eastus"
New-AzResourceGroup -Name "rg-lit-ADLab-cin" -Location "centralindia"

# UK West VMs
$loc = "ukwest"
$rg = "rg-lit-ADLab-ukw"

# lon-dc1
$vm = "lon-dc1"
$pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $rg -Location $loc -AllocationMethod Static -Sku Standard
$vnet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $loc -Name "vnet-$loc" -AddressPrefix "10.0.0.0/16" -Subnet (New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24")
$nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $rg -Location $loc -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name "$vm-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
$nic.NetworkSecurityGroup = $nsg
Set-AzNetworkInterface -NetworkInterface $nic
$vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $securePass)) | Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | Add-AzVMNetworkInterface -Id $nic.Id | Set-AzVMBootDiagnostic -Disable
New-AzVM -ResourceGroupName $rg -Location $loc -VM $vmConfig

# lon-dc2
$vm = "lon-dc2"
$pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $rg -Location $loc -AllocationMethod Static -Sku Standard
$nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $rg -Location $loc -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name "$vm-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
$nic.NetworkSecurityGroup = $nsg
Set-AzNetworkInterface -NetworkInterface $nic
$vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $securePass)) | Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | Add-AzVMNetworkInterface -Id $nic.Id | Set-AzVMBootDiagnostic -Disable
New-AzVM -ResourceGroupName $rg -Location $loc -VM $vmConfig

# East US VMs
$loc = "eastus"
$rg = "rg-lit-ADLab-eus"

# ny-dc1
$vm = "ny-dc1"
$pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $rg -Location $loc -AllocationMethod Static -Sku Standard
$vnet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $loc -Name "vnet-$loc" -AddressPrefix "10.1.0.0/16" -Subnet (New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.1.0.0/24")
$nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $rg -Location $loc -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name "$vm-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
$nic.NetworkSecurityGroup = $nsg
Set-AzNetworkInterface -NetworkInterface $nic
$vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $securePass)) | Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | Add-AzVMNetworkInterface -Id $nic.Id | Set-AzVMBootDiagnostic -Disable
New-AzVM -ResourceGroupName $rg -Location $loc -VM $vmConfig

# ny-dc2
$vm = "ny-dc2"
$pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $rg -Location $loc -AllocationMethod Static -Sku Standard
$nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $rg -Location $loc -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name "$vm-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
$nic.NetworkSecurityGroup = $nsg
Set-AzNetworkInterface -NetworkInterface $nic
$vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $securePass)) | Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | Add-AzVMNetworkInterface -Id $nic.Id | Set-AzVMBootDiagnostic -Disable
New-AzVM -ResourceGroupName $rg -Location $loc -VM $vmConfig

# Central India VMs
$loc = "centralindia"
$rg = "rg-lit-ADLab-cin"

# mum-dc1
$vm = "mum-dc1"
$pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $rg -Location $loc -AllocationMethod Static -Sku Standard
$vnet = New-AzVirtualNetwork -ResourceGroupName $rg -Location $loc -Name "vnet-$loc" -AddressPrefix "10.2.0.0/16" -Subnet (New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.2.0.0/24")
$nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $rg -Location $loc -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name "$vm-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
$nic.NetworkSecurityGroup = $nsg
Set-AzNetworkInterface -NetworkInterface $nic
$vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $securePass)) | Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | Add-AzVMNetworkInterface -Id $nic.Id | Set-AzVMBootDiagnostic -Disable
New-AzVM -ResourceGroupName $rg -Location $loc -VM $vmConfig

# mum-dc2
$vm = "mum-dc2"
$pip = New-AzPublicIpAddress -Name "$vm-pip" -ResourceGroupName $rg -Location $loc -AllocationMethod Static -Sku Standard
$nic = New-AzNetworkInterface -Name "$vm-nic" -ResourceGroupName $rg -Location $loc -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rg -Location $loc -Name "$vm-nsg" -SecurityRules (New-AzNetworkSecurityRuleConfig -Name "RDP" -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow)
$nic.NetworkSecurityGroup = $nsg
Set-AzNetworkInterface -NetworkInterface $nic
$vmConfig = New-AzVMConfig -VMName $vm -VMSize "Standard_B1s" | Set-AzVMOperatingSystem -Windows -ComputerName $vm -Credential (New-Object PSCredential($user, $securePass)) | Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | Add-AzVMNetworkInterface -Id $nic.Id | Set-AzVMBootDiagnostic -Disable
New-AzVM -ResourceGroupName $rg -Location $loc -VM $vmConfig

# Output connection information
Get-AzPublicIpAddress -ResourceGroupName "rg-lit-ADLab-ukw" | ForEach-Object { Write-Output "VM: $($_.Name.Replace('-pip','')) IP: $($_.IpAddress) RDP: mstsc /v:$($_.IpAddress) /u:$user" }
Get-AzPublicIpAddress -ResourceGroupName "rg-lit-ADLab-eus" | ForEach-Object { Write-Output "VM: $($_.Name.Replace('-pip','')) IP: $($_.IpAddress) RDP: mstsc /v:$($_.IpAddress) /u:$user" }
Get-AzPublicIpAddress -ResourceGroupName "rg-lit-ADLab-cin" | ForEach-Object { Write-Output "VM: $($_.Name.Replace('-pip','')) IP: $($_.IpAddress) RDP: mstsc /v:$($_.IpAddress) /u:$user" }