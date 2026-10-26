---
name: lint-scripts
description: Run and interpret the repo's full lint/test gate (shellcheck, shfmt, PSScriptAnalyzer, bats, Pester) and fix findings - use when asked to lint, format, check, validate, or fix scripts in this repo, or after modifying any script.
---

# Lint scripts

Run this repo's quality gate, interpret failures precisely, and fix them.

## The gate

```bash
make lint    # shellcheck + shfmt --diff (bash) + PSScriptAnalyzer (PS)
make test    # bats + Pester
```

Run both; `make prepush` runs them together (what the pre-push hook runs).
Tools come from mise pins in `.mise.toml` — if a tool is missing, run
`mise install` first (or `mise x -- make lint` to bypass PATH issues).

## Interpreting failures

**shellcheck**: fix the actual issue, don't blanket-disable. Targeted
disable only with justification on the same line:
`# shellcheck disable=SC2312  # subshell cost irrelevant here`.
Never add disables to `.shellcheckrc`.

**shfmt --diff**: it shows the canonical formatting. Fix by *applying* it
(`make fmt`), not by hand-editing. Then re-run `make lint` to confirm.
Note: shfmt reads `.editorconfig`; its flags and the editorconfig must
agree — never pass `-i`/`-ci`/`-sr` flags, they override editorconfig and
cause local/CI drift.

**PSScriptAnalyzer**: findings are Errors/Warnings (gate fails) and
Information (printed, non-fatal). Common fixes:
- `PSReviewUnusedParameter` in scripts that use a param inside a helper
  function: pass it as an explicit argument instead of closing over it.
- `PSUseDeclaredVarsMoreThanAssignments` in Pester `BeforeAll`: variable
  IS used, but in `It` blocks — prefix `$script:` to satisfy the analyzer.
- `PSAvoidUsingPositionalParameters`: switch to named params.
- Policy-level exceptions belong in `PSScriptAnalyzerSettings.psd1`
  ExcludeRules with a comment justifying them — not per-file suppressions
  unless a single file truly needs different treatment.

**bats/Pester failures**: reproduce minimally, identify whether the script
or the test is wrong, fix, re-run only that suite first
(`bats tests/foo.bats` or `pwsh -NoProfile -File scripts/test-ps.ps1`),
then the full gate.

## Before presenting results

Both `make lint` and `make test` must be green. Report what failed, what
was changed, and why — not just "all fixed".
