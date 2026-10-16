---
id: write-ad-script
name: write-ad-script
description: Scaffold PowerShell 5.1 AD logic (lib/AdTools) for the AD tools project - use when creating AD-related functions, password generation, OU/user/group operations with -WhatIf support and no passwords in logs.
---

# Skill: write-ad-script (PowerShell 5.1 AD logic)

This skill helps scaffold AD logic for `projects/ad-tools/`. Target is **Windows PowerShell 5.1** (exception to PS7-only). Code must be testable with Pester mocks and never log or persist cleartext passwords except the explicitly required temporary record file produced by the UI.

## Guidelines
- Target: Windows PowerShell 5.1 (`powershell.exe`), not PS7.
- Location: `projects/ad-tools/lib/AdTools/` as a module (`*.psm1`, optionally `*.psd1`).
- Pure logic where possible; separate from WPF UI.
- **-WhatIf support** on all state-changing functions (`New-AD*`, `Set-AD*`, `Disable-ADAccount`, `Move-ADObject` if ever used — note: archive disables only, no move).
- **No passwords in logs, transcripts, or commitable artifacts.** Only the UI may write the temporary `ad-tools-created-users-YYYYMMDD-HHMM.txt` file on successful creation (cleartext, never committed).
- Mock-friendly: avoid hard-coding cmdlet resolution in ways that break Pester mocks; call AD cmdlets directly (`Get-ADOrganizationalUnit`, `Get-ADUser`, `New-ADUser`, `Set-ADUser`, `Add-ADGroupMember`, `Get-ADGroup`, `New-ADGroup`, `Disable-ADAccount`).
- Idempotent where practical (check existence before creating).
- Error handling: throw descriptive errors; let UI present messages.
- Naming: PascalCase, singular/plural consistent. Functions in module export as needed.

## Password generation (required)
Use the French menuiserie word list with this algorithm (10 chars):
- Word list (60): porte, fenetre, vitre, chassis, cadre, bois, chene, hetre, sapin, lame, latte, gond, pene, clou, scie, rail, joint, tenon, rabot, seuil, appui, chant, about, fibre, noeud, placage, lambris, moulure, parquet, chevron, plinthe, solive, poutre, montant, vernis, lasure, mastic, liteau, verrou, bouton, agrafe, ecrou, ressort, vitrage, rainure, imposte, volet, maillet, etabli, gabarit, copeau, sciure, serrure, poignee, gache, cremone, equerre, boulon, tasseau, panneau
- Strip diacritics: é→e, ê/è→e, â→a, ç→c, ô→o, û→u, œ→oe
- Format: `<WordCap>` where first letter upper, rest lower + `<N digits>` + `<1 special>` = 10 total. For word length W (4-7), digits = 10 - W - 1 (≥2).
- Special set: `! # $ % & * ? @ + = -`
- Generate per user on creation (do not store). Never log.

## Archive (disable only)
Archive means `Disable-ADAccount` for the selected user(s). No move to archive OU. Users only. No deletion.

## Modify user
Only change group membership (add/remove from groups in the chosen/selected context). No other attribute changes.

## OU and groups
- OU: create or select existing (tree browse). All actions in that OU.
- Groups: create groups as needed (no permissions configuration). List groups in OU for user assignment.
- New OU path: may create groups.

## Dry-run preview
Logic functions must support `-WhatIf` so the UI can present a faithful preview. The preview content (including cleartext password shown to operator) is UI responsibility; the logic layer must not emit passwords to logs.

## File organization
Suggested:
- `projects/ad-tools/lib/AdTools/AdTools.psm1` — core functions
- `projects/ad-tools/lib/AdTools/password-words.txt` (optional) or embed the word list
- Functions: `Get-AdtWordList`, `New-AdtPassword`, `Get-AdtOU`, `New-AdtOU`, `Get-AdtGroup`, `New-AdtGroup`, `Get-AdtUser`, `New-AdtUser`, `Disable-AdtUser`, `Set-AdtUserGroupMembership`

## Testing
Functions must be testable via Pester mocks of AD cmdlets (`*-AD*`). No dependency on live AD in unit tests.
