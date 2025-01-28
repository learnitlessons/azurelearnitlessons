# Cautious Script to Repopulate AD Lab Structure with Verification

# Function to run a script block on a remote server
function Invoke-RemoteScript {
    param (
        [string]$ResourceGroupName,
        [string]$VMName,
        [scriptblock]$ScriptBlock
    )

    $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId 'RunPowerShellScript' -ScriptString $ScriptBlock.ToString()
    
    if ($result.Status -eq "Succeeded") {
        Write-Host $result.Value[0].Message
    } else {
        Write-Host "Error occurred while executing command on $VMName"
        Write-Host $result.Value[0].Message
    }
}

# Main script to be run on the remote server
$remoteScript = {
    # Import the Active Directory module
    Import-Module ActiveDirectory

    # Function to create and verify Organizational Units (OUs)
    function Create-and-Verify-OUs {
        $DomainDN = (Get-ADDomain).DistinguishedName
        $OUs = @(
            "OU=Computers,$DomainDN",
            "OU=IT,OU=Departments,$DomainDN",
            "OU=HR,OU=Departments,$DomainDN",
            "OU=Finance,OU=Departments,$DomainDN",
            "OU=Marketing,OU=Departments,$DomainDN",
            "OU=Sales,OU=Departments,$DomainDN"
        )

        $created = 0
        $existing = 0
        $total = $OUs.Count

        foreach ($OU in $OUs) {
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OU'" -ErrorAction SilentlyContinue)) {
                try {
                    New-ADOrganizationalUnit -Name $OU.Split(',')[0].Split('=')[1] -Path ($OU -replace "^[^,]+,","")
                    Write-Host "Created OU: $OU"
                    $created++
                } catch {
                    Write-Host "Error creating OU $OU : $_"
                }
            } else {
                Write-Host "OU already exists: $OU"
                $existing++
            }
        }

        Write-Host "OU Status: $created created, $existing already existed, out of $total total."
        return ($created + $existing -eq $total)
    }

    # Function to create and verify Security Groups
    function Create-and-Verify-SecurityGroups {
        $DomainDN = (Get-ADDomain).DistinguishedName
        $Groups = @(
            @{Name="IT-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="HR-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Finance-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Marketing-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Sales-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Helpdesk"; Path="OU=Security Groups,$DomainDN"}
        )

        $created = 0
        $existing = 0
        $total = $Groups.Count

        foreach ($Group in $Groups) {
            if (-not (Get-ADGroup -Filter "Name -eq '$($Group.Name)'" -ErrorAction SilentlyContinue)) {
                try {
                    New-ADGroup -Name $Group.Name -GroupScope Global -GroupCategory Security -Path $Group.Path
                    Write-Host "Created Security Group: $($Group.Name)"
                    $created++
                } catch {
                    Write-Host "Error creating Security Group $($Group.Name) : $_"
                }
            } else {
                Write-Host "Security Group already exists: $($Group.Name)"
                $existing++
            }
        }

        Write-Host "Security Group Status: $created created, $existing already existed, out of $total total."
        return ($created + $existing -eq $total)
    }

    # Function to create and verify Users
    function Create-and-Verify-Users {
        $DomainDN = (Get-ADDomain).DistinguishedName
        $Users = @(
            @{Name="John Doe"; SamAccountName="john.doe"; Department="IT"; Title="IT Manager"},
            @{Name="Jane Smith"; SamAccountName="jane.smith"; Department="HR"; Title="HR Manager"},
            @{Name="Bob Johnson"; SamAccountName="bob.johnson"; Department="Finance"; Title="Finance Manager"},
            @{Name="Alice Brown"; SamAccountName="alice.brown"; Department="Marketing"; Title="Marketing Manager"},
            @{Name="Charlie Davis"; SamAccountName="charlie.davis"; Department="Sales"; Title="Sales Manager"},
            @{Name="Eve Wilson"; SamAccountName="eve.wilson"; Department="IT"; Title="System Administrator"},
            @{Name="Frank Miller"; SamAccountName="frank.miller"; Department="HR"; Title="HR Specialist"},
            @{Name="Grace Lee"; SamAccountName="grace.lee"; Department="Finance"; Title="Accountant"},
            @{Name="Henry Taylor"; SamAccountName="henry.taylor"; Department="Marketing"; Title="Marketing Specialist"},
            @{Name="Ivy Chen"; SamAccountName="ivy.chen"; Department="Sales"; Title="Sales Representative"}
        )

        $Password = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force

        $created = 0
        $existing = 0
        $total = $Users.Count

        foreach ($User in $Users) {
            $UserPrincipalName = "$($User.SamAccountName)@$($DomainDN.Replace(',DC=','.').Replace('DC=',''))"
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($User.SamAccountName)'" -ErrorAction SilentlyContinue)) {
                try {
                    New-ADUser -Name $User.Name `
                               -SamAccountName $User.SamAccountName `
                               -UserPrincipalName $UserPrincipalName `
                               -GivenName $User.Name.Split()[0] `
                               -Surname $User.Name.Split()[1] `
                               -Enabled $true `
                               -ChangePasswordAtLogon $true `
                               -Department $User.Department `
                               -Title $User.Title `
                               -Path "OU=$($User.Department),OU=Departments,$DomainDN" `
                               -AccountPassword $Password
                    Write-Host "Created User: $($User.Name)"
                    $created++

                    # Add user to corresponding department group
                    Add-ADGroupMember -Identity "$($User.Department)-Staff" -Members $User.SamAccountName
                    Write-Host "Added $($User.Name) to $($User.Department)-Staff group"
                } catch {
                    Write-Host "Error creating User $($User.Name) : $_"
                }
            } else {
                Write-Host "User already exists: $($User.Name)"
                $existing++
            }
        }

        # Add John Doe to Domain Admins if not already a member
        if (-not (Get-ADGroupMember -Identity "Domain Admins" | Where-Object {$_.SamAccountName -eq "john.doe"})) {
            Add-ADGroupMember -Identity "Domain Admins" -Members "john.doe"
            Write-Host "Added John Doe to Domain Admins group"
        }

        # Add Eve Wilson to Helpdesk if not already a member
        if (-not (Get-ADGroupMember -Identity "Helpdesk" | Where-Object {$_.SamAccountName -eq "eve.wilson"})) {
            Add-ADGroupMember -Identity "Helpdesk" -Members "eve.wilson"
            Write-Host "Added Eve Wilson to Helpdesk group"
        }

        Write-Host "User Status: $created created, $existing already existed, out of $total total."
        return ($created + $existing -eq $total)
    }

    # Function to create and verify Service Accounts
    function Create-and-Verify-ServiceAccounts {
        $DomainDN = (Get-ADDomain).DistinguishedName
        $ServiceAccounts = @(
            @{Name="SQL Service Account"; SamAccountName="svc-sql"},
            @{Name="Web Service Account"; SamAccountName="svc-web"},
            @{Name="Backup Service Account"; SamAccountName="svc-backup"}
        )

        $Password = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force

        $created = 0
        $existing = 0
        $total = $ServiceAccounts.Count

        foreach ($Account in $ServiceAccounts) {
            $UserPrincipalName = "$($Account.SamAccountName)@$($DomainDN.Replace(',DC=','.').Replace('DC=',''))"
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($Account.SamAccountName)'" -ErrorAction SilentlyContinue)) {
                try {
                    New-ADUser -Name $Account.Name `
                               -SamAccountName $Account.SamAccountName `
                               -UserPrincipalName $UserPrincipalName `
                               -Enabled $true `
                               -PasswordNeverExpires $true `
                               -Path "OU=Service Accounts,$DomainDN" `
                               -AccountPassword $Password
                    Write-Host "Created Service Account: $($Account.Name)"
                    $created++
                } catch {
                    Write-Host "Error creating Service Account $($Account.Name) : $_"
                }
            } else {
                Write-Host "Service Account already exists: $($Account.Name)"
                $existing++
            }
        }

        Write-Host "Service Account Status: $created created, $existing already existed, out of $total total."
        return ($created + $existing -eq $total)
    }

    # Main script execution
    $ErrorActionPreference = "Continue"
    $overallSuccess = $true

    try {
        Write-Host "Creating and Verifying Organizational Units..."
        $ouSuccess = Create-and-Verify-OUs
        $overallSuccess = $overallSuccess -and $ouSuccess

        Write-Host "`nCreating and Verifying Security Groups..."
        $groupSuccess = Create-and-Verify-SecurityGroups
        $overallSuccess = $overallSuccess -and $groupSuccess

        Write-Host "`nCreating and Verifying Users..."
        $userSuccess = Create-and-Verify-Users
        $overallSuccess = $overallSuccess -and $userSuccess

        Write-Host "`nCreating and Verifying Service Accounts..."
        $serviceAccountSuccess = Create-and-Verify-ServiceAccounts
        $overallSuccess = $overallSuccess -and $serviceAccountSuccess

        if ($overallSuccess) {
            Write-Host "`nActive Directory lab structure repopulation completed successfully."
        } else {
            Write-Host "`nActive Directory lab structure repopulation completed with some issues. Please review the output above."
        }
    }
    catch {
        Write-Host "An error occurred: $_"
        $overallSuccess = $false
    }

    Write-Host "`nSummary:"
    Write-Host "OUs: $(if ($ouSuccess) { 'Success' } else { 'Incomplete' })"
    Write-Host "Security Groups: $(if ($groupSuccess) { 'Success' } else { 'Incomplete' })"
    Write-Host "Users: $(if ($userSuccess) { 'Success' } else { 'Incomplete' })"
    Write-Host "Service Accounts: $(if ($serviceAccountSuccess) { 'Success' } else { 'Incomplete' })"
    Write-Host "Overall Status: $(if ($overallSuccess) { 'Success' } else { 'Incomplete' })"
}

# Azure Cloud Shell execution
$resourceGroup = "rg-lit-ADLab-ukw"  # Replace with your resource group name
$vmName = "lon-dc1"  # Replace with your domain controller VM name

Write-Host "Executing cautious Active Directory repopulation script with verification on $vmName..."
Invoke-RemoteScript -ResourceGroupName $resourceGroup -VMName $vmName -ScriptBlock $remoteScript
