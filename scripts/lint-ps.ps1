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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoSettings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

# PSScriptAnalyzer's -Settings REPLACES the configuration rather than merging
# it, so a project that only adds a rule would otherwise silently lose the
# repo's ExcludeRules and formatting policy. Merge the two explicitly.
function Merge-AnalyzerSettings {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,

        [Parameter(Mandatory = $true)]
        [hashtable]$Override
    )

    $merged = @{}
    foreach ($key in $Base.Keys) {
        $merged[$key] = $Base[$key]
    }
    foreach ($key in $Override.Keys) {
        $baseValue = $merged[$key]
        $overrideValue = $Override[$key]
        if ($baseValue -is [hashtable] -and $overrideValue -is [hashtable]) {
            $merged[$key] = Merge-AnalyzerSettings -Base $baseValue -Override $overrideValue
        } elseif ($key -eq 'ExcludeRules' -and $baseValue -and $overrideValue) {
            # Exclusions accumulate: a project may add suppressions but cannot
            # quietly re-enable a rule the repo has deliberately disabled.
            $merged[$key] = @($baseValue) + @($overrideValue) | Select-Object -Unique
        } else {
            $merged[$key] = $overrideValue
        }
    }
    $merged
}

# Walk up from the linted file to the repo root and pick the nearest
# project-local settings file, so a project can scope its own rules
# (e.g. PSUseCompatibleSyntax targeting PS 5.1) without editing repo policy.
function Get-AnalyzerSettingsPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $dir = Split-Path -Path $FilePath -Parent
    while ($dir) {
        $candidate = Join-Path $dir 'PSScriptAnalyzerSettings.psd1'
        if ($candidate -ne $repoSettings -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        if ($dir -eq $repoRoot) {
            break
        }
        $dir = Split-Path -Path $dir -Parent
    }
    $repoSettings
}

# Each distinct settings file is resolved once, then reused for its files.
$script:settingsCache = @{}
$script:settingsCache[[string]$repoSettings] = Import-PowerShellDataFile -LiteralPath $repoSettings

function Get-AnalyzerSettings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingsPath
    )

    if (-not $script:settingsCache.ContainsKey($SettingsPath)) {
        $script:settingsCache[$SettingsPath] = Merge-AnalyzerSettings `
            -Base $script:settingsCache[[string]$repoSettings] `
            -Override (Import-PowerShellDataFile -LiteralPath $SettingsPath)
    }
    $script:settingsCache[$SettingsPath]
}

if (-not $Path -or $Path.Count -eq 0) {
    $targets = @(
        Get-ChildItem -Path $repoRoot -Recurse -Include *.ps1, *.psm1, *.psd1 |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
            ForEach-Object { $_.FullName }
    )
} else {
    $targets = @($Path | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
}

$findings = foreach ($t in $targets) {
    $settingsPath = Get-AnalyzerSettingsPath -FilePath $t
    Invoke-ScriptAnalyzer -Path $t -Settings (Get-AnalyzerSettings -SettingsPath $settingsPath)
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
