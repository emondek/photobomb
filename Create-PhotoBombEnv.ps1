<#
.SYNOPSIS
	This script uses a deployment template to provision an ARM environment.
	
.DESCRIPTION
	This script uses a deployment template to provision an ARM environment.
	
.NOTES
	Author: Ed Mondek
	Date: 01/25/2016
	Revision: 1.0

.CHANGELOG
    1.0  01/25/2016  Ed Mondek  Initial commit
#>

# Sign in to your Azure account
<#
Login-AzureRmAccount
#>

# Initialize variables
$subscriptionName = 'Windows Azure Internal Consumption'
$location = "West US"

# Set the current subscription
Select-AzureRmSubscription -SubscriptionName $subscriptionName

### BEGIN - Upload the ARM deployment template files to a storage account ###

# Get the list of files to upload
$path = 'C:\users\emondek\Documents\Git-Repos\photobomb'
$files = Get-ChildItem $path -force | Where-Object {$_.Extension -match '.json'}

# Get the storage account context object
$resourceGroup = 'sharedwurg1'
$storageAccount = 'sharedwussaimg1'
$container = 'photobomb'
$storageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccount).Key1
$context = New-AzureStorageContext –StorageAccountName $storageAccount -StorageAccountKey $storageKey

# Create the storage container if it doesn't exist
New-AzureStorageContainer -Name $container -Context $context -Permission Blob -ErrorAction Ignore

# Upload the files
foreach ($file in $files)
{
    $fqFilePath = $path + "\" + $file.Name
    Set-AzureStorageBlobContent -Blob $file.Name -Container $container -File $fqFilePath -Context $context -Force
}

### END - Upload the ARM deployment template files to a storage account ###

### BEGIN - Create the storage accounts and copy the custom VM image VHDs ###

# Create the resource group
$rgName = 'pbwurg1'
$tags = @{Name="App";Value="Photo Bomb"}
New-AzureRMResourceGroup -Name $rgName -Location $location -Tag $tags
Get-AzureRmResourceGroup -Name $rgName -Location $location

# Create the storage accounts (used for OS and Data disks)
$deployName = "Storage"
$templateUri = "https://{0}.blob.core.windows.net/{1}/deploy.storage.json" -f $storageAccount, $container
$templateParamUri = "https://{0}.blob.core.windows.net/{1}/deploy.storage.params.json" -f $storageAccount, $container
New-AzureRMResourceGroupDeployment -Name $deployName -ResourceGroupName $rgName -TemplateUri $templateUri -TemplateParameterUri $templateParamUri
Get-AzureRmResourceGroupDeployment -Name $deployName -ResourceGroupName $rgName

# Copy the custom images to the storage accounts
$srcRGName = 'sharedwurg1'
$srcStorageAccount = 'sharedwussaimg1'
$srcStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $srcRGName -Name $srcStorageAccount).Key1
$srcContext = New-AzureStorageContext –StorageAccountName $srcStorageAccount -StorageAccountKey $srcStorageKey
$srcContainer = 'system'
$srcBlob = 'Microsoft.Compute/Images/vhds/sharedimg1-osDisk.76317338-78fc-4e70-9547-f3d142bb9b36.vhd'

$destStorageAccounts = @('pbwussaapp1', 'pbwussadb1')
$destContainer = 'vhds'
$destBlob = 'sharedwuvmimg1.vhd'

$blobs = @()
foreach ($destStorageAccount in $destStorageAccounts)
{
    $destStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $rgName -StorageAccountName $destStorageAccount).Key1
    $destContext = New-AzureStorageContext –StorageAccountName $destStorageAccount -StorageAccountKey $destStorageKey

    New-AzureStorageContainer -Name $destContainer -Context $destContext -ErrorAction Ignore
    
    Write-Host Copying the custom VM image VHD to $destStorageAccount

    $blobs += Start-AzureStorageBlobCopy -Context $srcContext -SrcContainer $srcContainer -SrcBlob $srcBlob `
        -DestContext $destContext -DestContainer $destContainer -DestBlob $destBlob `
        -Force
}
$blobs | Get-AzureStorageBlobCopyState -WaitForComplete

### END - Create the storage accounts and copy the custom VM image VHDs ###

### BEGIN - Deploy the remainder of the environment including VNet, VMs, Application Gateways, Traffic Manager, etc. ###

# Deploy the remainder of the environment (VNet, VMs, ILBs, AppGWs, etc.)
$rgName = 'pbwurg1'
$deployName = 'Photo Bomb'
$templateUri = "https://{0}.blob.core.windows.net/{1}/azuredeploy.json" -f $storageAccount, $container
$templateParamUri = "https://{0}.blob.core.windows.net/{1}/azuredeploy.parameters.json" -f $storageAccount, $container
New-AzureRMResourceGroupDeployment -Name $rgName -ResourceGroupName $rgName -TemplateUri $templateUri -TemplateParameterUri $templateParamUri
Get-AzureRmResourceGroupDeployment -ResourceGroupName $rgName -Name $rgName

### END - Deploy the remainder of the environment including VNet, VMs, Application Gateways, Traffic Manager, etc. ###

<#
Remove-AzureRmResourceGroup -Name $rgName
#>
