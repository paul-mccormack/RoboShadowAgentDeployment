
# RoboShadow agent deployment on Windows Azure VM's and hybrid connected VM's at scale

## Introduction

RoboShadow is a cloud hosted cyber security platform offering external vulnerabiltiy scanning, device attack surface management, MFA auditing and 365 AD Sync.  You can find out more at [RoboShadow.com](https://www.roboshadow.com/)

RoboShadow provides an installable agent for monitoring your devices. This can be installed using the downloadable msi file, a PowerShell script provided by RoboShadow, which I have included in this script: [RoboShadowAgentInstall.ps1](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/RoboShadowAgentInstall.ps1). If you have Microsoft Intune within your organisation and you need to deploy to your workstations you can utilise the "Deploy RoboShadow With Intune" functionality once you have the integration set-up.  Detailed guidance is available in their [documentation](https://roboshadow.atlassian.net/wiki/spaces/Roboshadow/overview?homepageId=4882647)

This is fine for a few servers or to your users workstations. What if you want to deploy to all your Windows based servers?  That was what I had to do and I didn't want to logon to a few hundred machines to run the install manually.  The first batch was around 20 test servers to make sure the agent didn't have any adverse effects, which it did not.  These test servers were all in Azure and running in the same subscription.  The next section details how I did this.

## Az PowerShell and the VM run command

As I have a ready made PowerShell script for installing the agent I can leverage the "Run Command" feature on the Azure based VM's I am targetting.  Of course, there is a PowerShell command for doing this remotely in the Az Module.  First we get all the Windows based servers in a subscription using [Get-AzVM](https://learn.microsoft.com/en-us/powershell/module/az.compute/get-azvm?view=azps-12.4.0), store the output in a variable then loop through with the [Invoke-AzVMRunCommand](https://learn.microsoft.com/en-us/powershell/module/az.compute/invoke-azvmruncommand?view=azps-12.4.0) executing the PowerShell code block provided by RoboShadow.  Super quick and easy.  The script to do this is included here: [RoboShadowAzureBulkAgentInstall.ps1](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/RoboShadowAzureBulkAgentInstall.ps1)

After a period of monitoring we decided it was time to deploy to everything, but how do you do that when you have hundreds of Windows server spread across Azure and on premise and ensure it is automatically deployed to newly created Windows servers?

## Azure Machine Configuration

[Azure Machine Configuration](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/), previously named Azure Policy Guest Configuration provides the ability to both audit and configure operating system settings and installed software, both for machines running in Azure and hybrid Arc-enabled machines running on premise or other public clouds.  You can use this feature directly on a per machine basis or orchestrate at scale using Azure Policy.

### <ins>NOTE<ins>

There are some prerequisites that need to be in place before you can use Azure Machine Configuration.  Your machines must have a system assigned managed identity to enable authentication to the machine configuration service and the machine configuration extension must be enabled on the VM.  Microsoft provide a built in policy initiative to handle this for you called "Deploy prerequisites to enable Guest Configuration policies on virtual machines"  Further information on this can be found [here](https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/guest-configuration). Arc-enabled machines don't require the extension as it is included in the Arc Connected Machine Agent. 

Azure Machine Configuration relies on [PowerShell Desired State Configuration](https://learn.microsoft.com/en-us/powershell/scripting/dsc/overview?view=powershell-7.4).  There are many providers for DSC available to achieve your goal configuration.  Go to the [PowerShell Gallery](https://www.powershellgallery.com/packages) and you can filter the results to DSC Resources

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/DSC_Resources.jpg)

I am going to be using Azure Machine Configuration to deploy the RoboShadow agent to all the Windows server based machines in my environment, both in Azure and on premise via [Azure Arc](https://learn.microsoft.com/en-us/azure/azure-arc/overview).  This will not only enable us to deploy the agent with miminal administrative overhead and check for any failures using the policy compliance blade. It will also ensure any machines created in the future will get the agent automatically upon deployment.

In the interest of code reusability I intend to create a script that can be repurposed to mass deploy any msi based software package.  This script will perform steps 1 to 4 listed below.  I've left steps 5 and 6 out of the automation as there is a lot of flexilbity around where you can assign a policy.  It could be done at the Management Group scope, a Subscription scope or a Resource Group scope.  I've assumed the policy definition would be deployed at a Management Group scope as that makes the most sense to me.  Creating a remediation task to apply the policy has been left to manual intervention as you should really go through a change control process before doing that.  This way you can have everything ready in a published and assigned policy before going through change control prior to deployment.  The rest of this guide explains the step by step commands the script is running and I'll introduce the resuable script once we get to the end of step 4.

The workflow is as follows:

- [Create a custom machine configuration package](#creating-a-custom-machine-configuration-package)
- [Upload the package to an Azure Storage account and generate a blob SAS token](#upload-the-package-to-azure-storage-and-generate-the-access-token)
- [Generate a Machine Configuration Azure policy definition](#generate-a-machine-configuration-azure-policy-definition)
- [Publish the policy definition to Azure](#publish-the-policy-definition-to-azure)
- [Assign the policy](#assign-the-policy)
- [Create a remediation task to apply to existing resources](#create-a-remediation-task-to-apply-to-existing-resources)

## Setting up the authoring environment

To get started you will need the latest version of [Powershell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4) Installed.  You will then need to install the GuestConfiguration, PSDesiredStateConfiguration and Azure modules.  The following commands will do this:

```Powershell
Install-Module -Name GuestConfiguration -Repository PSGallery
Install-Module -Name PSDesiredStateConfiguration -Repository PSGallery
Install-Module -Name Az -Repository PSGallery
```
Now that is done we can get started.

## Creating a custom machine configuration package

The first step is to create a DSC Configuration PowerShell Script.  Different providers will have different requirements for this script.  The PSDscResources module provides a funtion for installing an MSI package.  The example code below would create a custom machine configuration package to install PowerShell 7.

```PowerShell
Configuration powershell7 {
    Import-DscResource -ModuleName 'PSDscResources' -ModuleVersion 2.12.0.0

    Node localhost {
        MsiPackage PowerShell7MsiPackage {
            Path      = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.5/PowerShell-7.4.5-win-x64.msi'
            ProductId = '{C1593F76-F694-448E-AD35-82DDD6203975}'
            Ensure    = 'Present'
        }
    }
}

powershell7
```
You need the Product ID of the package you are installing.  You can either get that from the registry of a machine with the package already installed in HKEY_LOCAL_MACHINE\SOFTWARE\.  If you already have the msi downloaded you could use the [Get-MsiProductCode](https://www.powershellgallery.com/packages/Get-MsiProductCode/1.0) script from the PowerShell Gallery.

My configuration script to deploy the RoboShadow agent is included: [RoboShadowDsc.ps1](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/RoboShadowDsc.ps1)

Run this script in a PowerShell 7 session and it will create a subfolder named the same as your configuration containing a file called localhost.mof

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/machine_config_output.jpg)

The mof file contains the information related to your configuration.  Rename the file to something more descriptive than localhost.  I prefer to rename it to the same as the powershell script that produced it.  So I will rename it to RoboShadowDsc.mof.

With this mof file you can then create the package.  The following command will do that.

```PowerShell
New-GuestConfigurationPackage -Name 'RoboShadowAgentDeploy' -Configuration './deployRoboShadow/RoboShadowDsc.mof' -Type 'AuditAndSet' -Version "1.0.0"
```
This will produce a zip file containing your configuration and all the PowerShell modules required for the target machine to be able to apply the configuration.  The -Type parameter has two options 'Audit' or 'AuditAndSet'.  Audit will check if a condition is as defined by the configuration, AuditAndSet will check then correct if the condition is not as desired.  The -Version parameter expects a version number in x.y.z format.  You cannot use 1.x.x as that is reserved for Azure Internal policies.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/machine_config_package.jpg)

## Upload the package to Azure Storage and generate the access token

We now have the configuration package and it is ready to upload to a storage account.  I'm not going to go into the process of creating a storage account, blob container and generating a SAS token here.  There is lot of information available online about accomplishing this.

If you are generating the blob uri and SAS token manually in the portal don't forget to save it before closing the blade.  You will not be able to retreive it afterwards and will need to generate a new one.

My resuable script assumes you already have the storage account and container available and will upload the configuration zip file then generate the URI and SAS token with a three year expiration.  Don't forget to set a reminder!  To generate a SAS token in code you need the storage account access keys, which are used to sign the SAS token.  I have stored this in a [Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) to be retrieved during deployment.  This is a good way to ensure we aren't exposing any secrets in code and is another component I have already created and configured.

## Generate a Machine Configuration Azure policy definition

We are now ready to generate the policy definition. First we need to setup the parameters we need to create the definition.  The following code will do that.

```PowerShell
$blobUri = "<Your blob uri and sas token"

#Generate a new GUID for policy id
$guid = (New-Guid).Guid

#Generate policy definition
$policyParameters = @{
    DisplayName = "Install RoboShadow Agent"
    Description = "Installs RoboShadow Agent onto Windows servers using Machine Configuration"
    PolicyId = $guid
    Path = './policies/'
    ContentUri = $blobUri
    PolicyVersion = "1.0.0"
    Platform = "Windows"
    Mode = "ApplyAndAutoCorrect"
}
```
Now generate the policy definition using the following command.

```Powershell
New-GuestConfigurationPolicy @policyParameters
```
You should now have a subfolder in your working directory named policies containing a json policy definition file suitable for deploying to Azure.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/new_guest_configuration_policy.jpg)

## Publish the policy definition to Azure

Finally we are in a position to deploy a policy definition.  Ensure your PowerShell session is logged into Azure.  If you are deploying to a management group scope, which to me it always makes sense to do when dealing with policies, it doesn't matter which subscription you are focused on.  If you are deploying the definition to a subscription or resource group scope you will need to make sure that subscription is your focus.

The command to deploy the the policy definition is shown below

```Powershell
New-AzPolicyDefinition -Name $policyParameters.PolicyId -ManagementGroupName <YOUR MANAGEMENT GROUP ID> -Policy .\policies\RoboShadowAgentDeploy_DeployIfNotExists.json
```
Running it will show the new policy definition has been successfuly deployed.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/deployed_policy_definition.jpg)

Log into the Azure portal, navigate to the policy blade and we can verify the new definition is as expected.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/policy_in_portal.jpg)

As explained earlier my script stops at this point and the next two steps are manual in the portal.  They could definitely be automated with just a couple of PowerShell commands adding to the script, if you know the assignment scope and want to proceed straight into a remediation task.  The commands to use would be [New-AzPolicyAssignment](https://learn.microsoft.com/en-us/powershell/module/az.resources/new-azpolicyassignment?view=azps-12.4.0) and [Start-AzPolicyRemediation](https://learn.microsoft.com/en-us/powershell/module/az.policyinsights/start-azpolicyremediation?view=azps-12.4.0)


The script is included: [AzureMachineConfigurationPolicyCreate.ps1](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/AzureMachineConfigurationPolicyCreate.ps1)

## Assign the policy

Assigning the policy definition in the portal is very simple.  Click the "Assign policy" button on the definition to get into the wizard.

Here you can choose the scope where you want to create the assignment.  I am assigning it to a resource group containing a test vm.  You can also choose to exclude resources that would be within the scope if required.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/policy_assignment_basics.jpg)

The next section allows you to configure any parameters that are included within the definition.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/policy_assignment_parameters.jpg)

The next page enables you to create a remediation task at the same time as the assignment.  This policy is a "deployIfNotExists" type.  So it needs to perform some actions to correct a non-compliant resource, hence the requirement for a managed identity and role assignment.  It's usually best to leave these as system assigned.  Azure will then handle the life of the identity.  If you delete the assignment, the identity goes with it.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/policy_assignment_remediation.jpg)

The final configuration option is to set a non-compliance message.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/policy_assignment_non-compliance.jpg)

With the assignment created we can then check the compliance of the resources.  Click the "View compliance" button on the assignment.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/compliance.jpg)

This page shows us a lot of information, most importantly that the resource is not compliant and the last time it was evaluated by the service.  It isn't compliant because I chose not to create a remediation task at the time of the assignment.  I'll do that next.  If any new resources were created within the scope after the assignment is in place they would be remediated automatically.

Going into the compliance details view will show the non-compliance message that was configured during the assignment.  This is very useful to give people a better chance of determining why an Azure policy might be non-compliant on some resources and how to bring them into compliance.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/compliance_details.jpg)

## Create a remediation task to apply to existing resources

On the policy compliance page click the "Create remediation task" button.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/remediation_task.jpg)

