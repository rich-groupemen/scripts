---
id: test-ps-ad-mocks
name: test-ps-ad-mocks
description: Scaffold Pester tests for AD tools using mocked ActiveDirectory cmdlets - use when writing unit tests for lib/AdTools with no live AD dependencies.
---

# Skill: test-ps-ad-mocks

Write Pester tests for `projects/ad-tools/lib/AdTools` using mocked `*-AD*` cmdlets. Pester 6.x is installed; the core syntax (`Should -Be`, `-ModuleName`, `-ParameterFilter`, `Should -Invoke`) is unchanged from Pester 5. Tests must run on Linux (pwsh 7) in CI but validate PowerShell 5.1-compatible logic. No live AD, no credentials.

## Guidelines
- Test location: `projects/ad-tools/tests/` (Pester `.Tests.ps1` files).
- Mock all AD cmdlets: `Get-ADOrganizationalUnit`, `Get-ADUser`, `New-ADUser`, `Set-ADUser`, `Add-ADGroupMember`, `Remove-ADGroupMember`, `Get-ADGroup`, `New-ADGroup`, `Disable-ADAccount`.
- Import the module under test with its manifest (`Import-Module $PSScriptRoot/../lib/AdTools/AdTools.psd1 -Force`) so exports match production. Pester's `Mock -ModuleName AdTools` must target the module name, not the file path.
- Cover: OU create/select, group create/list, user create (name.surname), password generation (length 10, pattern word+digits+special, accents stripped), group membership changes, disable-only archive, `-WhatIf` behavior.
- Never assert on cleartext password values in logs; only assert password length/format if needed.
- Deterministic tests. For date-stamped filenames in UI tests, mock `[DateTime]::Now` or test logic separately.
- Use `InModuleScope` if testing private helpers; otherwise test public functions.

## Password tests (must verify)
- Generated password is exactly 10 chars.
- Pattern: starts with uppercase, rest lowercase letters for the word portion, ends with a special char from `! # $ % & * ? @ + = -`, middle digits.
- Accents stripped (e.g. `fenetre` not `fenêtre`).
- Word comes from the allowed list.
- Multiple generations produce different passwords (basic sanity).
- No password written to any log/mock-verifiable output stream.

## -WhatIf tests
- State-changing functions with `-WhatIf` must not call create/disable/set cmdlets. When `-WhatIf` is specified, `Should -Not -Invoke` the corresponding AD cmdlet; when not specified, expect the appropriate `Should -Invoke`.
- Preview logic must not leak passwords to streams.

## Notes
- Keep tests focused and fast. No filesystem side effects except maybe temp paths for the credential file (but that’s UI responsibility; logic tests shouldn’t create the transfer file).
- CI runs on Linux/pwsh 7 with Pester 6.x; the core mock/assertion syntax is unchanged from Pester 5. Avoid PS5.1-only cmdlets in tests.
