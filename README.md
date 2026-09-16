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

**From this local checkout** (while developing / for yourself):

```text
/plugin marketplace add /Users/matt-nix/Projects/claude-todo-plugin
/plugin install todo@todo-marketplace
```

**Once pushed to a git repo**, anyone can install it the same way by
pointing at the repo instead of a local path:

```text
/plugin marketplace add <your-org>/claude-todo-plugin
/plugin install todo@todo-marketplace
```

## How it works

- `skills/todo/SKILL.md` — a Claude Code Skill. Its `description` tells
  Claude when to trigger it (any todo-list-shaped request), and its body
  tells Claude how to translate that request into one of the subcommands
  below.
- `scripts/todo.sh` — the actual storage logic (add/list/done/undone/rm/
  clear), a plain bash + awk script with no dependencies. It initializes
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
| `list` | show all tasks with ids and status |
| `done <id>` | mark a task complete |
| `undone <id>` | mark a task incomplete again |
| `rm <id>` | delete a task |
| `move <id> <position>` | reprioritize (1 = top = highest priority) |
| `top <id>` | shortcut for `move <id> 1` |
| `bottom <id>` | move a task to the end of the list (lowest priority) |
| `clear-done` | remove all completed tasks |
| `clear-all` | wipe the whole list |
