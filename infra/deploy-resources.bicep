param location string
param automationAccountName string
param storageAccountName string = 'defaultstorage123' // Storage account name must be between 3 and 24 characters and use only lowercase letters and numbers
param containerName string
param resourceGroupName string

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
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  dependsOn: [resourceGroupModule]
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2021-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

output automationAccountId string = automationAccount.id
output storageAccountId string = storageAccount.id
output containerId string = container.id
