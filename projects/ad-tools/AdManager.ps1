#Requires -Version 7
<#
.SYNOPSIS
    Interactive manager for Active Directory OUs, users, and groups.
.DESCRIPTION
    Placeholder entry point for the AD Tools project. The concrete behaviour
    is defined by the brief in this folder's README.md, currently being
    drafted in SCRATCH.md. Do not build UI or AD logic here until that brief
    is frozen.

    Open decisions that shape this file:
      - Windows PowerShell 5.1 vs PowerShell 7 on the client. Both the AD
        module compatibility layer and the WPF apartment state depend on it,
        so the #Requires line above may change.
      - UI stack: WPF plus a Fluent theme driven from PowerShell, versus a
        WinUI 3 / C# front end.
.NOTES
    Intended to run on a Windows client that has the Active Directory (RSAT)
    module and sufficient delegated rights. Never point it at production;
    integration testing targets the Proxmox lab domain only.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Information 'AdManager: skeleton only — implementation pending the brief.' -InformationAction Continue
