# Utility Functions used by AzureFileCopy.ps1 (other than azure calls) #

$ErrorActionPreference = 'Stop'

# Telemetry
$telemetryCodes = 
@{
  "PREREQ_NoWinRMHTTP_Port" = "PREREQ001";
  "PREREQ_NoWinRMHTTPSPort" = "PREREQ002";
  "PREREQ_NoResources" = "PREREQ003";
  "PREREQ_NoOutputVariableForSelectActionInAzureRG" = "PREREQ004";
  "PREREQ_InvalidServiceConnectionType" = "PREREQ_InvalidServiceConnectionType";
  "PREREQ_AzureRMModuleNotFound" = "PREREQ_AzureRMModuleNotFound";
  "PREREQ_InvalidFilePath" = "PREREQ_InvalidFilePath";
  "PREREQ_StorageAccountNotFound" = "PREREQ_StorageAccountNotFound";
  "PREREQ_NoVMResources" = "PREREQ_NoVMResources";
  "PREREQ_UnsupportedAzurePSVerion" = "PREREQ_UnsupportedAzurePSVerion";
  "PREREQ_ClassicStorageAccountNotFound" = "PREREQ_ClassicStorageAccountNotFound";
  "PREREQ_RMStorageAccountNotFound" = "PREREQ_RMStorageAccountNotFound";
  "PREREQ_NoClassicVMResources" = "PREREQ_NoClassicVMResources";
  "PREREQ_NoRMVMResources" = "PREREQ_NoRMVMResources";
  "PREREQ_ResourceGroupNotFound" = "PREREQ_ResourceGroupNotFound";

  "AZUREPLATFORM_BlobUploadFailed" = "AZUREPLATFORM_BlobUploadFailed";
  "AZUREPLATFORM_UnknownGetRMVMError" = "AZUREPLATFORM_UnknownGetRMVMError";

  "UNKNOWNPREDEP_Error" = "UNKNOWNPREDEP001";
  "UNKNOWNDEP_Error" = "UNKNOWNDEP_Error";

  "DEPLOYMENT_Failed" = "DEP001";
  "DEPLOYMENT_FetchPropertyFromMap" = "DEPLOYMENT_FetchPropertyFromMap";
  "DEPLOYMENT_CSMDeploymentFailed" = "DEPLOYMENT_CSMDeploymentFailed";  
  "DEPLOYMENT_PerformActionFailed" = "DEPLOYMENT_PerformActionFailed";

  "ENABLEWINRM_ProvisionVmCustomScriptFailed" = "ENABLEWINRM_ProvisionVmCustomScriptFailed"
  "ENABLEWINRM_ExecutionOfVmCustomScriptFailed" = "ENABLEWINRM_ExecutionOfVmCustomScriptFailed"

  "FILTERING_IncorrectFormat" = "FILTERING_IncorrectFormat";
  "FILTERING_NoVMResources" = "FILTERING_NoVMResources";
  "FILTERING_MachinesNotPresentInRG" = "FILTERING_MachinesNotPresentInRG"
 }

function Write-Telemetry
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$True,Position=1)]
        [string]$codeKey,
        [Parameter(Mandatory=$True,Position=2)]
        [string]$taskId
    )

    if($telemetrySet)
    {
        return
    }

    $code = $telemetryCodes[$codeKey]
    $telemetryString = "##vso[task.logissue type=error;code=" + $code + ";TaskId=" + $taskId + ";]"

    Write-Host $telemetryString
    $telemetrySet = $true
}

function Write-TaskSpecificTelemetry
{
    param([string]$codeKey)

    Write-Telemetry "$codeKey" "EB72CB01-A7E5-427B-A8A1-1B31CCAC8A43"
}

function Get-AzureUtility
{
    $currentVersion =  Get-AzureCmdletsVersion
    Write-Verbose -Verbose "Installed Azure PowerShell version: $currentVersion"

    $minimumAzureVersion = New-Object System.Version(0, 9, 9)
    $versionCompatible = Get-AzureVersionComparison -AzureVersion $currentVersion -CompareVersion $minimumAzureVersion

    $azureUtilityOldVersion = "AzureUtilityLTE9.8.ps1"
    $azureUtilityNewVersion = "AzureUtilityGTE1.0.ps1"

    if(!$versionCompatible)
    {
        $azureUtilityRequiredVersion = $azureUtilityOldVersion
    }
    else
    {
        $azureUtilityRequiredVersion = $azureUtilityNewVersion
    }

    Write-Verbose -Verbose "Required AzureUtility: $azureUtilityRequiredVersion"
    return $azureUtilityRequiredVersion
}

function Get-ConnectionType
{
    param([string][Parameter(Mandatory=$true)]$connectedServiceName,
          [object][Parameter(Mandatory=$true)]$distributedTaskContext)

    $serviceEndpoint = Get-ServiceEndpoint -Name "$ConnectedServiceName" -Context $distributedTaskContext
    $connectionType = $serviceEndpoint.Authorization.Scheme

    Write-Verbose -Verbose "Connection type used is $connectionType"
    return $connectionType
}

function Validate-AzurePowershellVersion
{
    Write-Verbose "Validating minimum required azure powershell version is greater than or equal to 0.9.0" -Verbose

    $currentVersion =  Get-AzureCmdletsVersion
    Write-Verbose -Verbose "Installed Azure PowerShell version: $currentVersion"

    $minimumAzureVersion = New-Object System.Version(0, 9, 0)
    $versionCompatible = Get-AzureVersionComparison -AzureVersion $currentVersion -CompareVersion $minimumAzureVersion

    if(!$versionCompatible)
    {
        Write-TaskSpecificTelemetry "PREREQ_UnsupportedAzurePSVerion"
        Throw (Get-LocalizedString -Key "The required minimum version {0} of the Azure Powershell Cmdlets are not installed. You can follow the instructions at http://azure.microsoft.com/en-in/documentation/articles/powershell-install-configure/ to get the latest Azure powershell" -ArgumentList $minimumAzureVersion)
    }

    Write-Verbose -Verbose "Validated the required azure powershell version is greater than or equal to 0.9.0"
}

