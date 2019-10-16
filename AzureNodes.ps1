#******************************************************************************
# Section: Header 
#
# Author: Jerome Allen
# GitHub name: sbJerome
# Last Updated: 8/12/2019
#
# Synopsos: This script should power on and off VM's as needed to process jobs
#           On the Azure HPC Nodes
# Notes: This script generally requires the use of an Azure Service Principal.
#        Please create one prior to using this script in a production, or test
#        Environment.
#******************************************************************************
<#
    
MIT License

Copyright (c) 2019 sbJerome

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


#>
#******************************************************************************
# Clear the Host 
#---------------------------------------------
Clear-Host

# Output to Console or EventViewer
#---------------------------------------------
# Specify 0 for Event Viewer, 1 for Console, 2 for both
$outputtoconsole = 2

# Run script One Time or Indefinitely.
#---------------------------------------------
# Specify 1 to Run Once, 0 Indefinitely
$runOnce = 1

# Import Modules, Scripts & Snappins
#---------------------------------------------
#Import-Module AzureRM
Add-PSSnapIn Microsoft.HPC

# Write to Windows > Application Event Log
#---------------------------------------------
# ! Change This Value
$LogName = Application
$SourceName = "Azure Modeling Nodes PS Automation"

# Specify Azure Subscription Here
#---------------------------------------------
# ! Change Theses Values
$subId = "<This is the Subscription ID Assigned to your Resource Group>"
$tenantId = "<Put Your Azure Tennance ID Here>"
$appId = "<This is the Application ID tied to your Service Princial>" # THIS IS ONLY NEEDED FOR SERVICE PRINCIPAL
#---------------------------------------------
# ! Change This Value
$AZVMRGName = "<Enter your Azure Resource Group Name"

# Set Error Action
#---------------------------------------------
$ErrorActionPreference = "SilentlyContinue"
# $ErrorActionPreference = "Continue"

# Misc Variables
#---------------------------------------------
$passwd = ConvertTo-SecureString -AsPlainText -Force -String '<Enter your Service Principal Password Here>'  # THIS IS ONLY NEEDED FOR SERVICE PRINCIPAL
$appCred = New-Object System.Management.Automation.PSCredential ($appId, $passwd);  # THIS IS ONLY NEEDED FOR SERVICE PRINCIPAL
$HPCDetail = @()

#******************************************************************************
# Section: Functions 
# All function Used in the Script Body are defined here
# Any new functions should be put here for preganization purposes
#******************************************************************************

function Login { # THIS IS ONLY NEEDED FOR SERVICE PRINCIPAL
    $repsonse = Connect-AzureRmAccount -ServicePrincipal -SubscriptionId $subId -Tenant $tenantId -Credential $appCred
    if ($repsonse -eq $null) { Write-Event -eventID 1403 -isType 1 -logMessage "Logon Failed!"; return 0; } else {
        Write-Event -eventID 1200 -isType 3 -logMessage "Logged into Azure"
        $passwd = $null
        $appCred = $null
        return 1
    }
}

function VerifyLogin { # THIS IS ONLY NEEDED FOR SERVICE PRINCIPAL
    if ($(Get-AzureRmContext).Account -eq $null) {
        Write-Event -eventID 1102 -isType 3 -logMessage "Attmepting Logon...`n";
        if(Login) {Write-Event -eventID 200 -isType 3 -logMessage "Logged into Azure"; return 1} else {return 0};
    } else {Write-Event -eventID 1200 -isType 3 -logMessage "Already Logged into Azure"; return 1}
}

function Write-Event($logMessage, $eventID, $isType) {
    if([System.Diagnostics.EventLog]::SourceExists($WindowsEventLogName) -eq $false) { New-EventLog –LogName $LogName -Source $SourceName }
    switch($outputtoconsole) {
        1 { write-host $logMessage; break; }
        2 { 
            write-host $logMessage 
            switch($isType) {
                1 { Write-EventLog –LogName Application –Source $WindowsEventLogName –EntryType Error –EventID $eventID -Category 1 –Message $logMessage; break} 
                2 { Write-EventLog –LogName Application –Source $WindowsEventLogName –EntryType Warning –EventID $eventID -Category 2 –Message $logMessage; break}
                3 { Write-EventLog –LogName Application –Source $WindowsEventLogName –EntryType Information –EventID $eventID -Category 3 –Message $logMessage; break}
            }
          }
        0 { 
            switch($isType) {
                1 { Write-EventLog –LogName Application –Source $WindowsEventLogName –EntryType Error –EventID $eventID -Category 1 –Message $logMessage; break} 
                2 { Write-EventLog –LogName Application –Source $WindowsEventLogName –EntryType Warning –EventID $eventID -Category 2 –Message $logMessage; break}
                3 { Write-EventLog –LogName Application –Source $WindowsEventLogName –EntryType Information –EventID $eventID -Category 3 –Message $logMessage; break}
            }
        }
    }
}
#

