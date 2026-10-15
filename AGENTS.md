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

## Development Workflow
- Always `cd` to the repository path before running repository actions.
- Always run local linters and tests (`make lint && make test`) and ensure
  they pass before presenting commit commands.
- Break work into clean, atomic commits with descriptive messages; one
  logical change per commit. Present them grouped, in order.

## Scratchpads & Documentation Lifecycle
- **Scratch Phase:** For every new script or project, open a scratch file to
  track progress in real time. Record all errors encountered, attempted
  fixes, successes, failures, and technical notes.
- **Redaction Phase:** Once a script or tool is fully functional, redact and
  condense the scratch log into a structured, production-ready documentation
  file for that app or script. Extract key lessons learned and append them
  to the repository's permanent guidelines. Only keep the redacted doc if it
  has reuse value (e.g. it lets you recreate the setup on another system);
  otherwise discard the scratch file.
