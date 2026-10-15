---
name: write-bash-script
description: Scaffold a new bash script for this repo that follows all conventions - use when creating, adding, or generating a new .sh/.bash file in bin/ or lib/, or when asked to "write a bash script".
---

# Write a bash script

Scaffold a new bash script conforming to this repo's conventions. After
writing, run the lint gate before presenting the result.

## Placement

| Kind | Location | Notes |
|---|---|---|
| Executable | `bin/<kebab-name>.sh` | `chmod +x`, has `main()`, parses args |
| Library | `lib/<snake-name>.sh` | sourced, never executed; add double-include guard |
| Test | `tests/<name>.bats` | one bats file per script under test |

## Required boilerplate for bin/ scripts

Copy from the exemplar `bin/greet.sh`. Non-negotiable elements, in order:

1. `#!/usr/bin/env bash` (never `/bin/bash` or `/bin/sh`)
2. Header comment: one-line purpose, `Usage:` with all options, at least one
   `Examples:` line.
3. `set -Eeuo pipefail` — always, no exceptions.
4. `trap 'echo "<script>: error on line ${LINENO}" >&2' ERR`
5. Repo-root resolution + sourcing:
   ```bash
   SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
   REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
   # shellcheck source=../lib/common.sh
   source "${REPO_ROOT}/lib/common.sh"
   ```
6. `usage()` function emitting help to stdout; `-h | --help` case calls it.
7. `main() { ... }` with `main "$@"` as the last line.
   Arg parsing: `while (( $# > 0 )); do case "$1" in ...` with a `*)` branch
   that logs the unknown option and returns 2.

For lib/ scripts: `# shellcheck shell=bash` directive, guard
`[[ -n "${_FOO_SH_LOADED:-}" ]] && return 0` + `_FOO_SH_LOADED=1`.

## Style rules (enforced by shfmt/editorconfig — do not fight them)

- 2-space indent, `case` labels NOT indented relative to `case`, one space
  inside `(( ))`, `>/dev/null` with no space before `>`.
- All expansions braced and quoted: `"${var}"`, `"$(cmd)"`.
- `local` for all function-scoped variables, declared at first assignment.
- Constants: `readonly` + SCREAMING_SNAKE. Functions: snake_case.
- Prefer `[[ ]]` over `[ ]`; string comparisons unquoted inside `[[ ]]`.

## Lint before presenting

```bash
make lint    # shellcheck + shfmt; must pass
make test    # if tests were written/changed
```

If shfmt rewrites the file, that is normal on first draft — accept its
formatting, do not hand-edit around it.