function Get-HPCVM($resourceGroupName) { 
    #Check for existing resource group
    
    if(!(Get-AzureRmResourceGroup -Name $resourceGroupName))
    {
        Write-Event -eventID 1003 -isType 1 -logMessage "Resource group $($resourceGroupName) does not exist.";
        break;
    }
    else{
        $HPCWT = 0
        $NODECT = 0
        $VMs = Get-AzureRmVM -ResourceGroupName $resourceGroupName

        foreach ($VM in $VMs) { 
            if ($VM.Name.Contains("HN")) { 
                $HPCHN = $VM.Name;
                Set-Content Env:CCP_SCHEDULER $VM.Name
                Set-Content Env:CCP_CONNECTIONSTRING $VM.Name
                break; 
            }
            elseif ($VM.Name.Contains("CN")) {
                $NODECT++
            }  
        }

        foreach($VM in $VMs) {

            $VMDetail = Get-AzureRmVM -ResourceGroupName $resourceGroupName -Name $VM.Name -Status
      
            foreach ($VMStatus in $VMDetail.Statuses)
            { 
                if($VMStatus.DisplayStatus -eq "VM running") { $VMPower = 1 } else { $VMPower = 0 }
            }

            # This is a flag that tells you the node type. 0 - HEAD NODE, 1 - COMPUTE NODE, 2 - OTHER
            if ($VM.Name.Contains("HN")) { $HPCNT = 0 } elseif ($VM.Name.Contains("CN")) { $HPCNT = 1; $HPCWT += ((100/$NODECT)/100) } else { $HPCNT = 2} 

            $hash = @{
                HPCNN = $VM.Name # THis is the HPC Node Name Ex. AZEAAIR06CN01
                HPCPP = $VMPower # This is a flag that tells you if the node is powered on or not
                HPCHN = $HPCHN   # This is the Name of the Head Node in the Resource Group
                HPCNT = $HPCNT   # This is a flag that tells you the node type. 0 - HEAD NODE, 1 - COMPUTE NODE, 2 - OTHER
                HPCWT = $HPCWT   # This is the total HPC Farm Compute Capacity. Each Node has a weight assigned to help the script power own machines based on need.
            }

            $newEntry = New-Object -TypeName PSObject -Property $hash
            $HPCDetail += $newEntry
            remove-variable newEntry
        }

        return $HPCDetail
    }
}

function Get-HPCJW($HPCS, $HPCNN) {
    #NJC is equal to the number of jobs running on the individual HPCNN (HPC NODE NAME) specified in the function call
    try {
        if($HPCNN -eq $null) { $NJC = 0 } else { $NJC = (Get-HpcJob -NodeName $HPCNN -Scheduler $HPCS[0].HPCHN).count }
        $HPCJOB = @{
            QJ = (Get-HpcClusterOverview -Scheduler $HPCS[0].HPCHN).QueuedJobCount
            RJ = (Get-HpcClusterOverview -Scheduler $HPCS[0].HPCHN).RunningJobCount
            SJ = (Get-HpcClusterOverview -Scheduler $HPCS[0].HPCHN).SubmittedJobCount
            FJ = (Get-HpcClusterOverview -Scheduler $HPCS[0].HPCHN).FinishingJobCount
            NJC = $NJC
        }
        if(($HPCJOB.QJ+$HPCJOB.RJ) -eq 0) {$HPCJOB.JW = ($HPCJOB.QJ/1)} else {$HPCJOB.JW = ($HPCJOB.QJ/($HPCJOB.QJ+$HPCJOB.RJ))}
        
        return $HPCJOB
    }
    catch {
        $_
    
    }
}

