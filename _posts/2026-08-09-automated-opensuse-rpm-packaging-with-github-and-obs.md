---
layout: post
title: "From Pull Request to Package: RPM Builds with GitHub Actions and OBS"
date: 2026-08-09 10:00:00 +0000
categories: post
tags: [opensuse, obs, rpm, github, ci, packaging, automation]
author: Tobias Geiser
image: "/assets/posts/2026-08-09/github-obs.png"
header: "/assets/posts/2026-08-09/github-obs-header.png"
excerpt_separator: <!--more-->
---

Some vendor-shipped packages do not match the openSUSE packaging guidelines: they unpack archives during `%post`, create launchers on the fly, or drop world-writable directories on your system. When I rebuild such a package, I want the replacement to move as fast as normal code: reviewed in pull requests, built automatically, and published without anyone touching OBS by hand. This guide is the workflow I built to do exactly that.
<!--more-->

## Overview

The central idea is to keep responsibilities separate:

- GitHub stores the packaging source and coordinates review.
- GitHub Actions runs validation, update checks, and OBS synchronization.
- OBS performs the actual distribution-specific RPM builds.
- Temporary OBS packages validate pull requests without changing the release repository.
- Merging to `main` synchronizes the reviewed package to the release project.

This guide is intentionally procedural. It shows the files to create, the values to configure, the commands to run, and the checks to perform before releasing a package. The examples use `<package>` as a placeholder for your package name, and `<package-pattern>` where multi-package repositories match several directories at once. Replace both with the values for your project.

