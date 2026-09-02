---
layout: post
title: "Create Reproducible Jekyll Guides from Engineering Sessions"
date: 2026-09-02 19:00:00 +0000
categories: post
tags: [jekyll, documentation, reproducibility, opencode, linux]
author: TEAM VROCK
excerpt_separator: <!--more-->
---

Engineering sessions contain valuable commands, failures, fixes, and operational decisions. This workflow turns that evidence into a reviewable Jekyll draft without publishing it automatically.
<!--more-->

The workflow is designed for technical guides that a reader can follow and verify. It records what was actually done, explains why the steps matter, and keeps draft review separate from publication.

## What the workflow creates

The global OpenCode components are installed here:

```text
~/.config/opencode/
├── agents/create-jekyll-post.md
└── skills/create-jekyll-post/SKILL.md
```

The website checkout used by the agent is:

```text
/home/xiur66/src/team-vrock/team-vrock.github.io
```

Generated drafts are written here:

```text
/home/xiur66/src/team-vrock/team-vrock.github.io/_drafts/
```

Supporting assets, when they are genuinely useful, are written under the existing `assets/` directory. The agent does not modify live `_posts/`, publish content, move files, or create a central index page.

Restart OpenCode after installing or changing the global agent or skill. OpenCode loads these components when it starts.

## Create a draft

Invoke the `create-jekyll-post` agent after completing a technical session. Give it a precise topic and identify the session or repositories it should use.

For example:

```text
Use create-jekyll-post to document the Parsec OBS build repair.
Use the current session evidence and the rpm-parsec-linux repository.
Include the original failure, root cause, exact fix, verification commands,
and the resulting OBS status. Save a draft only.
```

The agent examines the session history and relevant files before writing. It should not infer a successful result from an attempted command or from an outdated log.

## Draft structure

A useful guide normally contains these sections:

1. Goal
2. Prerequisites
3. Environment and versions
4. Initial state
5. Procedure
6. Verification commands
7. Expected output
8. Failure encountered
9. Root cause
10. Fix
11. Cleanup or rollback
12. Troubleshooting
13. Reproducibility notes

Not every guide needs every section. The important distinction is between observed evidence and advice. Commands that were run should be documented as verified. Commands that were not run should be labeled as examples or recommendations.

## Preserve reproducibility

Use complete commands rather than shortened descriptions when the exact syntax affects the result:

```bash
osc results home:team-vrock:releases parsec
```

Record the relevant result and the date it was observed. OBS status, package versions, repository contents, and external download URLs can change after the session.

Replace machine-specific or secret values with explicit placeholders:

```bash
osc results <OBS_PROJECT> <PACKAGE_NAME>
```

Explain each placeholder so a reader knows what must be substituted. Do not include passwords, API tokens, private keys, authorization headers, personal data, or unnecessary internal host information.

## Review before publishing

The generated file is only a draft. Review it in the website checkout:

```bash
cd /home/xiur66/src/team-vrock/team-vrock.github.io
git diff --check
git status --short
```

Check the following before moving a draft into the live site:

- The front matter has a valid date, title, layout, category, and tags.
- Every command has the required tools, permissions, paths, and environment.
- Expected output matches the evidence from the session.
- Destructive commands explain their impact and include a safe verification step.
- Links point to the intended repository, package, documentation, or service.
- Asset references resolve under the website's existing `assets/` directory.
- Secrets and private environment details are absent.

The production Jekyll build does not normally render files in `_drafts/`. After manually approving a draft, move or copy it into the live `_posts/` directory and place approved assets in the appropriate live asset directory. Then run the site's normal build:

```bash
bundle exec jekyll build
```

Only publish after the rendered result and commands have been reviewed by a person.

## Why draft-only matters

Session notes often contain temporary paths, incomplete attempts, credentials accidentally present in command output, or conclusions that changed later. Keeping generation in `_drafts/` creates a deliberate review boundary. The writer can be used frequently, while publication remains an explicit decision for each guide.