function Get-StorageKey
{
    param([string][Parameter(Mandatory=$true)]$storageAccountName,
          [string][Parameter(Mandatory=$true)]$connectionType)

    $storageAccountName = $storageAccountName.Trim()
    if($connectionType -eq 'Certificate' -or $connectionType -eq 'UserNamePassword')
    {
        try
        {
            # getting storage key from RDFE
            $storageKey = Get-AzureStorageKeyFromRDFE -storageAccountName $storageAccountName
        }
        catch [Hyak.Common.CloudException]
        {
            $exceptionMessage = $_.Exception.Message.ToString()
            Write-Verbose "[Azure Call](RDFE) ExceptionMessage: $exceptionMessage" -Verbose

            if($connectionType -eq 'Certificate')
            {
                Write-TaskSpecificTelemetry "PREREQ_ClassicStorageAccountNotFound"
                Throw (Get-LocalizedString -Key "Storage account: {0} not found. Selected Connection 'Certificate' supports storage account of Azure Classic type only." -ArgumentList $storageAccountName)
            }
            # Since authentication is UserNamePassword we will check whether storage is non-classic
            # Bug: We are validating azureps version to be atleast 0.9.0 though it is not required if user working on classic resources
            else
            {
                try
                {
                    # checking azure powershell version to make calls to ARM endpoint
                    Validate-AzurePowershellVersion

                    # getting storage account key from ARM endpoint
                    $storageKey = Get-AzureStorageKeyFromARM -storageAccountName $storageAccountName
                }
                catch
                {
                    #since authentication was UserNamePassword so we cant suggest user whether storage should be classic or non-classic
                    Write-TaskSpecificTelemetry "PREREQ_StorageAccountNotFound"
                    Throw (Get-LocalizedString -Key "Storage account: {0} not found. Please specify existing storage account" -ArgumentList $storageAccountName)
                }
            }
        }
    }
    else
    {
        # checking azure powershell version to make calls to ARM endpoint
        Validate-AzurePowershellVersion

        # getting storage account key from ARM endpoint
        $storageKey = Get-AzureStorageKeyFromARM -storageAccountName $storageAccountName
    }

    return $storageKey
}

function ThrowError
{
    param([string]$errorMessage)

    $readmelink = "http://aka.ms/azurefilecopyreadme"
    $helpMessage = (Get-LocalizedString -Key "For more info please refer to {0}" -ArgumentList $readmelink)
    throw "$errorMessage $helpMessage"
}

function Upload-FilesToAzureContainer
{
    param([string][Parameter(Mandatory=$true)]$sourcePath,
          [string][Parameter(Mandatory=$true)]$storageAccountName,
          [string][Parameter(Mandatory=$true)]$containerName,
          [string]$blobPrefix,
          [string][Parameter(Mandatory=$true)]$storageKey,
          [string][Parameter(Mandatory=$true)]$azCopyLocation,
          [string]$additionalArguments,
          [string][Parameter(Mandatory=$true)]$destinationType)

    $sourcePath = $sourcePath.Trim('"')
    $storageAccountName = $storageAccountName.Trim()
    try
    {
        Write-Output (Get-LocalizedString -Key "Uploading files from source path: '{0}' to storage account: '{1}' in container: '{2}' with blobprefix: '{3}'" -ArgumentList $sourcePath, $storageAccountName, $containerName, $blobPrefix)

        if([string]::IsNullOrWhiteSpace($additionalArguments))
        {
            $uploadResponse = Copy-FilesToAzureBlob -SourcePathLocation $sourcePath -StorageAccountName $storageAccountName -ContainerName $containerName -BlobPrefix $blobPrefix -StorageAccountKey $storageKey -AzCopyLocation $azCopyLocation
        }
        else
        {
            $uploadResponse = Copy-FilesToAzureBlob -SourcePathLocation $sourcePath -StorageAccountName $storageAccountName -ContainerName $containerName -BlobPrefix $blobPrefix -StorageAccountKey $storageKey -AzCopyLocation $azCopyLocation -AdditionalArguments $additionalArguments
        }
    }
    catch
    {
        # deletes container only if we have created temporary container
        if ($destinationType -ne "AzureBlob")
        {
            Remove-AzureContainer -containerName $containerName -storageContext $storageContext
        }

        $exceptionMessage = $_.Exception.Message.ToString()
        Write-Verbose "ExceptionMessage: $exceptionMessage" -Verbose

        $errorMessage = (Get-LocalizedString -Key "Upload to container: '{0}' in storage account: '{1}' with blobprefix: '{2}' failed with error: '{3}'" -ArgumentList $containerName, $storageAccountName, $blobPrefix, $exceptionMessage)
        Write-TaskSpecificTelemetry "AZUREPLATFORM_BlobUploadFailed"
        ThrowError -errorMessage $errorMessage
    }
    finally
    {
        if ($uploadResponse.Status -eq "Failed")
        {
            # deletes container only if we have created temporary container
            if ($destination -ne "AzureBlob")
            {
                Remove-AzureContainer -containerName $containerName -storageContext $storageContext
            }

            $uploadErrorMessage = $uploadResponse.Error
            Write-Verbose "UploadErrorMessage: $uploadErrorMessage" -Verbose

            $errorMessage = (Get-LocalizedString -Key "Upload to container: '{0}' in storage account: '{1}' with blobprefix: '{2}' failed with error: '{3}'" -ArgumentList $containerName, $storageAccountName, $blobPrefix, $uploadErrorMessage)
            Write-TaskSpecificTelemetry "AZUREPLATFORM_BlobUploadFailed"
            ThrowError -errorMessage $errorMessage
        }
        elseif ($uploadResponse.Status -eq "Succeeded")
        {
            Write-Output (Get-LocalizedString -Key "Uploaded files successfully from source path: '{0}' to storage account: '{1}' in container: '{2}' with blobprefix: '{3}'" -ArgumentList $sourcePath, $storageAccountName, $containerName, $blobPrefix)
        }
    }
}

