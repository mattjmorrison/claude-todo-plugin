#!/usr/bin/env bats
# Unit tests for scripts/todo.sh
# Run with: bats tests/todo.bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/todo.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  STORE="$HOME/.todo"
  FILE="$STORE/TODO.md"
}

commit_count() {
  git -C "$STORE" log --oneline | wc -l | tr -d ' '
}

# --- initialization -------------------------------------------------------

@test "first invocation initializes a git repo and TODO.md" {
  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  [ -d "$STORE/.git" ]
  [ -f "$FILE" ]
  grep -q '^# Todo' "$FILE"
  [ "$(commit_count)" -eq 1 ]
  git -C "$STORE" log -1 --format=%s | grep -q "Initialize todo list"
}

@test "initialization sets a local git identity when none is configured" {
  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  run git -C "$STORE" config user.email
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run git -C "$STORE" config user.name
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "second invocation does not re-run initialization" {
  "$SCRIPT" list
  before=$(commit_count)
  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  [ "$(commit_count)" -eq "$before" ]
}

# --- add --------------------------------------------------------------

@test "add creates task #1 and commits it" {
  run "$SCRIPT" add "write release notes"
  [ "$status" -eq 0 ]
  [[ "$output" == "Added #1: write release notes" ]]
  grep -qF -- "- [ ] #1 write release notes" "$FILE"
  git -C "$STORE" log -1 --format=%s | grep -qF "Add #1: write release notes"
}

@test "add increments ids across multiple tasks" {
  "$SCRIPT" add "first" >/dev/null
  "$SCRIPT" add "second" >/dev/null
  run "$SCRIPT" add "third"
  [ "$status" -eq 0 ]
  [[ "$output" == "Added #3: third" ]]
  grep -qF -- "- [ ] #1 first" "$FILE"
  grep -qF -- "- [ ] #2 second" "$FILE"
  grep -qF -- "- [ ] #3 third" "$FILE"
}

@test "add ignores id-like numbers inside other tasks' text when computing the next id" {
  "$SCRIPT" add "write release notes" >/dev/null
  "$SCRIPT" add "read PR #100" >/dev/null
  run "$SCRIPT" add "third task"
  [ "$status" -eq 0 ]
  [[ "$output" == "Added #3: third task" ]]
}

@test "add with no text fails and does not commit" {
  "$SCRIPT" list >/dev/null
  before=$(commit_count)
  run "$SCRIPT" add
  [ "$status" -ne 0 ]
  [[ "$output" == *"Nothing to add"* ]]
  [ "$(commit_count)" -eq "$before" ]
}

# --- list ---------------------------------------------------------------

@test "list on an empty todo list says so" {
  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  [[ "$output" == "Todo list is empty." ]]
}

@test "list shows pending and done tasks with checkboxes" {
  "$SCRIPT" add "task a" >/dev/null
  "$SCRIPT" add "task b" >/dev/null
  "$SCRIPT" done 1 >/dev/null
  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[x] #1 task a"* ]]
  [[ "$output" == *"[ ] #2 task b"* ]]
}

# --- done / undone --------------------------------------------------------

@test "done marks the matching task complete and commits" {
  "$SCRIPT" add "task a" >/dev/null
  run "$SCRIPT" done 1
  [ "$status" -eq 0 ]
  [[ "$output" == "Marked #1 done." ]]
  grep -qF -- "- [x] #1 task a" "$FILE"
  git -C "$STORE" log -1 --format=%s | grep -qF "Complete #1"
}

@test "done does not corrupt a task whose id is a prefix of another (#1 vs #10)" {
  for i in $(seq 1 10); do "$SCRIPT" add "task $i" >/dev/null; done
  run "$SCRIPT" done 1
  [ "$status" -eq 0 ]
  grep -qF -- "- [x] #1 task 1" "$FILE"
  grep -qF -- "- [ ] #10 task 10" "$FILE"
}

@test "done on a nonexistent id fails without committing" {
  "$SCRIPT" add "task a" >/dev/null
  before=$(commit_count)
  run "$SCRIPT" done 99
  [ "$status" -ne 0 ]
  [[ "$output" == *"No task #99"* ]]
  [ "$(commit_count)" -eq "$before" ]
}

@test "done without an id fails" {
  run "$SCRIPT" done
  [ "$status" -ne 0 ]
  [[ "$output" == *"Which task id?"* ]]
}

@test "undone reopens a completed task and commits" {
  "$SCRIPT" add "task a" >/dev/null
  "$SCRIPT" done 1 >/dev/null
  run "$SCRIPT" undone 1
  [ "$status" -eq 0 ]
  [[ "$output" == "Marked #1 pending." ]]
  grep -qF -- "- [ ] #1 task a" "$FILE"
  git -C "$STORE" log -1 --format=%s | grep -qF "Reopen #1"
}

@test "undone on a nonexistent id fails" {
  run "$SCRIPT" undone 99
  [ "$status" -ne 0 ]
  [[ "$output" == *"No task #99"* ]]
}

# --- rm -------------------------------------------------------------------

@test "rm removes the matching task and commits" {
  "$SCRIPT" add "task a" >/dev/null
  "$SCRIPT" add "task b" >/dev/null
  run "$SCRIPT" rm 1
  [ "$status" -eq 0 ]
  [[ "$output" == "Removed #1." ]]
  ! grep -qF -- "#1 task a" "$FILE"
  grep -qF -- "- [ ] #2 task b" "$FILE"
  git -C "$STORE" log -1 --format=%s | grep -qF "Remove #1"
}

@test "rm on a nonexistent id fails without committing" {
  "$SCRIPT" add "task a" >/dev/null
  before=$(commit_count)
  run "$SCRIPT" rm 99
  [ "$status" -ne 0 ]
  [[ "$output" == *"No task #99"* ]]
  [ "$(commit_count)" -eq "$before" ]
}

@test "rm without an id fails" {
  run "$SCRIPT" rm
  [ "$status" -ne 0 ]
  [[ "$output" == *"Which task id?"* ]]
}

# --- clear-done / clear-all -----------------------------------------------

@test "clear-done removes only completed tasks and commits" {
  "$SCRIPT" add "task a" >/dev/null
  "$SCRIPT" add "task b" >/dev/null
  "$SCRIPT" done 1 >/dev/null
  run "$SCRIPT" clear-done
  [ "$status" -eq 0 ]
  [[ "$output" == "Cleared completed tasks." ]]
  ! grep -qF -- "#1" "$FILE"
  grep -qF -- "- [ ] #2 task b" "$FILE"
  git -C "$STORE" log -1 --format=%s | grep -qF "Clear completed tasks"
}

@test "clear-done with nothing completed does not create an empty commit" {
  "$SCRIPT" add "task a" >/dev/null
  before=$(commit_count)
  run "$SCRIPT" clear-done
  [ "$status" -eq 0 ]
  [ "$(commit_count)" -eq "$before" ]
}

@test "clear-all wipes every task and commits" {
  "$SCRIPT" add "task a" >/dev/null
  "$SCRIPT" add "task b" >/dev/null
  "$SCRIPT" done 1 >/dev/null
  run "$SCRIPT" clear-all
  [ "$status" -eq 0 ]
  [[ "$output" == "Cleared all tasks." ]]
  run "$SCRIPT" list
  [[ "$output" == "Todo list is empty." ]]
  git -C "$STORE" log -1 --format=%s | grep -qF "Clear all tasks"
}

# --- misc -------------------------------------------------------------------

@test "an unknown subcommand prints usage and fails" {
  run "$SCRIPT" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: todo.sh"* ]]
}

@test "invoking with no subcommand prints usage and fails" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: todo.sh"* ]]
}

