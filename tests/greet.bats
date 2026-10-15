#!/usr/bin/env bash
# Example bats test for bin/greet.sh.
#
# Run: bats tests/greet.bats  (or: make test-bash)

setup() {
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "greets with default name" {
  run "${REPO_ROOT}/bin/greet.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello, World!"* ]]
}

@test "greets the given name" {
  run "${REPO_ROOT}/bin/greet.sh" --name Bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello, Bash!"* ]]
}

@test "shout uppercases the greeting" {
  run "${REPO_ROOT}/bin/greet.sh" --name Bash --shout
  [ "$status" -eq 0 ]
  [[ "$output" == *"HELLO, BASH!"* ]]
}

@test "rejects unknown options with exit 2" {
  run "${REPO_ROOT}/bin/greet.sh" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option"* ]]
}
