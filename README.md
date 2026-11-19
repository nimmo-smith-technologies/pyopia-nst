# pyopia-nst

pyopia-nst is the Nimmo Smith Technologies build of [PyOPIA](https://github.com/SINTEF/pyopia), the Python Ocean Particle Image Analysis toolbox. It carries features and optimisations meant for pyopia-web and pyopia-gui that are still waiting for review upstream. Work that proves itself here goes back to SINTEF/pyopia as pull requests, and this fork is rebased onto each new upstream state.

The code is under the same BSD-3-Clause licence as upstream. Documentation for PyOPIA itself is at https://pyopia.readthedocs.io.

## Installing

The package is called `pyopia-nst` and the import name stays `pyopia`. Versions are the upstream version plus a build number, for example `2.19.0.1` is the first NST build on top of upstream 2.19.0.

pyopia-nst and the upstream `pyopia` distribution install the same files, so they cannot share an environment. Importing `pyopia` raises an error if both are present. Packaging tools cannot enforce this on their own, so one has to be uninstalled before the other is installed.

Each release has a wheel attached and a container image:

```bash
docker run --rm ghcr.io/nimmo-smith-technologies/pyopia-nst:2.19.0.1 --help
```

The image behaves like the upstream one (see the Docker section of the upstream README); only the image name differs.

## Branch model

| Branch | What it is | Edited by |
|---|---|---|
| `main` | A mirror of upstream `main`. | No one. It only moves by fast-forward from SINTEF/pyopia. |
| `feature/<name>` | One change, cut from `main`, written so it can be offered upstream as it stands. | Maintainers. |
| `nst-patches` | Changes that only make sense here: the package name, the guard against installing next to upstream, the release workflow. | Maintainers. |
| `nst-release` | `main` plus `nst-patches` plus the feature branches listed in `nst-release.conf`. | No one. It is rebuilt from scratch each time and force-pushed. |
| `nst-ops` (default branch) | This README, the sync workflow, the scripts and `nst-release.conf`. | Maintainers. |

Upstream squash-merges pull requests, so one long branch rebased forever would pile up conflicts. Keeping each change on its own branch means a change that lands upstream simply empties its branch and comes off the list.

### Naming branches

Feature branches are named `feature/<type>-<subject>`. The `feature/` prefix is what the daily sync and `nst-release.conf` recognise, so every change that is meant to ship uses it, fixes included.

| Type | Use | Example |
|---|---|---|
| `fix` | Corrects a bug. | `feature/fix-process-crash` |
| `add` | New capability. | `feature/add-processing-engine` |
| `change` | Alters existing behaviour: a default, a deprecation, performance, a refactor. | `feature/change-merge-on-by-default` |
| `remove` | Deletes code or an option. | `feature/remove-dead-background-helpers` |
| `docs` | Documentation only. | `feature/docs-differences-from-upstream` |

- The subject is a short noun phrase naming the thing affected, in lowercase with hyphens. It does not name an application, an issue number or a date.
- A branch has exactly one type. If two fit, it is two changes and so two branches. When in doubt between `fix` and `change`, ask whether anyone would reasonably call the old behaviour correct: if so, it is a `change`.
- Feature branches are not stacked on each other, because the daily sync rebases each one onto `main`. A change that needs another waits for it to merge or takes it as a cherry-pick.
- Branches are never deleted. A merged or abandoned branch stays as part of the record.
- Scratch work and safety copies live in local branches called `wip/<name>` and `backup/<name>-<short-sha>`. They are not pushed.
- Release tags have four parts, such as `2.19.0.1`, and are created only by the `NST cut release` workflow.

Branches offered to SINTEF/pyopia are named as upstream prefers; the names here do not have to match.

### Daily sync

The workflow `NST sync with upstream` runs every day (and on demand). It fast-forwards `main` from SINTEF/pyopia, then rebases `nst-patches` and every `feature/*` branch onto the new `main` and pushes them with `--force-with-lease`. Conflicts on the `__version__` line of `pyopia/__init__.py` are resolved automatically: a feature branch gets the new upstream patch version plus one, which is what upstream's version check asks of a pull request. Any other conflict leaves the branch untouched and opens an issue named `Rebase conflict: <branch>`. The issue closes itself on the first sync that rebases that branch cleanly. A branch with nothing left after the rebase gets an issue called `Branch looks merged upstream: <branch>`. If `main` is no longer an ancestor of upstream `main`, nothing is moved and an issue says so.

### Starting a change (maintainers)

```bash
git fetch origin
git switch -c feature/my-change origin/main
# work, commit, push
git push -u origin feature/my-change
```

The pull request goes to SINTEF/pyopia when the change is ready. To ship it earlier through this fork, add `feature/my-change` to `nst-release.conf` on `nst-ops` and cut a release.

### Cutting a release (maintainers)

Run the workflow `NST cut release` from the Actions tab and enter the version, for example `2.19.0.1`. It rebuilds `nst-release`, sets the version and pushes the tag. The same steps by hand, from a clone with `nst-ops` checked out:

```bash
scripts/nst-rebuild-release.sh --version 2.19.0.1 --push
git tag 2.19.0.1 origin/nst-release
git push origin 2.19.0.1
```

The script resets `nst-release` to `main`, merges each branch in `nst-release.conf` in order, and ends with a commit that sets `__version__`. The first three parts of the version must match the upstream version on `main`. If merging a branch conflicts in anything but the version line, the script stops and says where. Without `--push` it builds the branch locally so it can be inspected.

Pushing a four-part tag starts the workflow `NST release (image and GitHub release)`. It checks that the tag equals `__version__`, that the package is named `pyopia-nst` and that the tagged commit is on `nst-release`. Then it builds the wheel and sdist, pushes the image to `ghcr.io/nimmo-smith-technologies/pyopia-nst` as both the tag and `latest`, and creates a GitHub release with the wheel and sdist attached. The version has four dotted parts because Docker tags cannot contain `+`.
