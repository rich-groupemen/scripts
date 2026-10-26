---
name: write-powershell-script
description: Scaffold a new PowerShell 7 script for this repo that follows all conventions - use when creating, adding, or generating a .ps1 file, or when asked to "write a PowerShell script".
---

# Write a PowerShell script

Scaffold a new PS7-only script conforming to this repo's conventions. After
writing, run the lint gate before presenting the result.

**This repo targets PowerShell 7 exclusively** (`pwsh`, installed via mise).
Always `#Requires -Version 7`. Never write for Windows PowerShell 5.1.

## Placement

| Kind | Location | Notes |
|---|---|---|
| Executable | `bin/<kebab-name>.ps1` | param block, CLI behavior |
| Helper | `scripts/<verb>-<noun>.ps1` | repo tooling (linters, tests) |
| Module | `lib/<name>.psm1` | dot-sourced or Import-Module'd |
| Test | `tests/<name>.Tests.ps1` | Pester 5+ (auto-installed by test-ps.ps1) |

## Required boilerplate for bin/ scripts

Copy from the exemplar `bin/greet.ps1`. Non-negotiable elements, in order:

1. `#Requires -Version 7`
2. Comment-based help: `.SYNOPSIS` (mandatory), `.DESCRIPTION`,
   `.EXAMPLE` blocks.
3. `[CmdletBinding()] param(...)` — before any other executable statement.
   Use validation attributes: `[ValidateNotNullOrEmpty()]`,
   `[ValidateSet(...)]`, `[ValidateScript(...)]` as appropriate.
4. `Set-StrictMode -Version Latest` then `$ErrorActionPreference = 'Stop'`.
5. Functions use `Verb-Noun` names from the approved verb list; every
   function gets its own `[CmdletBinding()]`, `[OutputType(...)]`, and
   validated `param()`.

## Style rules (enforced by PSScriptAnalyzer — see PSScriptAnalyzerSettings.psd1)

- 4-space indent, `{` on same line, `} else {` (not `}\nelse`), no
  single-line `if (...) { exit }` — always multi-line blocks.
- Named parameters on all cmdlet calls: `Join-Path -Path $a -ChildPath $b`,
  never positional.
- No aliases (`%`, `?`, `ft`, `select`...). Full cmdlet names always.
- Write-Host is allowed only for user-facing status in CLI scripts
  (rule excluded repo-wide); libraries use Write-Verbose/Write-Output.
- No `Invoke-Expression`. No plaintext password variables.

## Tests

Write `tests/<name>.Tests.ps1` in Pester 5 style: `BeforeAll` for setup
(use `$script:` scope for variables referenced in `It`), `Describe` >
`It`, `Should -Match`/`-Be`. Exemplar: `tests/greet.Tests.ps1`.

## Lint before presenting

```bash
make lint    # PSScriptAnalyzer via scripts/lint-ps.ps1; must pass
make test    # bats + Pester
```

Fix every Error and Warning finding; Information findings should be
addressed or deliberately justified.
