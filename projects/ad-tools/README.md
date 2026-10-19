# AD Tools — interactive OU and user manager

Interactive, Windows 11-style desktop app that builds an Active Directory
**OU hierarchy** and creates **users** on an on-prem domain, without the
operator having to memorise AD cmdlets or risk destructive mistakes.

Status: **second iteration.** Logic is unit-tested with mocked AD cmdlets; the
first-iteration WPF shell was exercised against a live lab domain. The
second-iteration shell (queue panel, cascading pickers, French labels) parses
clean and passes the full lint and test gate but is still awaiting its first run
on Windows. Working notes and host verification live in
[`SCRATCH.md`](SCRATCH.md).

## Purpose

Give a normal operator an approachable UI to:

- create a top-level OU, optionally seeding it with one **agence** per branch,
- add further agences under an existing OU at any time,
- add **department** OUs (RH, Compta, Dev, …) under each agence,
- create users inside a department OU with a generated password,
- archive a user by disabling the account.

The application is aimed at French operators, so **all labels, prompts and
messages are in French**. Identifiers and code comments stay in English, matching
the rest of the repository.

Users live in department OUs. Nothing is deleted, and no existing attribute is
modified beyond enabling/disabling an account.

**Groups are deferred.** Group creation and group-membership editing are out of
scope for this iteration — see [Roadmap](#roadmap). The module still exposes the
group functions (they are tested and will return) but the UI does not use them.

## Directory model

"Folder" means an **Organizational Unit**, never a file-system directory.

```
DC=ad,DC=dev
└── OU=Entreprises              ← Create OU
    ├── OU=Lyon                 ← agence
    │   ├── OU=RH               ← department: users live here
    │   ├── OU=Compta
    │   └── OU=Dev
    └── OU=Marseille            ← added later via Add Agence
        ├── OU=RH
        └── OU=Compta
```

An OU can be created empty and seeded with agences later, or seeded in the same
action. Agences are free-form names; departments are free-form names. Nothing
is hard-coded.

## User interface

Five sections, one panel each, plus a persistent queue panel on the right:

| Section | Location selectors | What it queues |
| --- | --- | --- |
| `Créer un OU` | none — always the domain root | one OU at the first level |
| `Créer une agence` | Établissement | one OU per named agence |
| `Créer un département` | Établissement → Agence | one OU per named department |
| `Créer un utilisateur` | Établissement → Agence → Département | one user |
| `Archiver un utilisateur` | the loaded account | one account disable |

### Location selectors

Each section offers only the selectors it actually needs, rather than the same
three-level cascade everywhere:

- `Créer un OU` has **no selector**: the name is the only input and the OU is
  created directly under the domain root. That is how a new site starts.
- `Créer une agence` picks Établissement only; departments belong to the next
  section.
- `Créer un département` picks Établissement then Agence.
- `Créer un utilisateur` picks all three, in that order.

**The effective parent is always the section's own last selector** — never "the
deepest non-empty one". A section cannot place an object somewhere the operator
did not explicitly point at.

Selectors are derived by walking parent DNs, so they work against any domain and
need no configuration. Each level lists only the children of the level above.
OUs queued but not yet created appear alongside real ones marked
`(en attente)`, so an operator can queue an OU, an agence under it, a
department under that, and a user inside it — all before the first write to the
directory.

A selector that comes back empty says what is missing instead of presenting a
blank field: `« Aucun établissement disponible. Créez-en d'abord un dans
« Créer un OU ». »`

Selectors show short, human-readable names. Where a full path is needed — the
queue labels and the "Ajouté par cette action" preview — it is rendered as
`Entreprises / Lyon / RH` rather than `OU=RH,OU=Lyon,OU=Entreprises,DC=ad,DC=dev`.

## Constraints

- **Windows PowerShell 5.1** — this project takes a scoped exception to the
  repo's "PowerShell 7 only" rule for client compatibility.
- **WPF UI, hand-rolled Fluent XAML** — no third-party theme libraries, no
  shipped DLLs. `.NET Framework 4.8` only.
- **STA apartment** required (the script relaunches itself in STA if needed).
- **On-prem Active Directory only.** The tool never writes to LDAP or GLPI.
- **One entry at a time in the UI.** No CSV bulk import. Entries accumulate in
  a queue and are applied together.
- **Windows-only execution.** The logic is developed and tested on Linux; the
  UI runs on Windows.

## Prerequisites (on the client)

The `ActiveDirectory` (RSAT) module must be present. Install it from an
elevated prompt:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

The operator runs the tool with their own credentials and whatever delegated
rights they hold; the tool does not centralise credentials. The process identity
must be a **domain** identity — a local account cannot bind to the directory.

## How it works: queue, review, apply

The tool does **not** confirm each action individually. Actions accumulate in a
queue; the operator reviews the whole plan and applies it once.

1. **Add actions.** Each section appends one or more planned actions to the
   queue. Nothing has touched AD yet.
2. **Review the queue.** Every queued action is listed with a readable path and,
   for users, the generated password in clear. Items can be removed before
   applying.
3. **Apply All.** One confirmation shows the whole batch, then the queue
   executes. OUs are always created before any user that depends on them,
   because a user can only target a parent that is already in the queue.
4. **Credential record.** On success the tool writes the hand-off record (see
   [Credential record](#credential-record)).

The queue stores the fully-resolved plan at add time, so what the operator
reviews is exactly what executes — preview and execution cannot diverge.

OUs queued but not yet created appear in the location selectors alongside real
ones, marked `(en attente)`, so an operator can create a user inside an agence
that has not been created yet.

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

## Credential record

After a successful apply that created users, the tool writes
`ad-tools-created-users-YYYYMMDD-HHMM.txt` to the operator's **Documents**
folder (`[Environment]::GetFolderPath('MyDocuments')`).

It contains `username <name.surname>` and `password <cleartext>` lines — a
one-time hand-off record for the operator. The generated password is shown on
screen and written here **on purpose**; it is never logged.

The record must never be committed and never left in the repository. It is
written outside the repo, and `.gitignore` also excludes the pattern as a second
layer. Delete it once the passwords have been handed over.

## Safety model

- **Nothing is created until Apply All.** Actions are queued, reviewed, then
  executed as one batch.
- **Full review before apply.** The queue shows the exact path and password for
  every pending action, and Apply All confirms the whole batch once.
- **Cleartext only on screen and in the record.** The generated password is
  shown on purpose. It is never logged.
- **Archive means disable.** The account is not deleted, not moved, and no other
  attribute is touched. It is reversible by re-enabling.
- **Partial failure is reported, not hidden.** If one action in the batch fails,
  the rest still run and the failures are listed. Successful user creations are
  still recorded.

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
`Get-AdtOU`, `New-AdtOU`, `Get-AdtUser`, `New-AdtUser`, `Disable-AdtUser`,
`Save-AdtCredentialRecord`.

Deferred (unused by the UI this iteration, retained and tested):
`Get-AdtGroup`, `New-AdtGroup`, `Add-AdtGroupMember`, `Remove-AdtGroupMember`.

The module does **not** import `ActiveDirectory` at load time, so it loads and
tests on Linux. The shell imports `ActiveDirectory` and derives the domain at
runtime via `Get-ADDomain` — no domain, DN, or UPN is hard-coded.

## Running

On a Windows client with RSAT installed, as a domain user:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\AdManager.ps1
```

Optional: `-RecordDirectory <path>` to override where the credential record is
written (defaults to the operator's Documents folder).

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

- The tool does not configure home directories, profile paths, or any attribute
  beyond name, UPN, password, and enabled state.
- Users are created with `-ChangePasswordAtLogon $false`; password rotation is
  domain policy and is not configured here.
- The location selectors expose exactly three levels, and `Créer un OU` creates
  only at the first level. OUs nested deeper than
  Établissement → Agence → Département cannot be created through the UI, though
  the module can still address them.
- The queue is in-memory only. Closing the window discards it.

## Roadmap

- **Groups** — creation and membership editing. The module functions already
  exist and are tested; the UI needs reintroducing when this returns.
- Optional: per-agence department templates.

## Ground rules

- Never run destructive directory operations without `-WhatIf` first, and
  never against anything but the named lab VM.
- Never commit credentials, domain credentials, DC names, tenant IDs, or the
  temporary credential record.
