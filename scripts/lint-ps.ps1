#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
    Lint PowerShell files with PSScriptAnalyzer using the repo settings.
.DESCRIPTION
    Used by the pre-commit psscriptanalyzer hook (which passes staged file
    names) and by `make lint-ps` (which passes paths, defaulting to the repo
    root scanned recursively). Exits non-zero on any finding at Warning level
    or above; Information-level findings are printed but non-fatal.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'

# PSScriptAnalyzer is not bundled with pwsh 7; bootstrap once per machine.
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'PSScriptAnalyzer not found, installing to CurrentUser scope...'
    Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module PSScriptAnalyzer

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

if (-not $Path -or $Path.Count -eq 0) {
    $targets = Get-ChildItem -Path $repoRoot -Recurse -Include *.ps1, *.psm1, *.psd1 |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
} else {
    $targets = $Path | ForEach-Object { Resolve-Path $_ }
}

$findings = foreach ($t in $targets) {
    Invoke-ScriptAnalyzer -Path $t -Settings $settings
}

if (-not $findings) {
    Write-Host "PSScriptAnalyzer: $($targets.Count) file(s) clean."
    exit 0
}

$findings |
    Sort-Object Severity, ScriptName, Line |
    Format-Table Severity, ScriptName, Line, RuleName, Message -AutoSize -Wrap |
    Out-String -Width 200 |
    Write-Host

$errors = @($findings | Where-Object Severity -eq 'Error').Count
$warnings = @($findings | Where-Object Severity -eq 'Warning').Count
Write-Host "PSScriptAnalyzer: $errors error(s), $warnings warning(s), $($findings.Count) finding(s) total."

if ($errors -gt 0 -or $warnings -gt 0) {
    exit 1
}
exit 0
