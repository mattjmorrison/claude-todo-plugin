# todo (Claude Code plugin)

A single, global todo list you manage entirely in natural language inside
Claude Code — no separate app, no exact command syntax required.

```text
you: add "write the release notes" to the todo list
you: what's on my todo list?
you: mark #2 done
you: clear the completed ones
```

Tasks live in a markdown file at `~/.todo/TODO.md`. That directory is a git
repository, and every change (add, complete, reopen, remove, clear) is
committed automatically, so the full history of your todo list is
preserved — run `git -C ~/.todo log -p` any time to see what changed and
when. You can also invoke it explicitly as a slash command, e.g.
`/todo:todo list`.

## Requirements

- `git` — required. `TODO.md` lives in a git repo at `~/.todo` and every
  add/complete/reopen/remove/clear is committed there to preserve history;
  this is the plugin's whole reason for existing, so git isn't optional.
  If `git` isn't on `PATH`, the script exits immediately with a clear error
  instead of failing partway through a mutation.
- `bash` and `awk` (present by default on macOS and Linux).

## Install

```text
/plugin marketplace add mattjmorrison/claude-todo-plugin
/plugin install todo@todo-marketplace
```

**From a local checkout** (while developing):

```text
/plugin marketplace add /path/to/claude-todo-plugin
/plugin install todo@todo-marketplace
```

## How it works

- `skills/todo/SKILL.md` — a Claude Code Skill. Its `description` tells
  Claude when to trigger it (any todo-list-shaped request), and its body
  tells Claude how to translate that request into one of the subcommands
  below.
- `scripts/todo.sh` — the actual storage logic (add/list/edit/set-body/
  append-body/done/undone/rm/move/clear), a plain bash + awk script with no
  dependencies. It initializes
  `~/.todo` as a git repo on first use and commits `TODO.md` after every
  mutating command, so ids, formatting, and history all stay consistent no
  matter how Claude phrases the call.

## Tests

`scripts/todo.sh` has a [bats](https://github.com/bats-core/bats-core) unit
test suite covering every subcommand, error path, and the git-commit
behavior. Install bats and run:

```bash
nix-shell -p bats --run 'bats tests/todo.bats'
# or, if you have bats installed some other way:
bats tests/todo.bats
```

## Subcommands

| Command | Effect |
| --- | --- |
| `add <text>` | add a new task |
| `list` | show all tasks with ids, status, and body |
| `edit <id> <text>` | rename a task's title |
| `set-body <id> [text]` | replace a task's markdown body (omit to clear) |
| `append-body <id> <text>` | add more markdown to a task's existing body |
| `done <id>` | mark a task complete |
| `undone <id>` | mark a task incomplete again |
| `rm <id>` | delete a task |
| `move <id> <position>` | reprioritize (1 = top = highest priority) |
| `top <id>` | shortcut for `move <id> 1` |
| `bottom <id>` | move a task to the end of the list (lowest priority) |
| `before <id> <target-id>` | move a task to sit immediately above another |
| `after <id> <target-id>` | move a task to sit immediately below another |
| `clear-done` | remove all completed tasks |
| `clear-all` | wipe the whole list |
