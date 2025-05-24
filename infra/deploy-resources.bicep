param location string
param automationAccountName string
param resourceGroupName string
param containerName string
// Updated storage parameters for more flexibility and uniqueness
param storageAccountName string = '' // Empty default - will use generated name if not provided
param createNewStorageAccount bool = true

// Generate a unique storage account name if none provided
var uniqueStorageName = 'ghcpdata${uniqueString(subscription().id, resourceGroupName)}'
var finalStorageAccountName = empty(storageAccountName) ? uniqueStorageName : storageAccountName

module resourceGroupModule './create-resource-group.bicep' = {
  name: 'resourceGroupDeployment'
  scope: subscription()
  params: {
    location: location
    resourceGroupName: resourceGroupName
  }
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2020-01-13-preview' = {
  name: automationAccountName
  location: location
  dependsOn: [resourceGroupModule]
  identity: {
    type: 'SystemAssigned' // Enable managed identity
  }
  properties: {
    sku: {
      name: 'Basic'
    }
  }
  tags: {
    application: 'ghcp-download-usage'
    purpose: 'GitHub Copilot Usage Tracking'
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = if (createNewStorageAccount) {
  name: finalStorageAccountName
  location: location
  dependsOn: [resourceGroupModule]
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: {
    application: 'ghcp-download-usage'
    purpose: 'GitHub Copilot Usage Data Storage'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

// Reference existing storage account if not creating new
resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' existing = if (!createNewStorageAccount) {
  name: finalStorageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2021-04-01' = if (createNewStorageAccount) {
  parent: storageAccount
  name: 'default'
}
resource blobServiceExisting 'Microsoft.Storage/storageAccounts/blobServices@2021-04-01' existing = if (!createNewStorageAccount) {
  parent: existingStorageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = if (createNewStorageAccount) {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}
resource containerExisting 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = if (!createNewStorageAccount) {
  parent: blobServiceExisting
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// Role assignment is now handled in the GitHub Actions workflow (deploy-automation-vars.yml)
// to avoid permission issues with service principals that lack User Access Administrator rights

// Outputs for reference in scripts and other deployments
output automationAccountId string = automationAccount.id
output automationAccountName string = automationAccount.name
output automationAccountPrincipalId string = automationAccount.identity.principalId
output storageAccountId string = (createNewStorageAccount ? storageAccount.id : existingStorageAccount.id)
output storageAccountName string = finalStorageAccountName
output containerId string = (createNewStorageAccount ? container.id : containerExisting.id)
output containerName string = containerName
