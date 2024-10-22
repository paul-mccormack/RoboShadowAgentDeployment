

#Setup variables

$dscConfigName = "deployRoboShadow" #this should match the name of the configuration in the DSC config script
$version = "1.0.0" # must be x.y.z format.  If updating an existing config and policy check the portal for the existing version
$packageName = "RoboShadowDsc"  # This should match the filename of DSC config script
$configMode = "AuditAndSet" # must be Audit or AuditAndSet
$storageAccountName = "machineconfiguksmgt"
$containerName = "artifacts"
$vaultName = "kv-uks-management-01"
$secretName = "machineConfigSaKey"
$policyDisplayName = "Install RoboShadow Agent"
$policyDescription = "Installs RoboShadow Agent onto Windows VM's using Machine Configuration"
$policyDeploymentScope = "MG-SCC-Common" #This would usually be the top level Management Group

# Check if required modules are installed
if(-not (Get-Module GuestConfiguration -ListAvailable)){
    Install-Module -Name GuestConfiguration
    Import-Module -Name GuestConfiguration
}

if(-not (Get-Module PSDesiredStateConfiguration -ListAvailable)){
    Install-Module -Name PSDesiredStateConfiguration
    Import-Module -Name PSDesiredStateConfiguration
}

if(-not (Get-Module Az -ListAvailable)){
    Install-Module -Name Az -Repository PSGallery -Force
    Import-Module -Name Az
}

#Login to Azure
Connect-AzAccount

#Run the DSC Script to generate the configuration
$dscConfigScript = "./" + $packageName + ".ps1"
Invoke-Expression $dscConfigScript

#Rename localhost.mof to the required package name
$originalMofName = "./" + $dscConfigName + "/localhost.mof"
$newMofName = $packageName + ".mof"
Rename-Item -Path $originalMofName -NewName $newMofName
$pathToMof = "./" + $dscConfigName + "/" + $newMofName

#Create Guest Configuration Package
New-GuestConfigurationPackage -Name $packageName -Configuration $pathToMof -Type $configMode -Version $version

#Get Storage Account Access Key from KeyVault
$secret = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -AsPlainText

#Create Storage Account Context
$context = New-AzStorageContext -StorageAccountName $storageAccountName -Protocol Https -StorageAccountKey $secret

#Upload to zip file to storage account
$configZipName = $packageName + ".zip"
$setParams = @{
    Container = $containerName
    File      = $configZipName
    Context   = $context
}
Set-AzStorageBlobContent @setParams

#Generate SAS Token with 3 year expiration date
$startTime = Get-Date
$endTime   = $startTime.AddYears(3)
$tokenParams = @{
    StartTime  = $startTime
    ExpiryTime = $endTime
    Container  = $containerName
    Blob       = $configZipName
    Permission = 'r'
    Context    = $context
    FullUri    = $true
}
$blobUri = New-AzStorageBlobSASToken @tokenParams

#Generate a new GUID for policy id
$guid = (New-Guid).Guid

#Generate policy definition
$policyParameters = @{
    DisplayName = $policyDisplayName
    Description = $policyDescription
    PolicyId = $guid
    Path = './policies/'
    ContentUri = $blobUri
    PolicyVersion = $version
    Platform = "Windows"
    Mode = "ApplyAndAutoCorrect"
}
New-GuestConfigurationPolicy @policyParameters

#Publish policy definition to Azure
$policyFile = "./policies/" + $packageName + "_DeployIfNotExists.json"
New-AzPolicyDefinition -Name $policyParameters.PolicyId -ManagementGroupName $policyDeploymentScope -Policy $policyFile
