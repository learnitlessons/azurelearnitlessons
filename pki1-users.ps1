#================================
# 1. BASIC SETTINGS
#================================

$domainName = "learnitlessons.com"
$netbiosName = "LIT"
$user = "shumi"
$pass = "YourSecurePassword123!" # Replace with the same secure password used in the previous script
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force

#================================
# 2. FUNCTION DEFINITIONS
#================================

# Function to create Organizational Units (OUs)
function Create-OrganizationalUnits {
    $ouStructure = @(
        "LIT",
        "LIT/Users",
        "LIT/Computers",
        "LIT/Servers",
        "LIT/Groups"
    )

    foreach ($ou in $ouStructure) {
        $ouPath = "OU=" + ($ou -replace "/", ",OU=") + ",DC=" + ($domainName -replace "\.", ",DC=")
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'" -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name ($ou -split "/")[-1] -Path ($ouPath -replace "OU=[^,]+,", "") -ProtectedFromAccidentalDeletion $true
            Write-Host "Created OU: $ou"
        } else {
            Write-Host "OU already exists: $ou"
        }
    }
}

# Function to create Groups
function Create-Groups {
    $groups = @(
        @{Name = "IT Admins"; Path = "OU=Groups,OU=LIT,DC=$($domainName -replace "\.", ",DC=")"},
        @{Name = "HR Staff"; Path = "OU=Groups,OU=LIT,DC=$($domainName -replace "\.", ",DC=")"},
        @{Name = "Finance Staff"; Path = "OU=Groups,OU=LIT,DC=$($domainName -replace "\.", ",DC=")"},
        @{Name = "Marketing Staff"; Path = "OU=Groups,OU=LIT,DC=$($domainName -replace "\.", ",DC=")"}
    )

    foreach ($group in $groups) {
        if (-not (Get-ADGroup -Filter "Name -eq '$($group.Name)'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $group.Name -GroupScope Global -GroupCategory Security -Path $group.Path
            Write-Host "Created group: $($group.Name)"
        } else {
            Write-Host "Group already exists: $($group.Name)"
        }
    }
}

# Function to create Users and add them to groups
function Create-UsersAndAddToGroups {
    $users = @(
        @{Name = "John Doe"; SamAccountName = "john.doe"; Group = "IT Admins"},
        @{Name = "Jane Smith"; SamAccountName = "jane.smith"; Group = "IT Admins"},
        @{Name = "Alice Johnson"; SamAccountName = "alice.johnson"; Group = "HR Staff"},
        @{Name = "Bob Brown"; SamAccountName = "bob.brown"; Group = "Finance Staff"},
        @{Name = "Carol White"; SamAccountName = "carol.white"; Group = "Marketing Staff"}
    )

    foreach ($user in $users) {
        $firstName, $lastName = $user.Name -split " "
        $userPrincipalName = "$($user.SamAccountName)@$domainName"
        $ouPath = "OU=Users,OU=LIT,DC=$($domainName -replace "\.", ",DC=")"

        if (-not (Get-ADUser -Filter "SamAccountName -eq '$($user.SamAccountName)'" -ErrorAction SilentlyContinue)) {
            New-ADUser -Name $user.Name `
                       -GivenName $firstName `
                       -Surname $lastName `
                       -SamAccountName $user.SamAccountName `
                       -UserPrincipalName $userPrincipalName `
                       -Path $ouPath `
                       -AccountPassword $securePass `
                       -Enabled $true
            Write-Host "Created user: $($user.Name)"

            Add-ADGroupMember -Identity $user.Group -Members $user.SamAccountName
            Write-Host "Added $($user.Name) to group: $($user.Group)"
        } else {
            Write-Host "User already exists: $($user.Name)"
        }
    }
}

#================================
# 3. MAIN EXECUTION
#================================

# Import the Active Directory module
Import-Module ActiveDirectory

# Create Organizational Units
Create-OrganizationalUnits

# Create Groups
Create-Groups

# Create Users and add them to groups
Create-UsersAndAddToGroups

#================================
# 4. VERIFICATION
#================================

Write-Host "`nVerifying Organizational Units:"
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName

Write-Host "`nVerifying Groups:"
Get-ADGroup -Filter * | Where-Object {$_.DistinguishedName -like "*OU=Groups,OU=LIT*"} | Select-Object Name, DistinguishedName

Write-Host "`nVerifying Users and their Group Memberships:"
Get-ADUser -Filter * -Properties MemberOf | Where-Object {$_.DistinguishedName -like "*OU=Users,OU=LIT*"} | ForEach-Object {
    $user = $_
    $groups = $user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }
    [PSCustomObject]@{
        Name = $user.Name
        SamAccountName = $user.SamAccountName
        Groups = ($groups -join ", ")
    }
} | Format-Table -AutoSize

Write-Host "`nScript execution completed."
Write-Host "Remember to run this script on the Domain Controller (lit-dc) after it has been promoted and AD DS is fully configured."
