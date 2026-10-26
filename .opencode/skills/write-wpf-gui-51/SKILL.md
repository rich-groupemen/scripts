---
name: write-wpf-gui-51
description: Scaffold WPF GUI in PowerShell 5.1 for the AD tools project (hand-rolled Fluent XAML, STA, dependency-free) - use when creating the UI shell that previews actions, confirms, and writes the temporary credential record.
---

# Skill: write-wpf-gui-51 (PowerShell 5.1 WPF)

Scaffold the WPF UI for `projects/ad-tools/AdManager.ps1` targeting Windows PowerShell 5.1. Must be dependency-free (hand-rolled Fluent XAML). The UI is the "shell"; AD logic lives in `lib/AdTools/`.

## Guidelines
- Target: Windows PowerShell 5.1, STA apartment required. Run as `powershell.exe` (not pwsh).
- Entry point: `projects/ad-tools/AdManager.ps1`. Drop `#Requires -Version 7` (scoped exception for 5.1).
- No third-party theme libraries (hand-rolled Fluent styles). Use native WPF: XAML loaded via `[System.Windows.Markup.XamlReader]::Load(...)` or inline XAML string.
- Dependency-free: no DLLs shipped. Works on Windows 11 with .NET Framework 4.8.
- Load with STA: `[System.Threading.Thread]::CurrentThread.SetApartmentState('STA')` (or run from powershell.exe in STA).
- Load required assemblies: `PresentationFramework`, `PresentationCore`, `WindowsBase`.

## Architecture
- Thin UI shell: calls functions from `lib/AdTools/AdTools.psm1` (pass-through with `-WhatIf`).
- ViewModel logic minimal; avoid putting AD logic in event handlers.
- Flow: Main menu → Add/Archive/Modify. Within Add: choose OU (create new or select existing) → then create users (and optionally groups if new OU). Sequential one-at-a-time entry.
- Modify user: change only group membership.

## Dry-run preview
- Before execution, build a preview showing pending changes. For each user creation: display **cleartext password** and the groups to join. Show next user sequentially.
- Require explicit confirmation (Yes/No) before executing state changes.
- Execute only after confirmation; reuse the same planned changes (no divergence between preview and execution).

## Temporary credential record (critical)
- On successful user creation(s), write a temporary text file named `ad-tools-created-users-YYYYMMDD-HHMM.txt` in the working directory (or a path chosen by operator) containing lines: `username name.surname` and `password <cleartext>` for each created user.
- This is a one-time memory record for transferring credentials to the new user. It must **never** be committed to git. Do not log it. Do not copy to repo.
- Treat as sensitive; warn the operator. Avoid duplicating passwords in other artifacts.

## Security
- Never log, trace, or write cleartext passwords except the explicit temporary file above.
- Disable or avoid transcript unless the operator explicitly enables and understands risk; do not default to logging passwords.
- No credentials/hostnames/DNs committed.
- Show passwords only on screen in the preview/confirmation UI; never echo to console in a way that persists (the UI is WPF).
- Archive = disable only (no move). Users only.

## UX (Fluent, Windows 11 style)
- Clean layout, Segoe UI (Variable if available, fallback Segoe UI), rounded corners, subtle spacing, accent-aware feel.
- Grouped sections, checkbox lists for group selection, list views for OU/user selection.
- Sequential entry (one-at-a-time) with Previous/Next, Add, Clear, Preview, Confirm/Execute.
- Disable/Archive section: select user(s) → disable (no delete).

## Implementation notes
- XAML: define Window, Grid, StackPanel, ListBox/ComboBox, CheckBox, TextBox, Button, GroupBox. Add Fluent-like styles (borders, corner radius, margins).
- Event wiring in PowerShell.
- Error messages user-friendly; stack traces minimal.

## Example skeleton (guidance)
- Import-Module (relative): `Import-Module "$PSScriptRoot\lib\AdTools\AdTools.psm1"`
- `[System.Threading.Thread]::CurrentThread.SetApartmentState([System.Threading.ApartmentState]::STA)`
- Load assemblies.
- Read XAML string and parse.
- Wire events, run `[System.Windows.Application]::Run($window)`

Do not invent AD logic — call AdTools functions. Do not log passwords. Write temporary record only on successful creation.