function Does-AzureVMMatchFilterCriteria
{
    param([object]$azureVMResource,
          [string]$resourceFilteringMethod,
          [string]$filter)

    if($azureVMResource -and -not [string]::IsNullOrEmpty($resourceFilteringMethod))
    {
        # If no filters are provided, by default operations are performed on all azure resources
        if([string]::IsNullOrEmpty($filter))
        {
            return $true
        }

        $tagsFilterArray = $filter.Split(';').Trim()
        foreach($tag in $tagsFilterArray)
        {
            $tagKeyValue = $tag.Split(':').Trim()
            $tagKey =  $tagKeyValue[0]
            $tagValues = $tagKeyValue[1]

            if($tagKeyValue.Length -ne 2 -or [string]::IsNullOrWhiteSpace($tagKey) -or [string]::IsNullOrWhiteSpace($tagValues))
            {
                Write-TaskSpecificTelemetry "FILTERING_IncorrectFormat"
                throw (Get-LocalizedString -Key "Tags have been incorrectly specified. They have to be in the format Role:Web,DB;Location:East US;Dept.:Finance,HR")
            }

            $tagValueArray = $tagValues.Split(',').Trim()

            if($azureVMResource.Tags)
            {
                foreach($azureVMResourceTag in $azureVMResource.Tags.GetEnumerator())
                {
                    if($azureVMResourceTag.Key -contains $tagKey)
                    {
                        $azureVMTagValueArray = $azureVMResourceTag.Value.Split(",").Trim()
                        foreach($tagValue in $tagValueArray)
                        {
                            if($azureVMTagValueArray -contains $tagValue)
                            {
                                return $true
                            }
                        }
                    }
                }
            }
        }

        return $false
    }
}

function Get-TagBasedFilteredAzureVMs
{
    param([object]$azureVMResources,
          [string]$filter)

    if($azureVMResources)
    {
        $filteredAzureVMResources = @()
        foreach($azureVMResource in $azureVMResources)
        {
            if(Does-AzureVMMatchFilterCriteria -azureVMResource $azureVMResource -resourceFilteringMethod $resourceFilteringMethod -filter $filter)
            {
                Write-Verbose -Verbose "azureVM with name: $($azureVMResource.Name) matches filter criteria"
                $filteredAzureVMResources += $azureVMResource
            }
        }

        return $filteredAzureVMResources
    }
}

function Get-MachineBasedFilteredAzureVMs
{
    param([object]$azureVMResources,
          [string]$filter)

    if($azureVMResources -and -not [string]::IsNullOrEmpty($filter))
    {
        $filteredAzureVMResources = @()

        $machineFilterArray = $machineFilterArray | % {$_.ToLower()} | Select -Uniq
        foreach($machine in $machineFilterArray)
        {
            $azureVMResource = $azureVMResources | Where-Object {$_.Name -contains $machine}
            if($azureVMResource)
            {
                $filteredAzureVMResources += $azureVMResource
            }
            else
            {
                $commaSeparatedMachinesNotPresentInRG += ($(if($commaSeparatedMachinesNotPresentInRG){", "}) + $machine)
            }

            if($commaSeparatedMachinesNotPresentInRG -ne $null)
            {
                Write-TaskSpecificTelemetry "FILTERING_MachinesNotPresentInRG"
                throw (Get-LocalizedString -Key "The following machines either do not exist in the resource group or their names have not been specified correctly: {0}. Provide the exact same machine names present in the resource group. Use comma to separate multiple machine names." -ArgumentList $commaSeparatedMachinesNotPresentInRG)
            }
        }

        return $filteredAzureVMResources
    }
}

function Get-FilteredAzureVMsInResourceGroup
{
    param([object]$azureVMResources,
          [string]$resourceFilteringMethod,
          [string]$filter)

    if($azureVMResources -and -not [string]::IsNullOrEmpty($resourceFilteringMethod))
    {
        if($resourceFilteringMethod -eq "tags" -or [string]::IsNullOrEmpty($filter))
        {
            $filteredAzureVMResources = Get-TagBasedFilteredAzureVMs -azureVMResources $azureVMResources -filter $filter
        }
        else
        {
            $filteredAzureVMResources = Get-MachineBasedFilteredAzureVMs -azureVMResources $azureVMResources -filter $filter
        }

        return $filteredAzureVMResources
    }
}

function Get-FilteredAzureClassicVMsInResourceGroup
{
    param([object]$azureClassicVMResources,
          [string]$resourceFilteringMethod,
          [string]$filter)

    if($azureClassicVMResources -and -not [string]::IsNullOrEmpty($resourceFilteringMethod))
    {
        Write-Verbose -Verbose "Filtering azureClassicVM resources with filtering option:'$resourceFilteringMethod' and filters:'$filter'"
        $filteredAzureClassicVMResources = Get-FilteredAzureVMsInResourceGroup -azureVMResources $azureClassicVMResources -resourceFilteringMethod $resourceFilteringMethod -filter $filter

        return $filteredAzureClassicVMResources
    }
}

function Get-FilteredAzureRMVMsInResourceGroup
{
    param([object]$azureRMVMResources,
          [string]$resourceFilteringMethod,
          [string]$filter)

    if($azureRMVMResources -and -not [string]::IsNullOrEmpty($resourceFilteringMethod))
    {
        Write-Verbose -Verbose "Filtering azureRMVM resources with filtering option:$resourceFilteringMethod and filters:$filter"
        $filteredAzureRMVMResources = Get-FilteredAzureVMsInResourceGroup -azureVMResources $azureRMVMResources -resourceFilteringMethod $resourceFilteringMethod -filter $filter

        return $filteredAzureRMVMResources
    }
}

function Get-MachineNameFromId
{
    param([string]$resourceGroupName,
          [System.Collections.Hashtable]$map,
          [string]$mapParameter,
          [Object]$azureRMVMResources,
          [boolean]$throwOnTotalUnavaialbility)

    if($map)
    {
        $errorCount = 0
        foreach($vm in $azureRMVMResources)
        {
            $value = $map[$vm.Id]
            $resourceName = $vm.Name
            if(-not [string]::IsNullOrEmpty($value))
            {
                Write-Verbose "$mapParameter value for resource $resourceName is $value" -Verbose
                $map.Remove($vm.Id)
                $map[$resourceName] = $value
            }
            else
            {
                $errorCount = $errorCount + 1
                Write-Verbose "Unable to find $mapParameter for resource $resourceName" -Verbose
            }
        }

        if($throwOnTotalUnavaialbility -eq $true)
        {
            if($errorCount -eq $azureRMVMResources.Count -and $azureRMVMResources.Count -ne 0)
            {
                throw (Get-LocalizedString -Key "Unable to get {0} for all resources in ResourceGroup : '{1}'" -ArgumentList $mapParameter, $resourceGroupName)
            }
            else
            {
                if($errorCount -gt 0 -and $errorCount -ne $azureRMVMResources.Count)
                {
                    Write-Warning (Get-LocalizedString -Key "Unable to get {0} for '{1}' resources in ResourceGroup : '{2}'" -ArgumentList $mapParameter, $errorCount, $resourceGroupName)
                }
            }
        }

        return $map
    }
}

