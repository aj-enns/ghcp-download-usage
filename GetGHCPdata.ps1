# Azure Function boilerplate
param($Request)

# Import required modules
Import-Module Az.Accounts
Import-Module Az.Storage
Import-Module Az.Automation

# Define variables by retrieving them from Azure Automation Account
$automationAccountName = "your_automation_account_name" # Replace with your Automation Account name
$resourceGroupName = "your_resource_group_name" # Replace with your Resource Group name

$githubApiUrl = "https://api.github.com/copilot/metrics/user_adoption" # Updated API endpoint based on documentation

# Try to get GitHub token from environment variable first, then fallback to Automation Account variable
$githubToken = $env:GITHUB_TOKEN
if (-not $githubToken) {
    $githubToken = (Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "GitHubToken").Value
}

# Try to get Storage Account Name from environment variable first, then fallback to Automation Account variable
$storageAccountName = $env:STORAGE_ACCOUNT_NAME
if (-not $storageAccountName) {
    $storageAccountName = (Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "StorageAccountName").Value
}

# Try to get Storage Account Key from environment variable first, then fallback to Automation Account variable
$storageAccountKey = $env:STORAGE_ACCOUNT_KEY
if (-not $storageAccountKey) {
    $storageAccountKey = (Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "StorageAccountKey").Value
}

# Try to get Container Name from environment variable first, then fallback to hardcoded value
$containerName = $env:CONTAINER_NAME
if (-not $containerName) {
    $containerName = "your_container_name" # Replace with your default container name
}

# Call GitHub Copilot API
$response = Invoke-RestMethod -Uri $githubApiUrl -Headers @{
    Authorization = "Bearer $githubToken"
    Accept = "application/vnd.github+json"
} -Method Get

# Convert response to JSON
$jsonData = $response | ConvertTo-Json -Depth 10

# Save JSON data to a temporary file
$tempFilePath = Join-Path $env:TEMP "user-adoption-data.json"
Set-Content -Path $tempFilePath -Value $jsonData

# Upload the file to Azure Blob Storage
$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
Set-AzStorageBlobContent -File $tempFilePath -Container $containerName -Blob "user-adoption-data.json" -Context $storageContext

# Clean up temporary file
Remove-Item -Path $tempFilePath -Force

Write-Output "User adoption data has been uploaded to Azure Blob Storage successfully."