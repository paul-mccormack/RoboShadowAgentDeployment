#Assign policy now?
$deployAssignment = Read-Host "Do you want to assign the policy now?  Enter Yes or No"
if ($deployAssignment -eq 'Yes'){
    $assignmentdeploymentScope = Read-Host "Do you want to assign at the policy definition scope? Enter Yes or No"
    if ($assignmentdeploymentScope -eq 'Yes'){
       $mg = Get-AzManagementGroup $policyDeploymentScope
       $policyDefinition = Get-AzPolicyDefinition -Name $policyParameters.PolicyId -ManagementGroupName $policyDeploymentScope
       New-AzPolicyAssignment -Name $policyDefinition.Id -Scope $mg.Id -Location uksouth -IdentityType SystemAssigned
    }
    elseif ($assignmentdeploymentScope -eq 'No') {
        <# Action when this condition is true #>
    }
}
elseif ($deployAssignment -eq 'No') {
    Write-Host "Script Complete"
}

if ($deployAssignment -eq 'Yes'){
    $remediate = Read-Host "Do you want to remediate the policy assignment now?  Enter Yes or No"
    if ($remediate -eq 'Yes'){
        Start-AzPolicyRemediation 
    }
    elseif ($remediate -eq 'No') {
        Write-Host "Script Complete"
    }
}
