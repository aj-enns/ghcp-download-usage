# GitHub Copilot Metrics API - Daily Usage Script with Azure Storage Upload
# Purpose: Fetch Copilot usage metrics for yesterday and upload to Azure Storage

$StorageAccountName = Get-AutomationVariable -Name 'StorageAccountName'
$ContainerName = Get-AutomationVariable -Name 'ContainerName' 
$StorageAccountKey = Get-AutomationVariable -Name 'StorageAccountKey'
# Get authentication token from environment for security
$authToken = Get-AutomationVariable -Name 'authToken'

if (-not $authToken) {
    Write-Error "GitHub token not found in environment variables. Please set the GITHUB_TOKEN environment variable."
    exit 1
}

# Set your organization name
$org = "CovenantCoders" # Replace with your GitHub organization name

# Calculate the previous day's date
$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
Write-Host "Fetching Copilot metrics for: $yesterday"

# Define the API endpoint for Copilot billing usage for the org and date
$apiUrl = "https://api.github.com/orgs/$org/copilot/metrics?since=$yesterday&until=$yesterday"

# Set the headers for the API request with proper GitHub API version
$headers = @{
    Authorization = "Bearer $authToken"
    Accept        = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "PowerShell-Script"
}


# Make the API request with error handling
try {
    Write-Host "Calling GitHub Copilot Metrics API..."
    $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
    
    
    # Define the output file path with new naming convention
    $BlobName = "ghcp_metrics_usage_$yesterday.json"
    
    # Write the usage data to a local JSON file
    $jsonContent = $response | ConvertTo-Json -Depth 10
    $tempFile = Join-Path $env:TEMP $BlobName
    $jsonContent | Set-Content -Path $tempFile -Encoding UTF8
    
    Write-Host "Success! Copilot billing usage data for $yesterday has been written to $localOutputFile"
    
    # Display summary information
    Write-Host "`nSummary for $yesterday"
    Write-Host "Total active users: $($response.total_active_users)"
    Write-Host "Total active seats: $($response.total_active_seats)"
    
    # Upload to Azure Storage if storage account is provided
    if ($StorageAccountName) {
        Write-Host "`nUploading metrics to Azure Storage..."
        
        # Import Azure Storage module if not already loaded
        if (-not (Get-Module -Name Az.Storage -ListAvailable)) {
            Write-Host "Az.Storage module not found. Installing..."
            Install-Module -Name Az.Storage -Scope CurrentUser -Force
        }
        
        Import-Module Az.Storage
        
        try {

            # Use storage account key if provided (not recommended for production)
            Write-Host "Using Storage Account Key for authentication (consider using Managed Identity instead)..."
            $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

            # Check if container exists, create if it doesn't
  
            $containerExists = Get-AzStorageContainer -Name $ContainerName -Context $context -ErrorAction SilentlyContinue
            if (-not $containerExists) {
                Write-Host "Container '$ContainerName' does not exist. Creating..."
                New-AzStorageContainer -Name $ContainerName -Context $context -Permission Off | Out-Null
            }
            
            # Upload the JSON content directly to blob storage
            Write-Host "Uploading $localOutputFile to $ContainerName container..."
            
            $blobProperties = @{
                File = $tempFile
                Container = $ContainerName
                Blob = $BlobName
                Context = $context
                StandardBlobTier = "Hot" # Set tier explicitly
                Metadata = @{
                    "UploadDate" = [DateTime]::UtcNow.ToString("o")
                    "Source" = "GHCopilotMetrics"
                    "Organization" = $org
                }
            }
            Set-AzStorageBlobContent @blobProperties -Force | Out-Null

            
            # Display the blob URL
            $blobUrl = "$($context.BlobEndPoint)$ContainerName/$localOutputFile"
            Write-Host "Upload successful! Blob URL: $blobUrl"
        }
        catch {
            Write-Error "Failed to upload to Azure Storage: $_"
        }
    }
} 
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $statusDescription = $_.Exception.Response.StatusDescription
    
    Write-Error "Failed to retrieve Copilot billing data. Status code: $statusCode, Description: $statusDescription"
    Write-Error $_.Exception.Message
    
    if ($statusCode -eq 404) {
        Write-Host "This could be because the organization doesn't have Copilot, or you don't have permission to access the data."
    }
    elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
        Write-Host "This could be because your token doesn't have the required permissions (read:org and read:copilot)."
        Write-Host "Make sure your token has these scopes: read:org, read:copilot"
    }
}