function Get-MachinesFqdns
{
    param([string]$resourceGroupName,
          [Object]$publicIPAddressResources,
          [Object]$networkInterfaceResources,
          [Object]$azureRMVMResources,
          [System.Collections.Hashtable]$fqdnMap)

    if(-not [string]::IsNullOrEmpty($resourceGroupName)-and $publicIPAddressResources -and $networkInterfaceResources)
    {
        Write-Verbose "Trying to get FQDN for the azureRM VM resources from resource Group $resourceGroupName" -Verbose

        #Map the ipc to the fqdn
        foreach($publicIp in $publicIPAddressResources)
        {
            if(-not [string]::IsNullOrEmpty($publicIP.DnsSettings.Fqdn))
            {
                $fqdnMap[$publicIp.IpConfiguration.Id] =  $publicIP.DnsSettings.Fqdn
            }
            else
            {
                $fqdnMap[$publicIp.IpConfiguration.Id] =  $publicIP.IpAddress
            }
        }

        #Find out the NIC, and thus the VM corresponding to a given ipc
        foreach($nic in $networkInterfaceResources)
        {
            foreach($ipc in $nic.IpConfigurations)
            {
                $fqdn =  $fqdnMap[$ipc.Id]
                if(-not [string]::IsNullOrEmpty($fqdn))
                {
                    $fqdnMap.Remove($ipc.Id)
                    if($nic.VirtualMachine)
                    {
                        $fqdnMap[$nic.VirtualMachine.Id] = $fqdn
                    }
                }
            }
        }

        $fqdnMap = Get-MachineNameFromId -resourceGroupName $resourceGroupName -Map $fqdnMap -MapParameter "FQDN" -azureRMVMResources $azureRMVMResources -ThrowOnTotalUnavaialbility $true
    }

    Write-Verbose "Got FQDN for the azureRM VM resources from resource Group $resourceGroupName" -Verbose
    return $fqdnMap
}

function Get-MachinesFqdnsForLB
{
    param([string]$resourceGroupName,
          [Object]$publicIPAddressResources,
          [Object]$networkInterfaceResources,
          [Object]$frontEndIPConfigs,
          [System.Collections.Hashtable]$fqdnMap)

    if(-not [string]::IsNullOrEmpty($resourceGroupName) -and $publicIPAddressResources -and $networkInterfaceResources -and $frontEndIPConfigs)
    {
        Write-Verbose "Trying to get FQDN for the RM azureVM resources from resource group: $resourceGroupName" -Verbose

        #Map the public ip id to the fqdn
        foreach($publicIp in $publicIPAddressResources)
        {
            if(-not [string]::IsNullOrEmpty($publicIP.DnsSettings.Fqdn))
            {
                $fqdnMap[$publicIp.Id] =  $publicIP.DnsSettings.Fqdn
            }
            else
            {
                $fqdnMap[$publicIp.Id] =  $publicIP.IpAddress
            }
        }

        #Get the NAT rule for a given ip id
        foreach($config in $frontEndIPConfigs)
        {
            $fqdn = $fqdnMap[$config.PublicIpAddress.Id]
            if(-not [string]::IsNullOrEmpty($fqdn))
            {
                $fqdnMap.Remove($config.PublicIpAddress.Id)
                foreach($rule in $config.InboundNatRules)
                {
                    $fqdnMap[$rule.Id] =  $fqdn
                }
            }
        }

        #Find out the NIC, and thus the corresponding machine to which the NAT rule belongs
        foreach($nic in $networkInterfaceResources)
        {
            foreach($ipc in $nic.IpConfigurations)
            {
                foreach($rule in $ipc.LoadBalancerInboundNatRules)
                {
                    $fqdn = $fqdnMap[$rule.Id]
                    if(-not [string]::IsNullOrEmpty($fqdn))
                    {
                        $fqdnMap.Remove($rule.Id)
                        if($nic.VirtualMachine)
                        {
                            $fqdnMap[$nic.VirtualMachine.Id] = $fqdn
                        }
                    }
                }
            }
        }
    }

    Write-Verbose "Got FQDN for the RM azureVM resources from resource Group $resourceGroupName" -Verbose
    return $fqdnMap
}

function Get-FrontEndPorts
{
    param([string]$backEndPort,
          [System.Collections.Hashtable]$portList,
          [Object]$networkInterfaceResources,
          [Object]$inboundRules)

    if(-not [string]::IsNullOrEmpty($backEndPort) -and $networkInterfaceResources -and $inboundRules)
    {
        Write-Verbose "Trying to get front end ports for $backEndPort" -Verbose

        $filteredRules = $inboundRules | Where-Object {$_.BackendPort -eq $backEndPort}

        #Map front end port to back end ipc
        foreach($rule in $filteredRules)
        {
            if($rule.BackendIPConfiguration)
            {
                $portList[$rule.BackendIPConfiguration.Id] = $rule.FrontendPort
            }
        }

        #Get the nic, and the corresponding machine id for a given back end ipc
        foreach($nic in $networkInterfaceResources)
        {
            foreach($ipConfig in $nic.IpConfigurations)
            {
                $frontEndPort = $portList[$ipConfig.Id]
                if(-not [string]::IsNullOrEmpty($frontEndPort))
                {
                    $portList.Remove($ipConfig.Id)
                    if($nic.VirtualMachine)
                    {
                        $portList[$nic.VirtualMachine.Id] = $frontEndPort
                    }
                }
            }
        }
    }
    
    Write-Verbose "Got front end ports for $backEndPort" -Verbose
    return $portList
}

