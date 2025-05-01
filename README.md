# ghcp-download-usage

## Overview
This project provides an Azure Function (PowerShell) that downloads GitHub Copilot user adoption metrics and uploads the data to Azure Blob Storage. Infrastructure is managed using Bicep (IaC) files for secure, repeatable deployments.

## What It Does
- Calls the GitHub Copilot API to retrieve user adoption metrics.
- Stores the data as JSON in Azure Blob Storage.
- Uses Azure Automation Account variables for secrets and configuration.
- Deploys all Azure resources using Bicep (infra/ folder).
- Supports CI/CD deployment via GitHub Actions.

## Prerequisites
- Azure Subscription
- Azure CLI installed
- Sufficient permissions to create resource groups, storage accounts, automation accounts, and function apps
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
   - As the value for the `GitHubToken` variable in your Azure Automation Account (see step 2 above).

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
```

### How to Get the Azure Storage Account Key
To retrieve the storage account key (required for uploading to Blob Storage), use the following Azure CLI command:

```sh
az storage account keys list \
  --resource-group <resource-group-name> \
  --account-name <storage-account-name> 
```

This will output a JSON array of keys. Use the value of `key1` or `key2` as your `StorageAccountKey` when creating the Automation Account variable or setting your local environment variable.

### 3. Configure the Azure Function
- Update `GetGHCPdata.ps1` with your Automation Account and Resource Group names.
- Ensure the container name in the script matches your Blob Storage container.

### 4. Set Up GitHub Actions (Optional)
- Add the following secrets to your GitHub repository:
  - `AZURE_CREDENTIALS`: Output from `az ad sp create-for-rbac ... --sdk-auth`
  - `AZURE_FUNCTIONAPP_NAME`: Your Azure Function App name
  - `AZURE_FUNCTIONAPP_PUBLISH_PROFILE`: Publish profile for your Function App
- The workflow in `.github/workflows/deploy-azure-function.yml` will deploy your function on push to main.

#### Example command to create Azure credentials for GitHub Actions:
```sh
az ad sp create-for-rbac --name "<service-principal-name>" --role contributor --scopes /subscriptions/<subscription-id>/resourceGroups/<resource-group-name> --sdk-auth
```
Copy the JSON output and store it as the `AZURE_CREDENTIALS` secret in GitHub.

## References
- [Azure Functions PowerShell docs](https://learn.microsoft.com/azure/azure-functions/functions-reference-powershell)
- [Azure Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview)
- [GitHub Actions for Azure](https://github.com/Azure/functions-action)

## Security & Best Practices
- Never hardcode secrets; always use Azure Key Vault or Automation Account variables.
- Use managed identities where possible.
- Follow the principle of least privilege for all Azure resources and Service Principals.
- Validate deployments with `az deployment what-if` or `azd provision --preview` before applying changes.