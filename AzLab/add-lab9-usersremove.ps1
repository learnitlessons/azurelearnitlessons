# Active Directory Cleanup Script for Azure Cloud Shell

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

    # Function to remove GPOs
    function Remove-CustomGPOs {
        $GPOs = @(
            "Default Domain Policy",
            "IT Department Policy",
            "HR Department Policy",
            "Finance Department Policy",
            "Marketing Department Policy",
            "Sales Department Policy"
        )

        foreach ($GPO in $GPOs) {
            if (Get-GPO -Name $GPO -ErrorAction SilentlyContinue) {
                Remove-GPO -Name $GPO -Force
                Write-Host "Removed GPO: $GPO"
            } else {
                Write-Host "GPO not found: $GPO"
            }
        }
    }

    # Function to remove Users and Service Accounts
    function Remove-CustomUsers {
        $Users = @(
            "john.doe", "jane.smith", "bob.johnson", "alice.brown", "charlie.davis",
            "eve.wilson", "frank.miller", "grace.lee", "henry.taylor", "ivy.chen",
            "svc-sql", "svc-web", "svc-backup"
        )

        foreach ($User in $Users) {
            if (Get-ADUser -Filter {SamAccountName -eq $User} -ErrorAction SilentlyContinue) {
                Remove-ADUser -Identity $User -Confirm:$false
                Write-Host "Removed User: $User"
            } else {
                Write-Host "User not found: $User"
            }
        }
    }

    # Function to remove Security Groups
    function Remove-CustomGroups {
        $Groups = @(
            "IT-Staff", "HR-Staff", "Finance-Staff", "Marketing-Staff", "Sales-Staff",
            "Domain-Admins", "Helpdesk"
        )

        foreach ($Group in $Groups) {
            if (Get-ADGroup -Filter {Name -eq $Group} -ErrorAction SilentlyContinue) {
                Remove-ADGroup -Identity $Group -Confirm:$false
                Write-Host "Removed Group: $Group"
            } else {
                Write-Host "Group not found: $Group"
            }
        }
    }

    # Function to remove Organizational Units
    function Remove-CustomOUs {
        $OUs = @(
            "Departments",
            "Security Groups",
            "Service Accounts",
            "Computers"
        )

        foreach ($OU in $OUs) {
            $ouDN = "OU=$OU," + (Get-ADDomain).DistinguishedName
            if (Get-ADOrganizationalUnit -Filter {DistinguishedName -eq $ouDN} -ErrorAction SilentlyContinue) {
                # Remove protection against accidental deletion
                Set-ADOrganizationalUnit -Identity $ouDN -ProtectedFromAccidentalDeletion $false
                # Remove the OU and all its child objects
                Remove-ADOrganizationalUnit -Identity $ouDN -Recursive -Confirm:$false
                Write-Host "Removed OU: $OU"
            } else {
                Write-Host "OU not found: $OU"
            }
        }
    }

    # Main cleanup execution
    $ErrorActionPreference = "Continue"

    try {
        Write-Host "Removing GPOs..."
        Remove-CustomGPOs

        Write-Host "Removing Users and Service Accounts..."
        Remove-CustomUsers

        Write-Host "Removing Security Groups..."
        Remove-CustomGroups

        Write-Host "Removing Organizational Units..."
        Remove-CustomOUs

        Write-Host "Active Directory cleanup completed successfully."
    }
    catch {
        Write-Host "An error occurred during cleanup: $_"
    }
}

# Azure Cloud Shell execution
$resourceGroup = "rg-lit-ADLab-ukw"  # Replace with your resource group name
$vmName = "lon-dc1"  # Replace with your domain controller VM name

Write-Host "Executing Active Directory cleanup script on $vmName..."
Invoke-RemoteScript -ResourceGroupName $resourceGroup -VMName $vmName -ScriptBlock $remoteScript
