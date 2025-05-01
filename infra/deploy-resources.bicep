param location string
param automationAccountName string
param resourceGroupName string
param containerName string
// Updated storage parameters for more flexibility and uniqueness
param storageAccountName string = '' // Empty default - will use generated name if not provided
param createNewStorageAccount bool = true
param functionAppName string = 'func-ghcp-usage' // Default name for function app
param appInsightsName string = '' // Default is empty, will use function app name if not provided

// Generate a unique storage account name if none provided
var uniqueStorageName = 'ghcpdata${uniqueString(subscription().id, resourceGroupName)}'
var finalStorageAccountName = empty(storageAccountName) ? uniqueStorageName : storageAccountName
var finalAppInsightsName = empty(appInsightsName) ? 'ai-${functionAppName}' : appInsightsName

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

// Add hosting plan for Function App (consumption plan)
resource hostingPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'plan-${functionAppName}'
  location: location
  dependsOn: [resourceGroupModule]
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false // Required for Windows (false) vs Linux (true)
  }
  tags: {
    application: 'ghcp-download-usage'
  }
}

// Log Analytics workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${functionAppName}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
  tags: {
    application: 'ghcp-download-usage'
  }
}

// Add Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: finalAppInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: {
    application: 'ghcp-download-usage'
    purpose: 'GitHub Copilot Usage Monitoring'
  }
}

// Function App resource
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  dependsOn: [
    resourceGroupModule
  ]
  identity: {
    type: 'SystemAssigned' // Enable managed identity for secure access
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      powerShellVersion: '7.4' // Updated to PowerShell 7.4 runtime
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${createNewStorageAccount ? storageAccount.name : existingStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${createNewStorageAccount ? listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value : listKeys(existingStorageAccount.id, existingStorageAccount.apiVersion).keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${createNewStorageAccount ? storageAccount.name : existingStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${createNewStorageAccount ? listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value : listKeys(existingStorageAccount.id, existingStorageAccount.apiVersion).keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME_VERSION'
          value: '~7.4'
        }
        {
          name: 'AUTOMATION_ACCOUNT_NAME'
          value: automationAccountName
        }
        {
          name: 'RESOURCE_GROUP_NAME'
          value: resourceGroupName
        }
        {
          name: 'CONTAINER_NAME'
          value: containerName
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
  tags: {
    application: 'ghcp-download-usage'
    purpose: 'GitHub Copilot Usage Processing'
  }
}

// Outputs for reference in scripts and other deployments
output automationAccountId string = automationAccount.id
output automationAccountName string = automationAccount.name
output storageAccountId string = (createNewStorageAccount ? storageAccount.id : existingStorageAccount.id)
output storageAccountName string = finalStorageAccountName
output containerId string = (createNewStorageAccount ? container.id : containerExisting.id)
output containerName string = containerName
output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
