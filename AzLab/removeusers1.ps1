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
    Import-Module GroupPolicy

    # Function to remove GPOs
    function Remove-CustomGPOs {
        $GPOs = @(
            "IT Department Policy",
            "HR Department Policy",
            "Finance Department Policy",
            "Marketing Department Policy",
            "Sales Department Policy"
        )

        foreach ($GPO in $GPOs) {
            try {
                $gpoObject = Get-GPO -Name $GPO -ErrorAction SilentlyContinue
                if ($gpoObject) {
                    # Remove all links to the GPO
                    $gpoObject | Get-GPOReport -ReportType XML | 
                    Select-String -Pattern '<SOMPath>(.*?)</SOMPath>' | 
                    ForEach-Object { 
                        $somPath = $_.Matches.Groups[1].Value
                        Remove-GPLink -Name $GPO -Target $somPath -ErrorAction SilentlyContinue
                    }
                    
                    # Now remove the GPO
                    Remove-GPO -Name $GPO -ErrorAction Stop
                    Write-Host "Removed GPO: $GPO"
                } else {
                    Write-Host "GPO not found: $GPO"
                }
            } catch {
                Write-Host "Error removing GPO $GPO : $_"
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
            try {
                if (Get-ADUser -Filter {SamAccountName -eq $User} -ErrorAction SilentlyContinue) {
                    Remove-ADUser -Identity $User -Confirm:$false
                    Write-Host "Removed User: $User"
                } else {
                    Write-Host "User not found: $User"
                }
            } catch {
                Write-Host "Error removing User $User : $_"
            }
        }
    }

    # Function to remove Security Groups
    function Remove-CustomGroups {
        $Groups = @(
            "IT-Staff", "HR-Staff", "Finance-Staff", "Marketing-Staff", "Sales-Staff",
            "Helpdesk"
        )

        foreach ($Group in $Groups) {
            try {
                if (Get-ADGroup -Filter {Name -eq $Group} -ErrorAction SilentlyContinue) {
                    Remove-ADGroup -Identity $Group -Confirm:$false
                    Write-Host "Removed Group: $Group"
                } else {
                    Write-Host "Group not found: $Group"
                }
            } catch {
                Write-Host "Error removing Group $Group : $_"
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
            try {
                $ouDN = "OU=$OU," + (Get-ADDomain).DistinguishedName
                if (Get-ADOrganizationalUnit -Filter {DistinguishedName -eq $ouDN} -ErrorAction SilentlyContinue) {
                    # Remove protection against accidental deletion
                    Set-ADOrganizationalUnit -Identity $ouDN -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
                    # Remove the OU and all its child objects
                    Remove-ADOrganizationalUnit -Identity $ouDN -Recursive -Confirm:$false -ErrorAction Stop
                    Write-Host "Removed OU: $OU"
                } else {
                    Write-Host "OU not found: $OU"
                }
            } catch {
                Write-Host "Error removing OU $OU : $_"
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
