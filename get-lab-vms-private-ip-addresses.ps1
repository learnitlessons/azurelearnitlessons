# Login to Azure (uncomment if not already logged in)
# Connect-AzAccount

# Set the subscription context
Set-AzContext -SubscriptionName "Azure subscription 1"

# Define the resource group names
$resourceGroups = @("rg-lit-ADLab-cin", "rg-lit-ADLab-ukw", "rg-lit-ADLab-weu")

# Initialize an array to store the results
$allPrivateNICs = @()

# Loop through each resource group
foreach ($rg in $resourceGroups) {
    # Get all NICs in the current resource group
    $nics = Get-AzNetworkInterface -ResourceGroupName $rg

    # Filter for private NICs and add to the results
    $privateNICs = $nics | Where-Object { $_.IpConfigurations.PrivateIpAddress -ne $null }
    $allPrivateNICs += $privateNICs
}

# Output the results
$allPrivateNICs | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        ResourceGroup = $_.ResourceGroupName
        PrivateIP = $_.IpConfigurations.PrivateIpAddress
        Location = $_.Location
    }
} | Format-Table -AutoSize

# Optionally, export to CSV
# $allPrivateNICs | Export-Csv -Path "PrivateNICs.csv" -NoTypeInformation
