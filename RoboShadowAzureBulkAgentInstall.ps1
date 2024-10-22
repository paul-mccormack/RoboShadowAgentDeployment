#Script prepared by Paul McCormack.  This script will find all powered on Windows VM's in an Azure subscription and install the RoboShadow monitoring agent
#Instructions for use
#Login to Azure in PowerShell using "Connect-AzAccount".  Set your context to the target subscription using Set-AzContext -SubscriptionId <your sub id> then run the script.

#Powershell script to run
$scriptBlock = {
    $organisationId = "YOUR ORGANISATION ID"
    $haveSetOrgId = $True

    $version = (Get-ItemProperty -Path "HKLM:\SOFTWARE\RoboShadowLtd\Rubicon\Agent" -Name "Version" -ErrorAction SilentlyContinue).$valueName

    if ($haveSetOrgId -and (-not $version -or [int]($version -split '\.')[0] -lt 4)) {
        Start-Process "C:\Windows\System32\msiexec.exe" -ArgumentList "/i https://cdn.roboshadow.com/GetAgent/RoboShadowAgent-x64.msi /qb /norestart ORGANISATION_ID=$organisationId" -Wait
    }
}

$script = [scriptblock]::create($scriptBlock)

#Get all fully provisioned Windows VM's
$VmResources = Get-AzVm | Where-Object {$_.StorageProfile.OsDisk.OsType -eq "Windows" -and $_.ProvisioningState -eq "Succeeded"}

#Install RoboShadow Agent onto each running Windows based VM discovered
foreach($VmResource in $VmResources)
{
    Invoke-AzVMRunCommand -ResourceGroupName $VmResource.ResourceGroupName -VMName $VmResource.Name -CommandId 'RunPowerShellScript' -ScriptString $script
}