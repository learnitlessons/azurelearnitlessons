# Configure ams-dc1
$nic = Get-AzNetworkInterface -Name "ams-dc1-nic" -ResourceGroupName "rg-lit-ADLab-weu"
$nic.IpConfigurations[0].PrivateIpAddress = "10.1.0.4"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
Set-AzNetworkInterface -NetworkInterface $nic

# Configure ams-dc2
$nic = Get-AzNetworkInterface -Name "ams-dc2-nic" -ResourceGroupName "rg-lit-ADLab-weu"
$nic.IpConfigurations[0].PrivateIpAddress = "10.1.0.5"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
Set-AzNetworkInterface -NetworkInterface $nic

# Configure mum-dc1
$nic = Get-AzNetworkInterface -Name "mum-dc1-nic" -ResourceGroupName "rg-lit-ADLab-cin"
$nic.IpConfigurations[0].PrivateIpAddress = "10.2.0.4"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
Set-AzNetworkInterface -NetworkInterface $nic

# Configure mum-dc2
$nic = Get-AzNetworkInterface -Name "mum-dc2-nic" -ResourceGroupName "rg-lit-ADLab-cin"
$nic.IpConfigurations[0].PrivateIpAddress = "10.2.0.5"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
Set-AzNetworkInterface -NetworkInterface $nic

# Verify IP configurations
Get-AzNetworkInterface -Name "ams-dc1-nic" -ResourceGroupName "rg-lit-ADLab-weu" | Select-Object -ExpandProperty IpConfigurations
Get-AzNetworkInterface -Name "ams-dc2-nic" -ResourceGroupName "rg-lit-ADLab-weu" | Select-Object -ExpandProperty IpConfigurations
Get-AzNetworkInterface -Name "mum-dc1-nic" -ResourceGroupName "rg-lit-ADLab-cin" | Select-Object -ExpandProperty IpConfigurations
Get-AzNetworkInterface -Name "mum-dc2-nic" -ResourceGroupName "rg-lit-ADLab-cin" | Select-Object -ExpandProperty IpConfigurations

Write-Host "Static IP configuration complete. Please review the output above to verify the changes."
Write-Host "Remember to update DNS settings within each VM's operating system and restart the VMs if necessary."
