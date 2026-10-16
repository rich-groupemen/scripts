# AD Tools — interactive OU / user / group manager

Interactive, Windows 11-style desktop app that creates and archives Active
Directory **OUs, users, and groups** on an on-prem domain, without the operator
having to memorise AD cmdlets or risk destructive mistakes.

Status: **first iteration.** Logic is unit-tested with mocked AD cmdlets; the
WPF shell has not yet run against a live domain (see [Prerequisites](#prerequisites)).
Working notes and host verification live in [`SCRATCH.md`](SCRATCH.md).

## Purpose

Give a normal operator an approachable UI to:

- create organizational units,
- create users (one at a time) with a generated password,
- create groups,
- change a user's group membership,
- archive a user by disabling the account.

Nothing is deleted, and no existing attribute is modified beyond group
membership.

## Constraints

- **Windows PowerShell 5.1** — this project takes a scoped exception to the
  repo's "PowerShell 7 only" rule for client compatibility.
- **WPF UI, hand-rolled Fluent XAML** — no third-party theme libraries, no
  shipped DLLs. `.NET Framework 4.8` only.
- **STA apartment** required (the script relaunches itself in STA if needed).
- **On-prem Active Directory only.** The tool never writes to LDAP or GLPI.
- **One entry at a time.** No CSV bulk import.
- **Windows-only execution.** The logic is developed and tested on Linux; the
  UI runs on Windows.

## Prerequisites (on the client)

The `ActiveDirectory` (RSAT) module must be present. Install it from an
elevated prompt:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

The operator runs the tool with their own credentials and whatever delegated
rights they hold; the tool does not centralise credentials.

## How it works

The UI collects input, computes a **preview** of the planned change, and only
executes after the operator confirms. The preview and the executed action reuse
the same stored plan, so they can never diverge.

| Section | Action |
|---|---|
| Create OU | Adds one OU under a chosen parent container. |
| Create user | Creates one user: `name.surname`, generated password, chosen OU, selected groups. |
| Create group | Creates one group (Global/Security by default); no permissions are configured. |
| Modify user | Stages group-membership additions/removals, then applies them. |
| Archive user | Disables the account in place. |

All write operations go through `lib/AdTools` and support `-WhatIf`.

## Password generation

Passwords are 10 characters: a French menuiserie word + random digits + one
trailing special character.

- Word: first letter upper, rest lower, diacritics stripped for ASCII safety.
- Digits: `10 − len(word) − 1` (the 4–7 letter word list always yields ≥2).
- Special set: `! # $ % & * ? @ + = -`.
- Examples: `Porte8402!` · `Chassis37#` · `Bois12345?`.

This satisfies typical AD complexity (upper + lower + digit + special). The
3-month rotation is **domain policy**; the tool does not configure it and only
sets `-ChangePasswordAtLogon $false`.

The word list is `data/french-words-60.txt` (60 words, 4–7 letters, ASCII);
the module falls back to an embedded copy if the file is missing.

## Safety model

- **Preview first.** Every operation shows what will happen before it does.
- **Explicit confirmation.** A Yes/No dialog gates every state change.
- **Cleartext only on screen and in the temporary record.** The generated
  password is shown in the preview on purpose. It is never logged.
- **Temporary credential record.** On a successful user creation the tool
  writes `ad-tools-created-users-YYYYMMDD-HHMM.txt` containing
  `username <name.surname>` and `password <cleartext>` lines — a one-time
  hand-off record for the operator. It must never be committed and never left
  in the repository. It is written outside the repo (the `.gitignore` also
  excludes the pattern).
- **Archive means disable.** The account is not deleted, not moved, and its
  group membership is unchanged. It is reversible by re-enabling.
- **Modify means group membership only.** No other attribute is touched.

## Layout

```
projects/ad-tools/
├── README.md                      # this document (the frozen brief)
├── SCRATCH.md                     # working log (discard after Windows validation)
├── AdManager.ps1                  # WPF shell (Windows-only execution)
├── PSScriptAnalyzerSettings.psd1  # project-local 5.1 syntax enforcement
├── data/
│   └── french-words-60.txt        # password word list
├── lib/AdTools/
│   ├── AdTools.psd1               # module manifest
│   └── AdTools.psm1               # pure, mock-testable AD logic
└── tests/
    └── AdTools.Tests.ps1          # Pester tests with mocked AD cmdlets
```

### Module surface (`lib/AdTools`)

`Remove-AdtDiacritics`, `Get-AdtWordList`, `New-AdtPassword`,
`Get-AdtSamAccountName`, `ConvertTo-AdtSecureString`, `Get-AdtDefaultSearchBase`,
`Get-AdtOU`, `New-AdtOU`, `Get-AdtGroup`, `New-AdtGroup`, `Get-AdtUser`,
`New-AdtUser`, `Disable-AdtUser`, `Add-AdtGroupMember`, `Remove-AdtGroupMember`,
`Save-AdtCredentialRecord`.

The module does **not** import `ActiveDirectory` at load time, so it loads and
tests on Linux. The shell imports `ActiveDirectory` and derives the domain at
runtime via `Get-ADDomain` — no domain, DN, or UPN is hard-coded.

## Running

On a Windows client with RSAT installed:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\AdManager.ps1
```

Optional: `-RecordDirectory <path>` to choose where the temporary credential
record is written (defaults to the user temporary folder).

## Testing and linting

```sh
make lint    # shellcheck + shfmt + PSScriptAnalyzer (repo + project settings)
make test    # Pester, including the mocked AD suite
```

`scripts/lint-ps.ps1` deep-merges the repo settings with the nearest
project-local `PSScriptAnalyzerSettings.psd1`, so this project enforces
`PSUseCompatibleSyntax` targeting `5.1` without weakening repo policy.

The Pester suite runs on Linux under `pwsh` with no live AD: it declares
parameter-compatible stubs for the AD cmdlets, then mocks them with
`-ModuleName AdTools`, and asserts on the calls the module makes.

## Known limitations

- The UI has not yet been exercised against a live domain (the client's RSAT
  module is not installed — see `SCRATCH.md`).
- Group pickers are scoped to the selected OU; groups in other OUs are not
  listed.
- New groups default to Global/Security; no permissions are configured.

## Ground rules

- Never run destructive directory operations without `-WhatIf` first, and
  never against anything but the named lab VM.
- Never commit credentials, domain credentials, DC names, tenant IDs, or the
  temporary credential record.
