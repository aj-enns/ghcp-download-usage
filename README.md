# ghcp-download-usage

## Overview
This project provides an Azure Automation Runbook (PowerShell) that downloads GitHub Copilot user adoption metrics and uploads the data to Azure Blob Storage. Infrastructure is managed using Bicep (IaC) files for secure, repeatable deployments. The solution uses Azure Managed Identity for secure, key-less authentication to Azure Storage.

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
   - Any additional scopes required by the Copilot metrics API (check [GitHub Copilot API documentation](https://docs.github.com/en/copilot) for updates)
5. Click **Generate token** and copy the token value. You will not be able to see it again!
6. Store this token securely:
   - As the value for the `GitHubToken` variable in your Azure Automation Account (see step 2 below).
   - **Add it as a secret named `REPO_PAT` in your GitHub repository** (Settings > Secrets and variables > Actions > New repository secret).

**Never commit your PAT to source control.**

## Setup Steps

## Recommended Setup Order

Follow these steps in order for a successful deployment:

### 1. Create the Resource Group
Create your Azure resource group (if it doesn't already exist):

```sh
az group create --name <your-resource-group> --location <your-location>
```

### 2. Create Azure Service Principal and Set GitHub Secrets/Variables
- Create a service principal and get the credentials JSON:

```sh
az ad sp create-for-rbac --name "<service-principal-name>" --role contributor --scopes /subscriptions/<subscription-id>/resourceGroups/<your-resource-group> --sdk-auth
```
- Add the following to your GitHub repository (as secrets or variables as appropriate):
  - `AZURE_CREDENTIALS` (secret): The JSON output from the command above
  - `AZURE_RESOURCE_GROUP` (secret or variable): Your resource group name
  - `AZURE_AUTOMATION_ACCOUNT` (secret or variable): Your Automation Account name
  - `AZURE_LOCATION` (variable): Your Azure region (e.g., canadacentral)
  - `AZURE_CONTAINER_NAME` (variable): Your blob container name
  - `AZURE_STORAGE_ACCOUNT_NAME` (variable): Your storage account name (optional, only if you want to override the default)

- **Assign the Contributor role to your service principal at the subscription level:**

  ```sh
  az role assignment create --assignee <client_id> --role Contributor --scope /subscriptions/<subscription-id>
  ```
  Replace `<client_id>` with your service principal's clientId and `<subscription-id>` with your Azure subscription ID. This is required for deployments that create resource groups or use subscription-scoped modules in Bicep.

### 3. Deploy Infrastructure Using GitHub Actions
- Go to the **Actions** tab in your GitHub repository.
- Select the **Deploy Azure Infrastructure** workflow.
- Click **Run workflow** to deploy the Bicep template and provision all required Azure resources.

### 4. Set Up Azure Automation Account Variables
After the infrastructure is deployed, you can set up the required Automation Account variables for your runbook in two ways:

#### Option 1: Using the deploy-automation-vars.yml GitHub Actions Workflow (Recommended)
This automated workflow sets up all necessary variables in your Automation Account:

1. Go to the **Actions** tab in your GitHub repository.
2. Select the **Deploy Runbook Vars** workflow.
3. Click **Run workflow** to create all required variables in your Automation Account.

The workflow automatically:
- Creates the following variables in your Automation Account:
  - `authToken`: Your GitHub Personal Access Token (from `REPO_PAT` secret)
  - `StorageAccountName`: Your storage account name
  - `ContainerName`: Your blob container name
  
Note: This project uses Azure managed identity for secure, key-less authentication to Azure Storage.

#### Option 2: Manual Setup Using Azure CLI
If you prefer to set up the variables manually:

```sh
az automation variable create \
  --resource-group <your-resource-group> \
  --automation-account-name <your-automation-account> \
  --name authToken \
  --value <your-github-token> --encrypted true

az automation variable create \
  --resource-group <your-resource-group> \
  --automation-account-name <your-automation-account> \
  --name StorageAccountName \
  --value <your-storage-account-name>

az automation variable create \
  --resource-group <your-resource-group> \
  --automation-account-name <your-automation-account> \
  --name ContainerName \
  --value <your-container-name>
```

Note: Storage account key is not needed as the runbook uses the Automation Account's managed identity to access the storage account.

### 5. Deploy the Runbook Script
You can deploy the PowerShell script (`GetGHCPUsageData/GetEnterpriseUsage.ps1`) to your Automation Account using the provided GitHub Actions workflow or manually with the Azure CLI:

```sh
az automation runbook create \
  --automation-account-name <your-automation-account> \
  --resource-group <your-resource-group> \
  --name "GetGHCPUsageData" \
  --type PowerShell \
  --location <your-location>

az automation runbook replace-content \
  --automation-account-name <your-automation-account> \
  --resource-group <your-resource-group> \
  --name "GetGHCPUsageData" \
  --content @./GetGHCPUsageData/GetEnterpriseUsage.ps1
```

Or use the `.github/workflows/deploy-automation-runbook.yml` workflow to automate this step.

## Setting up GitHub Actions Azure Credentials Secret

To enable GitHub Actions to deploy resources to Azure, you need to create a service principal and add its credentials as a secret named `AZURE_CREDENTIALS` in your repository.

### 1. Generate the credentials JSON
Run this command in your terminal (replace the placeholders with your values):

```sh
az ad sp create-for-rbac --name "<service-principal-name>" --role contributor --scopes /subscriptions/<subscription-id>/resourceGroups/<resource-group-name> --sdk-auth
```

### 2. The output will look like this:

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

### 3. Add this JSON as the value for the `AZURE_CREDENTIALS` secret in your GitHub repository
- Go to your repository’s **Settings** > **Secrets and variables** > **Actions**.
- Click **New repository secret**.
- Name: `AZURE_CREDENTIALS`
- Value: *(Paste the entire JSON output above)*

This secret will be used by the `azure/login@v2` GitHub Action to authenticate your workflow.

## GitHub Actions Workflows

### 1. Deploying Infrastructure - `deploy-infra.yml`

You can deploy the Azure infrastructure (Automation Account, Storage, etc.) using the provided GitHub Actions workflow: `.github/workflows/deploy-infra.yml`.

#### Steps to Deploy

1. **Ensure required secrets are set in your GitHub repository:**
   - `AZURE_CREDENTIALS`: Output from `az ad sp create-for-rbac ... --sdk-auth`
   - `AZURE_AUTOMATION_ACCOUNT`: Your Azure Automation Account name
   - `AZURE_RESOURCE_GROUP`: Resource group containing the Automation Account
   - (Optional) If you want to keep your container name private, add it as a secret and update the workflow accordingly.

2. **Trigger the workflow manually:**
   - Go to the **Actions** tab in your GitHub repository.
   - Select the **Deploy Azure Infrastructure** workflow.
   - Click the **Run workflow** button and confirm.

3. **What the workflow does:**
   - Checks out your code.
   - Logs in to Azure using the credentials from `AZURE_CREDENTIALS`.
   - Extracts the subscription ID from the credentials.
   - Runs the Bicep deployment using the parameters:
     - `location=canadacentral`
     - `automationAccountName` (from secret)
     - `resourceGroupName` (from secret)
     - `containerName` (set in the workflow or as a secret)

4. **Monitor the deployment:**
   - The workflow logs will show the progress and results of the deployment.
   - Any errors or issues will be displayed in the Actions run output.

### 2. Setting Up Azure Automation Variables - `deploy-automation-vars.yml`

This workflow automates the creation of required variables in your Azure Automation Account.

#### Prerequisites

1. **Required GitHub Secrets:**
   - `AZURE_CREDENTIALS`: Azure service principal credentials in JSON format
   - `AZURE_AUTOMATION_ACCOUNT`: Your Azure Automation Account name
   - `REPO_PAT`: Your GitHub Personal Access Token

2. **Required GitHub Variables:**
   - `AZURE_RESOURCE_GROUP`: Your Azure resource group name
   - `AZURE_LOCATION`: Azure region (e.g., canadacentral)
   - `AZURE_CONTAINER_NAME`: Your blob container name
   - `AZURE_STORAGE_ACCOUNT_NAME`: Your storage account name

#### Steps to Run

1. **Trigger the workflow manually:**
   - Go to the **Actions** tab in your GitHub repository.
   - Select the **Deploy Runbook Vars** workflow.
   - Click the **Run workflow** button and confirm.

2. **What the workflow does:**
   - Logs in to Azure using the service principal credentials.
   - Retrieves the storage account key from your storage account.
   - Creates the following variables in your Azure Automation Account:
     - `authToken`: Your GitHub PAT for accessing the Copilot API
     - `StorageAccountName`: Name of your Azure Storage account
     - `StorageAccountKey`: Access key for your storage account (encrypted)
     - `ContainerName`: Name of your blob container

3. **Monitor the deployment:**
   - The workflow logs will show the progress and results.
   - Any errors will be displayed in the Actions run output.

### 3. Deploying Runbook - `deploy-automation-runbook.yml`

This workflow deploys the PowerShell runbook script to your Azure Automation Account.

**Note:**
- You can also run these deployments locally using the Azure CLI if needed (see earlier instructions in this README).
- The workflows only run when triggered manually or on specific file changes.

## References
- [Azure Automation PowerShell Runbooks](https://learn.microsoft.com/azure/automation/automation-runbook-types)
- [Azure Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview)
- [GitHub Actions for Azure](https://github.com/Azure/actions)

## Security & Best Practices
- Never hardcode secrets; always use Azure Key Vault or Automation Account variables.
- Use managed identities where possible (this solution uses managed identity for Azure Storage access).
- Avoid using storage account keys; prefer managed identities or SAS tokens with appropriate permissions.
- Follow the principle of least privilege for all Azure resources and Service Principals.
- Validate deployments with `az deployment what-if` or `azd provision --preview` before applying changes.