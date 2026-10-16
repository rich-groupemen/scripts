# Project-local PSScriptAnalyzer overrides.
#
# AD Tools targets Windows PowerShell 5.1 (scoped exception to the repo's
# PS7-only rule) because it must run on a corporate Windows 11 client that
# ships 5.1 and where RSAT's ActiveDirectory module integrates natively.
#
# scripts/lint-ps.ps1 merges this file over the repo-root settings: Rules are
# merged per rule name, ExcludeRules are unioned, scalars are replaced. So a
# project can add checks but cannot silently drop repo-wide policy.
#
# NOTE: PSUseCompatibleSyntax does not flag `#Requires -Version 7`. That is a
# manual fix; do not reintroduce a PS7 header in this project.
@{
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1')
        }
    }
}
