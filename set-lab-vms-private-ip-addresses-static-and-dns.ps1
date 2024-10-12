# Connect to Azure
Connect-AzAccount

# Set the correct subscription context
Set-AzContext -Subscription "Your-Subscription-ID"

# Configure lon-dc1
$nic = Get-AzNetworkInterface -Name "lon-dc1-nic" -ResourceGroupName "rg-lit-ADLab-ukw"
$nic.IpConfigurations[0].PrivateIpAddress = "10.0.0.4"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
$nic.DnsSettings.DnsServers.Clear()
$nic.DnsSettings.DnsServers.Add("127.0.0.1")
$nic.DnsSettings.DnsServers.Add("10.0.0.5")
Set-AzNetworkInterface -NetworkInterface $nic

# Configure lon-dc2
$nic = Get-AzNetworkInterface -Name "lon-dc2-nic" -ResourceGroupName "rg-lit-ADLab-ukw"
$nic.IpConfigurations[0].PrivateIpAddress = "10.0.0.5"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
$nic.DnsSettings.DnsServers.Clear()
$nic.DnsSettings.DnsServers.Add("127.0.0.1")
$nic.DnsSettings.DnsServers.Add("10.0.0.4")
Set-AzNetworkInterface -NetworkInterface $nic

# Configure ams-dc1
$nic = Get-AzNetworkInterface -Name "ams-dc1-nic" -ResourceGroupName "rg-lit-ADLab-weu"
$nic.IpConfigurations[0].PrivateIpAddress = "10.1.0.4"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
$nic.DnsSettings.DnsServers.Clear()
$nic.DnsSettings.DnsServers.Add("127.0.0.1")
$nic.DnsSettings.DnsServers.Add("10.1.0.5")
Set-AzNetworkInterface -NetworkInterface $nic

# Configure ams-dc2
$nic = Get-AzNetworkInterface -Name "ams-dc2-nic" -ResourceGroupName "rg-lit-ADLab-weu"
$nic.IpConfigurations[0].PrivateIpAddress = "10.1.0.5"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
$nic.DnsSettings.DnsServers.Clear()
$nic.DnsSettings.DnsServers.Add("127.0.0.1")
$nic.DnsSettings.DnsServers.Add("10.1.0.4")
Set-AzNetworkInterface -NetworkInterface $nic

# Configure mum-dc1
$nic = Get-AzNetworkInterface -Name "mum-dc1-nic" -ResourceGroupName "rg-lit-ADLab-cin"
$nic.IpConfigurations[0].PrivateIpAddress = "10.2.0.4"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
$nic.DnsSettings.DnsServers.Clear()
$nic.DnsSettings.DnsServers.Add("127.0.0.1")
$nic.DnsSettings.DnsServers.Add("10.2.0.5")
Set-AzNetworkInterface -NetworkInterface $nic

# Configure mum-dc2
$nic = Get-AzNetworkInterface -Name "mum-dc2-nic" -ResourceGroupName "rg-lit-ADLab-cin"
$nic.IpConfigurations[0].PrivateIpAddress = "10.2.0.5"
$nic.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
$nic.DnsSettings.DnsServers.Clear()
$nic.DnsSettings.DnsServers.Add("127.0.0.1")
$nic.DnsSettings.DnsServers.Add("10.2.0.4")
Set-AzNetworkInterface -NetworkInterface $nic

# Verify IP and DNS configurations
Get-AzNetworkInterface -Name "lon-dc1-nic" -ResourceGroupName "rg-lit-ADLab-ukw" | Select-Object -ExpandProperty IpConfigurations
Get-AzNetworkInterface -Name "lon-dc2-nic" -ResourceGroupName "rg-lit-ADLab-ukw" | Select-Object -ExpandProperty IpConfigurations
Get-AzNetworkInterface -Name "ams-dc1-nic" -ResourceGroupName "rg-lit-ADLab-weu" | Select-Object -ExpandProperty IpConfigurations
Get-AzNetworkInterface -Name "ams-dc2-nic" -ResourceGroupName "rg-lit-ADLab-weu" | Select-Object -ExpandProperty IpConfigurations
Get-AzNetworkInterface -Name "mum-dc1-nic" -ResourceGroupName "rg-lit-ADLab-cin" | Select-Object -ExpandProperty IpConfigurations
Get-AzNetworkInterface -Name "mum-dc2-nic" -ResourceGroupName "rg-lit-ADLab-cin" | Select-Object -ExpandProperty IpConfigurations

Get-AzNetworkInterface -Name "lon-dc1-nic" -ResourceGroupName "rg-lit-ADLab-ukw" | Select-Object -ExpandProperty DnsSettings
Get-AzNetworkInterface -Name "lon-dc2-nic" -ResourceGroupName "rg-lit-ADLab-ukw" | Select-Object -ExpandProperty DnsSettings
Get-AzNetworkInterface -Name "ams-dc1-nic" -ResourceGroupName "rg-lit-ADLab-weu" | Select-Object -ExpandProperty DnsSettings
Get-AzNetworkInterface -Name "ams-dc2-nic" -ResourceGroupName "rg-lit-ADLab-weu" | Select-Object -ExpandProperty DnsSettings
Get-AzNetworkInterface -Name "mum-dc1-nic" -ResourceGroupName "rg-lit-ADLab-cin" | Select-Object -ExpandProperty DnsSettings
Get-AzNetworkInterface -Name "mum-dc2-nic" -ResourceGroupName "rg-lit-ADLab-cin" | Select-Object -ExpandProperty DnsSettings

Write-Host "Static IP and DNS configuration complete for all domain controllers. Please review the output above to verify the changes."
Write-Host "Remember to restart the VMs for the changes to take effect."
