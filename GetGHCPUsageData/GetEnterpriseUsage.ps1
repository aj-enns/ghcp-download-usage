# GitHub Copilot Metrics API - Daily Usage Script with Azure Storage Upload
# Purpose: Fetch Copilot usage metrics for yesterday and upload to Azure Storage

# Get required variables from Automation Account
$StorageAccountName = Get-AutomationVariable -Name 'StorageAccountName'
$ContainerName = Get-AutomationVariable -Name 'ContainerName'
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
    
    # Define the blob name with new naming convention
    $blobName = "ghcp_metrics_usage_$yesterday.json"
    
    # Check if response contains data
    if ($null -eq $response) {
        Write-Warning "API returned null response. Creating empty JSON object. This likely means no data was found for the specified date."
        $jsonContent = "{}"
    } else {
        # Convert the response to JSON
        $jsonContent = $response | ConvertTo-Json -Depth 10
        
        # Ensure the JSON content is not null
        if ([string]::IsNullOrEmpty($jsonContent)) {
            Write-Warning "JSON conversion resulted in null or empty string. Creating empty JSON object."
            $jsonContent = "{}"
        }
    }
    
    # Display success message
    Write-Host "Success! Retrieved Copilot billing usage data for $yesterday"
    
    # Display summary information if available
    Write-Host "`nSummary for $yesterday"
    if ($null -ne $response -and $null -ne $response.total_active_users) {
        Write-Host "Total active users: $($response.total_active_users)"
        Write-Host "Total active seats: $($response.total_active_seats)"
    } else {
        Write-Host "No summary data available."
    }
    
    # Upload to Azure Storage if storage account is provided
    if ($StorageAccountName) {
        Write-Host "`nUploading metrics directly to Azure Storage..."
        
        # Import required Azure modules
        if (-not (Get-Module -Name Az.Storage -ListAvailable)) {
            Write-Host "Az.Storage module not found. Installing..."
            Install-Module -Name Az.Storage -Scope CurrentUser -Force
        }
        
        if (-not (Get-Module -Name Az.Accounts -ListAvailable)) {
            Write-Host "Az.Accounts module not found. Installing..."
            Install-Module -Name Az.Accounts -Scope CurrentUser -Force
        }
        
        # Import-Module Az.Accounts
        # Import-Module Az.Storage
        
        try {
            # Connect using the Automation Account's managed identity
            Write-Host "Connecting with Managed Identity..."
            Connect-AzAccount -Identity
            
            # Get storage context using the managed identity
            Write-Host "Getting storage context using Managed Identity..."
            $context = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

            # Check if container exists, create if it doesn't
            $containerExists = Get-AzStorageContainer -Name $ContainerName -Context $context -ErrorAction SilentlyContinue
            if (-not $containerExists) {
                Write-Host "Container '$ContainerName' does not exist. Creating..."
                New-AzStorageContainer -Name $ContainerName -Context $context -Permission Off | Out-Null
            }
            
            # Upload the JSON content directly to blob storage without using a temp file
            Write-Host "Uploading $blobName to $ContainerName container using Managed Identity..."
            
            # Create blob metadata
            $metadata = @{
                "UploadDate" = [DateTime]::UtcNow.ToString("o")
                "Source" = "GHCopilotMetrics"
                "Organization" = $org
            }
              # Ensure JSON content is not null or empty before proceeding
            if ([string]::IsNullOrEmpty($jsonContent)) {
                $jsonContent = "{}" # Use empty JSON object if content is null
            }
            
            try {
                # Convert JSON content to bytes with explicit error handling
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonContent)
                $stream = [System.IO.MemoryStream]::new($bytes)
                  # Upload directly from memory stream
                Set-AzStorageBlobContent -Container $ContainerName `
                                       -Context $context `
                                       -Blob $blobName `
                                       -Stream $stream `
                                       -Properties @{ContentType = "application/json"} `
                                       -Metadata $metadata `
                                       -StandardBlobTier "Hot" `
                                       -Force | Out-Null
                
                # Close the stream
                $stream.Close()
            }
            catch {
                Write-Error "Error processing JSON content: $_"
                  # Fallback: Write a simple empty JSON object directly
                Write-Host "Falling back to direct string upload method..."
                $emptyJson = "{}"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($emptyJson)
                $stream = [System.IO.MemoryStream]::new($bytes)
                
                Set-AzStorageBlobContent -Container $ContainerName `
                                       -Context $context `
                                       -Blob $blobName `
                                       -Stream $stream `
                                       -Properties @{ContentType = "application/json"} `
                                       -Metadata $metadata `
                                       -StandardBlobTier "Hot" `
                                       -Force | Out-Null
                
                $stream.Close()
            }
            
            # Display the blob URL
            $blobUrl = "$($context.BlobEndPoint)$ContainerName/$blobName"
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

