# GitHub Copilot Metrics API - Daily Usage Script with Azure Blob Storage Upload
# Fetches Copilot usage metrics for yesterday and uploads to Azure Storage using managed identity

#region Configuration and Setup
# Get required variables from Automation Account
$StorageAccountName = Get-AutomationVariable -Name 'StorageAccountName'
$ContainerName = Get-AutomationVariable -Name 'ContainerName'
$authToken = Get-AutomationVariable -Name 'authToken'

if (-not $authToken) {
    Write-Error "GitHub token not found. Please set the authToken variable in your Automation Account."
    exit 1
}

# Configuration
$org = "CovenantCoders" # GitHub organization name
$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$blobName = "ghcp_metrics_usage_$yesterday.json"
$apiUrl = "https://api.github.com/orgs/$org/copilot/metrics?since=$yesterday&until=$yesterday"
$headers = @{
    Authorization = "Bearer $authToken"
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "PowerShell-Script"
}
#endregion

#region Function Definitions
function Get-CopilotMetricsData {
    [CmdletBinding()]
    param()
    
    Write-Host "Fetching Copilot metrics for: $yesterday"
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $statusDescription = $_.Exception.Response.StatusDescription
        
        Write-Error "Failed to retrieve Copilot data. Status code: $statusCode, Description: $statusDescription"
        
        if ($statusCode -eq 404) {
            Write-Host "Organization may not have Copilot, or you lack permissions to access the data."
        }
        elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Host "Token may not have required permissions (read:org and read:copilot)."
        }
        
        return $null
    }
}

function Upload-ToAzureBlob {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $JsonContent
    )
    
    try {
        # Connect using managed identity and get storage context
        Write-Host "Connecting with Managed Identity..."
        Connect-AzAccount -Identity
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
        
        # Ensure container exists
        $containerExists = Get-AzStorageContainer -Name $ContainerName -Context $context -ErrorAction SilentlyContinue
        if (-not $containerExists) {
            Write-Host "Creating container '$ContainerName'..."
            New-AzStorageContainer -Name $ContainerName -Context $context -Permission Off | Out-Null
        }
        
        # Prepare blob metadata
        $metadata = @{
            "UploadDate" = [DateTime]::UtcNow.ToString("o")
            "Source" = "GHCopilotMetrics"
            "Organization" = $org
        }
        
        # Create a temporary file
        $tempJsonFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), $blobName)
        
        try {
            # Upload file
            Set-Content -Path $tempJsonFile -Value $JsonContent -Force
            Write-Host "Uploading to $ContainerName blob container..."
            
            Set-AzStorageBlobContent -Container $ContainerName `
                                   -Context $context `
                                   -Blob $blobName `
                                   -File $tempJsonFile `
                                   -Properties @{ContentType = "application/json"} `
                                   -Metadata $metadata `
                                   -StandardBlobTier "Hot" `
                                   -Force | Out-Null
            
            $blobUrl = "$($context.BlobEndPoint)$ContainerName/$blobName"
            Write-Host "Upload successful! Blob URL: $blobUrl"
            return $true
        }
        catch {
            Write-Error "Failed to upload blob: $_"
            return $false
        }
        finally {
            # Clean up temp file
            if (Test-Path $tempJsonFile) {
                Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Error "Azure Storage connection failed: $_"
        return $false
    }
}
#endregion

#region Main Script Execution
# Step 1: Get Copilot metrics data
$metricsData = Get-CopilotMetricsData

# Step 2: Process and display data
if ($null -eq $metricsData) {
    Write-Warning "No metrics data returned from API. Creating empty JSON object."
    $jsonContent = "{}"
} 
else {
    $jsonContent = $metricsData | ConvertTo-Json -Depth 10
    if ([string]::IsNullOrEmpty($jsonContent)) {
        Write-Warning "JSON conversion resulted in null or empty string. Using empty object."
        $jsonContent = "{}"
    }
    
    # Display summary
    Write-Host "`nSummary for $yesterday"
    if ($null -ne $metricsData.total_active_users) {
        Write-Host "Total active users: $($metricsData.total_active_users)"
        Write-Host "Total active seats: $($metricsData.total_active_seats)"
    } else {
        Write-Host "No summary data available."
    }
}

# Step 3: Upload to Azure Blob Storage
if ($StorageAccountName) {
    $result = Upload-ToAzureBlob -JsonContent $jsonContent
    if (-not $result) {
        Write-Warning "Upload attempt failed. Check previous errors for details."
    }
} else {
    Write-Warning "StorageAccountName not provided. Skipping Azure Storage upload."
}
#endregion