# --- move / top / bottom (priority ordering) -------------------------------

@test "top moves a task to position 1 and commits" {
  "$SCRIPT" add "one" >/dev/null
  "$SCRIPT" add "two" >/dev/null
  "$SCRIPT" add "three" >/dev/null
  run "$SCRIPT" top 3
  [ "$status" -eq 0 ]
  [[ "$output" == "Moved #3 to position 1." ]]
  run "$SCRIPT" list
  [[ "${lines[0]}" == "- [ ] #3 three" ]]
  [[ "${lines[1]}" == "- [ ] #1 one" ]]
  [[ "${lines[2]}" == "- [ ] #2 two" ]]
  git -C "$STORE" log -1 --format=%s | grep -qF "Move #3 to top"
}

@test "bottom moves a task to the last position" {
  "$SCRIPT" add "one" >/dev/null
  "$SCRIPT" add "two" >/dev/null
  "$SCRIPT" add "three" >/dev/null
  run "$SCRIPT" bottom 1
  [ "$status" -eq 0 ]
  [[ "$output" == "Moved #1 to position 3." ]]
  run "$SCRIPT" list
  [[ "${lines[2]}" == "- [ ] #1 one" ]]
  git -C "$STORE" log -1 --format=%s | grep -qF "Move #1 to bottom"
}

