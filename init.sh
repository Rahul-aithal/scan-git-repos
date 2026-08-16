#!/usr/bin/env bash
#
# scan-git-repos.sh
#
# Walks through every subdirectory of the given directory (default: ~/code)
# and classifies each into one of:
#
#   1. Committed & Pushed        — clean tree, in sync with remote
#   2. Committed but NOT Pushed  — clean tree, local commits not yet pushed
#   3. Not Committed / Unstaged  — working tree has uncommitted changes
#   4. Committed but No Remote   — clean tree, no remote configured
#   5. Not a Git Repository      — directory is not under version control
#
# Also checks for .env files without a corresponding .env.example file.
#
# Usage:  ./scan-git-repos.sh [path-to-code-dir]
#

CODE_DIR="${1:-$HOME/code}"

[ -d "$CODE_DIR" ] || {
  echo "Error: '$CODE_DIR' is not a directory." >&2
  exit 1
}

shopt -s nullglob # empty glob → nothing, not a literal pattern

# ── Buckets ──────────────────────────────────────────────────────────────────
PUSHED=()
NOT_PUSHED=()
NOT_COMMITTED=()
NO_REMOTE=()
NO_GIT=()

# ── Classify each subdirectory ───────────────────────────────────────────────
for dir in "$CODE_DIR"/*/; do
  name="$(basename "$dir")"
  [[ "$name" == .* ]] && continue # skip hidden dirs

  # 1. Is it a git repo at all?
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    NO_GIT+=("$name")
    continue
  fi

  # ── .env File Check ──────────────────────────────────────────────────────
  # Look for any .env file, but ignore .env.example, .env.sample, etc.
  # Also ignore .envrc (used by direnv) and .env.d directories.
  env_warning=""
  has_env=false
  has_example=false

  for envfile in "$dir"/.env*; do
    base="$(basename "$envfile")"
    case "$base" in
    .env.example | .env.sample | .env.template | .env.dist)
      has_example=true
      ;;
    .envrc | .env.d)
      ;; # ignore
    *)
      has_env=true
      ;;
    esac
  done

  # If it has an actual .env but no example/template, flag it
  if [ "$has_env" = true ] && [ "$has_example" = false ]; then
    env_warning=" [⚠️ Missing .env.example]"
  fi
  # ─────────────────────────────────────────────────────────────────────────

  # 2. Are there uncommitted / unstaged / untracked changes?
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    NOT_COMMITTED+=("$name$env_warning")
    continue
  fi

  # 3. Does it have any remote configured?
  if [ -z "$(git -C "$dir" remote)" ]; then
    NO_REMOTE+=("$name$env_warning")
    continue
  fi

  # 4. Does the current branch track an upstream?
  upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

  if [ -z "$upstream" ]; then
    NOT_PUSHED+=("$name$env_warning  [remote exists, but no upstream branch set]")
    continue
  fi

  # 5. Compare local HEAD ↔ upstream
  ahead="$(git -C "$dir" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  behind="$(git -C "$dir" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"

  if [ "$ahead" -gt 0 ]; then
    NOT_PUSHED+=("$name$env_warning  [${ahead} commit(s) ahead of remote]")
  elif [ "$behind" -gt 0 ]; then
    NOT_PUSHED+=("$name$env_warning  [${behind} commit(s) behind — pull needed]")
  else
    PUSHED+=("$name$env_warning")
  fi
done

# ── Pretty-print ─────────────────────────────────────────────────────────────
show() {
  local title="$1"
  shift
  echo
  echo "══════════════════════════════════════════════════════════════"
  echo "  $title   ($#)"
  echo "══════════════════════════════════════════════════════════════"
  if [ "$#" -eq 0 ]; then
    echo "    (none)"
  else
    for r in "$@"; do
      printf '    • %s\n' "$r"
    done
  fi
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Git Repo Scanner — scanning: $CODE_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"

show "✓  Committed & Pushed" "${PUSHED[@]}"
show "⚠  Committed but NOT Pushed" "${NOT_PUSHED[@]}"
show "✎  Not Committed / Unstaged" "${NOT_COMMITTED[@]}"
show "⇄  Committed but No Remote" "${NO_REMOTE[@]}"
show "⊘  Not a Git Repository" "${NO_GIT[@]}"

echo
echo "────────────────────────────────────────────────────────────────"
echo "  Summary:  Pushed=${#PUSHED[@]}  NotPushed=${#NOT_PUSHED[@]}  Dirty=${#NOT_COMMITTED[@]}  NoRemote=${#NO_REMOTE[@]}  NoGit=${#NO_GIT[@]}"
echo "────────────────────────────────────────────────────────────────"
echo
