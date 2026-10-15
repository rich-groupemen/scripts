# scripts

Personal Bash and PowerShell 7 scripts, with enforced conventions, a
version-pinned toolchain, and a lint/test gate that runs identically
locally and in CI.

## Layout

```
bin/       Executable scripts (.sh / .ps1), kebab-case names
lib/       Shared code: bash source libraries, PS modules — never executed directly
scripts/   Repo tooling (lint/test helpers)
tests/     bats tests (*.bats) and Pester tests (*.Tests.ps1)
.opencode/ OpenCode agent skills for writing and linting scripts here
```

## Conventions

**Bash** (enforced by shellcheck + shfmt):

- `#!/usr/bin/env bash`, `set -Eeuo pipefail`, ERR trap with `${LINENO}`
- Header comment with usage and examples; `--help` support in every executable
- `main() { ... }` + `main "$@"` structure; arg parsing via `while (( $# > 0 ))`
- 2-space indent, braced/quoted expansions, `local` vars, snake_case
  functions, SCREAMING_SNAKE constants
- Policy lives in `.shellcheckrc` and `.editorconfig` (shfmt reads it)

**PowerShell** — **PS7 only**, never 5.1 (enforced by PSScriptAnalyzer):

- `#Requires -Version 7`, comment-based help, `[CmdletBinding()]` + validated
  `param()`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`
- Verb-Noun function names, named parameters, no aliases, no Invoke-Expression
- 4-space indent, `{` on same line
- Policy lives in `PSScriptAnalyzerSettings.psd1`

## Setup

Requires [mise](https://mise.jdx.dev). Then:

```bash
make install    # mise install + git hooks (pre-commit and pre-push)
```

Tool versions are pinned in `.mise.toml` — local and CI use identical
binaries, so a pass locally means a pass in CI.

Setting this up on another machine, or copying the conventions into a new
project? See [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md) for the full recipe and
the gotchas that cost real debugging time.

## Everyday commands

```bash
make help    # list targets
make fmt     # auto-format bash with shfmt
make lint    # shellcheck + shfmt --diff + PSScriptAnalyzer
make test    # bats + Pester (Pester auto-installs on first run)
make prepush # lint + test — the full pre-push gate
```

## Git hooks

- **pre-commit**: fast per-file checks (shellcheck, shfmt, PSScriptAnalyzer,
  whitespace/yaml/toml hygiene) on staged files.
- **pre-push**: `make prepush` — the full suite, mirroring CI.

Re-install after cloning: `pre-commit install --hook-type pre-commit --hook-type pre-push`

## CI

`.github/workflows/lint.yml` runs `make lint` and `make test` with the same
mise pins on every push and pull request.

## Adding a script

Use the repo's OpenCode skills — `write-bash-script`,
`write-powershell-script` — which scaffold conforming boilerplate, or copy
`bin/greet.sh` / `bin/greet.ps1` and their tests as templates. After writing:
`make lint && make test`.