function Get-AzureRMVMsConnectionDetailsInResourceGroup
{
    param([string]$resourceGroupName,
          [object]$azureRMVMResources,
          [string]$enableCopyPrerequisites)

    [hashtable]$fqdnMap = @{}
    [hashtable]$winRMHttpsPortMap = @{}
    [hashtable]$azureRMVMsDetails = @{}

    if (-not [string]::IsNullOrEmpty($resourceGroupName) -and $azureRMVMResources)
    {
        $azureRGResourcesDetails = Get-AzureRMResourceGroupResourcesDetails -resourceGroupName $resourceGroupName -azureRMVMResources $azureRMVMResources

        $networkInterfaceResources = $azureRGResourcesDetails["networkInterfaceResources"]
        $publicIPAddressResources = $azureRGResourcesDetails["publicIPAddressResources"]
        $loadBalancerResources = $azureRGResourcesDetails["loadBalancerResources"]

        if($loadBalancerResources)
        {
            foreach($lbName in $loadBalancerResources.Keys)
            {
                $lbDetails = $loadBalancerResources[$lbName]
                $frontEndIPConfigs = $lbDetails["frontEndIPConfigs"]
                $inboundRules = $lbDetails["inboundRules"]

                $fqdnMap = Get-MachinesFqdnsForLB -resourceGroupName $resourceGroupName -publicIPAddressResources $publicIPAddressResources -networkInterfaceResources $networkInterfaceResources -frontEndIPConfigs $frontEndIPConfigs -fqdnMap $fqdnMap
                $winRMHttpsPortMap = Get-FrontEndPorts -BackEndPort "5986" -PortList $winRMHttpsPortMap -networkInterfaceResources $networkInterfaceResources -inboundRules $inboundRules
            }

            $fqdnMap = Get-MachineNameFromId -resourceGroupName $resourceGroupName -Map $fqdnMap -MapParameter "FQDN" -azureRMVMResources $azureRMVMResources -ThrowOnTotalUnavaialbility $true
            $winRMHttpsPortMap = Get-MachineNameFromId -Map $winRMHttpsPortMap -MapParameter "Front End port" -azureRMVMResources $azureRMVMResources -ThrowOnTotalUnavaialbility $false
        }
        else
        {
            $fqdnMap = Get-MachinesFqdns -resourceGroupName $resourceGroupName -publicIPAddressResources $publicIPAddressResources -networkInterfaceResources $networkInterfaceResources -azureRMVMResources $azureRMVMResources -fqdnMap $fqdnMap
            $winRMHttpsPortMap = New-Object 'System.Collections.Generic.Dictionary[string, string]'
        }

        foreach ($resource in $azureRMVMResources)
        {
            $resourceName = $resource.Name
            $resourceFQDN = $fqdnMap[$resourceName]
            $resourceWinRMHttpsPort = $winRMHttpsPortMap[$resourceName]
            if([string]::IsNullOrWhiteSpace($resourceWinRMHttpsPort))
            {
                Write-Verbose -Verbose "Defaulting WinRmHttpsPort of $resourceName to 5986"
                $resourceWinRMHttpsPort = "5986"
            }

            $resourceProperties = @{}
            $resourceProperties.Name = $resourceName
            $resourceProperties.fqdn = $resourceFQDN
            $resourceProperties.winRMHttpsPort = $resourceWinRMHttpsPort

            $azureRMVMsDetails.Add($resourceName, $resourceProperties)

            if ($enableCopyPrerequisites -eq "true")
            {
                Write-Verbose "Enabling winrm for virtual machine $resourceName" -Verbose
                Add-AzureVMCustomScriptExtension -resourceGroupName $resourceGroupName -vmName $resourceName -dnsName $resourceFQDN -location $resource.Location
            }
        }

        return $azureRMVMsDetails
    }
}

function Check-AzureCloudServiceExists
{
    param([string]$cloudServiceName,
          [string]$connectionType)

    if(-not [string]::IsNullOrEmpty($cloudServiceName) -and -not [string]::IsNullOrEmpty($connectionType))
    {
        try
        {
            $azureCloudService = Get-AzureCloudService -cloudServiceName $cloudServiceName
        }
        catch [Hyak.Common.CloudException]
        {
            $exceptionMessage = $_.Exception.Message.ToString()
            Write-Verbose "ExceptionMessage: $exceptionMessage" -Verbose

            # throwing only in case of Certificate authentication, Since userNamePassword authentication works with ARM resources also
            if($connectionType -eq 'Certificate')
            {
                Write-TaskSpecificTelemetry "PREREQ_ResourceGroupNotFound"
                throw (Get-LocalizedString -Key "Provided resource group '{0}' does not exist." -ArgumentList $cloudServiceName)
            }
        }
    }
}

