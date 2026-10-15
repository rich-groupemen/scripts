# Scratch log — AD Tools project

Working notes for the AD interactive manager. Live scratch file; when the
brief is agreed it is redacted into `README.md` and then discarded (see repo
`AGENTS.md`). Not a spec yet — expect churn.

## Host verification — RESULTS (2026-10-15)

Checked on the target Windows client `2025-0540` (domain `GROUPE`), in
**Windows PowerShell 5.1** (Desktop):

```
SHELL      : Desktop 5.1.26100.9711
OS         : Windows NT 10.0.26200.0        # Windows 11, build 26200
User       : GROUPE\richard.pearsall
RSAT AD    : MISSING
AD import  : FAILED — module 'ActiveDirectory' not found
Apartment  : STA                            # good: WPF works as-is
WPF load   : OK
```

### What this means
- **BLOCKER:** the client has no Active Directory (RSAT) module, so nothing
  AD-related can run or be tested there yet. Install the RSAT AD DS tools
  (see below) before any build/test work on the client.
- **PowerShell 7 was not tested.** The block was run in 5.1 only. Either
  pwsh 7 is not installed on the client, or it was skipped. Until we have the
  PS7 result, the edition decision below stays open — but the client being
  corporate Windows 11 with 5.1 present leans toward **5.1**.
- **STA + WPF OK** — a WPF UI is viable on the client with no apartment
  workaround. Good news for the "Windows 11 style" requirement.

### Install RSAT AD DS tools (run as admin on the client)
```powershell
# Install
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

# Verify
Get-WindowsCapability -Online -Name Rsat.ActiveDirectory* |
    Select-Object Name, State          # expect: Installed

# Then re-run the AD checks; expect Get-ADDomain to succeed.
```
If Windows Update is managed/blocked, source the FoD from a mounted ISO:
```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 `
    -Source D:\ -LimitAccess
```

## Brief capture (from Richard, 2026-10-15) — DRAFT, not final

### 1. Lab environment
- Two VMs mirroring production: (a) **AD** domain controller, (b) **Debian**
  running **LDAP + GLPI**.
- "All users and passwords are shared across logins" — i.e. the same user
  identity/password works for AD and for GLPI/LDAP. Whether the tool must
  *write* to LDAP/GLPI as well as AD is TBD (§8, "discuss later"). Working
  assumption for now: **the tool manages AD only**; LDAP/GLPI stays in sync
  by its own mechanism.

### 2. Archive = deactivate, never delete
- Archiving a user means **disabling the account** (`Disable-ADAccount`),
  not deleting it. Reversible by re-enabling.
- Open: does "archive" *also* move the user to an archive OU, or disable
  in place? (Affects the whole menu design.)

### 3. Users and passwords
- Username format: **`name.surname`** (e.g. `richard.pearsall`).
- Password value: **defined later** (to be given). Where it comes from
  (prompt per user, generated, CSV column) is TBD.
- Password **changes every 3 months** — presumably domain/PSO policy
  (script likely sets nothing, or must set expiry?). TBD.
- **No forced change at first logon** → `-ChangePasswordAtLogon $false`.

### 4. Interactive flow (the core spec)
```
Main menu:  [ Add ]   [ Archive ]   [ Modify user ]

Add
 └─ Choose OU:  ( Create new OU )  |  ( Use existing OU → pick from list )
    └─ all subsequent actions happen in that OU
       ├─ New OU          → Create new groups
       └─ Existing OU     → Create new groups | Create new users
            ├─ Create new group  → create group + set its "permissions"
            └─ Create new user   → create user + pick from the OU's
                                    groups to join (checkbox list)

Modify user
 └─ change the groups a user belongs to
```
- "setting permissions" on a new group is **ambiguous** — needs definition
  (group scope/category? membership? delegated rights? NTFS/share ACL?).

### 5. Dry-run / confirmation (IMPORTANT + security-sensitive)
- Must **preview all pending changes** and ask for confirmation before
  executing.
- Preview shows, per user: **the password in clear text** and the groups to
  be joined — then moves to the **next user** (implies **bulk**, multiple
  users in one run).
- Security note: clear-text passwords must appear **only on screen**, never
  in logs, transcripts, or files. Consider a show/hide toggle and a warning.

### 7. Rights
- The operator account has rights to modify the AD. Good — no elevation
  design needed beyond their existing delegated/administrative rights.

### 8. To discuss later
- AD ↔ LDAP/GLPI relationship and whether the tool touches both.
- Everything else not yet pinned down.

## Open questions (need answers before the brief can freeze)

1. **PowerShell edition on the client** — run the check block in `pwsh` too,
   or confirm pwsh 7 isn't installed. If it's 5.1-only, we grant this
   project a scoped exception to the repo's "PS7 only" rule.
2. **UI stack** — WPF + Fluent theme from PowerShell (recommended, fits the
   toolchain and the client), or a WinUI 3 / C# app?
3. **Input mode for users** — typed interactively one at a time, or a CSV
   bulk import? ("next user" in the preview suggests bulk.)
4. **Password source** — who/what defines each password, and is the
   "every 3 months" expiry set by the script or by domain policy?
5. **Archive scope** — disable only, or disable + move to an archive OU?
   Does it apply to OUs/groups too, or users only?
6. **"Setting permissions" on a group** — what exactly?
7. **Modify user** — only group membership changes, or also other
   attributes (name, OU, enable/disable)?
8. **Logging/audit** — transcript, file, or event log? (must exclude passwords)

## Notes for whoever implements
- Do NOT commit credentials, DC names, or domain identifiers.
- Every write operation must support `-WhatIf` and be exercised that way first
  — the user-visible dry-run is the product's core safety feature.
- Architecture: `AdManager.ps1` (WPF shell) + `lib/AdTools/` (pure,
  mock-testable AD logic) + `tests/` (Pester with mocked AD cmdlets).
