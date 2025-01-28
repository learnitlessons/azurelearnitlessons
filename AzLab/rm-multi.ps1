# UK West
$rg = "rg-lit-ADLab-ukw"

# Remove lon-dc1
Remove-AzVM -ResourceGroupName $rg -Name "lon-dc1" -Force
Remove-AzNetworkInterface -ResourceGroupName $rg -Name "lon-dc1-nic" -Force
Remove-AzPublicIpAddress -ResourceGroupName $rg -Name "lon-dc1-pip" -Force
Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "lon-dc1-nsg" -Force

# Remove lon-dc2
Remove-AzVM -ResourceGroupName $rg -Name "lon-dc2" -Force
Remove-AzNetworkInterface -ResourceGroupName $rg -Name "lon-dc2-nic" -Force
Remove-AzPublicIpAddress -ResourceGroupName $rg -Name "lon-dc2-pip" -Force
Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "lon-dc2-nsg" -Force

# Remove UK West vnet
Remove-AzVirtualNetwork -ResourceGroupName $rg -Name "vnet-ukwest" -Force

# East US
$rg = "rg-lit-ADLab-eus"

# Remove ny-dc1
Remove-AzVM -ResourceGroupName $rg -Name "ny-dc1" -Force
Remove-AzNetworkInterface -ResourceGroupName $rg -Name "ny-dc1-nic" -Force
Remove-AzPublicIpAddress -ResourceGroupName $rg -Name "ny-dc1-pip" -Force
Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "ny-dc1-nsg" -Force

# Remove ny-dc2
Remove-AzVM -ResourceGroupName $rg -Name "ny-dc2" -Force
Remove-AzNetworkInterface -ResourceGroupName $rg -Name "ny-dc2-nic" -Force
Remove-AzPublicIpAddress -ResourceGroupName $rg -Name "ny-dc2-pip" -Force
Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "ny-dc2-nsg" -Force

# Remove East US vnet
Remove-AzVirtualNetwork -ResourceGroupName $rg -Name "vnet-eastus" -Force

# Central India
$rg = "rg-lit-ADLab-cin"

# Remove mum-dc1
Remove-AzVM -ResourceGroupName $rg -Name "mum-dc1" -Force
Remove-AzNetworkInterface -ResourceGroupName $rg -Name "mum-dc1-nic" -Force
Remove-AzPublicIpAddress -ResourceGroupName $rg -Name "mum-dc1-pip" -Force
Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "mum-dc1-nsg" -Force

# Remove mum-dc2
Remove-AzVM -ResourceGroupName $rg -Name "mum-dc2" -Force
Remove-AzNetworkInterface -ResourceGroupName $rg -Name "mum-dc2-nic" -Force
Remove-AzPublicIpAddress -ResourceGroupName $rg -Name "mum-dc2-pip" -Force
Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "mum-dc2-nsg" -Force

# Remove Central India vnet
Remove-AzVirtualNetwork -ResourceGroupName $rg -Name "vnet-centralindia" -Force

# Remove Resource Groups
Remove-AzResourceGroup -Name "rg-lit-ADLab-ukw" -Force
Remove-AzResourceGroup -Name "rg-lit-ADLab-eus" -Force
Remove-AzResourceGroup -Name "rg-lit-ADLab-cin" -Force

Write-Output "All specified resources have been removed."