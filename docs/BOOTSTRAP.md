# Reproducing this setup on another machine

How to stand up this repo — and the same conventions/tooling in a fresh
project — on another Debian/Ubuntu-family system (Linux Mint, Ubuntu, Pop!_OS;
adapt the package manager for Fedora/macOS). Written to be followed top to
bottom; it takes about five minutes plus downloads.

Verified on: Linux Mint 22.3 (Ubuntu "noble" base), bash 5.2, 2026-10.

## What you get

- Pinned toolchain (mise) shared by your machine and CI, so "green locally"
  means "green in CI".
- shellcheck + shfmt for bash, PSScriptAnalyzer for PowerShell 7.
- bats for bash tests, Pester for PowerShell tests.
- pre-commit hooks that block bad commits, and a pre-push gate running the
  full suite before anything leaves your machine.
- GitHub Actions running the identical `make lint` / `make test`.

## 1. Per-machine prerequisites (once per computer)

Install `mise` (manages shellcheck, shfmt, pwsh, bats, pre-commit — no apt/Microsoft
repos for the linters, and PowerShell comes from mise, not `packages.microsoft.com`):

```bash
curl https://mise.run | sh
echo 'eval "$(mise activate bash)"' >> ~/.bashrc
```

Install `pre-commit` with pipx (keeps the system Python clean):

```bash
sudo apt update
sudo apt install -y python3-pip pipx
pipx install pre-commit
pipx ensurepath
```

Then open a new shell (or `source ~/.bashrc`) and confirm:

```bash
mise --version        # expect a date-style version, e.g. 2026.10.10
pre-commit --version  # expect 4.x
```

Optional, for watching CI from the terminal:

```bash
sudo apt install -y gh
gh auth login
```

> `pipx ensurepath` appends `~/.local/bin` to `~/.bashrc`. If a tool seems
> "missing", the usual cause is a shell that hasn't sourced the updated rc.

## 2. The repo (once per clone)

```bash
git clone git@github.com:rich-groupemen/scripts.git
cd scripts
mise install     # installs exactly the pinned versions from .mise.toml
make install     # == mise install + git hook installation
```

`make install` installs both hook types; equivalently:

```bash
pre-commit install --hook-type pre-commit --hook-type pre-push
```

Confirm everything works:

```bash
make lint    # shellcheck + shfmt + PSScriptAnalyzer — must be green
make test    # bats + Pester (Pester auto-installs on first run)
```

## 3. Pinned versions

From `.mise.toml` — this is the single source of truth for both your machine
and CI:

| Tool | Version | Role |
|---|---|---|
| shellcheck | 0.11.0 | bash static analysis |
| shfmt | 3.14.1 | bash formatting |
| powershell | 7.6.7 | PS7 runtime (`pwsh`) |
| bats | 1.14.0 | bash tests |
| pre-commit | 4.7.0 | git hook framework |

Re-check for newer pins deliberately with `mise latest <tool>`, then bump
`.mise.toml`, run `make prepush`, and commit.

## 4. Starting a *new* project with the same conventions

Copy these files verbatim into the new repo — they are the whole convention
layer and contain no project-specific logic:

```
.mise.toml  .editorconfig  .shellcheckrc  .pre-commit-config.yaml
Makefile  PSScriptAnalyzerSettings.psd1  scripts/lint-ps.ps1
scripts/test-ps.ps1  .github/workflows/lint.yml
.opencode/skill/   (optional: agent conventions)
```

Then `make install`, and use `bin/greet.sh` / `bin/greet.ps1` (with their
tests) as templates — or the `write-bash-script` / `write-powershell-script`
skills if you're driving an agent.

## 5. Gotchas that cost real time (read before debugging)

These are the non-obvious failures hit while building this repo. They are the
reason several files look the way they do — change them and they'll come back.

### shfmt + `.editorconfig`

- shfmt's own editorconfig options are **unprefixed**:
  `switch_case_indent`, `space_redirects`, `binary_next_line`. The
  `shfmt_`-prefixed names are silently ignored.
- `indent_size` alone does nothing — you also need `indent_style = space`,
  or shfmt falls back to tabs.
- Passing a formatting flag on the command line (`-i 2`, `-ci`, or even
  `--language-dialect=bash`) makes shfmt **ignore `.editorconfig` entirely**
  for that run. This made `make fmt` (no flags → 2-space) and `make lint`
  (had `--language-dialect` → tabs) disagree. Rule: never pass style flags;
  configure everything in `.editorconfig`, keep `fmt` and `lint` flag-free
  and identical. shfmt already defaults to the bash dialect.

### PowerShell (pwsh 7)

- `pwsh -File script.ps1 a b c` does **not** reliably bind multiple args to a
  `[string[]]` positional parameter. Use
  `[Parameter(Position = 0, ValueFromRemainingArguments = $true)]`. Needed for
  the pre-commit hook, which appends filenames.
- PSScriptAnalyzer and Pester are **not** bundled with pwsh 7. The `scripts/`
  runners install them to `CurrentUser` scope on first run.
- Common false positives:
  - `PSReviewUnusedParameter` when a script parameter is used inside a helper
    function (closure). Fix by passing it as an explicit argument.
  - `PSUseDeclaredVarsMoreThanAssignments` for Pester `BeforeAll` variables
    that are used in `It` blocks. Fix with `$script:` scope.
- `PSUseBOMForUnicodeEncodedFile`: files with non-ASCII characters need a
  UTF-8 BOM. Add one rather than stripping the characters.

### pre-commit hooks

- With `language: system`, hooks run in the git process's environment, which
  may not have mise activated (GUI git clients especially). Every custom hook
  is therefore written as `mise x -- <tool>` so it resolves its own tools.
- `pre-commit run --all-files` only sees files tracked by git; stage new files
  first or the shell hooks report "no files to check" and pass vacuously.

### Environment

- `pipx install` appends the PATH entry to `~/.bashrc`; the running shell
  won't see it until you `source ~/.bashrc` or open a new terminal.
- Watch for duplicate `eval "$(mise activate bash)"` lines if you paste setup
  snippets twice — harmless, but delete the extra.

## 6. CI

`.github/workflows/lint.yml` runs on every push and pull request:

1. `actions/checkout@v4`
2. `jdx/mise-action@v2` — installs the same `.mise.toml` pins
3. `make lint`
4. `make test`

This intentionally duplicates the local pre-push gate: local fails fast,
CI is the authoritative, clean-environment check. Do not "optimize away" the
CI run — it is the independent second verification.
