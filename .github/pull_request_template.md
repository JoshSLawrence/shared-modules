# Pull Request

<!--
Fill this out. HTML comments like this one don't render on GitHub, but they
can end up in squash-merge commit messages, so remove them before merging.
-->

## Type of Change

- [ ] New shared module
- [ ] Non-breaking change to an existing module
- [ ] Breaking change to an existing module (major version bump)
- [ ] Repo tooling / docs / templates (not a module change)
- [ ] Repo settings (`iac/`) -- applied from this PR (approve the iac
      workflow's apply) before merging

## Description

<!-- Briefly summarize the change and why it is needed. -->

## Rollback Plan

**Default:** shared modules aren't deployed from this repo -- consumers pull
a pinned `ref`, so there's no "apply" here to roll back. Revert this PR's
merge commit. If a tag was already cut for this change, delete it (and its
GitHub Release) *after* the revert lands, rather than leaving a broken
release available for consumers to pin to -- the release workflow recreates
any tag that's missing for a module's current `VERSION`. Release tags are
protected, so only a repository admin can delete one.

For `iac/` changes, roll back by applying `iac/` from `main` (run the iac
workflow on `main`) and closing this PR -- `iac/` is applied from the PR
before merging, so nothing needs reverting in git.

**Special considerations:**

<!--
Document consumer follow-up, such as re-pinning to a previous tag or re-running
their own apply. Use "N/A" if the default rollback is sufficient.
-->

## Testing & Validation

<!--
Maintainers reviewing an external PR: a PR runs its own copy of the
workflows, so changes under .github/, mise-tasks/, iac/, or tests/ mean a
green check proves little. See CONTRIBUTING.md#reviewing-external-pull-requests.
-->

- [ ] `pre-commit` hooks pass
- [ ] `VERSION` file bumped and `CHANGELOG.md` updated for module changes
- [ ] `examples/` added/updated and plan cleanly with `tofu`
- [ ] Example `source` refs match the new `VERSION`
- [ ] No secrets, credentials, or connection strings committed
- [ ] If breaking, upgrade notes are documented in CHANGELOG

## Additional Notes

<!-- Add reviewer context, dependencies, or risks. Use "N/A" if none. -->
