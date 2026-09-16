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

# List order is priority order: the top task (position 1) is the highest
# priority. Moves an existing task to a 1-based position among all tasks.
move_task() {
  local id="$1" pos="$2" msg="$3"
  # id is spliced into a grep/awk regex below, so it must be numeric —
  # callers validate this too, but re-check here since this regex is
  # what actually decides which task gets moved.
  require_numeric_id "$id"
  grep -qE "^- \[[ x]\] #${id}([^0-9]|\$)" "$FILE" || { echo "No task #$id." >&2; exit 1; }

  local header=() tasks=() line idx=-1 i all_lines
  mapfile -t all_lines < "$FILE"
  for line in "${all_lines[@]}"; do
    if [[ "$line" =~ ^-\ \[[\ x]\]\ #[0-9]+ ]]; then
      tasks+=("$line")
    else
      header+=("$line")
    fi
  done

  for i in "${!tasks[@]}"; do
    if [[ "${tasks[$i]}" =~ ^-\ \[[\ x]\]\ #${id}([^0-9]|$) ]]; then
      idx=$i
      break
    fi
  done

  local task="${tasks[$idx]}"
  local rest=("${tasks[@]:0:$idx}" "${tasks[@]:$((idx + 1))}")
  local count=${#rest[@]}
  local total=$((count + 1))
  [ "$pos" -ge 1 ] || pos=1
  [ "$pos" -le "$total" ] || pos=$total

  local new_tasks=("${rest[@]:0:$((pos - 1))}" "$task" "${rest[@]:$((pos - 1))}")

  tmp=$(mktemp)
  [ "${#header[@]}" -gt 0 ] && printf '%s\n' "${header[@]}" >> "$tmp"
  [ "${#new_tasks[@]}" -gt 0 ] && printf '%s\n' "${new_tasks[@]}" >> "$tmp"
  mv "$tmp" "$FILE"
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
    task_lines=$(grep -E '^- \[[ x]\] #[0-9]+' "$FILE" || true)
    if [ -z "$task_lines" ]; then
      echo "Todo list is empty."
    else
      echo "$task_lines"
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
    tmp=$(mktemp)
    awk -v id="$id" '!($0 ~ ("^- \\[[ x]\\] #" id "([^0-9]|$)"))' "$FILE" > "$tmp" && mv "$tmp" "$FILE"
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
    tmp=$(mktemp)
    awk '!/^- \[x\]/' "$FILE" > "$tmp" && mv "$tmp" "$FILE"
    commit_change "Clear completed tasks"
    echo "Cleared completed tasks."
    ;;

  clear-all)
    tmp=$(mktemp)
    awk '!/^- \[[ x]\]/' "$FILE" > "$tmp" && mv "$tmp" "$FILE"
    commit_change "Clear all tasks"
    echo "Cleared all tasks."
    ;;

  *)
    usage
    ;;
esac
