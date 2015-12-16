function Format-MSBuildArguments {
    [CmdletBinding()]
    param(
        [string]$MSBuildArguments,
        [string]$Platform,
        [string]$Configuration,
        [string]$VSVersion)

    Trace-VstsEnteringInvocation $MyInvocation
    if ($Platform) {
        Write-Verbose "Adding platform: $Platform"
        $MSBuildArguments = "$MSBuildArguments /p:platform=`"$Platform`""
    }

    if ($Configuration) {
        Write-Verbose "Adding configuration: $Configuration"
        $MSBuildArguments = "$MSBuildArguments /p:configuration=`"$Configuration`""
    }

    if ($VSVersion) {
        Write-Verbose ('Adding VisualStudioVersion: {0}' -f $VSVersion)
        $MSBuildArguments = "$MSBuildArguments /p:VisualStudioVersion=`"$VSVersion`""
    }

    Write-Verbose "MSBuildArguments = $MSBuildArguments"
    $MSBuildArguments
    Trace-VstsLeavingInvocation $MyInvocation
}

function Get-SolutionFiles {
    [CmdletBinding()]
    param([string]$Solution)

    Trace-VstsEnteringInvocation $MyInvocation
    if ($Solution.Contains("*") -or $Solution.Contains("?")) {
        $solutionFiles = Find-VstsFiles -LegacyPattern $Solution
        if (!$solutionFiles.Count) {
            throw (Get-LocString -Key "SolutionNotFoundUsingSearchPattern0" -ArgumentList $Solution)
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
        [switch]$NoTimelineLogger)

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

            $slnFolder = [System.IO.Path]::GetDirectoryName($file)
            Invoke-VstsTool -FileName $nugetPath -Arguments "restore `"$file`" -NonInteractive" -WorkingDirectory $slnFolder
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
    param([string]$VSVersion, [string]$Architecture)

    Trace-VstsEnteringInvocation $MyInvocation

    # Determine which MSBuild version to use.
    $msBuildVersion = $null;
    switch ("$VSVersion") {
        '' { break }
        '14.0' { $msBuildVersion = '14.0' ; break }
        '12.0' { $msBuildVersion = '12.0' ; break }
        '11.0' { $msBuildVersion = '4.0' ; break }
        '10.0' { $msBuildVersion = '4.0' ; break }
        default { throw (Get-LocString -Key "UnexpectedVisualStudioVersion0" -ArgumentList $VSVersion) }
    }

    # Find the MSBuild location.
    if (!($msBuildLocation = Get-VstsMSBuildPath -Version $msBuildVersion -Architecture $Architecture)) {
        throw (Get-LocalizedString -Key 'MSBuildNotFoundVersion0Architecture1' -ArgumentList $msBuildVersion, $Architecture)
    }

    $msBuildLocation
    Trace-VstsLeavingInvocation $MyInvocation
}

function Select-VSVersion {
    [CmdletBinding()]
    param([string]$PreferredVersion)

    Trace-VstsEnteringInvocation $MyInvocation
    try {
        # Look for a specific version of Visual Studio.
        if ($PreferredVersion -and $PreferredVersion -ne 'latest') {
            if ($location = Get-VstsVisualStudioPath -Version $PreferredVersion) {
                return $PreferredVersion
            }

            Write-Warning (Get-LocalizedString -Key 'VisualStudioNotFoundVersion0LookingForLatest' -ArgumentList $PreferredVersion)
        }

        # Look for the latest version of Visual Studio.
        [string[]]$knownVersions = '14.0', '12.0', '11.0', '10.0' |
            Where-Object { $_ -ne $PreferredVersion }
        foreach ($version in $knownVersions) {
            if ($location = Get-VstsVisualStudioPath -Version $version) {
                return $version
            }
        }

        Write-Warning (Get-LocalizedString -Key 'VisualStudioNotFoundTry')
    } finally {
        Trace-VstsLeavingInvocation $MyInvocation
    }
}
