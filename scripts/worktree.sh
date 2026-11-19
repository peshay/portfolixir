#!/usr/bin/env bash
# Create a linked git worktree for a story, the way Portfolixir's sprints use
# them.
#
#   scripts/worktree.sh add <path> <base-ref> [branch] [--db <name>]
#
# * The base ref is required, never implied: agent worktrees that started
#   from `main` instead of the sprint branch opened on the wrong base
#   (Sprint 18 retrospective). Without a branch the worktree is detached at
#   the base.
# * `deps` and `mcp-server/node_modules` become symlinks to the main
#   checkout's: they are read-only inputs, and fetching them again per
#   worktree costs minutes. `_build` stays the worktree's own directory,
#   because two checkouts compiling into one `_build` at once corrupt it.
# * The links are kept out of every commit: the repository's .gitignore says
#   `/deps/`, and a pattern with a trailing slash matches only a directory,
#   never a symlink, which is how a Sprint 22 worktree commit tracked the
#   `deps` symlink and cherry-picking it replaced the main checkout's `deps`
#   (Sprint 22 retrospective). So the helper writes `/deps`, `/_build`,
#   `node_modules` and `/mcp-server/node_modules`, without the slash, into
#   the exclude file. Git has no per-worktree exclude file: `info/exclude`
#   is read from the common git directory, which every worktree shares (see
#   gitrepository-layout), so the lines go there, appended only when absent.
#   They are harmless in the main checkout, whose `deps` is a directory the
#   .gitignore already ignores. The pre-commit hook `no-symlinks`
#   (scripts/check_no_symlinks.py) refuses a tracked symlink in any case.
# * The gettext merge driver, scripts/merge_gettext.py, is registered where
#   every worktree starts: `merge.gettext.name` and `merge.gettext.driver`
#   in the repository's local config, and the two lines that route
#   `priv/gettext` to it in `info/attributes`, both in the common git
#   directory every worktree shares, each written only when absent (an
#   existing value is the owner's and stays). Nothing is committed: a driver
#   needs a command on the machine (docs/development/guide.md, "Integrating
#   gettext catalogues"). *Why:* the resolver existed since Sprint 22, but
#   nothing registered it, so a Sprint 29 session wrote a second one
#   (Sprint 29 retrospective, carry-forward 3; Sprint 30 plan M3).
# * Each worktree that runs `mix test` at the same time as another needs a
#   test database of its own. The helper prints the commands; `--db <name>`
#   runs them in the new worktree.
set -euo pipefail

usage() {
  echo "usage: scripts/worktree.sh add <path> <base-ref> [branch] [--db <name>]" >&2
  exit 2
}

[[ $# -ge 1 && "$1" == "add" ]] || usage
shift

database=""
positionals=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)
      [[ $# -ge 2 ]] || usage
      database="$2"
      shift 2
      ;;
    -*)
      usage
      ;;
    *)
      positionals+=("$1")
      shift
      ;;
  esac
done

if [[ ${#positionals[@]} -lt 2 ]]; then
  echo "worktree.sh: name the base ref; a worktree never starts from main implicitly" >&2
  usage
fi
[[ ${#positionals[@]} -le 3 ]] || usage

path="${positionals[0]}"
base="${positionals[1]}"
branch="${positionals[2]:-}"

if ! base_commit="$(git rev-parse --verify --quiet "${base}^{commit}")"; then
  echo "worktree.sh: the base ref '${base}' names no commit" >&2
  exit 1
fi

# The main checkout is the first entry `git worktree list` prints.
main_checkout="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"

if [[ -n "$branch" ]]; then
  git worktree add -b "$branch" "$path" "$base_commit"
else
  git worktree add --detach "$path" "$base_commit"
fi
path="$(cd "$path" && pwd -P)"

for shared in deps mcp-server/node_modules; do
  if [[ -e "$main_checkout/$shared" && ! -e "$path/$shared" && ! -L "$path/$shared" ]]; then
    mkdir -p "$(dirname "$path/$shared")"
    ln -s "$main_checkout/$shared" "$path/$shared"
    echo "linked $shared -> $main_checkout/$shared"
  fi
done

# Appends a line to a file when the file lacks it, keeping the file's last
# line intact if it has no final newline.
append_once() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -qxF -- "$line" "$file"; then
    if [[ -s "$file" && -n "$(tail -c 1 "$file")" ]]; then
      echo >> "$file"
    fi
    echo "$line" >> "$file"
  fi
}

exclude="$(git -C "$path" rev-parse --path-format=absolute --git-path info/exclude)"
for pattern in /deps /_build node_modules /mcp-server/node_modules; do
  append_once "$exclude" "$pattern"
done

if ! git -C "$path" config --local --get merge.gettext.name > /dev/null; then
  git -C "$path" config --local merge.gettext.name "gettext catalogue merge"
fi
if ! git -C "$path" config --local --get merge.gettext.driver > /dev/null; then
  git -C "$path" config --local merge.gettext.driver "python3 scripts/merge_gettext.py %O %A %B"
fi
attributes="$(git -C "$path" rev-parse --path-format=absolute --git-path info/attributes)"
for line in "priv/gettext/**/*.po merge=gettext" "priv/gettext/*.pot merge=gettext"; do
  append_once "$attributes" "$line"
done

name="${database:-portfolixir_test_<n>}"
if [[ -n "$database" ]]; then
  (
    cd "$path"
    DATABASE_NAME="$database" MIX_ENV=test mix ecto.create
    DATABASE_NAME="$database" MIX_ENV=test mix ecto.migrate
  )
  echo "test database $database created and migrated"
else
  # %q quotes the path, so a path with a space copies into a valid command.
  cat <<EOF
A test database of the worktree's own, once, before its first mix test:
  cd $(printf '%q' "$path")
  DATABASE_NAME=$name MIX_ENV=test mix ecto.create
  DATABASE_NAME=$name MIX_ENV=test mix ecto.migrate
EOF
fi
echo "then: DATABASE_NAME=$name mix test"
