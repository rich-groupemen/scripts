#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
    Run Pester tests for the repo, bootstrapping Pester 5 if absent.
#>
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0.0')) {
    Write-Host 'Pester 5+ not found, installing to CurrentUser scope...'
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
}

# Scan the whole repo (not just the root tests/ folder) so projects such as
# ad-tools can keep their own Pester suite under projects/<name>/tests/.
$repoRoot = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
$testFiles = Get-ChildItem -Path $repoRoot -Recurse -Filter *.Tests.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
if (-not $testFiles) {
    Write-Host 'test-ps: no *.Tests.ps1 files, skipping'
    exit 0
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = $testFiles.FullName
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $configuration
