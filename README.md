# ghcp-download-usage

## Overview
This project provides an Azure Automation Runbook (PowerShell) that downloads GitHub Copilot user adoption metrics and uploads the data to Azure Blob Storage. Infrastructure is managed using Bicep (IaC) files for secure, repeatable deployments.

## What It Does
- Calls the GitHub Copilot API to retrieve user adoption metrics.
- Stores the data as JSON in Azure Blob Storage.
- Uses Azure Automation Account variables for secrets and configuration.
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

**Never commit your PAT to source control.**

## Setup Steps

### 1. Deploy Azure Resources with Bicep
Navigate to the project root and run:

```sh
az deployment sub create \
  --location <location> \
  --template-file infra/deploy-resources.bicep \
  --parameters <your-parameters-file>.json
```

Or, for a resource group deployment:

```sh
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file infra/deploy-resources.bicep \
  --parameters <your-parameters-file>.json
```

### 2. Create Azure Automation Account Variables
Store secrets and configuration as Automation Account variables:

```sh
az automation variable create \
  --resource-group <resource-group-name> \
  --automation-account-name <automation-account-name> \
  --name GitHubToken \
  --value <your-github-token> --encrypted true

az automation variable create \
  --resource-group <resource-group-name> \
  --automation-account-name <automation-account-name> \
  --name StorageAccountName \
  --value <your-storage-account-name>

az automation variable create \
  --resource-group <resource-group-name> \
  --automation-account-name <automation-account-name> \
  --name StorageAccountKey \
  --value <your-storage-account-key> --encrypted true

az automation variable create \
  --resource-group <resource-group-name> \
  --automation-account-name <automation-account-name> \
  --name ContainerName \
  --value <your-container-name>
```

### How to Get the Azure Storage Account Key
To retrieve the storage account key (required for uploading to Blob Storage), use the following Azure CLI command:

```sh
az storage account keys list \
  --resource-group <resource-group-name> \
  --account-name <storage-account-name> 
```

This will output a JSON array of keys. Use the value of `key1` or `key2` as your `StorageAccountKey` when creating the Automation Account variable or setting your local environment variable.

### 3. Import the Runbook Script
You can import the PowerShell script (`GetGHCPUsageData/run.ps1`) into your Azure Automation Account either manually or using the Azure CLI:

```sh
az automation runbook import \
  --automation-account-name <automation-account-name> \
  --resource-group <resource-group-name> \
  --name "GetGHCPUsageData" \
  --type PowerShell \
  --path ./GetGHCPUsageData/run.ps1 \
  --force
```

### 4. Set Up GitHub Actions (Optional)
- Add the following secrets to your GitHub repository:
  - `AZURE_CREDENTIALS`: Output from `az ad sp create-for-rbac ... --sdk-auth`
  - `AZURE_AUTOMATION_ACCOUNT`: Your Azure Automation Account name
  - `AZURE_RESOURCE_GROUP`: Resource group containing the Automation Account
- The workflow in `.github/workflows/deploy-automation-runbook.yml` will deploy your runbook on push to the specified branch.

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

## Deploying Infrastructure from GitHub Actions

You can deploy the Azure infrastructure (Automation Account, Storage, etc.) using the provided GitHub Actions workflow: `.github/workflows/deploy-infra.yml`.

### Steps to Deploy

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

**Note:**
- You can also run the Bicep deployment locally using the Azure CLI if needed (see earlier instructions in this README).
- The workflow only runs when triggered manually (not on push).

## References
- [Azure Automation PowerShell Runbooks](https://learn.microsoft.com/azure/automation/automation-runbook-types)
- [Azure Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview)
- [GitHub Actions for Azure](https://github.com/Azure/actions)

## Security & Best Practices
- Never hardcode secrets; always use Azure Key Vault or Automation Account variables.
- Use managed identities where possible.
- Follow the principle of least privilege for all Azure resources and Service Principals.
- Validate deployments with `az deployment what-if` or `azd provision --preview` before applying changes.