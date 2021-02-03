<#
.SYNOPSIS
    This script enumerates all resource groups in a subscription and deletes the
    resources from each resource group.

.DESCRIPTION
    This script enumerates all resource groups in a subscription and deletes the
    resources from each resource group.
    It asks for confirmation if the resource group should be deleted.
    It also has the option to delete all empty resource groups without deleting 
    any resource groups with resources inside.
    
.EXAMPLE
    .\Clean-SubscriptionResources.ps1 -SubscriptionId $SubscriptionId `
        -TenantId $TenantId `
        -ServicePrincipalId $ServicePrincipalId `
        -ServicePrincipalSecret $ServicePrincipalSecret `

.PARAMETER SubscriptionId
    The ID of the subscription where the deployments are done.
    
.PARAMETER TenantId
    The ID of the tenant in which the subscription is located.

.PARAMETER ServicePrincipalId
    The ID of the service principal that will be used to fetch the data. Must 
    have read access to the subscription.
    
.PARAMETER ServicePrincipalSecret
    The password for the service principal that will be used to fetch the data. 
    Must have read access to the subscription.

.PARAMETER CleanEmptyResourceGroups
    Set to $true to automatically delete all empty resource groups.

.PARAMETER ForceDelete
    Set to $true to force delete resources without confirmation.

.PARAMETER Transcribe
    Set to $true to transcribe the invocation.

.OUTPUTS

.NOTES
#>

param(
    [Parameter(Mandatory=$True)]
    [string]
    $SubscriptionId,
   
    [Parameter(Mandatory=$True)]
    [string]
    $TenantId,
   
    [Parameter(Mandatory=$True)]
    [string]
    $ServicePrincipalId,
   
    [Parameter(Mandatory=$True)]
    [string]
    $ServicePrincipalPassword,

    [Parameter(Mandatory=$False)]
    [bool]
    $CleanEmptyResourceGroups = $False,

    [Parameter(Mandatory=$False)]
    [bool]
    $ForceDelete = $False,

    [Parameter(Mandatory=$False)]
    [bool]
    $Transcribe = $False
)

<#
.SYNOPSIS
    Registers Resource Providers
#>
Function RegisterRP {
    Param(
        [string]$ResourceProviderNamespace
    )

    Write-Host "Registering resource provider '$ResourceProviderNamespace'" 
    Register-AzResourceProvider -ProviderNamespace $ResourceProviderNamespace
}

<#
.SYNOPSIS
    Deletes all empty resource groups

.DESCRIPTION
    Deletes resource groups that have no resource in them.
    
.EXAMPLE
    DeleteEmptyResourceGroups($resourceGroups)

.PARAMETER ResourceGroups
    An array with resource group names to evaluate for deletion.
#>
Function DeleteEmptyResourceGroups {
    param(
        [Parameter(Mandatory=$True)]
        [array]
        $ResourceGroups
    )

    $jobs = [System.Collections.ArrayList]@()

    $ResourceGroups | ForEach-Object {
        try {
            # Get all the resources for a resource group
            $resourceGroupName = $_.ResourceGroupName
            Write-Host "Evaluating resource group  '$resourceGroupName'..."
            $rgResources = Get-AzResource -ResourceGroupName $resourceGroupName
            Write-Host "Retrieved resources for resource group  '$resourceGroupName'..." -ForegroundColor "Green"

            if ($rgResources.count -eq 0) {
                # Delete the resource group if there are no resource in it
                Write-Host "Deleting resource group  '$resourceGroupName'..." -ForegroundColor "Yellow"
                $null = $jobs.Add($(Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob))
                Write-Host "Resource group '$resourceGroupName' scheduled for deletedion!" -ForegroundColor "Green"
            }
        }
        catch {
            throw $_.Exception.Message
        }
    }

    Write-Host "Jobs status..." -ForegroundColor "Green"
    $jobs | Format-Table -AutoSize
    Write-Host "$($jobs.count) resource groups scheduled for deletion!" -ForegroundColor "Yellow"
}

<#
.SYNOPSIS
    Deletes resource groups and their resources

