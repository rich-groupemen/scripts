# AD Tools — interactive OU / user / group manager

Status: **brief in progress.** The requirements are being drafted in
[`SCRATCH.md`](SCRATCH.md). Do not implement logic or UI yet — this file
becomes the frozen brief once that draft is agreed.

## Purpose

Give a normal operator an interactive, familiar Windows UI to create and
archive Active Directory **OUs, users, and groups** on an on-prem domain,
without memorising AD cmdlets or risking destructive mistakes.

## Confirmed so far

- **Target:** on-prem Active Directory (not Entra ID / Graph).
- **Runs from:** a Windows client, using the operator's own credentials and
  whatever delegated rights they hold. It does not centralise credentials.
- **UI:** must be familiar to non-technical users; explicitly *not* a TUI.
  A "Windows 11 style" desktop experience.
- **Testing:** against a dedicated AD in a Proxmox lab VM. Never production.
- **Repo model:** authored, linted, and unit-tested (with AD cmdlet mocks)
  on Linux; executed and integration-tested on Windows.

## Open decisions

1. **PowerShell edition on the client** — PowerShell 7 (`pwsh`) vs Windows
   PowerShell 5.1. Drives both AD-module compatibility and the WPF apartment
   state. Verification commands are in `SCRATCH.md`; results pending.
2. **UI stack** — WPF + a Fluent theme driven from PowerShell (matches the
   repo toolchain) vs a WinUI 3 / C# front end (truest Windows 11 look, but
   no longer a pure PowerShell project).
3. **Scope of "create"** — exact attributes for users/groups, naming
   conventions, UPN suffix, password policy / forced change at logon.
4. **"Archive" semantics** — move to an archive OU, disable, strip group
   memberships, rename? Must it be reversible, and how?
5. **Input mode** — one object at a time interactively, or bulk from CSV.
6. **Idempotency & failure handling** — behaviour on existing names, partial
   failures, and rollback.
7. **Audit/logging** — transcript, file log, or Windows event log.

## What the brief must settle

Fill these in `SCRATCH.md`, then promote the agreed text into this README:

- Client OS build, PowerShell edition/version, and RSAT availability.
- The operator's delegated rights (least privilege, or Domain Admin).
- Domain FQDN and OU tree of the lab, plus production topology (read-only
  reference for design only).
- Every operation and its parameters, with examples.
- Archive definition and reversibility.
- Logging, audit, and rollback requirements.

## Planned layout

```
projects/ad-tools/
├── README.md        # this brief (frozen once agreed)
├── SCRATCH.md       # working notes → redacted into README, then discarded
├── AdManager.ps1    # UI entry point (Windows-only execution)
├── lib/AdTools/     # pure AD logic, Pester-testable with mocks
└── tests/           # Pester tests (mocked cmdlets; integration opts-in)
```

## Ground rules (from repo AGENTS.md)

- Never run destructive directory operations without `-WhatIf` first, and
  never against anything but the named lab VM.
- Never commit credentials, domain credentials, DC names, or tenant IDs.