function HPCVMturnoff($HPCVMN, $ARGN = $AZVMRGName) { #remove " -WhatIf" to run in Production
    $VMStatus1 = Set-HpcNodeState -Name $HPCVMN -State "Offline" -Async -Force
    $VMStatus2 = Stop-AzureRMVM -ResourceGroupName $ARGN -Name $HPCVMN  -Force

$message = @"
$($VMStatus1)
$($VMStatus2)
"Powered $($HPC.HPCNN) OFF"
"@ #DO NOT MOVE THIS - IT WILL CAUSE AN ERROR (POWERSHELL HERE-STRING)

    Write-Event -eventID 1003 -isType 3 -logMessage $message
}

function HPCVMturnon($HPCVMN, $ARGN = $AZVMRGName) { #remove "-WhatIf" to run in Production
    $VMStatus1 = Start-AzureRMVM -ResourceGroupName $ARGN -Name $HPCVMN
    $VMStatus2 = Set-HpcNodeState -Name $HPCVMN -State "Online" -Async

$message = @"
$($VMStatus1)
$($VMStatus2)
"Powered $($HPC.HPCNN) ON"
"@ #DO NOT MOVE THIS - IT WILL CAUSE AN ERROR (POWERSHELL HERE-STRING)

    Write-Event -eventID 1002 -isType 3 -logMessage $message
}

#******************************************************************************
# Section: Script Body
# The actual script is being run here
#******************************************************************************
#VerifyLogin
while(VerifyLogin) { # WHILE LOOP IS ONLY NEEDED WHEN USING SERVICE PRINCIPAL
    $HPCS = Get-HPCVM -resourceGroupName $AZVMRGName
    $HPCJOB = Get-HPCJW -HPCS $HPCS

    ForEach ($HPC in $HPCS) {      
        
        # HPCNT Identifier ->  0 - HEAD NODE, 1 - COMPUTE NODE, 2 - OTHER
        if(($HPC.HPCNT -eq 0) -and ($HPC.HPCPP -eq 1)) {
            $HPCJOB = Get-HPCJW -HPCS $HPCS
            Write-Event -eventID 1208 -isType 3 -logMessage "$($HPC.HPCNN) HeadNode is Powered ON and queueing  $($HPCJOB.QJ) job[s]"
            
        }
        if(($HPC.HPCNT -eq 0) -and ($HPC.HPCPP -eq 0)) {
            Write-Event -eventID 1404 -isType 1 -logMessage "$($HPC.HPCNN) HeadNode is Powered Off, Send Email Alert"
            
            break;
        }
        if(($HPC.HPCNT -eq 1) -and ($HPC.HPCPP -eq 1)) {
            $HPCJOB = Get-HPCJW -HPCS $HPCS -HPCNN $HPC.HPCNN

$message = @" 
$($HPC.HPCNN) ComputeNode is Powered ON with $($HPCJOB.NJC) job[s] running
$($HPC.HPCNN) ComputeNode weight is $($HPC.HPCWT)
Job weight is $($HPCJOB.JW)
"@ #DO NOT MOVE THIS - IT WILL CAUSE AN ERROR (POWERSHELL HERE-STRING)

            Write-Event -eventID 208 -isType 3 -logMessage $message
            
            if(($HPCJOB.NJC -eq 0) -and ($HPCJOB.JW -eq 0)) { 
                if ($HPC.HPCNN.Contains("CN01")) { 
                    Write-Event -eventID 1403 -isType 2 -logMessage "$($HPC.HPCNN) SHOULD NOT BE POWERED OFF" 
                } 
                else {
                    HPCVMturnoff -HPCVMN $HPC.HPCNN
                }
            }
        }      
        if(($HPC.HPCNT -eq 1) -and ($HPC.HPCPP -eq 0)) {
            $HPCJOB = Get-HPCJW -HPCS $HPCS

$message = @" 
$($HPC.HPCNN) ComputeNode is Powered OFF
$($HPC.HPCNN) ComputeNode weight is $($HPC.HPCWT)
Job weight is $($HPCJOB.JW)
"@ #DO NOT MOVE THIS - IT WILL CAUSE AN ERROR (POWERSHELL HERE-STRING)

            Write-Event -eventID 1208 -isType 3 -logMessage $message

            if($HPCJOB.JW -ge $HPC.HPCWT ) {
                Write-Event -eventID 208 -isType 3 -logMessage "$($HPC.HPCNN) ComputeNode weight is $($HPC.HPCWT)"
                HPCVMturnon -HPCVMN $HPC.HPCNN
            }

        }
    
    }
    # Run Script Once or Wait 5 minutes and Run Again, Script will run indefinietly until all jobs have completed
    if($runOnce -eq 1) { break; } else { Start-Sleep -s 300 } 
}