The workflow combines the [Open Build Service User Guide](https://openbuildservice.org/help/manuals/obs-user-guide/) with the [openSUSE Packaging Guidelines](https://en.opensuse.org/openSUSE:Packaging_guidelines). Use those references for the complete OBS command reference, project configuration options, source-service behavior, RPM conventions, and policy details. This post focuses on the GitHub-to-OBS automation layer and the practical packaging decisions used in this workflow.

## Architecture

The workflow uses two OBS projects:

```text
home:team-vrock:branches/   # Temporary pull-request packages
home:team-vrock:releases/   # Reviewed release packages
```

A pull request for package `<package>` becomes this temporary OBS package:

```text
home:team-vrock:branches/<package>-pr123
```

After the pull request is merged, the package is synchronized as:

```text
home:team-vrock:releases/<package>
```

When the pull request closes, `<package>-pr123` is deleted. The same mechanism supports repositories containing several package directories; the workflows then match a pattern such as `<package-pattern>` (for example `font-*`).

![The packaging pipeline: a GitHub pull request triggers validation in GitHub Actions, builds in a temporary OBS staging project, publishes to the release project on merge, and cleans up the staging package.](/assets/posts/2026-08-09/github-obs-pipeline.png){: style="max-width: 100%; min-width: 100%; height: auto"}

## Prerequisites

You need:

- A GitHub repository containing the RPM packaging files.
- An OBS account with permission to write to the target projects.
- An OBS project with a Tumbleweed repository and the required architectures.
- GitHub Actions enabled for the repository.
- The reusable workflows from the org-internal `team-vrock/workflow-obs` repository.
- `git`, `osc`, and the relevant RPM tools for local verification.

Configure these GitHub Actions secrets in **Settings -> Secrets and variables -> Actions -> Secrets**:

| Secret | Purpose |
| --- | --- |
| `obs_user` | OBS account name (use a dedicated automation account) |
| `obs_password` | OBS password or API token for that user |
| `BOT_PAT` | *(Optional)* Personal Access Token with pull-request permissions. Pull requests created with the default `GITHUB_TOKEN` do not trigger other workflows; a PAT allows automated update PRs to start validation and branch builds. |

Create an OBS API token under your OBS user page (`https://build.opensuse.org/show/user/<YOURUSER>`) and prefer it over the account password.

Configure these repository variables in **Settings -> Secrets and variables -> Actions -> Variables**:

| Variable | Value |
| --- | --- |
| `OBS_PROJECT_RELEASES` | `home:team-vrock:releases` |
| `OBS_PROJECT_BRANCHES` | `home:team-vrock:branches` |

Do not put OBS credentials in `_service`, spec files, workflow source, or shell scripts.

## Walkthrough

### Prepare OBS Projects

Create or select an OBS project that contains a Tumbleweed repository. The repository used by this workflow must have the project path configured, for example:

```xml
<project name="home:team-vrock:releases">
  <repository name="openSUSE_Tumbleweed">
    <path project="openSUSE:Factory" repository="snapshot"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>
</project>
```

Use a separate project for temporary pull-request packages:

```text
home:team-vrock:branches
```

The GitHub Actions account needs permission to create, update, build, and delete packages in both projects. Verify the projects before configuring GitHub:

```bash
osc ls home:team-vrock:releases
osc ls home:team-vrock:branches
```

The branches project may initially be empty. Do not create a separate OBS package for every pull request by hand; the branch workflow creates packages with the `-pr<NUMBER>` suffix.

### Configure GitHub

In the package repository, open **Settings -> Secrets and variables -> Actions**.

Create the secrets (`obs_user`, `obs_password`, and optionally `BOT_PAT`) and the repository variables (`OBS_PROJECT_RELEASES`, `OBS_PROJECT_BRANCHES`) listed in the prerequisites. Project names are configuration, while credentials must remain secrets.

Under **Settings -> Actions -> General -> Workflow permissions**:

- Select **Read and write permissions**.
- Check **Allow GitHub Actions to create and approve pull requests** (required by the update workflow).

### Repository Layout

A single-package repository can use this layout:

```text
rpm-package/
├── .github/
│   └── workflows/
│       ├── check-update.yml
│       ├── obs-pr-branch.yml
│       ├── obs-pr-cleanup.yml
│       ├── obs-push-main.yml
│       ├── validate-main.yml
│       └── validate-pr.yml
├── .gitignore
└── <package>/
    ├── _service
    ├── <package>.changes
    ├── <package>-rpmlintrc
    └── <package>.spec
```

The package directory must contain at least:

- One `.spec` file.
- One `.changes` file.
- One `_service` file.

The same repository can contain several package directories. In that case, use a package pattern such as `<package-pattern>` (for example `font-*`) in the workflows.

Add a `.gitignore` that excludes downloaded artifacts so locally fetched sources and packages are never committed by accident:

```text
*.rpm
*.tar.gz
*.tar.xz
*.tar.zst
```

### The OBS Service File

The `_service` file tells OBS how to retrieve sources. For a source archive, a `download_url` service avoids storing generated archives in Git:

```xml
<services>
  <service name="download_url">
    <param name="protocol">https</param>
    <param name="host">github.com</param>
    <param name="path">/example/project/archive/refs/tags/v1.2.3.tar.gz</param>
  </service>
</services>
```

For a binary repackaging project, the service can download an upstream package instead:

```xml
<services>
  <service name="download_url">
    <param name="protocol">https</param>
    <param name="host">example.org</param>
    <param name="path">/downloads/example-1.2.3.x86_64.rpm</param>
  </service>
</services>
```

The `protocol` parameter must match what the upstream host actually serves. Some upstream repositories, such as proprietary vendor RPM repositories, only publish over plain `http`; in that case set `http` and note the limitation in the package.

Run the service locally when debugging a package checkout:

```bash
osc service runall
```

The generated source files should be reviewed before they are committed to OBS. For services intended to run on the OBS server, keep the service definition in the package and let OBS execute it.

### The RPM Spec File

The spec file defines how OBS builds and installs the package. Keep the package release at zero when OBS manages the distribution release suffix:

```spec
Name:           example
Version:        1.2.3
Release:        0
Summary:        Example application
License:        MIT
URL:            https://example.org/
Source0:        %{name}-%{version}.tar.gz
```

For source packages, use normal `%prep`, `%build`, `%check`, and `%install` stages. For proprietary binary packages, a clean repackaging can legitimately have an empty `%build` stage, but all installed files must still be copied into `%{buildroot}` during `%install`.

The package should install files into standard locations and avoid doing installation work in `%post`. In particular, do not dynamically unpack archives, create launchers, modify users' home directories, or alter unrelated system files from RPM scriptlets.

For a binary repackaging package, inspect the upstream archive before writing the spec. Check its file list, scriptlets, dynamic libraries, permissions, and architecture. Copy all runtime files into `%{buildroot}` during `%install`; do not leave an archive to unpack during package installation.

For example, inspect an upstream RPM locally with:

```bash
rpm -qip upstream-package.rpm
rpm -qpl upstream-package.rpm
rpm -qp --scripts upstream-package.rpm
```

This inspection is how invasive installation behavior in vendor packages gets identified. The replacement package installs its files during the build and uses only standard package integration macros.

### GitHub Actions Workflow Files

The repository workflows are intentionally thin callers of reusable workflows. This keeps the package-specific repository easy to audit while allowing improvements to be made centrally. Create the following files in `.github/workflows/`. The reusable workflow repository contains the implementation; the package repository supplies only the package pattern and inherits its configured secrets.

For a single package, use the package name itself as the pattern. For a repository containing several package directories, use a shell pattern such as `<package-pattern>` (for example `font-*`).

Pull-request branch build:

```yaml
# .github/workflows/obs-pr-branch.yml
name: OBS PR Branch

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  create-obs-branch:
    uses: team-vrock/workflow-obs/.github/workflows/push-branch-build.yml@main
    secrets: inherit
    with:
      package_pattern: "<package>"
```

If the package needs a generated vendor archive, pass `build_vendor: true`. This is useful for projects such as Rust or Zig applications whose builds must run without network access in OBS.

Main branch release synchronization. Use a push to `main` as the release event; do not use a separate `pull_request: types: [closed]` trigger for release synchronization. A merged pull request already produces a push to `main`, and separating the events prevents a closed, unmerged pull request from being released accidentally.

```yaml
# .github/workflows/obs-push-main.yml
name: OBS Push to Main

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  push:
    uses: team-vrock/workflow-obs/.github/workflows/push-main-release.yml@main
    secrets: inherit
    with:
      package_pattern: "<package>"
```

Pull-request cleanup. Temporary OBS packages must be removed for both merged and unmerged pull requests, so keep cleanup as a separate `pull_request: closed` workflow. Cleanup placed only inside a `push` workflow cannot run when a pull request is closed without a merge.

```yaml
# .github/workflows/obs-pr-cleanup.yml
name: OBS PR Cleanup

on:
  pull_request:
    types: [closed]

jobs:
  cleanup:
    uses: team-vrock/workflow-obs/.github/workflows/cleanup-pr-branch.yml@main
    secrets: inherit
    with:
      package_pattern: "<package>"
```

Validation for pull requests. It checks that matching package directories contain the expected spec, changelog, and service files before OBS synchronization starts:

```yaml
# .github/workflows/validate-pr.yml
name: Validate Pull Request

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - '<package>/**'
      - '.obs/**'

jobs:
  validate:
    uses: team-vrock/workflow-obs/.github/workflows/validate-pr.yml@main
    secrets: inherit
    with:
      package_pattern: '<package>'
```

Validation for pushes to `main`:

```yaml
# .github/workflows/validate-main.yml
name: Validate Main Branch

on:
  push:
    branches:
      - main
    paths:
      - '<package>/**'
      - '.obs/**'

jobs:
  validate:
    uses: team-vrock/workflow-obs/.github/workflows/validate-main.yml@main
    secrets: inherit
    with:
      package_pattern: '<package>'
```

The examples track the shared workflows at `@main`. This is appropriate while the shared workflow is actively developed; pin the reference to a release tag once the shared repository has a stable release policy.

### Upstream Version Updates

An update checker can query the upstream release API or repository metadata. When it finds a newer version, it should update all related package files together:

- `VERSION`, if the repository uses one.
- The spec file's `Version:` and source reference.
- The `_service` source URL.
- The openSUSE `.changes` entry.

The `check_version.py` script used in this workflow is repository-specific: each package needs its own checker that understands its upstream source (release API, repository metadata, or download page). For vendors that publish an RPM repository, the checker can read the upstream `repomd.xml`/`primary.xml.zst` repository metadata and supports:

```bash
python3 check_version.py --print-latest
python3 check_version.py --check-only
python3 check_version.py --new-version 1.2.4
```

The update workflow runs the checker on a schedule, applies the update, and opens a pull request rather than pushing directly to `main`. That gives the package a review boundary and starts the OBS branch build:

```yaml
# .github/workflows/check-update.yml
name: Check for Updates

on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:
    inputs:
      version:
        description: 'Manually specify version to update to'
        required: false
        type: string

permissions:
  contents: write
  pull-requests: write

jobs:
  check-update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Get current version
        id: current
        run: echo "version=$(cat VERSION)" >> $GITHUB_OUTPUT
      - name: Check for new version
        id: check
        run: |
          NEW_VERSION=$(python3 check_version.py --print-latest)
          if [ "$NEW_VERSION" != "$(cat VERSION)" ]; then
            echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT
            echo "has_update=true" >> $GITHUB_OUTPUT
          else
            echo "has_update=false" >> $GITHUB_OUTPUT
          fi
      - name: Update package files
        if: steps.check.outputs.has_update == 'true'
        run: python3 check_version.py --new-version "${{ steps.check.outputs.new_version }}"
      - name: Create Pull Request
        if: steps.check.outputs.has_update == 'true'
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.BOT_PAT }}
          branch: update-<package>-${{ steps.check.outputs.new_version }}
          delete-branch: true
          title: "Update <package> to ${{ steps.check.outputs.new_version }}"
          labels: automated, update
```

One GitHub Actions detail matters here: pull requests created with the default `GITHUB_TOKEN` do not trigger other workflows, so the validation and OBS branch builds would not start for an automated update PR. Use a dedicated PAT (the `BOT_PAT` secret) for the `create-pull-request` step when the automated PRs must run CI.

### Verify OBS Builds

After the branch workflow synchronizes a pull request, inspect the temporary package:

```bash
osc results home:team-vrock:branches <package>-pr123
```

A successful Tumbleweed result looks like this conceptually:

```text
openSUSE_Tumbleweed  x86_64  succeeded
```

Use the OBS build log when a result is `failed` or `broken`:

```bash
osc buildlog home:team-vrock:branches <package>-pr123 \
  openSUSE_Tumbleweed x86_64
```

After merge, inspect the release package:

```bash
osc results home:team-vrock:releases <package>
```

Build status is time-sensitive. A package can be `scheduled`, `building`, `finished`, `published`, `outdated`, or `failed` at different points in its lifecycle. Always include the command and the observation time when recording a result in a technical report.

GitHub Actions success means that the source files were synchronized to OBS. It does not prove that the RPM build succeeded. Always check the OBS result separately and wait for a final result before announcing a successful package.

### Installing the Published Package

Once the release project has published the package, users can install it directly from OBS. Add the release repository, refresh, and install the package:

For openSUSE Tumbleweed:

```bash
sudo zypper addrepo -f https://download.opensuse.org/repositories/home:/team-vrock:/releases/openSUSE_Tumbleweed/home:team-vrock:releases.repo
sudo zypper refresh
sudo zypper install <package>
```

The release project above currently publishes the `openSUSE_Tumbleweed` target. For other openSUSE versions, check which targets the project publishes on build.opensuse.org and substitute the matching repository path:

```bash
sudo zypper addrepo -f https://download.opensuse.org/repositories/home:/team-vrock:/releases/<distribution>/home:team-vrock:releases.repo
sudo zypper refresh
sudo zypper install <package>
```

A README badge can link the OBS build status to make the state of the package visible in the repository:

```markdown
[![OBS Build](https://build.opensuse.org/projects/home:team-vrock:releases/packages/<package>/badge.svg?type=default)](https://build.opensuse.org/package/show/home:team-vrock:releases/<package>)
```

### Cleanup

The cleanup workflow normally removes temporary packages automatically. If a previous workflow failed before cleanup was added, list the branch project:

```bash
osc ls home:team-vrock:branches
```

Delete only packages that are confirmed to belong to closed pull requests:

```bash
osc rdelete -f -m "PR closed, cleaning up" \
  home:team-vrock:branches <package>-pr123
```

The `-f` option is destructive. Verify the exact project and package name before running it. Never delete the entire OBS project to remove one temporary package.

### Security and Maintenance

- Keep credentials in GitHub Actions secrets.
- Use API tokens with only the OBS permissions required by the workflow.
- Do not print `oscrc` contents in CI logs.
- Do not store generated credentials or private configuration in the repository.
- Review shell expansion when package patterns contain wildcards.
- Pin reusable workflow references to a release tag when the shared workflow has a stable release policy; use `@main` only when intentionally tracking current changes.
- Keep the package's `.changes` file updated for every packaging change.
- Treat proprietary upstream binaries as untrusted input and inspect their scriptlets, file list, permissions, and dynamic dependencies before repackaging.

### Local Verification

Before opening a pull request, validate the package files locally:

```bash
rpmlint <package>/<package>.spec
osc service runall
osc build openSUSE_Tumbleweed x86_64 <package>/<package>.spec
```

For the GitHub repository itself, check the workflow files and package layout before pushing:

```bash
git diff --check
git status --short
find <package> -maxdepth 1 -type f -print
```

Use `osc service runall` only when the package's services are intended to run locally. For a server-side service, inspect the service definition and let OBS execute it. Do not commit credentials or generated private configuration.

For a package with a source service that must run remotely, use the OBS package checkout and inspect the generated sources before committing them. The exact local build command depends on the installed `osc` and `obs-build` versions.

After a pull request is merged, verify the release repository:

```bash
osc results home:team-vrock:releases <package>
```

The GitHub workflow result only confirms that files were synchronized to OBS. It does not replace checking the OBS build result.

## Troubleshooting

### OBS project not found

If a workflow reports:

```text
Project not found: home:team-vrock:branches
```

Check the repository variable used by the workflow. The shared workflows expect:

```text
OBS_PROJECT_BRANCHES=home:team-vrock:branches
OBS_PROJECT_RELEASES=home:team-vrock:releases
```

Older package repositories may instead use a single `OBS_PROJECT` secret. Migrate them to the shared variable names and pass the secrets through `secrets: inherit`.

### `_meta` is not under version control

OBS treats `_meta` as package metadata, not as a source file. If a workflow copies `_meta` into an `osc` checkout and then runs `osc addremove`, it can fail with:

```text
osc: '_meta' is not under version control
```

Remove `_meta` from the local checkout before `osc addremove`. Apply its contents through `osc meta pkg` instead. The current shared workflow handles this case.

### No build log exists

If `osc buildlog` reports that the package has no logfile, the package may not have been dispatched yet, may be excluded for that architecture, or may already be represented by a published repository result. Check the result first:

```bash
osc results home:team-vrock:releases <package>
```

### Offline dependency failure

OBS builds do not depend on arbitrary network access. Rust projects need a vendored dependency archive and a Cargo configuration that points to it:

```toml
[net]
offline = true

[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
```

The vendor archive must be generated before the OBS build and declared as a source in the spec file. The same principle applies to other build systems that normally download dependencies during `%build`.

For Rust packages, one practical pattern is a repository-local `build-vendor.sh` script. It downloads the tagged source, runs `cargo vendor`, and creates `vendor.tar.zst` before the branch workflow uploads it to OBS. If the script may be run more than once, remove or force-overwrite the output first:

```bash
rm -f vendor.tar.zst
tar --sort=name --owner=0 --group=0 --numeric-owner \
  -cf - vendor | zstd -f -T0 -19 -o vendor.tar.zst
```

Without `-f` or `rm -f`, `zstd` can refuse to replace an existing archive and the vendor job fails even though dependency resolution succeeded.

### Debian payload compression changes

A binary Debian package is an `ar` archive containing a data tarball. The compression format can change between upstream releases. A spec that assumes only `data.tar.xz` fails when the upstream package contains `data.tar.zst` instead.

Use the required decompressor as a build dependency and inspect the archive after extraction:

```spec
BuildRequires: zstd

%prep
ar x %{SOURCE0}
tar -xf data.tar.*
```

The wildcard is appropriate when the package contains one data payload. If an upstream package could contain multiple matching files, identify the actual member first and fail explicitly when it is ambiguous.

### Compiler version requirements

Do not select a compiler version from the current distribution alone. Read the upstream source's declared requirement. For example, while packaging Ghostty (a terminal emulator) version 1.3.1 for openSUSE, the build with Zig 0.13.0 failed because the source declared `minimum_zig_version = "0.15.2"`; the fix used Zig 0.15.2 and the corresponding archive names:

```text
zig-x86_64-linux-0.15.2.tar.xz
zig-aarch64-linux-0.15.2.tar.xz
```

The `_service` filenames, `Source2`/`Source3`, extracted directory names, and `%build` `PATH` must all agree. A compiler API error can be a version mismatch rather than a source-code defect.

### Automated update PRs do not trigger CI

Pull requests created with the built-in `GITHUB_TOKEN` do not start other workflows. Use a dedicated PAT (`BOT_PAT`) in the `create-pull-request` step so automated update PRs run validation and the OBS branch build.

## Summary

This workflow makes RPM packaging reviewable and repeatable:

1. An updater opens a GitHub pull request.
2. GitHub Actions validates the package structure.
3. The pull request is synchronized to a temporary OBS package.
4. OBS builds the package for openSUSE Tumbleweed.
5. Reviewers inspect the source and build result.
6. A merge to `main` synchronizes the package to the OBS release project.
7. A dedicated closed-pull-request workflow removes the temporary package.
8. Users install the published package from the OBS release repository.

Keeping the packaging files in GitHub and the builds in OBS gives maintainers a clear audit trail while retaining OBS's distribution-specific build environment.

## References

- [Open Build Service User Guide](https://openbuildservice.org/help/manuals/obs-user-guide/)
- [openSUSE Packaging Guidelines](https://en.opensuse.org/openSUSE:Packaging_guidelines)