function Get-AzureVMResourcesProperties
{
    param([string]$resourceGroupName,
          [string]$connectionType,
          [string]$resourceFilteringMethod,
          [string]$machineNames,
          [string]$enableCopyPrerequisites)

    $machineNames = $machineNames.Trim()
    if(-not [string]::IsNullOrEmpty($resourceGroupName) -and -not [string]::IsNullOrEmpty($connectionType))
    {
        if($connectionType -eq 'Certificate' -or $connectionType -eq 'UserNamePassword')
        {
            Check-AzureCloudServiceExists -cloudServiceName $resourceGroupName -connectionType $connectionType

            $azureClassicVMResources = Get-AzureClassicVMsInResourceGroup -resourceGroupName $resourceGroupName
            $filteredAzureClassicVMResources = Get-FilteredAzureClassicVMsInResourceGroup -azureClassicVMResources $azureClassicVMResources -resourceFilteringMethod $resourceFilteringMethod -filter $machineNames
            $azureVMsDetails = Get-AzureClassicVMsConnectionDetailsInResourceGroup -resourceGroupName $resourceGroupName -azureClassicVMResources $filteredAzureClassicVMResources

            # since authentication is userNamePassword, we will check whether resource group has RM resources
            if($connectionType -eq 'UserNamePassword' -and $azureVMsDetails.Count -eq 0)
            {
                Write-Verbose "Trying to find RM resources since there are no classic resources in resource group: $resourceGroupName" -Verbose

                $azureRMVMResources = Get-AzureRMVMsInResourceGroup -resourceGroupName  $resourceGroupName
                $filteredAzureRMVMResources = Get-FilteredAzureRMVMsInResourceGroup -azureRMVMResources $azureRMVMResources -resourceFilteringMethod $resourceFilteringMethod -filter $machineNames
                $azureVMsDetails = Get-AzureRMVMsConnectionDetailsInResourceGroup -resourceGroupName $resourceGroupName -azureRMVMResources $filteredAzureRMVMResources -enableCopyPrerequisites $enableCopyPrerequisites
            }
        }
        else
        {
            $azureRMVMResources = Get-AzureRMVMsInResourceGroup -resourceGroupName  $resourceGroupName
            $filteredAzureRMVMResources = Get-FilteredAzureRMVMsInResourceGroup -azureRMVMResources $azureRMVMResources -resourceFilteringMethod $resourceFilteringMethod -filter $machineNames
            $azureVMsDetails = Get-AzureRMVMsConnectionDetailsInResourceGroup -resourceGroupName $resourceGroupName -azureRMVMResources $filteredAzureRMVMResources -enableCopyPrerequisites $enableCopyPrerequisites
        }

        # throw if no azure VMs found in resource group or due to filtering
        if($azureVMsDetails.Count -eq 0)
        {
            if([string]::IsNullOrEmpty($machineNames) -or ($azureClassicVMResources.Count -eq 0 -and $azureRMVMResources.Count -eq 0))
            {
                if($connectionType -eq 'Certificate')
                {
                    Write-TaskSpecificTelemetry "PREREQ_NoClassicVMResources"
                    throw (Get-LocalizedString -Key "No machine exists under resource group: '{0}' for copy. Selected Connection '{1}' supports Virtual Machines of Azure Classic type only." -ArgumentList $resourceGroupName, $connectionType)
                }
                elseif($connectionType -eq 'ServicePrincipal')
                {
                    Write-TaskSpecificTelemetry "PREREQ_NoRMVMResources"
                    throw (Get-LocalizedString -Key "No machine exists under resource group: '{0}' for copy. Selected Connection '{1}' supports Virtual Machines of Azure Resource Manager type only." -ArgumentList $resourceGroupName, $connectionType)
                }
                else
                {
                     Write-TaskSpecificTelemetry "PREREQ_NoVMResources"
                     throw (Get-LocalizedString -Key "No machine exists under resource group: '{0}' for copy." -ArgumentList $resourceGroupName)
                }
            }
            else
            {
                Write-TaskSpecificTelemetry "FILTERING_NoVMResources"
                throw (Get-LocalizedString -Key "No machine exists under resource group: '{0}' with the following {1} '{2}'." -ArgumentList $resourceGroupName, $resourceFilteringMethod, $machineNames)
            }
        }

        return $azureVMsDetails
    }
}

function Get-SkipCACheckOption
{
    param([string]$skipCACheck)

    $doSkipCACheckOption = '-SkipCACheck'
    $doNotSkipCACheckOption = ''

    if(-not [string]::IsNullOrEmpty($skipCACheck))
    {
        if ($skipCACheck -eq "false")
        {
            Write-Verbose "Not skipping CA Check" -Verbose
            return $doNotSkipCACheckOption
        }

        Write-Verbose "Skipping CA Check" -Verbose
        return $doSkipCACheckOption
    }
}

function Get-AzureVMsCredentials
{
    param([string][Parameter(Mandatory=$true)]$vmsAdminUserName,
          [string][Parameter(Mandatory=$true)]$vmsAdminPassword)

    Write-Verbose "Azure VMs Admin Username: $vmsAdminUserName" -Verbose
    $azureVmsCredentials = New-Object 'System.Net.NetworkCredential' -ArgumentList $vmsAdminUserName, $vmsAdminPassword

    return $azureVmsCredentials
}

function Copy-FilesSequentiallyToAzureVMs
{
    param([string][Parameter(Mandatory=$true)]$storageAccountName,
          [string][Parameter(Mandatory=$true)]$containerName,
          [string][Parameter(Mandatory=$true)]$containerSasToken,
          [string][Parameter(Mandatory=$true)]$targetPath,
          [string][Parameter(Mandatory=$true)]$azCopyLocation,
          [string][Parameter(Mandatory=$true)]$resourceGroupName,
          [object][Parameter(Mandatory=$true)]$azureVMResourcesProperties,
          [object][Parameter(Mandatory=$true)]$azureVMsCredentials,
          [string][Parameter(Mandatory=$true)]$cleanTargetBeforeCopy,
          [string]$communicationProtocol,
          [string][Parameter(Mandatory=$true)]$skipCACheckOption,
          [string][Parameter(Mandatory=$true)]$enableDetailedLoggingString,
          [string]$additionalArguments)

    foreach ($resource in $azureVMResourcesProperties.Keys)
    {
        $resourceProperties = $azureVMResourcesProperties[$resource]
        $resourceFQDN = $resourceProperties.fqdn
        $resourceName = $resourceProperties.Name
        $resourceWinRMHttpsPort = $resourceProperties.winRMHttpsPort

        Write-Output (Get-LocalizedString -Key "Copy started for machine: '{0}'" -ArgumentList $resourceName)

        $copyResponse = Invoke-Command -ScriptBlock $AzureFileCopyJob -ArgumentList `
                            $resourceFQDN, $storageAccount, $containerName, $containerSasToken, $azCopyLocation, $targetPath, $azureVMsCredentials, `
                            $cleanTargetBeforeCopy, $resourceWinRMHttpsPort, $communicationProtocal, $skipCACheckOption, $enableDetailedLoggingString, $additionalArguments

        $status = $copyResponse.Status

        Write-ResponseLogs -operationName 'AzureFileCopy' -fqdn $resourceName -deploymentResponse $copyResponse
        Write-Output (Get-LocalizedString -Key "Copy status for machine '{0}' : '{1}'" -ArgumentList $resourceName, $status)

        if ($status -ne "Passed")
        {
            $winrmHelpMsg = Get-LocalizedString -Key "To fix WinRM connection related issues, select the 'Enable Copy Prerequisites' task parameter."
            $copyErrorMessage =  $copyResponse.Error.Message + $winrmHelpMsg
            Write-Verbose "CopyErrorMessage: $copyErrorMessage" -Verbose

            Write-TaskSpecificTelemetry "UNKNOWNDEP_Error"
            ThrowError -errorMessage $copyErrorMessage
        }
    }
}