There is not much to do here other than set a failure threshold, limit the resource count and choose to re-evaluate the resources before remediating.  A word about resource applicable view.  In the example above there is only one resource within the assignment scope as can be seen in the screenshot.  If you have made the assignment at a higher scope like Management Group or Subscription you are unlikely to see them on this screen.

## Monitoring remediation

The last section is very much a waiting game.  From my experience it can take around an hour before the software has been installed.

You can go to the policy assignment page, click on "Remediation" and it will show as complete.  This is a bit misleading.  The remediation task deployment has completed but the Local Configuration Manager on the Windows Machine hasn't checked in, picked up the task, completed it then reported the results back to the service.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/remediation_complete_but_not.jpg)

The policy compliance page is the best place to check.  Checking there after an hour we can see the test machine is now showing as complaint.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/compliant.jpg)

Then just as a final check I will get the status of the services on the machine.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/running_services.jpg)

That's the agent successfuly installed on one test server using Azure Machine Configuration and Desired State Configuration.  To push this configuration out to all the Windows based servers I need to assign the policy at the top level management group then wait for it to do the work.  Any failures will show up in the policy compliance view and can be investigated and resolved.  Any new machines deployed into Azure will get remediated upon deployment and any new on premise machine that are registered into Azure Arc will also have the agent installed.

So in summary, Azure Machine Confiuration is hugely powerful tool.  Given the range of configuration options available within Desired State Configuration the amount you can automate and audit is wide and varied.  Combine that with Arc and you've got a great hybrid cloud management tool.