@test "move places a task at an arbitrary position" {
  "$SCRIPT" add "one" >/dev/null
  "$SCRIPT" add "two" >/dev/null
  "$SCRIPT" add "three" >/dev/null
  run "$SCRIPT" move 3 2
  [ "$status" -eq 0 ]
  [[ "$output" == "Moved #3 to position 2." ]]
  run "$SCRIPT" list
  [[ "${lines[0]}" == "- [ ] #1 one" ]]
  [[ "${lines[1]}" == "- [ ] #3 three" ]]
  [[ "${lines[2]}" == "- [ ] #2 two" ]]
}

@test "move clamps a position beyond the list length to the last slot" {
  "$SCRIPT" add "one" >/dev/null
  "$SCRIPT" add "two" >/dev/null
  run "$SCRIPT" move 1 999
  [ "$status" -eq 0 ]
  [[ "$output" == "Moved #1 to position 2." ]]
  run "$SCRIPT" list
  [[ "${lines[0]}" == "- [ ] #2 two" ]]
  [[ "${lines[1]}" == "- [ ] #1 one" ]]
}

@test "move clamps a position below 1 to the top" {
  "$SCRIPT" add "one" >/dev/null
  "$SCRIPT" add "two" >/dev/null
  run "$SCRIPT" move 2 0
  [ "$status" -eq 0 ]
  run "$SCRIPT" list
  [[ "${lines[0]}" == "- [ ] #2 two" ]]
}

@test "move preserves done/pending status of the moved task" {
  "$SCRIPT" add "one" >/dev/null
  "$SCRIPT" add "two" >/dev/null
  "$SCRIPT" done 1 >/dev/null
  "$SCRIPT" move 1 2 >/dev/null
  run "$SCRIPT" list
  [[ "${lines[1]}" == "- [x] #1 one" ]]
}

@test "move on a nonexistent id fails without committing" {
  "$SCRIPT" add "one" >/dev/null
  before=$(commit_count)
  run "$SCRIPT" move 99 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"No task #99"* ]]
  [ "$(commit_count)" -eq "$before" ]
}

@test "move with a non-numeric position fails" {
  "$SCRIPT" add "one" >/dev/null
  run "$SCRIPT" move 1 abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"Which position"* ]]
}

@test "done rejects a non-numeric id instead of matching every task" {
  "$SCRIPT" add "one" >/dev/null
  "$SCRIPT" add "two" >/dev/null
  "$SCRIPT" add "three" >/dev/null
  run "$SCRIPT" done ".*"
  [ "$status" -ne 0 ]
  run "$SCRIPT" list
  [[ "$output" == *"[ ] #1 one"* ]]
  [[ "$output" == *"[ ] #2 two"* ]]
  [[ "$output" == *"[ ] #3 three"* ]]
}

@test "move/top/bottom reject a non-numeric id instead of matching every task" {
  "$SCRIPT" add "one" >/dev/null
  "$SCRIPT" add "two" >/dev/null
  "$SCRIPT" add "three" >/dev/null

  run "$SCRIPT" move ".*" 1
  [ "$status" -ne 0 ]
  run "$SCRIPT" top ".*"
  [ "$status" -ne 0 ]
  run "$SCRIPT" bottom ".*"
  [ "$status" -ne 0 ]

  run "$SCRIPT" list
  [[ "${lines[0]}" == "- [ ] #1 one" ]]
  [[ "${lines[1]}" == "- [ ] #2 two" ]]
  [[ "${lines[2]}" == "- [ ] #3 three" ]]
}

@test "top/bottom without an id fail" {
  run "$SCRIPT" top
  [ "$status" -ne 0 ]
  [[ "$output" == *"Which task id?"* ]]
  run "$SCRIPT" bottom
  [ "$status" -ne 0 ]
  [[ "$output" == *"Which task id?"* ]]
}

# --- missing git ----------------------------------------------------------

@test "fails with a clear message when git is not on PATH" {
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  for c in bash awk grep mktemp mv tr wc seq cat printf sh env; do
    real=$(command -v "$c")
    ln -s "$real" "$fakebin/$c"
  done
  PATH="$fakebin" run "$SCRIPT" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires git"* ]]
  [ ! -d "$STORE" ]
}

@test "history survives across a full lifecycle" {
  "$SCRIPT" add "ship the plugin" >/dev/null
  "$SCRIPT" done 1 >/dev/null
  "$SCRIPT" undone 1 >/dev/null
  "$SCRIPT" rm 1 >/dev/null
  # init + add + done + undone + rm = 5 commits
  [ "$(commit_count)" -eq 5 ]
  run git -C "$STORE" log --oneline
  [[ "$output" == *"Remove #1"* ]]
  [[ "$output" == *"Reopen #1"* ]]
  [[ "$output" == *"Complete #1"* ]]
  [[ "$output" == *"Add #1: ship the plugin"* ]]
  [[ "$output" == *"Initialize todo list"* ]]
}