function Copy-FilesParallelyToAzureVMs
{
    param([string][Parameter(Mandatory=$true)]$storageAccountName,
          [string][Parameter(Mandatory=$true)]$containerName,
          [string][Parameter(Mandatory=$true)]$containerSasToken,
          [string][Parameter(Mandatory=$true)]$targetPath,
          [string][Parameter(Mandatory=$true)]$azCopyLocation,
          [string][Parameter(Mandatory=$true)]$resourceGroupName,
          [object][Parameter(Mandatory=$true)]$azureVMResourcesProperties,
          [object][Parameter(Mandatory=$true)]$azureVMsCredentials,
          [string][Parameter(Mandatory=$true)]$cleanTargetBeforeCopy,
          [string]$communicationProtocol,
          [string][Parameter(Mandatory=$true)]$skipCACheckOption,
          [string][Parameter(Mandatory=$true)]$enableDetailedLoggingString,
          [string]$additionalArguments)

    [hashtable]$Jobs = @{}
    foreach ($resource in $azureVMResourcesProperties.Keys)
    {
        $resourceProperties = $azureVMResourcesProperties[$resource]
        $resourceFQDN = $resourceProperties.fqdn
        $resourceName = $resourceProperties.Name
        $resourceWinRMHttpsPort = $resourceProperties.winRMHttpsPort

        Write-Output (Get-LocalizedString -Key "Copy started for machine: '{0}'" -ArgumentList $resourceName)

        $job = Start-Job -ScriptBlock $AzureFileCopyJob -ArgumentList `
                   $resourceFQDN, $storageAccount, $containerName, $containerSasToken, $azCopyLocation, $targetPath, $azureVmsCredentials, `
                   $cleanTargetBeforeCopy, $resourceWinRMHttpsPort, $communicationProtocal, $skipCACheckOption, $enableDetailedLoggingString, $additionalArguments

        $Jobs.Add($job.Id, $resourceProperties)
    }

    While (Get-Job)
    {
        Start-Sleep 10
        foreach ($job in Get-Job)
        {
            if ($job.State -ne "Running")
            {
                $output = Receive-Job -Id $job.Id
                Remove-Job $Job

                $status = $output.Status
                $resourceName = $Jobs.Item($job.Id).Name

                Write-ResponseLogs -operationName 'AzureFileCopy' -fqdn $resourceName -deploymentResponse $output
                Write-Output (Get-LocalizedString -Key "Copy status for machine '{0}' : '{1}'" -ArgumentList $resourceName, $status)

                if ($status -ne "Passed")
                {
                    $parallelOperationStatus = "Failed"
                    $errorMessage = ""
                    if($output.Error -ne $null)
                    {
                        $winrmHelpMsg = Get-LocalizedString -Key "To fix WinRM connection related issues, select the 'Enable Copy Prerequisites' task parameter."
                        $errorMessage = $output.Error.Message + $winrmHelpMsg            
                    }

                    Write-Output (Get-LocalizedString -Key "Copy failed on machine '{0}' with following message : '{1}'" -ArgumentList $resourceName, $errorMessage)
                }
            }
        }
    }

    # While copying paralelly, if copy failed on one or more azure VMs then throw
    if ($parallelOperationStatus -eq "Failed")
    {
        $errorMessage = (Get-LocalizedString -Key 'Copy to one or more machines failed.')
        Write-TaskSpecificTelemetry "UNKNOWNDEP_Error"
        ThrowError -errorMessage $errorMessage
    }
}

function Copy-FilesToAzureVMsFromStorageContainer
{
    param([string][Parameter(Mandatory=$true)]$storageAccountName,
          [string][Parameter(Mandatory=$true)]$containerName,
          [string][Parameter(Mandatory=$true)]$containerSasToken,
          [string][Parameter(Mandatory=$true)]$targetPath,
          [string][Parameter(Mandatory=$true)]$azCopyLocation,
          [string][Parameter(Mandatory=$true)]$resourceGroupName,
          [object][Parameter(Mandatory=$true)]$azureVMResourcesProperties,
          [object][Parameter(Mandatory=$true)]$azureVMsCredentials,
          [string][Parameter(Mandatory=$true)]$cleanTargetBeforeCopy,
          [string]$communicationProtocol,
          [string][Parameter(Mandatory=$true)]$skipCACheckOption,
          [string][Parameter(Mandatory=$true)]$enableDetailedLoggingString,
          [string]$additionalArguments,
          [string][Parameter(Mandatory=$true)]$copyFilesInParallel)

    # copies files sequentially
    if ($copyFilesInParallel -eq "false" -or ( $azureVMResourcesProperties.Count -eq 1 ))
    {

        Copy-FilesSequentiallyToAzureVMs `
                -storageAccountName $storageAccount -containerName $containerName -containerSasToken $containerSasToken -targetPath $targetPath -azCopyLocation $azCopyLocation `
                -resourceGroupName $environmentName -azureVMResourcesProperties $azureVMResourcesProperties -azureVMsCredentials $azureVMsCredentials `
                -cleanTargetBeforeCopy $cleanTargetBeforeCopy -communicationProtocol $useHttpsProtocolOption -skipCACheckOption $skipCACheckOption `
                -enableDetailedLoggingString $enableDetailedLoggingString -additionalArguments $additionalArguments
    }
    # copies files parallely
    else
    {
        Copy-FilesParallelyToAzureVMs `
                -storageAccountName $storageAccount -containerName $containerName -containerSasToken $containerSasToken -targetPath $targetPath -azCopyLocation $azCopyLocation `
                -resourceGroupName $environmentName -azureVMResourcesProperties $azureVMResourcesProperties -azureVMsCredentials $azureVMsCredentials `
                -cleanTargetBeforeCopy $cleanTargetBeforeCopy -communicationProtocol $useHttpsProtocolOption -skipCACheckOption $skipCACheckOption `
                -enableDetailedLoggingString $enableDetailedLoggingString -additionalArguments $additionalArguments
    }

    # if no error thrown, copy succesfully succeeded
    Write-Output (Get-LocalizedString -Key "Copied files from source path: '{0}' to target azure vms in resource group: '{1}' successfully" -ArgumentList $sourcePath, $environmentName)
}

