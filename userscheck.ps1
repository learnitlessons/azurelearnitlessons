# Active Directory Lab Verification Script for Azure Cloud Shell

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
    Import-Module GroupPolicy

    # Function to check Organizational Units
    function Check-OUs {
        $ExpectedOUs = @(
            "Departments",
            "Security Groups",
            "Service Accounts",
            "Computers",
            "IT",
            "HR",
            "Finance",
            "Marketing",
            "Sales"
        )

        $DomainDN = (Get-ADDomain).DistinguishedName

        foreach ($OU in $ExpectedOUs) {
            $OUDN = "OU=$OU,$DomainDN"
            if (Get-ADOrganizationalUnit -Filter {DistinguishedName -eq $OUDN} -ErrorAction SilentlyContinue) {
                Write-Host "OU exists: $OU" -ForegroundColor Green
            } else {
                Write-Host "OU missing: $OU" -ForegroundColor Red
            }
        }
    }

    # Function to check Security Groups
    function Check-SecurityGroups {
        $ExpectedGroups = @(
            "IT-Staff", "HR-Staff", "Finance-Staff", "Marketing-Staff", "Sales-Staff",
            "Helpdesk"
        )

        foreach ($Group in $ExpectedGroups) {
            if (Get-ADGroup -Filter {Name -eq $Group} -ErrorAction SilentlyContinue) {
                Write-Host "Security Group exists: $Group" -ForegroundColor Green
            } else {
                Write-Host "Security Group missing: $Group" -ForegroundColor Red
            }
        }
    }

    # Function to check Users
    function Check-Users {
        $ExpectedUsers = @(
            "john.doe", "jane.smith", "bob.johnson", "alice.brown", "charlie.davis",
            "eve.wilson", "frank.miller", "grace.lee", "henry.taylor", "ivy.chen"
        )

        foreach ($User in $ExpectedUsers) {
            if (Get-ADUser -Filter {SamAccountName -eq $User} -ErrorAction SilentlyContinue) {
                Write-Host "User exists: $User" -ForegroundColor Green
            } else {
                Write-Host "User missing: $User" -ForegroundColor Red
            }
        }
    }

    # Function to check Service Accounts
    function Check-ServiceAccounts {
        $ExpectedServiceAccounts = @(
            "svc-sql", "svc-web", "svc-backup"
        )

        foreach ($Account in $ExpectedServiceAccounts) {
            if (Get-ADUser -Filter {SamAccountName -eq $Account} -ErrorAction SilentlyContinue) {
                Write-Host "Service Account exists: $Account" -ForegroundColor Green
            } else {
                Write-Host "Service Account missing: $Account" -ForegroundColor Red
            }
        }
    }

    # Function to check GPOs
    function Check-GPOs {
        $ExpectedGPOs = @(
            "IT Department Policy",
            "HR Department Policy",
            "Finance Department Policy",
            "Marketing Department Policy",
            "Sales Department Policy"
        )

        foreach ($GPO in $ExpectedGPOs) {
            if (Get-GPO -Name $GPO -ErrorAction SilentlyContinue) {
                Write-Host "GPO exists: $GPO" -ForegroundColor Green
            } else {
                Write-Host "GPO missing: $GPO" -ForegroundColor Red
            }
        }
    }

    # Main verification execution
    try {
        Write-Host "Checking Organizational Units..." -ForegroundColor Yellow
        Check-OUs

        Write-Host "`nChecking Security Groups..." -ForegroundColor Yellow
        Check-SecurityGroups

        Write-Host "`nChecking Users..." -ForegroundColor Yellow
        Check-Users

        Write-Host "`nChecking Service Accounts..." -ForegroundColor Yellow
        Check-ServiceAccounts

        Write-Host "`nChecking Group Policies..." -ForegroundColor Yellow
        Check-GPOs

        Write-Host "`nActive Directory lab structure verification completed." -ForegroundColor Yellow
    }
    catch {
        Write-Host "An error occurred during verification: $_" -ForegroundColor Red
    }
}

# Azure Cloud Shell execution
$resourceGroup = "rg-lit-ADLab-ukw"  # Replace with your resource group name
$vmName = "lon-dc1"  # Replace with your domain controller VM name

Write-Host "Executing Active Directory lab verification script on $vmName..."
Invoke-RemoteScript -ResourceGroupName $resourceGroup -VMName $vmName -ScriptBlock $remoteScript
