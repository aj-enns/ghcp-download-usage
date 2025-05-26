# GitHub Copilot Download Usage

## Overview
By default the GitHub API only retains data for 30 days.  If an organization wants to retain the usage data for longer they need to manually download the data. This project provides an Azure Automation Runbook (PowerShell) that downloads GitHub Copilot user adoption metrics and uploads the data to Azure Blob Storage. Infrastructure is managed using Bicep (IaC) files for secure, repeatable deployments. The solution uses Azure Managed Identity for secure, key-less authentication to Azure Storage.

## What It Does
- Calls the GitHub Copilot API to retrieve user adoption metrics.
- Stores the data as JSON in Azure Blob Storage.
- Uses Azure Automation Account variables for secrets and configuration.
- Uses Azure Managed Identity for secure, key-less authentication to Azure Storage.
- Deploys all Azure resources using Bicep (infra/ folder).
- Supports CI/CD deployment via GitHub Actions.

## Prerequisites
- Azure Subscription
- Azure CLI installed
- Sufficient permissions to create resource groups, storage accounts, and automation accounts
- GitHub Personal Access Token with required API access

## Creating a GitHub Personal Access Token (PAT)
To call the GitHub Copilot API, you need a GitHub Personal Access Token (PAT) with the correct permissions.

### Steps to Create a GitHub PAT:
1. Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens).
2. Click **Generate new token** (classic) or **Fine-grained token**.
3. Give your token a descriptive name and set an expiration date.
4. Under **Scopes/permissions**, select:
   - `read:org` (to read organization membership)
   - `read:user` (to read user profile)
   - `copilot` (to access Copilot metrics)
   - Any additional scopes required by the Copilot metrics API (check [GitHub Copilot API documentation](https://docs.github.com/en/copilot) for updates)
5. Click **Generate token** and copy the token value. You will not be able to see it again!
6. Store this token securely:
   - **Add it as a secret named `REPO_PAT` in your GitHub repository** (Settings > Secrets and variables > Actions > New repository secret).

**Never commit your PAT to source control.**


# Recommended Setup Order

Follow these steps in order for a successful deployment:

### 1. Create the Resource Group
- Create your Azure resource group (if it doesn't already exist):

```sh
az group create --name <your-resource-group> --location <your-location>
```

### 2. Setting up GitHub Actions Azure Credentials Secret

To enable GitHub Actions to deploy resources to Azure, you need to create a service principal and add its credentials as a secret named `AZURE_CREDENTIALS` in your repository.

Run this command in your terminal (replace the placeholders with your values):

```sh
az ad sp create-for-rbac --name "<service-principal-name>" --role contributor --scopes /subscriptions/<subscription-id>/resourceGroups/<resource-group-name> --sdk-auth
```

The output will look like this:

```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
```

#### Add this JSON as the value for the `AZURE_CREDENTIALS` secret in your GitHub repository
- Go to your repository’s **Settings** > **Secrets and variables** > **Actions**.
- Click **New repository secret**.
- Name: `AZURE_CREDENTIALS`
- Value: *(Paste the entire JSON output above)*

This secret will be used by the `azure/login@v2` GitHub Action to authenticate your workflow.

### 3. Add the following to your GitHub repository (as secrets or variables as appropriate):
  - `AZURE_RESOURCE_GROUP` (secret or variable): Your resource group name
  - `AZURE_AUTOMATION_ACCOUNT` (secret or variable): Your Automation Account name
  - `AZURE_LOCATION` (variable): Your Azure region (e.g., canadacentral)
  - `AZURE_CONTAINER_NAME` (variable): Your blob container name
  - `AZURE_STORAGE_ACCOUNT_NAME` (variable): Your storage account name (optional, only if you want to override the default)

### 4. **Assign the necessary roles to your service principal:**

  _Please pick from ONE of the two following options:_
  ```sh
  # Required for deploying resources at subscription level
  az role assignment create --assignee <client_id> --role Contributor --scope /subscriptions/<subscription-id>
  # Required for creating role assignments in the GitHub Actions workflow
  az role assignment create --assignee <client_id> --role "User Access Administrator" --scope /subscriptions/<subscription-id>/resourceGroups/<your-resource-group>
  ```
  Replace `<client_id>` with your service principal's clientId, `<subscription-id>` with your Azure subscription ID, and `<your-resource-group>` with your resource group name.
  
  Note: If you prefer not to grant "User Access Administrator" role to your service principal, you can manually assign the "Storage Blob Data Contributor" role to the Automation Account's managed identity after deployment.

### 5. Deploy the Infrastructure Using GitHub Actions
- Go to the **Actions** tab in your GitHub repository.
- Select the **Deploy Runbook Infra** workflow.
- Click **Run workflow** to deploy the Bicep template and provision all required Azure resources.

### 6. Set Up Azure Automation Account Variables
After the infrastructure is deployed, you can set up the required Automation Account variables for your runbook:

####  Using the deploy-automation-vars.yml GitHub Actions Workflow

This automated workflow sets up all necessary variables in your Automation Account and configures the role assignment:

-  Go to the **Actions** tab in your GitHub repository.
-  Select the **Deploy Runbook Vars** workflow.
-  Click **Run workflow** to create all required variables in your Automation Account.

The workflow automatically:

- Creates the following variables in your Automation Account:
  - `authToken`: Your GitHub Personal Access Token (from `REPO_PAT` secret)
  - `StorageAccountName`: Your storage account name
  - `ContainerName`: Your blob container name
- Retrieves the Automation Account's managed identity principal ID
- Assigns the "Storage Blob Data Contributor" role to this managed identity on the storage account
  
Note: This project uses Azure managed identity for secure, key-less authentication to Azure Storage. No storage keys are stored in the Automation Account, enhancing security by avoiding shared secrets.



Note: Storage account key is not needed as the runbook uses the Automation Account's managed identity to access the storage account.

### Role Assignment Management

This solution uses Azure Managed Identity to securely access the storage account without keys. The role assignments are managed in two possible ways:

1. **Via GitHub Actions Workflow (Recommended)**: The `deploy-automation-vars.yml` workflow automatically assigns the "Storage Blob Data Contributor" role to the Automation Account's managed identity. This approach handles the role assignment after deployment, making it suitable even when the service principal lacks elevated permissions during Bicep deployment.

2. **Manually**: If your service principal doesn't have "User Access Administrator" rights, you can assign the role manually after deployment:

   ```sh
   az role assignment create --assignee <automation-account-principal-id> --role "Storage Blob Data Contributor" --scope /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Storage/storageAccounts/<storage-account>
   ```

   You can get the `automation-account-principal-id` from the Azure Portal or from the output of the Bicep deployment by checking the `automationAccountPrincipalId` output value.

### 7. Deploy the Runbook Script
You can deploy the PowerShell script (`GetGHCPUsageData/GetEnterpriseUsage.ps1`) to your Automation Account using the provided GitHub Actions workflow or manually with the Azure CLI:

Use the `.github/workflows/deploy-automation-runbook.yml` workflow to automate this step.

### 8. Runbook Schedule

The runbook is automatically scheduled to run daily at 1:00 AM UTC as part of the deployment process. This scheduling is handled by the GitHub Actions workflow (`deploy-automation-runbook.yml`) when you update the runbook content.

If you want to view or modify the schedule:

1. **In the Azure Portal:**
   - Navigate to your Automation Account
   - Select the runbook named "GetGHCPUsageData"
   - Click on "Schedules" in the left menu
   - You should see the "Daily-GHCP-Usage-Download" schedule
   - You can modify it or create additional schedules as needed

2. **Using Azure CLI:**

   ```sh
   # View existing schedules
   az automation schedule list \
     --automation-account-name <your-automation-account> \
     --resource-group <your-resource-group> \
     --query "[].{Name:name, Frequency:frequency, StartTime:startTime}"
   
   # Create an additional schedule if needed
   az automation schedule create \
     --name "CustomScheduleName" \
     --automation-account-name <your-automation-account> \
     --resource-group <your-resource-group> \
     --frequency "Day" \
     --interval 1 \
     --start-time "$(date -d 'tomorrow 01:00' --iso-8601=seconds)" \
     --timezone "UTC"   # Link the additional schedule to your runbook
   az automation runbook link \
     --automation-account-name <your-automation-account> \
     --resource-group <your-resource-group> \
     --runbook-name "GetGHCPUsageData" \
     --schedule-name "CustomScheduleName"
   ```

### 9. Testing and Validation

After deployment, it's important to verify that the managed identity and role assignments are working correctly:

1. **Test the Runbook Manually:**
   - In the Azure Portal, navigate to your Automation Account
   - Select the "GetGHCPUsageData" runbook
   - Click "Start" to run it manually
   - Monitor the job output for successful execution

2. **Verify Managed Identity Access:**
   - Check that the runbook successfully connects to Azure Storage using managed identity
   - Look for messages like "Connecting with Managed Identity..." in the job output
   - If you see errors about unauthorized access, verify that the role assignment was created correctly

3. **Check Role Assignments:**
   - In the Azure Portal, navigate to your storage account
   - Click on "Access control (IAM)" in the left menu
   - Select the "Role assignments" tab
   - Verify that your Automation Account's managed identity has the "Storage Blob Data Contributor" role
   - The Principal Name should match your Automation Account name

4. **Monitor Blob Creation:**
   - After a successful run, navigate to your storage account in the portal
   - Go to the "Containers" section and open your container
   - Verify that a new blob with GitHub Copilot metrics has been created with a name pattern like `ghcp_metrics_usage_YYYY-MM-DD.json`
   - Check the blob metadata to confirm it contains the expected fields

5. **Troubleshooting Role Assignment Issues:**
   - If the workflow or manual assignment process fails to create the role assignment, ensure your service principal has "User Access Administrator" permissions
   - Check the GitHub Actions workflow logs for detailed error messages
   - As a last resort, you can manually create the role assignment in the Azure Portal by:
     - Going to your storage account → Access control (IAM) → Add role assignment
     - Selecting "Storage Blob Data Contributor" role
     - Under "Assign access to", choosing "Managed identity" 
     - Selecting your Automation Account from the list

## References
- [Azure Automation PowerShell Runbooks](https://learn.microsoft.com/azure/automation/automation-runbook-types)
- [Azure Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview)
- [GitHub Actions for Azure](https://github.com/Azure/actions)

## Security & Best Practices

- Never hardcode secrets; always use Azure Key Vault or Automation Account variables
- Use managed identities where possible (this solution uses managed identity for Azure Storage access)
- Avoid using storage account keys; prefer managed identities or SAS tokens with appropriate permissions
- Follow the principle of least privilege for all Azure resources and Service Principals
- Validate deployments with `az deployment what-if` or `azd provision --preview` before applying changes

## Understanding Managed Identity Implementation

This solution uses Azure's managed identity feature to enhance security by eliminating the need for storage account keys:

### How It Works

1. **System-Assigned Managed Identity**: The Bicep template (`deploy-resources.bicep`) enables a system-assigned managed identity on the Automation Account:

   ```bicep
   identity: {
     type: 'SystemAssigned'
   }
   ```

2. **Role Assignment**: The GitHub Actions workflow (`deploy-automation-vars.yml`) assigns the "Storage Blob Data Contributor" role to this managed identity:

   ```powershell
   # Get the Automation Account's managed identity principal ID
   $principalId = $automationAccount.Identity.PrincipalId
   
   # Create the role assignment
   New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionId $roleDefinitionId -Scope $storageAccount.Id
   ```

3. **Authentication in Code**: The PowerShell runbook authenticates using this managed identity:

   ```powershell
   # Connect using managed identity
   Connect-AzAccount -Identity
   
   # Create storage context using connected account (no keys required)
   $context = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
   ```

This approach is more secure than using storage account keys because:

- No sensitive credentials are stored in variables or code
- Authentication is handled by Azure's secure identity platform
- Access can be precisely controlled through role-based access control (RBAC)
- Credentials don't need to be rotated manually

## Future Enhancements

Potential improvements for this project:

1. **Enhanced Error Notifications**: Configure Azure Monitor alerts for runbook failures
2. **Data Analytics Integration**: Connect Azure Storage to Power BI for Copilot usage dashboards
3. **Historical Trend Analysis**: Extend the script to retrieve data for multiple dates and generate trend reports
4. **Multi-Organization Support**: Expand to collect metrics from multiple GitHub organizations
5. **Retention Policy**: Implement automated data lifecycle management for long-term storage efficiency