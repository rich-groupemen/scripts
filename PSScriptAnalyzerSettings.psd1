# PSScriptAnalyzer settings — repo policy (PS7-only target).
# Run: pwsh -NoProfile -File scripts/lint-ps.ps1  (or: make lint-ps)
@{
    Severity = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        # Verb-Noun naming is still enforced; this fires on legitimate
        # admin-script names (e.g. Get-SystemInfos).
        'PSUseSingularNouns'
        # The scripts/ helpers are CLIs, not modules: Write-Host is the
        # correct tool for user-facing status output there.
        'PSAvoidUsingWriteHost'
    )
    Rules = @{
        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckSeparator = $true
            CheckParameter = $true
            IgnoreOpenBrace = $false
            IgnoreOpenParen = $false
            IgnorePipeAfterRedirection = $false
            IgnorePipelineLength = $false
            IgnoreSeparator = $false
            IgnoreAssignmentOperatorAfterKeyword = $false
        }
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $false
            IgnoreOneLineBlock = $false
        }
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $false
            IgnoreOneLineBlock = $false
        }
        PSUseApprovedVerbs = @{
            Enable = $true
        }
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }
        PSAvoidUsingPlainTextForPassword = @{
            Enable = $true
        }
        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }
        PSAvoidUsingInvokeExpression = @{
            Enable = $true
        }
    }
}
