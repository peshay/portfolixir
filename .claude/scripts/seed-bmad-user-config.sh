#!/usr/bin/env bash
#
# Seeds the gitignored `_bmad/config.user.toml` in a fresh clone.
#
# The BMAD installer writes its user-scope answers (user_name,
# communication_language, user_skill_level) to `_bmad/config.user.toml`,
# which is personal and gitignored ("Privacy And Disclosure" in AGENTS.md).
# A Claude Code web session starts from a fresh clone without it, so the
# renderer behind bmad-build and bmad-build-auto halts on
# "missing config value `communication_language`". The installer commits the
# same answers in its per-module config.yaml files; this script copies them
# into the user layer and adds nothing that is not already in the repository.
#
# It never overwrites an existing file, so a local checkout keeps its own
# answers.
#
# Usage: seed-bmad-user-config.sh <project-root>
set -euo pipefail

ROOT="${1:?usage: seed-bmad-user-config.sh <project-root>}"
TARGET="${ROOT}/_bmad/config.user.toml"

if [ -e "${TARGET}" ]; then
  exit 0
fi

# Prints the first top-level `key: value` of a module config.yaml, without
# surrounding quotes; prints nothing when the file or the key is absent.
yaml_value() {
  local file="$1" key="$2"
  [ -f "${file}" ] || return 0
  sed -n "/^${key}:/{s/^${key}:[[:space:]]*//;s/[[:space:]]*\$//;p;q;}" "${file}" \
    | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

# Prints `key = "value"` as a TOML basic string, or nothing for an empty value.
toml_line() {
  local key="$1" value="$2"
  [ -n "${value}" ] || return 0
  value="${value//\\/\\\\}"
  printf '%s = "%s"\n' "${key}" "${value//\"/\\\"}"
}

CORE="${ROOT}/_bmad/core/config.yaml"
BMM="${ROOT}/_bmad/bmm/config.yaml"

core_lines="$(
  toml_line user_name "$(yaml_value "${CORE}" user_name)"
  toml_line communication_language "$(yaml_value "${CORE}" communication_language)"
)"
bmm_lines="$(toml_line user_skill_level "$(yaml_value "${BMM}" user_skill_level)")"

if [ -z "${core_lines}" ] && [ -z "${bmm_lines}" ]; then
  exit 0
fi

{
  echo "# Seeded by .claude/scripts/seed-bmad-user-config.sh from the committed"
  echo "# _bmad/<module>/config.yaml answers. Personal and gitignored: never commit."
  if [ -n "${core_lines}" ]; then
    printf '\n[core]\n%s\n' "${core_lines}"
  fi
  if [ -n "${bmm_lines}" ]; then
    printf '\n[modules.bmm]\n%s\n' "${bmm_lines}"
  fi
} > "${TARGET}"
