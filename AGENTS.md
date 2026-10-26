# Instructions

## Git operations — user only (hard boundary)
- The user performs ALL `git add`, `git commit`, and `git push` commands,
  plus any other history-changing git operation (rebase, reset, revert,
  tag, stash pop, branch deletion). Never run these, even after approval.
- The agent MAY run read-only git commands (`status`, `diff`, `log`,
  `show`, `blame`) and `pre-commit run` for verification.
- When changes are ready, the agent stops and PRESENTS the exact commit
  commands (message included) for the user to review and run.
- Never bypass or amend around a failing pre-commit hook; report the
  failure and fix the underlying cause instead.
- **Commit command presentation:** When presenting ANY `git add`/`git commit` commands to the user, ALWAYS prefix with `cd <absolute-repo-root> &&`. Use absolute paths (e.g. `cd /home/rich/git/scripts && ...` or `cd /home/rich/git/docs && ...`). Never assume the current working directory.
- **Multi-repo changes:** If changes span multiple repositories, present SEPARATE command blocks per repo, each with its own `cd`. Do not chain across repos.
- **Commit messages:** Break work into clean, atomic commits with descriptive messages, one logical change per commit. Present them grouped in order.

## Development Workflow
- Always `cd` to the repository path before running repository actions.
- Always run local linters and tests (`make lint && make test`) and ensure
  they pass before presenting commit commands for that repo.
- Break work into clean, atomic commits with descriptive messages; one
  logical change per commit. Present them grouped, in order.

## Cross-repo Documentation
- **Source of truth:** For any documentation artifact (scratch, design notes, redaction, or final docs), follow `/home/rich/git/docs/AGENTS.md`. Read it before writing anything under `/home/rich/git/docs/`.
- **Scratch location:** All in-progress notes MUST live under `/home/rich/git/docs/scratch/<category>/<project>/`.
  - For `scripts/projects/<name>/` use `/home/rich/git/docs/scratch/scripts/<name>/`.
  - For ad-hoc work under `scripts/` not tied to a project directory use `/home/rich/git/docs/scratch/scripts/<task-name>/`.
  - For other repos follow the same `<category>/<project>/` convention.
- **Do not create scratch next to code:** Never create `SCRATCH.md` inside `projects/*/` or any other code directory.
- **Skills:** Respect skills located in `/home/rich/git/docs/.opencode/skills/`. Load them when they apply to the documentation task at hand.
- **Write scope:** You may write to `/home/rich/git/docs/` from this repo as needed to complete documentation, but only within `scratch/`, `projects/`, and `docs/` (the docs site).
- **Never edit docs AGENTS directly:** Do not directly edit `/home/rich/git/docs/AGENTS.md`. If a change to its rules is warranted, propose a diff to the user.
- **Plan mode:** Writing and updating files under `/home/rich/git/docs/scratch/` is allowed in plan mode for real time notes. No need to run `make` in `scripts/` or `docs/` to do so.

## Scratchpads & Documentation Lifecycle
- **Scratch Phase:** For every new script or project, create/open the scratch file under the canonical docs location above. Record all errors encountered, attempted fixes, successes, failures, and technical notes.
- **Redaction Phase:** Once a script or tool is fully functional, redact and condense the scratch log into a structured, production-ready documentation file for that app or script following `/home/rich/git/docs/AGENTS.md`. Extract key lessons learned and append them to the repository's permanent guidelines only if appropriate. Only keep the redacted doc if it has reuse value; otherwise follow docs retention rules.
