[cmdletbinding()]
param()

# Arrange.
. $PSScriptRoot\..\..\lib\Initialize-Test.ps1
. $PSScriptRoot\..\..\..\Tasks\MSBuild\Helpers.ps1
Register-Mock Write-Warning
Register-Mock Get-MSBuildLocation { 'Some latest location' } -- -Version '' -Architecture 'Some architecture'

# Act/Assert.
Assert-Throws {
        Select-MSBuildLocation -Method 'Version' -Location '' -Version 'Some unknown version' -RequireVersion -Architecture 'Some architecture'
    } -MessagePattern '*MSBuild not found: Version = Some unknown version, Architecture = Some architecture*'
