function Format-MSBuildArguments {
    [CmdletBinding()]
    param(
        [string]$MSBuildArguments,
        [string]$Platform,
        [string]$Configuration)

    Trace-VstsEnteringInvocation $MyInvocation
    if ($Platform) {
        Write-Verbose "Adding platform: $platform"
        $MSBuildArguments = "$MSBuildArguments /p:platform=`"$Platform`""
    }

    if ($Configuration) {
        Write-Verbose "Adding configuration: $Configuration"
        $MSBuildArguments = "$MSBuildArguments /p:configuration=`"$Configuration`""
    }

    $MSBuildArguments
    Trace-VstsLeavingInvocation $MyInvocation
}

function Get-SolutionFiles {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $true)]
        [string]$Solution)

    Trace-VstsEnteringInvocation $MyInvocation
    if ($Solution.Contains("*") -or $Solution.Contains("?")) {
        $solutionFiles = Find-VstsFiles -LegacyPattern $Solution
        if (!$solutionFiles.Count) {
            throw (Get-VstsLocString -Key "SolutionNotFoundUsingSearchPattern0" -ArgumentList $Solution)
        }
    } else {
        $solutionFiles = ,$Solution
    }

    $solutionFiles
    Trace-VstsLeavingInvocation $MyInvocation
}

function Invoke-BuildTools {
    [CmdletBinding()]
    param(
        [switch]$NuGetRestore,
        [string[]]$SolutionFiles,
        [string]$MSBuildLocation,
        [string]$MSBuildArguments,
        [switch]$Clean,
        [switch]$NoTimelineLogger
    )

    Trace-VstsEnteringInvocation $MyInvocation
    $nugetPath = Get-VstsAgentToolPath -Name 'NuGet.exe'
    if (-not $nugetPath -and $NuGetRestore) {
        Write-Warning (Get-VstsLocString -Key "UnableToLocateNugetExeRestoreNotPerformed" -ArgumentList 'nuget.exe')
    }

    foreach ($file in $SolutionFiles) {
        if ($nugetPath -and $NuGetRestore) {
            if ($env:NUGET_EXTENSIONS_PATH) {
                Write-Host (Get-VstsLocString -Key "DetectedNuGetExtensionsLoaderPath0" -ArgumentList $env:NUGET_EXTENSIONS_PATH)
            }

            $slnDirectory = [System.IO.Path]::GetDirectoryName($file)
            Invoke-VstsTool -FileName $nugetPath -Arguments "restore `"$file`" -NonInteractive" -WorkingDirectory $slnDirectory
        }

        if ($Clean) {
            Invoke-VstsMSBuild -ProjectFile $file -Targets Clean -LogFile "$file-clean.log" -MSBuildPath $MSBuildLocation -AdditionalArguments $MSBuildArguments -NoTimelineLogger:$NoTimelineLogger
        }

        Invoke-VstsMSBuild -ProjectFile $file -LogFile "$file.log" -MSBuildPath $MSBuildLocation -AdditionalArguments $MSBuildArguments -NoTimelineLogger:$NoTimelineLogger
    }

    Trace-VstsLeavingInvocation $MyInvocation
}

function Select-MSBuildLocation {
    [CmdletBinding()]
    param(
        [string]$Method,
        [string]$Location,
        [string]$Version,
        [switch]$RequireVersion,
        [string]$Architecture
    )

    Trace-VstsEnteringInvocation $MyInvocation

    # Default the msbuildLocationMethod if not specified. The input msbuildLocationMethod
    # was added to the definition after the input msbuildLocation.
    if ("$Method".ToUpperInvariant() -ne 'LOCATION' -and "$Method".ToUpperInvariant() -ne 'VERSION') {
        # Infer the msbuildLocationMethod based on the whether msbuildLocation is specified.
        if ($Location) {
            $Method = 'location'
        } else {
            $Method = 'version'
        }

        Write-Verbose "Defaulted MSBuild location method to: $Method"
    }

    # Default to 'version' if the user chose 'location' but didn't specify a location.
    if ("$Method".ToUpperInvariant() -eq 'LOCATION' -and !$Location) {
        Write-Verbose 'Location not specified. Using version instead.'
        $Method = 'version'
    }

    if ("$Method".ToUpperInvariant() -eq 'VERSION') {
        $Location = ''

        # Look for a specific version of MSBuild.
        if ($Version -and "$Version".ToUpperInvariant() -ne 'LATEST') {
            $Location = Get-VstsMSBuildPath -Version $Version -Architecture $Architecture

            # Warn if not found and the preferred version is not required.
            if (!$Location -and !$RequireVersion) {
                Write-Warning (Get-VstsLocString -Key 'UnableToFindMSBuildVersion0Architecture1LookingForLatestVersion.' -ArgumentList $Version, $Architecture)
            }
        }

        # Look for the latest version of MSBuild.
        if (!$Location -and ("$Version".ToUpperInvariant() -eq 'LATEST' -or !$RequireVersion)) {
            Write-Verbose 'Searching for latest MSBuild version.'
            $Location = Get-VstsMSBuildPath -Version '' -Architecture $Architecture
        }

        # Throw if not found.
        if (!$Location) {
            throw (Get-VstsLocString -Key 'MSBuildNotFoundVersion0Architecture1TryDifferent' -ArgumentList $Version, $Architecture)
        }
    }

    $Location
    Trace-VstsLeavingInvocation $MyInvocation
}
