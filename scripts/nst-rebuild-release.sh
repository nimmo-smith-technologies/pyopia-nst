#!/usr/bin/env bash
# Rebuild nst-release from main plus the branches listed in nst-release.conf.
#
# Usage: scripts/nst-rebuild-release.sh [--version 2.19.0.1] [--push]
#
# nst-release is thrown away and rebuilt every time, never edited by hand.
# Without --push the result stays in a local branch called nst-release.
# With --version the last commit sets __version__; the first three parts
# must equal the upstream version on main.
set -euo pipefail

version=""; do_push=0
while [ $# -gt 0 ]; do
  case $1 in
    --version) version=$2; shift 2 ;;
    --push) do_push=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

conf="$(cd "$(dirname "$0")/.." && pwd)/nst-release.conf"
[ -f "$conf" ] || { echo "missing $conf" >&2; exit 1; }
git fetch -q origin '+refs/heads/*:refs/remotes/origin/*'

upstream_version=$(git show origin/main:pyopia/__init__.py | sed -n 's/^__version__ = "\(.*\)"$/\1/p')
if [ -n "$version" ]; then
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "version must look like 2.19.0.1" >&2; exit 1; }
  [ "${version%.*}" = "$upstream_version" ] \
    || { echo "version $version does not extend upstream version $upstream_version" >&2; exit 1; }
fi

work=$(mktemp -d)
trap 'git worktree remove --force "$work" 2>/dev/null || true' EXIT
git worktree add -q -B nst-release "$work" origin/main

git_w() { git -C "$work" "$@"; }

while IFS= read -r branch; do
  branch=${branch%%#*}; branch=$(echo "$branch" | xargs)
  [ -n "$branch" ] || continue
  echo "Merging $branch"
  if ! git_w merge -q --no-ff -m "Merge $branch into nst-release" "origin/$branch" >/dev/null 2>&1; then
    # Upstream forces a __version__ bump on every PR, so branches often clash
    # on that one line. Keep what is already there; the version is set at the end.
    conflicted=$(git_w diff --name-only --diff-filter=U)
    if [ "$conflicted" = "pyopia/__init__.py" ]; then
      git_w checkout --ours pyopia/__init__.py
      git_w add pyopia/__init__.py
      git_w commit -q --no-edit
    else
      echo "Conflict merging $branch in:" >&2; echo "$conflicted" >&2
      git_w merge --abort
      exit 1
    fi
  fi
done < "$conf"

if [ -n "$version" ]; then
  sed -i "s/^__version__ = \".*\"$/__version__ = \"$version\"/" "$work/pyopia/__init__.py"
  git_w commit -q -am "Set version to $version"
fi

echo "nst-release is at $(git_w rev-parse --short HEAD)"
if [ "$do_push" = 1 ]; then
  git push --force-with-lease="refs/heads/nst-release:$(git rev-parse -q --verify refs/remotes/origin/nst-release || echo '')" \
    origin nst-release
fi
