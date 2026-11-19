#!/usr/bin/env bash
# Fast-forward main from upstream and rebase nst-patches and feature/* on it.
#
# Environment:
#   UPSTREAM_URL  upstream repository (default https://github.com/SINTEF/pyopia.git)
#   DRY_RUN=1     report what would happen without pushing
#   REPORT_DIR    where the report files go (default ./sync-report)
#
# Report files (one branch name per line):
#   conflicts.txt  rebase onto main failed; branch left untouched
#   merged.txt     branch has nothing left after the rebase, so upstream
#                  probably contains it already
#   rebased.txt    branch was rebased and pushed
#   clean.txt      branch needed no change
#   diverged.txt   main is not an ancestor of upstream main; main left alone
#   upstream.txt   the upstream main commit this run synced to
set -euo pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/SINTEF/pyopia.git}
REPORT_DIR=${REPORT_DIR:-sync-report}
DRY_RUN=${DRY_RUN:-0}
mkdir -p "$REPORT_DIR"
: > "$REPORT_DIR/conflicts.txt"; : > "$REPORT_DIR/merged.txt"
: > "$REPORT_DIR/rebased.txt"; : > "$REPORT_DIR/clean.txt"
: > "$REPORT_DIR/diverged.txt"

push() { if [ "$DRY_RUN" = 1 ]; then echo "(dry run) git push $*"; else git push "$@"; fi; }

git remote remove upstream 2>/dev/null || true
git remote add upstream "$UPSTREAM_URL"
git fetch -q upstream main
git fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
upstream_sha=$(git rev-parse upstream/main)
echo "$upstream_sha" > "$REPORT_DIR/upstream.txt"

# 1. main follows upstream by fast-forward only.
main_sha=$(git rev-parse origin/main)
if [ "$main_sha" = "$upstream_sha" ]; then
  echo "main already at upstream $upstream_sha"
elif git merge-base --is-ancestor "$main_sha" "$upstream_sha"; then
  echo "Fast-forwarding main $main_sha -> $upstream_sha"
  push origin "$upstream_sha:refs/heads/main"
else
  echo "main is not an ancestor of upstream main; leaving main alone"
  echo main >> "$REPORT_DIR/diverged.txt"
  exit 0
fi

# Upstream bumps __version__ on every PR, and so does every feature branch, so
# a rebase onto a moved main nearly always stops on pyopia/__init__.py. When
# that is the only conflict, take upstream's file and redo the branch's small
# change to it: nst-patches re-adds its import guard, a feature branch gets the
# patch version bumped (what upstream's version check asks of a PR).
resolve_init() {
  local b=$1 v
  git -C "$work" checkout --ours pyopia/__init__.py   # during a rebase, ours = upstream
  if [ "$b" = nst-patches ]; then
    printf '\nfrom pyopia import _nst_guard  # noqa: E402,F401\n' >> "$work/pyopia/__init__.py"
  else
    v=$(sed -n 's/^__version__ = "\(.*\)"$/\1/p' "$work/pyopia/__init__.py")
    sed -i "s/^__version__ = \".*\"\$/__version__ = \"${v%.*}.$(( ${v##*.} + 1 ))\"/" "$work/pyopia/__init__.py"
  fi
  git -C "$work" add pyopia/__init__.py
}

rebase_branch() {
  local b=$1 conflicted
  git -C "$work" rebase -q --empty=drop "$upstream_sha" >/dev/null 2>&1 && return 0
  while [ -d "$(git -C "$work" rev-parse --git-path rebase-merge)" ]; do
    conflicted=$(git -C "$work" diff --name-only --diff-filter=U)
    if [ "$conflicted" != "pyopia/__init__.py" ]; then
      git -C "$work" rebase --abort 2>/dev/null || true
      return 1
    fi
    resolve_init "$b"
    GIT_EDITOR=true git -C "$work" rebase --continue >/dev/null 2>&1 && return 0
  done
  return 0
}

# 2. Rebase every branch that sits on main, in a scratch worktree.
work=$(mktemp -d)
trap 'git worktree remove --force "$work" 2>/dev/null || true' EXIT
git worktree add -q --detach "$work" "$upstream_sha"

branches=$(git for-each-ref --format='%(refname:strip=3)' \
  refs/remotes/origin/nst-patches 'refs/remotes/origin/feature/*')
for b in $branches; do
  old=$(git rev-parse "origin/$b")
  if git merge-base --is-ancestor "$upstream_sha" "$old"; then
    echo "$b already on main"; echo "$b" >> "$REPORT_DIR/clean.txt"; continue
  fi
  git -C "$work" checkout -q --detach "$old"
  if rebase_branch "$b"; then
    new=$(git -C "$work" rev-parse HEAD)
    if [ "$new" = "$upstream_sha" ]; then
      echo "$b is empty after rebase; probably merged upstream"
      echo "$b" >> "$REPORT_DIR/merged.txt"
    else
      echo "Rebased $b"
      push --force-with-lease="refs/heads/$b:$old" origin "$new:refs/heads/$b"
      echo "$b" >> "$REPORT_DIR/rebased.txt"
    fi
  else
    echo "Rebase conflict on $b"
    echo "$b" >> "$REPORT_DIR/conflicts.txt"
  fi
done
