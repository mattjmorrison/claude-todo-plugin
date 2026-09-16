#!/usr/bin/env bash
# Global todo list stored as markdown at ~/.todo/TODO.md, version-controlled
# with git — every mutating command commits the change.
set -euo pipefail

DIR="$HOME/.todo"
FILE="$DIR/TODO.md"

require_git() {
  command -v git >/dev/null 2>&1 || {
    echo "todo plugin requires git (used to keep TODO.md's version history) but it isn't installed or isn't on PATH." >&2
    echo "Install git and try again." >&2
    exit 1
  }
}

init_store() {
  require_git
  mkdir -p "$DIR"
  if [ ! -d "$DIR/.git" ]; then
    git -C "$DIR" init -q
  fi
  # ensure a git identity exists (local override only if no global one is set)
  if ! git -C "$DIR" config user.email >/dev/null 2>&1; then
    git -C "$DIR" config user.email "todo-plugin@local"
  fi
  if ! git -C "$DIR" config user.name >/dev/null 2>&1; then
    git -C "$DIR" config user.name "Todo Plugin"
  fi
  if [ ! -f "$FILE" ]; then
    printf '# Todo\n\n' > "$FILE"
    git -C "$DIR" add TODO.md
    git -C "$DIR" commit -q -m "Initialize todo list"
  fi
}

commit_change() {
  local msg="$1"
  git -C "$DIR" add TODO.md
  if ! git -C "$DIR" diff --cached --quiet; then
    git -C "$DIR" commit -q -m "$msg"
  fi
}

next_id() {
  local max=0 n ids
  mapfile -t ids < <(grep -oE '^- \[[ x]\] #[0-9]+' "$FILE" 2>/dev/null | grep -oE '[0-9]+')
  for n in "${ids[@]}"; do
    [ -n "$n" ] && [ "$n" -gt "$max" ] && max="$n"
  done
  echo $((max + 1))
}

