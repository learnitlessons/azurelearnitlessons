# Active Directory RID Pool Check and Fix Script

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
    # Import necessary modules
    Import-Module ActiveDirectory

    # Function to check RID pool status
    function Check-RIDPoolStatus {
        $ridPool = Get-ADDomain | Select-Object -ExpandProperty RIDAvailable
        Write-Host "Current RID Pool Available: $ridPool"
        return $ridPool
    }

    # Function to increase RID pool
    function Increase-RIDPool {
        try {
            # Increase the RID pool by 100,000
            Write-Host "Attempting to increase RID pool..."
            $result = Invoke-Expression -Command "C:\Windows\System32\ntdsutil.exe `"rid master`" `"rid pool`" `"rid allocation set 100000`" q q"
            Write-Host $result
            Write-Host "RID pool increase attempted. Please check the output above for success or failure."
        }
        catch {
            Write-Host "An error occurred while trying to increase the RID pool: $_"
        }
    }

    # Main execution
    $ridPoolStatus = Check-RIDPoolStatus

    if ($ridPoolStatus -lt 1000) {
        Write-Host "RID pool is low. Attempting to increase..."
        Increase-RIDPool
        
        # Check status again after increase attempt
        $newRidPoolStatus = Check-RIDPoolStatus
        if ($newRidPoolStatus -gt $ridPoolStatus) {
            Write-Host "RID pool successfully increased."
        } else {
            Write-Host "Failed to increase RID pool. Please check domain controller logs for more information."
        }
    } else {
        Write-Host "RID pool seems to be sufficient. If you're still experiencing issues, please check other aspects of your Active Directory."
    }
}

# Azure Cloud Shell execution
$resourceGroup = "rg-lit-ADLab-ukw"  # Replace with your resource group name
$vmName = "lon-dc1"  # Replace with your domain controller VM name

Write-Host "Executing Active Directory RID pool check and fix script on $vmName..."
Invoke-RemoteScript -ResourceGroupName $resourceGroup -VMName $vmName -ScriptBlock $remoteScript
