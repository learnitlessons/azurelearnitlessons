# Azure AD Multi-Region Deployment Script (Simplified Version)

# Basic settings
$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with a secure password
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force

# Function to install ADDS role and promote DC
function Install-ADDSAndPromoteDC {
    param (
        [string]$resourceGroup,
        [string]$vmName,
        [string]$domainName,
        [string]$parentDomainName,
        [bool]$isFirstDC,
        [string]$netbiosName,
        [string]$firstDCIP
    )

    # Install ADDS role
    $script = "Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools"
    $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script

    if ($result.Status -ne "Succeeded") {
        Write-Host "Failed to install ADDS role on $vmName. Skipping DC promotion."
        return $false
    }

    # Promote DC
    if ($isFirstDC) {
        if ([string]::IsNullOrEmpty($parentDomainName)) {
            # First DC in forest
            $script = @"
            Import-Module ADDSDeployment
            `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
            Install-ADDSForest ``
                -CreateDnsDelegation:`$false ``
                -DatabasePath "C:\Windows\NTDS" ``
                -DomainMode "WinThreshold" ``
                -DomainName "$domainName" ``
                -DomainNetbiosName "$netbiosName" ``
                -ForestMode "WinThreshold" ``
                -InstallDns:`$true ``
                -LogPath "C:\Windows\NTDS" ``
                -NoRebootOnCompletion:`$false ``
                -SysvolPath "C:\Windows\SYSVOL" ``
                -Force:`$true ``
                -SafeModeAdministratorPassword `$securePassword
"@
        } else {
            # First DC in child domain
            $script = @"
            Import-Module ADDSDeployment
            `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
            `$cred = New-Object System.Management.Automation.PSCredential ("$user@$parentDomainName", `$securePassword)
            Install-ADDSDomain ``
                -NewDomainName "$domainName" ``
                -ParentDomainName "$parentDomainName" ``
                -DomainMode "WinThreshold" ``
                -DomainType "ChildDomain" ``
                -InstallDns:`$true ``
                -CreateDnsDelegation:`$true ``
                -Credential `$cred ``
                -DatabasePath "C:\Windows\NTDS" ``
                -LogPath "C:\Windows\NTDS" ``
                -SysvolPath "C:\Windows\SYSVOL" ``
                -NewDomainNetbiosName "$netbiosName" ``
                -NoRebootOnCompletion:`$false ``
                -Force:`$true ``
                -SafeModeAdministratorPassword `$securePassword
"@
        }
    } else {
        # Additional DC
        $script = @"
        Import-Module ADDSDeployment
        `$securePassword = ConvertTo-SecureString '$pass' -AsPlainText -Force
        `$cred = New-Object System.Management.Automation.PSCredential ("$user@$domainName", `$securePassword)
        Install-ADDSDomainController ``
            -DomainName "$domainName" ``
            -Credential `$cred ``
            -InstallDns:`$true ``
            -DatabasePath "C:\Windows\NTDS" ``
            -LogPath "C:\Windows\NTDS" ``
            -SysvolPath "C:\Windows\SYSVOL" ``
            -NoRebootOnCompletion:`$false ``
            -Force:`$true ``
            -SafeModeAdministratorPassword `$securePassword
"@
    }

    $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
    if ($result.Status -eq "Succeeded") {
        Write-Host "ADDS installation and DC promotion completed successfully on $vmName"
        return $true
    } else {
        Write-Host "Failed to promote $vmName to a domain controller."
        return $false
    }
}

# Function to install ADDS for a region
function Install-ADDSForRegion {
    param (
        [hashtable]$region
    )
    
    $success = Install-ADDSAndPromoteDC -resourceGroup $region.resourceGroup -vmName $region.vm1 `
                                        -domainName $region.domainName -parentDomainName $region.parentDomainName `
                                        -isFirstDC $true -netbiosName $region.netbiosName -firstDCIP $region.vm1StaticIP
    if ($success) {
        Write-Host "Waiting 15 minutes for AD replication and DNS propagation..."
        Start-Sleep -Seconds 900
        
        $success = Install-ADDSAndPromoteDC -resourceGroup $region.resourceGroup -vmName $region.vm2 `
                                            -domainName $region.domainName -isFirstDC $false -netbiosName $region.netbiosName `
                                            -firstDCIP $region.vm1StaticIP
        if ($success) {
            Write-Host "$($region.vm2) successfully promoted to a domain controller."
        } else {
            Write-Host "Failed to promote $($region.vm2) to a domain controller."
        }
    } else {
        Write-Host "Failed to promote $($region.vm1). Skipping second DC installation."
    }
}

# Function to create route tables and routes
function Create-RouteTables {
    param (
        [array]$regions
    )

    foreach ($region in $regions) {
        $routeTableName = "rt-" + ($region.name -replace '\s', '-')
        $routeTable = New-AzRouteTable -Name $routeTableName -ResourceGroupName $region.resourceGroup -Location $region.location -Force

        foreach ($otherRegion in $regions) {
            if ($otherRegion.name -ne $region.name) {
                $routeName = "route-to-" + ($otherRegion.name -replace '\s', '-')
                Add-AzRouteConfig -Name $routeName `
                                  -AddressPrefix $otherRegion.addressPrefix `
                                  -NextHopType VirtualAppliance `
                                  -NextHopIpAddress $otherRegion.vm1StaticIP `
                                  -RouteTable $routeTable
            }
        }

        $routeTable | Set-AzRouteTable

        $vnet = Get-AzVirtualNetwork -ResourceGroupName $region.resourceGroup -Name "vnet-$($region.location)"
        $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name "default"
        
        Set-AzVirtualNetworkSubnetConfig -Name "default" `
                                         -VirtualNetwork $vnet `
                                         -AddressPrefix $subnet.AddressPrefix `
                                         -RouteTable $routeTable | Set-AzVirtualNetwork
        
        Write-Host "Route table created and associated successfully for $($region.name)"
    }
}

# Function to create VNet peering between regions
function Create-VNetPeering {
    param (
        [array]$regions
    )

    for ($i = 0; $i -lt $regions.Count; $i++) {
        for ($j = $i + 1; $j -lt $regions.Count; $j++) {
            $region1 = $regions[$i]
            $region2 = $regions[$j]

            $vnet1 = Get-AzVirtualNetwork -ResourceGroupName $region1.resourceGroup -Name "vnet-$($region1.location)"
            $vnet2 = Get-AzVirtualNetwork -ResourceGroupName $region2.resourceGroup -Name "vnet-$($region2.location)"

            $peering1Name = "$($region1.name)-to-$($region2.name)" -replace '\s', '-'
            Add-AzVirtualNetworkPeering -Name $peering1Name `
                                        -VirtualNetwork $vnet1 `
                                        -RemoteVirtualNetworkId $vnet2.Id `
                                        -AllowForwardedTraffic

            $peering2Name = "$($region2.name)-to-$($region1.name)" -replace '\s', '-'
            Add-AzVirtualNetworkPeering -Name $peering2Name `
                                        -VirtualNetwork $vnet2 `
                                        -RemoteVirtualNetworkId $vnet1.Id `
                                        -AllowForwardedTraffic

            Write-Host "VNet peering created successfully between $($region1.name) and $($region2.name)"
        }
    }
}

# Main script
$regions = @(
    @{
        name = "UK West"
        location = "ukwest"
        resourceGroup = "rg-lit-ADLab-ukw"
        addressPrefix = "10.0.0.0/16"
        vm1 = "lon-dc1"
        vm2 = "lon-dc2"
        vm1StaticIP = "10.0.0.4"
        vm2StaticIP = "10.0.0.5"
        domainName = "learnitlessons.com"
        netbiosName = "LIT"
        parentDomainName = ""
    },
    @{
        name = "West Europe"
        location = "westeurope"
        resourceGroup = "rg-lit-ADLab-weu"
        addressPrefix = "10.1.0.0/16"
        vm1 = "ams-dc1"
        vm2 = "ams-dc2"
        vm1StaticIP = "10.1.0.4"
        vm2StaticIP = "10.1.0.5"
        domainName = "ams.learnitlessons.com"
        netbiosName = "AMS"
        parentDomainName = "learnitlessons.com"
    },
    @{
        name = "Central India"
        location = "centralindia"
        resourceGroup = "rg-lit-ADLab-cin"
        addressPrefix = "10.2.0.0/16"
        vm1 = "mum-dc1"
        vm2 = "mum-dc2"
        vm1StaticIP = "10.2.0.4"
        vm2StaticIP = "10.2.0.5"
        domainName = "mum.learnitlessons.com"
        netbiosName = "MUM"
        parentDomainName = "learnitlessons.com"
    }
)

do {
    Write-Host "`nSelect an action:"
    Write-Host "1. Install ADDS and Promote DCs"
    Write-Host "2. Create Route Tables"
    Write-Host "3. Create VNet Peering"
    Write-Host "4. Exit"

    $action = Read-Host "Enter your choice (1-4)"

    switch ($action) {
        "1" {
            foreach ($region in $regions) {
                Install-ADDSForRegion -region $region
            }
            Write-Host "ADDS installation and DC promotion completed for all regions."
        }
        "2" {
            Create-RouteTables -regions $regions
            Write-Host "Route tables created successfully for all regions."
        }
        "3" {
            Create-VNetPeering -regions $regions
            Write-Host "VNet peering created successfully between all regions."
        }
        "4" { break }
        default { Write-Host "Invalid choice. Please try again." }
    }

    if ($action -ne "4") {
        Read-Host "Press Enter to continue..."
    }
} while ($action -ne "4")

Write-Host "Script execution completed."