# A task's checkbox line ("- [ ] #N ..." / "- [x] #N ...") is its title.
# Everything after that line, up to the next checkbox line (or EOF), is that
# task's body and travels with it as a single unit — verbatim, whatever
# markdown it contains (lists, fences, headings, blank lines, ...).
#
# Splits $FILE into `header_lines` (any lines before the first task) and
# `task_blocks` (one array element per task, title + body joined by real
# newlines). Callers further down operate on `task_blocks` and then call
# write_blocks to persist the result.
split_into_blocks() {
  header_lines=()
  task_blocks=()
  local in_task=0 current="" line all_lines
  mapfile -t all_lines < "$FILE"
  for line in "${all_lines[@]}"; do
    if [[ "$line" =~ ^-\ \[[\ x]\]\ #[0-9]+ ]]; then
      if [ "$in_task" -eq 1 ]; then task_blocks+=("$current"); fi
      current="$line"
      in_task=1
    elif [ "$in_task" -eq 1 ]; then
      current+=$'\n'"$line"
    else
      header_lines+=("$line")
    fi
  done
  if [ "$in_task" -eq 1 ]; then task_blocks+=("$current"); fi
}

write_blocks() {
  local tmp
  tmp=$(mktemp)
  [ "${#header_lines[@]}" -gt 0 ] && printf '%s\n' "${header_lines[@]}" >> "$tmp"
  local b
  for b in "${task_blocks[@]}"; do
    printf '%s\n' "$b" >> "$tmp"
  done
  mv "$tmp" "$FILE"
}

# List order is priority order: the top task (position 1) is the highest
# priority. Moves an existing task (title + body, as one unit) to a 1-based
# position among all tasks.
move_task() {
  local id="$1" pos="$2" msg="$3"
  # id is spliced into a grep/regex below, so it must be numeric —
  # callers validate this too, but re-check here since this regex is
  # what actually decides which task gets moved.
  require_numeric_id "$id"
  grep -qE "^- \[[ x]\] #${id}([^0-9]|\$)" "$FILE" || { echo "No task #$id." >&2; exit 1; }

  split_into_blocks
  local idx=-1 i
  for i in "${!task_blocks[@]}"; do
    if [[ "${task_blocks[$i]}" =~ ^-\ \[[\ x]\]\ #${id}([^0-9]|$) ]]; then
      idx=$i
      break
    fi
  done

  local task="${task_blocks[$idx]}"
  local rest=("${task_blocks[@]:0:$idx}" "${task_blocks[@]:$((idx + 1))}")
  local count=${#rest[@]}
  local total=$((count + 1))
  [ "$pos" -ge 1 ] || pos=1
  [ "$pos" -le "$total" ] || pos=$total

  task_blocks=("${rest[@]:0:$((pos - 1))}" "$task" "${rest[@]:$((pos - 1))}")
  write_blocks
  commit_change "$msg"
  echo "Moved #$id to position $pos."
}

require_numeric_id() {
  [[ "$1" =~ ^[0-9]+$ ]] || { echo "No task #$1." >&2; exit 1; }
}

usage() {
  echo "Usage: todo.sh {add <text>|list|done <id>|undone <id>|rm <id>|move <id> <position>|top <id>|bottom <id>|clear-done|clear-all}" >&2
  exit 1
}

init_store

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift || true

case "$cmd" in
  add)
    text="$*"
    [ -n "$text" ] || { echo "Nothing to add." >&2; exit 1; }
    id=$(next_id)
    printf -- "- [ ] #%s %s\n" "$id" "$text" >> "$FILE"
    commit_change "Add #$id: $text"
    echo "Added #$id: $text"
    ;;

  list)
    split_into_blocks
    if [ "${#task_blocks[@]}" -eq 0 ]; then
      echo "Todo list is empty."
    else
      printf '%s\n' "${task_blocks[@]}"
    fi
    ;;

  done)
    id="${1:-}"
    [ -n "$id" ] || { echo "Which task id?" >&2; exit 1; }
    require_numeric_id "$id"
    grep -qE "^- \[[ x]\] #${id}([^0-9]|\$)" "$FILE" || { echo "No task #$id." >&2; exit 1; }
    tmp=$(mktemp)
    awk -v id="$id" '{
      if ($0 ~ ("^- \\[[ x]\\] #" id "([^0-9]|$)")) sub(/\[[ x]\]/, "[x]")
      print
    }' "$FILE" > "$tmp" && mv "$tmp" "$FILE"
    commit_change "Complete #$id"
    echo "Marked #$id done."
    ;;

  undone)
    id="${1:-}"
    [ -n "$id" ] || { echo "Which task id?" >&2; exit 1; }
    require_numeric_id "$id"
    grep -qE "^- \[[ x]\] #${id}([^0-9]|\$)" "$FILE" || { echo "No task #$id." >&2; exit 1; }
    tmp=$(mktemp)
    awk -v id="$id" '{
      if ($0 ~ ("^- \\[[ x]\\] #" id "([^0-9]|$)")) sub(/\[[ x]\]/, "[ ]")
      print
    }' "$FILE" > "$tmp" && mv "$tmp" "$FILE"
    commit_change "Reopen #$id"
    echo "Marked #$id pending."
    ;;

  rm)
    id="${1:-}"
    [ -n "$id" ] || { echo "Which task id?" >&2; exit 1; }
    require_numeric_id "$id"
    grep -qE "^- \[[ x]\] #${id}([^0-9]|\$)" "$FILE" || { echo "No task #$id." >&2; exit 1; }
    split_into_blocks
    kept=()
    for b in "${task_blocks[@]}"; do
      [[ "$b" =~ ^-\ \[[\ x]\]\ #${id}([^0-9]|$) ]] && continue
      kept+=("$b")
    done
    task_blocks=("${kept[@]}")
    write_blocks
    commit_change "Remove #$id"
    echo "Removed #$id."
    ;;

  move)
    id="${1:-}"; pos="${2:-}"
    [ -n "$id" ] || { echo "Which task id?" >&2; exit 1; }
    require_numeric_id "$id"
    [[ "$pos" =~ ^[0-9]+$ ]] || { echo "Which position (1 = top)?" >&2; exit 1; }
    move_task "$id" "$pos" "Move #$id to position $pos"
    ;;

  top)
    id="${1:-}"
    [ -n "$id" ] || { echo "Which task id?" >&2; exit 1; }
    require_numeric_id "$id"
    move_task "$id" 1 "Move #$id to top"
    ;;

  bottom)
    id="${1:-}"
    [ -n "$id" ] || { echo "Which task id?" >&2; exit 1; }
    require_numeric_id "$id"
    move_task "$id" 999999999 "Move #$id to bottom"
    ;;

  clear-done)
    split_into_blocks
    kept=()
    for b in "${task_blocks[@]}"; do
      [[ "$b" =~ ^-\ \[x\] ]] && continue
      kept+=("$b")
    done
    task_blocks=("${kept[@]}")
    write_blocks
    commit_change "Clear completed tasks"
    echo "Cleared completed tasks."
    ;;

  clear-all)
    split_into_blocks
    task_blocks=()
    write_blocks
    commit_change "Clear all tasks"
    echo "Cleared all tasks."
    ;;

  *)
    usage
    ;;
esac
