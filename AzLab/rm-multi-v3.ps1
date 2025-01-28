# Azure AD Multi-Region VM Removal Script

# Function to remove resources in a specific region
function Remove-RegionResources {
    param (
        [string]$resourceGroup
    )

    Write-Host "Removing all resources in resource group: $resourceGroup"
    try {
        Remove-AzResourceGroup -Name $resourceGroup -Force -ErrorAction Stop
        Write-Host "Resources removed successfully."
    }
    catch {
        Write-Host "Error occurred while removing resources in $resourceGroup"
        Write-Host $_.Exception.Message
    }
}

# Region definitions
$regions = @(
    @{
        name = "UK West"
        resourceGroup = "rg-lit-ADLab-ukw"
    },
    @{
        name = "West Europe"
        resourceGroup = "rg-lit-ADLab-weu"
    },
    @{
        name = "Central India"
        resourceGroup = "rg-lit-ADLab-cin"
    }
)

# Main script
do {
    Write-Host "`nSelect the region(s) where you want to remove resources:"
    for ($i = 0; $i -lt $regions.Count; $i++) {
        Write-Host "$($i+1). $($regions[$i].name)"
    }
    Write-Host "4. All regions"
    Write-Host "5. Exit"

    $choice = Read-Host "Enter your choice (1-5)"

    switch ($choice) {
        "1" { Remove-RegionResources -resourceGroup $regions[0].resourceGroup }
        "2" { Remove-RegionResources -resourceGroup $regions[1].resourceGroup }
        "3" { Remove-RegionResources -resourceGroup $regions[2].resourceGroup }
        "4" { 
            foreach ($region in $regions) {
                Remove-RegionResources -resourceGroup $region.resourceGroup
            }
        }
        "5" { break }
        default { Write-Host "Invalid choice. Please try again." }
    }

    if ($choice -ne "5") {
        Write-Host "Resource removal completed."
        Read-Host "Press Enter to continue..."
    }
} while ($choice -ne "5")

Write-Host "Script execution completed."
