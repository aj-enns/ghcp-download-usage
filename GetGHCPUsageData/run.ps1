# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# Write an information log with the current time.
Write-Host "GitHub Copilot Usage data download function started at: $currentUTCtime"

# Import required modules
Import-Module Az.Accounts
Import-Module Az.Storage
Import-Module Az.Automation

# Start with basic verbose logging to help diagnose issues
Write-Host "Function starting - $(Get-Date)"
$ErrorActionPreference = "Stop" # This ensures errors are captured properly

try {
    # First check if modules are available without importing
    Write-Host "Checking for required modules..."
    $modules = @('Az.Accounts', 'Az.Storage', 'Az.Automation')
    foreach ($module in $modules) {
        if (!(Get-Module -ListAvailable -Name $module)) {
            Write-Host "Module $module not found, attempting to install..."
            Install-Module -Name $module -Force -Scope CurrentUser -AllowClobber
        }
    }

    # Now import modules with logging
    Write-Host "Importing modules..."
    foreach ($module in $modules) {
        Write-Host "Importing $module..."
        Import-Module $module
    }
    
    # Rest of your function code
    # ...
} 
catch {
    # Detailed error logging
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    throw
}

# Define variables by retrieving them from environment variables or Azure Automation Account
$automationAccountName = $env:AUTOMATION_ACCOUNT_NAME
$resourceGroupName = $env:RESOURCE_GROUP_NAME

$githubApiUrl = "https://api.github.com/copilot/metrics/user_adoption" # GitHub Copilot API endpoint

# Try to get GitHub token from environment variable first, then fallback to Automation Account variable
$githubToken = $env:gh_pat
if (-not $githubToken) {
    try {
        $githubToken = (Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "GitHubToken").Value
        Write-Host "Successfully retrieved GitHub token from Automation Account"
    }
    catch {
        Write-Error "Failed to retrieve GitHub token: $_"
        throw
    }
}

# Try to get Storage Account Name from environment variable first, then fallback to Automation Account variable
$storageAccountName = $env:STORAGE_ACCOUNT_NAME
if (-not $storageAccountName) {
    try {
        $storageAccountName = (Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "StorageAccountName").Value
        Write-Host "Successfully retrieved Storage Account name from Automation Account"
    }
    catch {
        Write-Error "Failed to retrieve Storage Account name: $_"
        throw
    }
}

# Try to get Storage Account Key from environment variable first, then fallback to Automation Account variable
$storageAccountKey = $env:STORAGE_ACCOUNT_KEY
if (-not $storageAccountKey) {
    try {
        $storageAccountKey = (Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "StorageAccountKey").Value
        Write-Host "Successfully retrieved Storage Account key from Automation Account"
    }
    catch {
        Write-Error "Failed to retrieve Storage Account key: $_"
        throw
    }
}

# Try to get Container Name from environment variable first, then fallback to hardcoded value
$containerName = $env:CONTAINER_NAME
if (-not $containerName) {
    $containerName = "ghcp-adoption-data"
    Write-Host "Using default container name: $containerName"
}

try {
    # Add timestamp for logging and unique file naming
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    
    # Call GitHub Copilot API with retry logic and exponential backoff
    $maxRetries = 3
    $retryCount = 0
    $success = $false
    $baseDelaySec = 2
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            Write-Host "Calling GitHub Copilot API (Attempt $($retryCount + 1))"
            $response = Invoke-RestMethod -Uri $githubApiUrl -Headers @{
                Authorization = "Bearer $githubToken"
                Accept = "application/vnd.github+json"
            } -Method Get -TimeoutSec 30
            $success = $true
            Write-Host "Successfully retrieved data from GitHub Copilot API"
        }
        catch {
            $retryCount++
            if ($retryCount -ge $maxRetries) {
                Write-Error "Failed to call GitHub API after $maxRetries attempts: $_"
                throw
            }
            # Exponential backoff with jitter
            $delaySec = $baseDelaySec * [Math]::Pow(2, $retryCount - 1) + (Get-Random -Minimum 0 -Maximum 2)
            Write-Host "API call failed. Retrying in $delaySec seconds... Error: $_"
            Start-Sleep -Seconds $delaySec
        }
    }
    
    # Convert response to JSON
    $jsonData = $response | ConvertTo-Json -Depth 10
    
    # Save JSON data to a temporary file with timestamp
    $filename = "user-adoption-data_$timestamp.json"
    $tempFilePath = Join-Path $env:TEMP $filename
    Set-Content -Path $tempFilePath -Value $jsonData
    
    # Upload the file to Azure Blob Storage with retry logic
    $storageRetries = 2
    $storageRetryCount = 0
    $storageSuccess = $false
    
    while (-not $storageSuccess -and $storageRetryCount -lt $storageRetries) {
        try {
            Write-Host "Connecting to storage account and uploading data (Attempt $($storageRetryCount + 1))"
            $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
            Set-AzStorageBlobContent -File $tempFilePath -Container $containerName -Blob $filename -Context $storageContext -Force
            $storageSuccess = $true
        }
        catch {
            $storageRetryCount++
            if ($storageRetryCount -ge $storageRetries) {
                Write-Error "Failed to upload to Azure Storage after $storageRetries attempts: $_"
                throw
            }
            Write-Host "Storage upload failed. Retrying in 3 seconds..."
            Start-Sleep -Seconds 3
        }
    }
    
    # Clean up temporary file
    Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue
    
    Write-Host "User adoption data has been successfully uploaded to Azure Blob Storage as $filename"
    
    # Return success information for logging
    return @{
        Status = "Success"
        Message = "User adoption data has been successfully uploaded to Azure Blob Storage"
        Timestamp = $timestamp
        FileName = $filename
    }
}
catch {
    Write-Error "Error in GitHub Copilot Usage data function: $_"
    throw
}