.DESCRIPTION
    Deletes resource groups that have resource in them after asking for confirmation.
    
.EXAMPLE
    DeleteResourceGroups($resourceGroups)

.PARAMETER ResourceGroups
    An array with resource group names to evaluate for deletion.

.PARAMETER ForceDelete
    $true if the resources should be deleted without confirmation
#>
Function DeleteResourceGroups {
    param(
        [Parameter(Mandatory=$True)]
        [array]
        $ResourceGroups,

        [Parameter(Mandatory=$False)]
        [bool]
        $ForceDelete = $False
    )

    $jobs = [System.Collections.ArrayList]@()

    $ResourceGroups | ForEach-Object {
        try {
            # Get all the resources for a resource group
            $resourceGroupName = $_.ResourceGroupName
            Write-Host "Evaluating resource group  '$resourceGroupName'..."
            $rgResources = Get-AzResource -ResourceGroupName $resourceGroupName
            Write-Host "Retrieved resources for resource group  '$resourceGroupName'..." -ForegroundColor "Green"

            if ($rgResources.count -eq 0) {
                # Delete the resource group if there are no resource in it
                Write-Host "Deleting resource group  '$resourceGroupName'..." -ForegroundColor "Yellow"
                $null = $jobs.Add($(Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob))
                Write-Host "Resource group '$resourceGroupName' scheduled for deletedion!" -ForegroundColor "Green"
            } else {
                # Delete the resource group if there are no resource in it
                Write-Host "Resource group  '$resourceGroupName' contains the following resources:" -ForegroundColor "Yellow"
                $rgResources | Format-Table -AutoSize

                if ($ForceDelete -ne $True) {
                    $confirmation = Read-Host -Prompt "Are you sure you want to delete the following resources from resource group  '$resourceGroupName'? [y/N]"
                }

                if ($confirmation -eq 'y' -or $confirmation -eq 'Y' -or $ForceDelete -eq $True) {
                    $null = $jobs.Add($(Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob))
                    Write-Host "Resource group '$resourceGroupName' scheduled for deletedion!" -ForegroundColor "Red"
                } else {
                    Write-Host "Resource group '$resourceGroupName' will not be deleted!" -ForegroundColor "Green"
                }
            }
        }
        catch {
            throw $_.Exception.Message
        }
    }

    Write-Host "Jobs status..." -ForegroundColor "Green"
    $jobs | Format-Table -AutoSize
    Write-Host "$($jobs.count) resource groups scheduled for deletion!" -ForegroundColor "Yellow"
}

$ErrorActionPreference = "Stop"

# Sign In
$securePassword = ConvertTo-SecureString -String $ServicePrincipalPassword -AsPlainText -Force
$credentials = New-Object -TypeName System.Management.Automation.PSCredential($ServicePrincipalId, $securePassword)

$azureProfile = $null

try {
    # Remove stale context
    Clear-AzContext -Force
    
    Write-Host "Login to subscription '${SubscriptionId}'..." -ForegroundColor "White"
    $azureProfile =  Connect-AzAccount -Credential $credentials -ServicePrincipal -Tenant $TenantId -SubscriptionId $SubscriptionId
    Write-Host "Login to subscription '${SubscriptionId}' successful!" -ForegroundColor "Green"
}
catch {
    throw $_.Exception.Message
}

# Register RPs
$resourceProviders = @()
if($resourceProviders.length) {
    Write-Host "Registering resource providers"
    foreach($resourceProvider in $resourceProviders) {
        RegisterRP($resourceProvider)
    }
}

# Get all resource groups from the subscription
Write-Host "Retrieving a list of all resource groups for subscription '$($azureProfile.Context.Subscription.Name)'..."
$resourceGroups = Get-AzResourceGroup
Write-Host "Retrieved $($resourceGroups.count) resource groups for subscription '$($azureProfile.Context.Subscription.Name)'!" `
    -ForegroundColor "Green"

if ($CleanEmptyResourceGroups) {
    DeleteEmptyResourceGroups($resourceGroups)
} else {
    DeleteResourceGroups($resourceGroups)
}