function Validate-CustomScriptExecutionStatus
{
    param([string]$resourceGroupName,
          [string]$vmName,
          [string]$extensionName)
		  
    Write-Verbose -Verbose "Validating the winrm configuration custom script extension status"

    $isScriptExecutionPassed = $true
    try
    {
        $status = Get-AzureMachineStatus -resourceGroupName $resourceGroupName -Name $vmName

        $customScriptExtension = $status.Extensions | Where-Object { $_.ExtensionType -eq "Microsoft.Compute.CustomScriptExtension" -and $_.Name -eq $extensionName }

        if($customScriptExtension)
        {
            $subStatuses = $customScriptExtension.SubStatuses
            $subStatusesStr = $subStatuses | Out-String

            Write-Verbose -Verbose "Custom script extension execution statuses: $subStatusesStr"

            if($subStatuses)
            {
                foreach($subStatus in $subStatuses)
                {
                    if($subStatus.Code.Contains("ComponentStatus/StdErr") -and (-not [string]::IsNullOrEmpty($subStatus.Message)))
                    {
                        $isScriptExecutionPassed = $false
                        $errMessage = $subStatus.Message
                        break
                    }
                }
            }
            else
            {
                $isScriptExecutionPassed = $false
                $errMessage = "No execution status exists for the custom script extension '$extensionName'"
            }
        }
        else
        {
            $isScriptExecutionPassed = $false
            $errMessage = "No custom script extension '$extensionName' exists"     
        }
    }
    catch
    {
        $isScriptExecutionPassed = $false
        $errMessage = $_.Exception.Message  
    }

    if(-not $isScriptExecutionPassed)
    {
        $response = Remove-AzureMachineCustomScriptExtension -resourceGroupName $resourceGroupName -vmName $vmName -name $extensionName
        throw (Get-LocalizedString -Key "Setting the custom script extension '{0}' for virtual machine '{1}' failed with error : {2}" -ArgumentList $extensionName, $vmName, $errMessage)
    }

    Write-Verbose -Verbose "Validated the script execution successfully"
}

function Is-WinRMCustomScriptExtensionExists
{
    param([string]$resourceGroupName,
    [string]$vmName,
    [string]$extensionName)
	 
    $isExtensionExists = $true
    $removeExtension = $false
	
    try
    {
        $customScriptExtension = Get-AzureMachineCustomScriptExtension -resourceGroupName $resourceGroupName -vmName $vmName -name $extensionName

        if($customScriptExtension)
        {
            if($customScriptExtension.ProvisioningState -ne "Succeeded")
            {	
                $removeExtension = $true  
            }
            else
            {
                try
                {
                    Validate-CustomScriptExecutionStatus -resourceGroupName $resourceGroupName -vmName $vmName -extensionName $extensionName
                }
                catch
                {
                    $isExtensionExists = $false
                }				
            }
        }
        else
        {
            $isExtensionExists = $false
        }
    }
    catch
    {
        $isExtensionExists = $false	
    }		
    
    if($removeExtension)
    {
        $response = Remove-AzureMachineCustomScriptExtension -resourceGroupName $resourceGroupName -vmName $vmName -name $extensionName
        $isExtensionExists = $false
    }

    $isExtensionExists
}

function Add-AzureVMCustomScriptExtension
{
    param([string]$resourceGroupName,
          [string]$vmName,          
          [string]$dnsName,
          [string]$location)

    $configWinRMScriptFile="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/201-vm-winrm-windows/ConfigureWinRM.ps1"
    $makeCertFile="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/201-vm-winrm-windows/makecert.exe"
    $winrmConfFile="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/201-vm-winrm-windows/winrmconf.cmd"
    $scriptToRun="ConfigureWinRM.ps1"
    $extensionName="WinRMCustomScriptExtension"

    Write-Verbose -Verbose "Adding custom script extension '$extensionName' for virtual machine '$vmName'"
    Write-Verbose -Verbose "VM Location : $location"
    Write-Verbose -Verbose "VM DNS : $dnsName"

    try
    {
        $isExtensionExists = Is-WinRMCustomScriptExtensionExists -resourceGroupName $resourceGroupName -vmName $vmName -extensionName $extensionName
        Write-Verbose -Verbose "IsExtensionExists: $isExtensionExists"

        if($isExtensionExists)
        {
            Write-Verbose -Verbose "Skipping the addition of custom script extension '$extensionName' as it already exists"
            return
        }

        $result = Set-AzureMachineCustomScriptExtension -resourceGroupName $resourceGroupName -vmName $vmName -name $extensionName -fileUri $configWinRMScriptFile, $makeCertFile, $winrmConfFile  -run $scriptToRun -argument $dnsName -location $location

        if($result.Status -ne "Succeeded")
        {
            Write-TaskSpecificTelemetry "ENABLEWINRM_ProvisionVmCustomScriptFailed"			

            $response = Remove-AzureMachineCustomScriptExtension -resourceGroupName $resourceGroupName -vmName $vmName -name $extensionName
            throw (Get-LocalizedString -Key "Unable to set the custom script extension '{0}' for virtual machine '{1}': {2}" -ArgumentList $extensionName, $vmName, $result.Error.Message)
        }

        Validate-CustomScriptExecutionStatus -resourceGroupName $resourceGroupName -vmName $vmName -extensionName $extensionName
    }
    catch
    {
         Write-TaskSpecificTelemetry "ENABLEWINRM_ExecutionOfVmCustomScriptFailed"    
        throw (Get-LocalizedString -Key "Failed to enable copy prerequisites. {0}" -ArgumentList $_.exception.message)
    }

    Write-Verbose -Verbose "Successfully added the custom script extension '$extensionName' for virtual machine '$vmName'"
}