#Requires -Version 7
<#
.SYNOPSIS
    Example PowerShell executable. Template for new bin/ scripts.
.DESCRIPTION
    Greets someone. Demonstrates repo conventions: strict mode, CmdletBinding,
    approved verbs for functions, parameter validation.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Name = 'World',

    [Parameter()]
    [switch]$Shout
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Greeting {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter()]
        [bool]$Uppercase = $false
    )

    $greeting = "Hello, $Target!"
    if ($Uppercase) {
        $greeting = $greeting.ToUpperInvariant()
    }
    return $greeting
}

Write-Information (Get-Greeting -Target $Name -Uppercase $Shout.IsPresent) -InformationAction Continue
