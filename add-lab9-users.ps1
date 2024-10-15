# Active Directory Users and Computers Lab Script for Azure Cloud Shell

# This script assumes that the Azure AD Multi-Region Deployment Script has been run
# and that the domain controllers are set up and operational.

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

    # Function to create Organizational Units (OUs)
    function Create-OUs {
        param (
            [string]$DomainDN
        )
        
        $OUs = @(
            "OU=Departments,$DomainDN",
            "OU=Security Groups,$DomainDN",
            "OU=Service Accounts,$DomainDN",
            "OU=Computers,$DomainDN"
        )

        $DepartmentOUs = @(
            "OU=IT,OU=Departments,$DomainDN",
            "OU=HR,OU=Departments,$DomainDN",
            "OU=Finance,OU=Departments,$DomainDN",
            "OU=Marketing,OU=Departments,$DomainDN",
            "OU=Sales,OU=Departments,$DomainDN"
        )

        foreach ($OU in $OUs + $DepartmentOUs) {
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OU'" -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $OU.Split(',')[0].Split('=')[1] -Path ($OU -replace "^[^,]+,","")
                Write-Host "Created OU: $OU"
            } else {
                Write-Host "OU already exists: $OU"
            }
        }
    }

    # Function to create Security Groups
    function Create-SecurityGroups {
        param (
            [string]$DomainDN
        )
        
        $Groups = @(
            @{Name="IT-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="HR-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Finance-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Marketing-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Sales-Staff"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Domain-Admins"; Path="OU=Security Groups,$DomainDN"},
            @{Name="Helpdesk"; Path="OU=Security Groups,$DomainDN"}
        )

        foreach ($Group in $Groups) {
            if (-not (Get-ADGroup -Filter "Name -eq '$($Group.Name)'" -ErrorAction SilentlyContinue)) {
                New-ADGroup -Name $Group.Name -GroupScope Global -GroupCategory Security -Path $Group.Path
                Write-Host "Created Security Group: $($Group.Name)"
            } else {
                Write-Host "Security Group already exists: $($Group.Name)"
            }
        }
    }

    # Function to create Users
    function Create-Users {
        param (
            [string]$DomainDN
        )
        
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

        foreach ($User in $Users) {
            $UserPrincipalName = "$($User.SamAccountName)@$($DomainDN.Replace(',DC=','.').Replace('DC=',''))"
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($User.SamAccountName)'" -ErrorAction SilentlyContinue)) {
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

                # Add user to corresponding department group
                Add-ADGroupMember -Identity "$($User.Department)-Staff" -Members $User.SamAccountName
                Write-Host "Added $($User.Name) to $($User.Department)-Staff group"
            } else {
                Write-Host "User already exists: $($User.Name)"
            }
        }

        # Add John Doe to Domain Admins
        Add-ADGroupMember -Identity "Domain Admins" -Members "john.doe"
        Write-Host "Added John Doe to Domain Admins group"

        # Add Eve Wilson to Helpdesk
        Add-ADGroupMember -Identity "Helpdesk" -Members "eve.wilson"
        Write-Host "Added Eve Wilson to Helpdesk group"
    }

    # Function to create Service Accounts
    function Create-ServiceAccounts {
        param (
            [string]$DomainDN
        )
        
        $ServiceAccounts = @(
            @{Name="SQL Service Account"; SamAccountName="svc-sql"},
            @{Name="Web Service Account"; SamAccountName="svc-web"},
            @{Name="Backup Service Account"; SamAccountName="svc-backup"}
        )

        $Password = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force

        foreach ($Account in $ServiceAccounts) {
            $UserPrincipalName = "$($Account.SamAccountName)@$($DomainDN.Replace(',DC=','.').Replace('DC=',''))"
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($Account.SamAccountName)'" -ErrorAction SilentlyContinue)) {
                New-ADUser -Name $Account.Name `
                           -SamAccountName $Account.SamAccountName `
                           -UserPrincipalName $UserPrincipalName `
                           -Enabled $true `
                           -PasswordNeverExpires $true `
                           -Path "OU=Service Accounts,$DomainDN" `
                           -AccountPassword $Password
                Write-Host "Created Service Account: $($Account.Name)"
            } else {
                Write-Host "Service Account already exists: $($Account.Name)"
            }
        }
    }

    # Function to create GPOs
    function Create-GPOs {
        param (
            [string]$DomainName
        )
        
        $GPOs = @(
            @{Name="Default Domain Policy"; Target="Domain"},
            @{Name="IT Department Policy"; Target="OU=IT,OU=Departments"},
            @{Name="HR Department Policy"; Target="OU=HR,OU=Departments"},
            @{Name="Finance Department Policy"; Target="OU=Finance,OU=Departments"},
            @{Name="Marketing Department Policy"; Target="OU=Marketing,OU=Departments"},
            @{Name="Sales Department Policy"; Target="OU=Sales,OU=Departments"}
        )

        foreach ($GPO in $GPOs) {
            if (-not (Get-GPO -Name $GPO.Name -ErrorAction SilentlyContinue)) {
                $NewGPO = New-GPO -Name $GPO.Name
                if ($GPO.Target -eq "Domain") {
                    New-GPLink -Guid $NewGPO.Id -Target "DC=$($DomainName.Replace('.',',DC='))"
                } else {
                    New-GPLink -Guid $NewGPO.Id -Target "$($GPO.Target),DC=$($DomainName.Replace('.',',DC='))"
                }
                Write-Host "Created and linked GPO: $($GPO.Name)"
            } else {
                Write-Host "GPO already exists: $($GPO.Name)"
            }
        }
    }

    # Main script execution
    $ErrorActionPreference = "Stop"

    try {
        # Get the domain information
        $Domain = Get-ADDomain
        $DomainDN = $Domain.DistinguishedName
        $DomainName = $Domain.DNSRoot

        Write-Host "Creating Organizational Units..."
        Create-OUs -DomainDN $DomainDN

        Write-Host "Creating Security Groups..."
        Create-SecurityGroups -DomainDN $DomainDN

        Write-Host "Creating Users..."
        Create-Users -DomainDN $DomainDN

        Write-Host "Creating Service Accounts..."
        Create-ServiceAccounts -DomainDN $DomainDN

        Write-Host "Creating Group Policies..."
        Create-GPOs -DomainName $DomainName

        Write-Host "Active Directory Users and Computers lab setup completed successfully."
    }
    catch {
        Write-Host "An error occurred: $_"
    }
}

# Azure Cloud Shell execution
$resourceGroup = "rg-lit-ADLab-ukw"  # Replace with your resource group name
$vmName = "lon-dc1"  # Replace with your domain controller VM name

Write-Host "Executing Active Directory setup script on $vmName..."
Invoke-RemoteScript -ResourceGroupName $resourceGroup -VMName $vmName -ScriptBlock $remoteScript
