# West Europe # UK West
$rg = "rg-lit-ADLab-weu"
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
# Remove West Europe vnet
Remove-AzVirtualNetwork -ResourceGroupName $rg -Name "vnet-westeurope" -Force
# West Europe
$rg = "rg-lit-ADLab-weu"
# Remove ams-dc1
Remove-AzVM -ResourceGroupName $rg -Name "ams-dc1" -Force
Remove-AzNetworkInterface -ResourceGroupName $rg -Name "ams-dc1-nic" -Force
Remove-AzPublicIpAddress -ResourceGroupName $rg -Name "ams-dc1-pip" -Force
Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "ams-dc1-nsg" -Force
# Remove ams-dc2
Remove-AzVM -ResourceGroupName $rg -Name "ams-dc2" -Force
Remove-AzNetworkInterface -ResourceGroupName $rg -Name "ams-dc2-nic" -Force
Remove-AzPublicIpAddress -ResourceGroupName $rg -Name "ams-dc2-pip" -Force
Remove-AzNetworkSecurityGroup -ResourceGroupName $rg -Name "ams-dc2-nsg" -Force
# Remove West Europe vnet
Remove-AzVirtualNetwork -ResourceGroupName $rg -Name "vnet-westeurope" -Force
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
Remove-AzResourceGroup -Name "rg-lit-ADLab-weu" -Force
Remove-AzResourceGroup -Name "rg-lit-ADLab-cin" -Force
Write-Output "All specified resources have been removed."
