
# RoboShadow agent deployment on Windows Azure VM's and hybrid connected VM's at scale

## Introduction

RoboShadow is a cloud hosted cyber security platform offering external vulnerabiltiy scanning, device attack surface management, MFA auditing and 365 AD Sync.  You can find out more at [RoboShadow.com](https://www.roboshadow.com/)

RoboShadow provides an installable agent for monitoring your devices. This is very simple to install using the downloadable msi file, a PowerShell script provided by RoboShadow, which can be found [here](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/RoboShadowAgentInstall.ps1), or if you have Microsoft Intune within your organisation and you want to deploy to your workstations you can utilise the very handy "Deploy RoboShadow With Intune" once you have integration set-up completed.  Detailed guidance is available in their [documentation](https://roboshadow.atlassian.net/wiki/spaces/Roboshadow/overview?homepageId=4882647)

This is all great for a few servers or to your users workstations. What if you want to deploy to all your Windows based servers?  That was what I had to do and I didn't want to logon to a few hundred devices and run the install manually.  The first batch was around 20 test servers to make sure the agent didn't have any adverse effects, which it did not.  These test servers were all in Azure and running in the same subscription.  The next section details how I did this

## Az PowerShell and the VM run command

This was quite an easy task I have done many times using the Az PowerShell modules.  We get all the Windows based servers in a subscription, store that in a variable then loop through them with the [Invoke-AzVMRunCommand](https://learn.microsoft.com/en-us/powershell/module/az.compute/invoke-azvmruncommand?view=azps-12.4.0) executing the PowerShell code block provided by RoboShadow.  Super quick and easy.  The script to do this can be found [here](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/RoboShadowAzureBulkAgentInstall.ps1)

After a period of monitoring we decided it was time to deploy to everything, but how do you do that when you have hundreds of Windows server spread across Azure and on premise and ensure it is automatically deployed to newly created Windows servers?

## Azure Machine Configuration

[Azure Machine Configuration](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/), previously named Azure Policy Guest Configuration provides the ability to both audit and configure operating system settings and installed software, both for machines running in Azure and hybrid Arc-enabled machines running on premise or other public clouds.  You can use this feature directly on a per machine basis or orchestrate at scale using Azure Policy.  Azure Machine Configuration relies on [PowerShell Desired State Configuration](https://learn.microsoft.com/en-us/powershell/scripting/dsc/overview?view=powershell-7.4).  There are many providers for DSC available to acheive your goal configuration.  Go to the [PowerShell Gallery](https://www.powershellgallery.com/packages) and you can filter the results to DSC Resources

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/DSC_Resources.jpg)

I am going to be using Azure Machine Configuration to deploy the RoboShadow agent to all the Windows server based machines in our environment, both in Azure and on premise via [Azure Arc](https://learn.microsoft.com/en-us/azure/azure-arc/overview).  This will not only enable us easily deploy the agent with miminal administrative overhead and easily check for any failures but also ensure any machines created in the future will get the agent automatically upon deployment.

In the interest of code reusability I intend to create a script that can easily be repurposed in the future to mass deploy an msi based software package.  This script will perform steps 1 to 4 listed below.  I've left steps 5 and 6 out of the automation as there is a lot of flexilbity around where you want to assign a policy.  It could be at the Management Group scope, a Subscription scope or a Resource Group scope.  I've assumed the policy definition would be deployed at a Management Group scope as that makes the most sense to me.  Also creating a remediation task to apply the policy has been left to manual intervention as really you want to go through a change control process before doing that.  This way you can have everything ready in a published policy before going through change control.

The workflow is as follows:

- [Create a custom machine configuration package](#creating-a-custom-machine-configuration-package)
- [Upload the package to an Azure Storage account and generate a blob SAS token](#upload-the-package-to-azure-storage-and-generate-the-access-token)
- [Generate a Machine Configuration Azure policy definition](#generate-a-machine-configuration-azure-policy-definition)
- [Publish the policy definition to Azure](#publish-the-policy-definition-to-azure)
- [Assign the policy](#assign-the-policy)
- [Create a remediation task to apply to existing resources](#create-a-remediation-task-to-apply-to-existing-resources)

## Setting up the authoring environment

To get started you will need the latest version of [Powershell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4) Installed.  You will then need to install the GuestConfiguration, PSDesiredStateConfiguration and Azure modules.  The following code will do this:

```Powershell
Install-Module -Name GuestConfiguration -Repository PSGallery
Install-Module -Name PSDesiredStateConfiguration -Repository PSGallery
Install-Module -Name Az -Repository PSGallery
```
Now that is done we can get started.

## Creating a custom machine configuration package

The first step is to create a DSC Configuration PowerShell Script.  Different providers will have different requirements for this script.  The PSDscResources module provides a funtions for installing an MSI package, among loads of other useful abilities.  The expample code below would create a custom machine configuration package to install PowerShell 7

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
You need the Product ID of the package you are installing.  You can either get that from the registry of a machine with the package already installed in HKEY_LOCAL_MACHINE\SOFTWARE\.  If you already have the msi downloaded you could use this handy [Get-MsiProductCode](https://www.powershellgallery.com/packages/Get-MsiProductCode/1.0) script from the PowerShell Gallery.

My configuration script to deploy the RoboShadow agent is available [here](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/RoboShadowDsc.ps1)

Run this script in a PowerShell 7 session and it will create a subfoler with the name of your configuration containing a file called localhost.mof

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/machine_config_output.jpg)

The mof file contains the information realted to your configuration.  Rename the file to something more descriptive than localhost.  I prefer to rename it to the same as the powershell script that produced it.  So I will rename it to RoboShadowDsc.mof.

With this mof file you can then create the package.  The following command will take care of that

```PowerShell
New-GuestConfigurationPackage -Name 'RoboShadowAgentDeploy' -Configuration './deployRoboShadow/RoboShadowDsc.mof' -Type 'AuditAndSet' -Version "1.0.0"
```
This will produce a zip file containing your configuration and all the PowerShell modules required for the target machine to be able to apply the configuration.  The -Type parameter has two options 'Audit' or 'AuditAndSet'.  Audit will check if a condition is as defined by the congiuration and AuditAndSet will check then correct if the condtion is not as desired.  The -Version parameter expects a version number in x.y.z format.  You cannot use 1.x.x as that is reserved for Azure Internal policies.

![alt text](https://github.com/paul-mccormack/RoboShadowAgentDeployment/blob/main/images/machine_config_package.jpg)

## Upload the package to Azure Storage and generate the access token

We now have our package and it is ready to upload to a storage account.

## Generate a Machine Configuration Azure policy definition


## Publish the policy definition to Azure


## Assign the policy


## Create a remediation task to apply to existing resources


