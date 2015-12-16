[CmdletBinding()]
param([switch]$OmitDotSource)

Trace-VstsEnteringInvocation $MyInvocation
try {
    [string]$MSBuildLocationMethod = Get-VstsInput -Name 'MSBuildLocationMethod'
    [string]$MSBuildLocation = Get-VstsInput -Name 'MSBuildLocation'
    [string]$MSBuildArguments = Get-VstsInput -Name 'MSBuildArguments'
    [string]$Solution = Get-VstsInput -Name 'Solution' -Require
    [string]$Platform = Get-VstsInput -Name 'Platform'
    [string]$Configuration = Get-VstsInput -Name 'Configuration'
    [bool]$Clean = Get-VstsInput -Name 'Clean' -AsBool
    [bool]$RestoreNuGetPackages = Get-VstsInput -Name 'RestoreNuGetPackages' -AsBool
    [bool]$LogProjectEvents = Get-VstsInput -Name 'LogProjectEvents' -AsBool
    [string]$MSBuildVersion = Get-VstsInput -Name 'MSBuildVersion'
    [bool]$RequireMSBuildVersion = Get-VstsInput -Name 'RequireMSBuildVersion' -AsBool
    [string]$MSBuildArchitecture = Get-VstsInput -Name 'MSBuildArchitecture'
    if (!$OmitDotSource) {
        . $PSScriptRoot\Helpers_PSExe.ps1
    }

    $solutionFiles = Get-SolutionFiles -Solution $Solution
    $MSBuildArguments = Format-MSBuildArguments -MSBuildArguments $MSBuildArguments -Platform $Platform -Configuration $Configuration
    $MSBuildLocation = Select-MSBuildLocation -Method $MSBuildLocationMethod -Location $MSBuildLocation -Version $MSBuildVersion -RequireVersion:$RequireMSBuildVersion -Architecture $MSBuildArchitecture
    Invoke-BuildTools -NuGetRestore:$RestoreNuGetPackages -SolutionFiles $solutionFiles -MSBuildLocation $MSBuildLocation -MSBuildArguments $MSBuildArguments -Clean:$Clean -NoTimelineLogger:(!$LogProjectEvents)
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}