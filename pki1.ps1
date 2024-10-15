# Azure PKI Lab Setup Script

# ... (previous code remains the same)

# Function to create OUs and users
function Create-OUsAndUsers {
    param (
        [string]$vmName
    )

    $script = @"
    # Create OUs
    New-ADOrganizationalUnit -Name "LIT_Computers" -Path "DC=learnitlessons,DC=com"
    New-ADOrganizationalUnit -Name "LIT_Users" -Path "DC=learnitlessons,DC=com"

    # Create users
    `$users = @(
        @{Name="John Doe"; Username="jdoe"; Department="IT"},
        @{Name="Jane Smith"; Username="jsmith"; Department="HR"},
        @{Name="Bob Johnson"; Username="bjohnson"; Department="Finance"},
        @{Name="Alice Brown"; Username="abrown"; Department="Marketing"},
        @{Name="Charlie Wilson"; Username="cwilson"; Department="Sales"}
    )

    foreach (`$user in `$users) {
        New-ADUser -Name `$user.Name ``
                   -SamAccountName `$user.Username ``
                   -UserPrincipalName "`$(`$user.Username)@$domainName" ``
                   -Path "OU=LIT_Users,DC=learnitlessons,DC=com" ``
                   -AccountPassword (ConvertTo-SecureString "$pass" -AsPlainText -Force) ``
                   -Department `$user.Department ``
                   -Enabled `$true

        Write-Output "Created user: `$(`$user.Name)"
    }

    # Create groups
    `$groups = @("IT", "HR", "Finance", "Marketing", "Sales")
    foreach (`$group in `$groups) {
        New-ADGroup -Name `$group -GroupScope Global -Path "OU=LIT_Users,DC=learnitlessons,DC=com"
        Write-Output "Created group: `$group"
    }

    # Add users to their respective groups
    foreach (`$user in `$users) {
        Add-ADGroupMember -Identity `$user.Department -Members `$user.Username
        Write-Output "Added `$(`$user.Name) to `$(`$user.Department) group"
    }
"@

    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
}

# ... (rest of the script remains the same)

# Main script
# ... (previous main script code remains the same)

# Create OUs and users
Write-Host "Creating OUs, users, and groups..."
Create-OUsAndUsers -vmName "lit-dc1"

# ... (rest of the main script remains the same)
