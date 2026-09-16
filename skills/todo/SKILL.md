---
description: Manage a persistent todo/task list for this project. Use whenever the user asks to add something to their todo list, view/check their tasks, mark something done, remove a task, reorder/reprioritize tasks, or clear the list — including casual phrasing like "add X to the todo list", "what's on my todo list", "mark #3 as done", "cross off Y", "clear my todos", "make X top priority", "bump Y down the list".
allowed-tools: Bash
---

# Todo list

A single, global todo list backed by a markdown file at `~/.todo/TODO.md`.
That directory is its own git repository, and every add/complete/reopen/
remove/clear runs a commit, so the full history of the list is preserved
and can be inspected with `git -C ~/.todo log` or `git -C ~/.todo log -p`.

Do not read or edit `TODO.md` directly — always go through the bundled
script so ids, formatting, and commits stay consistent:

```
${CLAUDE_PLUGIN_ROOT}/scripts/todo.sh <subcommand> [args]
```

Subcommands:
- `add <text>` — add a new task, e.g. `add Fix the login bug`
- `list` — show all tasks with their ids and status
- `done <id>` — mark a task complete
- `undone <id>` — mark a task incomplete again
- `rm <id>` — delete a task
- `move <id> <position>` — reprioritize a task to a 1-based position
  (position 1 = top = highest priority; list order *is* priority order)
- `top <id>` — shortcut for `move <id> 1`
- `bottom <id>` — move a task to the end (lowest priority)
- `clear-done` — remove all completed tasks
- `clear-all` — wipe the whole list

## How to respond to requests

Map the user's natural-language request to the right subcommand yourself —
they will rarely type exact command syntax. Examples:

- "add buy milk to my todo list" → `add buy milk`
- "what's on my todo list?" / "show my tasks" → `list`
- "mark #2 done" / "I finished the login fix" (referring to a listed task)
  → run `list` first if you don't already know the id, then `done <id>`
- "remove the third one" / "delete that task" → `rm <id>`
- "make #4 top priority" / "move fixing the bug to the top" → `top <id>`
- "deprioritize #2" / "move that to the bottom" → `bottom <id>`
- "move #3 to the second spot" → `move 3 2`
- "clear completed tasks" → `clear-done`
- "clear the whole list" / "start over" → confirm with the user first
  (destructive), then `clear-all`

After adding, completing, or removing a task, show the user the updated
`list` output so they can see current state. Keep responses short — this is
a lightweight task list, not a project management report.

## Requirements

This requires `git` on `PATH` (it's how history is preserved) — if the
script exits with a "requires git" error, tell the user to install git
rather than retrying.
