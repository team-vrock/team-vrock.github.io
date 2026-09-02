---
layout: post
title: "Repeatable Engineering with OpenCode Agents and Skills"
date: 2026-09-02 22:30:00 +0000
categories: post
tags: [opencode, ai-agents, coding, skills, automation, documentation]
author: Tobias Geiser
image: "/assets/posts/2026-09-02/ai-agent-skills.png"
excerpt_separator: <!--more-->
---

Every engineering session I finish leaves behind the same mess: commands that worked, failures I fixed, and knowledge that evaporates the moment the terminal closes. I got tired of rewriting documentation from memory, so I taught OpenCode to do it for me — with agents that define roles and skills that encode procedures. The result is a setup where a completed session becomes a reviewable, reproducible draft post instead of a lost evening.
<!--more-->

The configuration described here is a snapshot of a working environment. Provider names, model identifiers, MCP servers, and paths are examples from that environment and should be replaced when reproducing the setup. Secrets and API credentials are intentionally omitted.

## Overview

The setup is intentionally small and layered:

- `opencode.json` selects the default coding model and agent.
- Agent files define specialized roles and permission boundaries.
- Skill files encode reusable procedures.
- The `create-jekyll-post` agent and skill turn verified engineering sessions into draft-only Jekyll documentation.
- `rbenv`, Bundler, and Jekyll provide a repeatable local preview.
- Human review remains the gate for publication.

This structure lets an AI coding assistant contribute to implementation and documentation without making drafts indistinguishable from approved publications.

## Architecture

OpenCode's coding behavior is split into three useful layers:

1. **Global configuration** selects defaults and registers providers, MCP servers, permissions, agents, and skill search paths.
2. **Agents** define a role, operating mode, model choice, permissions, and system instructions.
3. **Skills** define reusable procedures that an agent can load when a task matches the skill description.

The global files are normally stored under:

```text
~/.config/opencode/
├── opencode.json
├── agents/
│   └── <agent-name>.md
└── skills/
    └── <skill-name>/
        └── SKILL.md
```

Project-local configuration can override global configuration. A project can also contain its own `.opencode/agent/` and `.opencode/skills/` directories. Keep reusable personal procedures global, and keep project-specific procedures in the project so they can be reviewed with the source code.

## Prerequisites

- OpenCode installed and starting cleanly on your workstation.
- A writable `~/.config/opencode/` configuration directory.
- A local checkout of the Jekyll website you want to document into (used by the `create-jekyll-post` examples). The guide uses `~/src/team-vrock/team-vrock.github.io`; replace it with your checkout path.
- `rbenv`, Bundler, and the website's Ruby version for local previews, as described in the [rbenv setup guide](/post/2026/07/19/install-jekyll-with-rbenv-on-opensuse.html).

## Walkthrough

### Inspect the active configuration

Before changing an agent or skill, inspect the files that OpenCode loads:

```bash
ls -la ~/.config/opencode
find ~/.config/opencode/agents -maxdepth 1 -type f -name '*.md' -print
find ~/.config/opencode/skills -mindepth 2 -maxdepth 2 -name SKILL.md -print
```

The configuration file should declare the official schema so editors can validate it:

```json
{
  "$schema": "https://opencode.ai/config.json"
}
```

Use the configuration schema as the authority for fields and types. Unknown or misspelled fields can prevent OpenCode from starting.

In this setup the relevant defaults are conceptually:

```json
{
  "default_agent": "build",
  "model": "provider/model-id",
  "small_model": "provider/model-id"
}
```

The actual provider and model identifiers are environment-specific. Do not copy private gateway URLs or credentials into a public post or repository.

### Choose the default coding agent

The `default_agent` determines which primary agent handles normal requests. A coding setup commonly uses the built-in `build` agent as the default and keeps planning or specialist roles available for explicit delegation.

```json
{
  "default_agent": "build"
}
```

The built-in `plan` agent is useful for read-only analysis before implementation. In this environment it has a separate model override:

```json
{
  "agent": {
    "plan": {
      "model": "provider/model-id"
    }
  }
}
```

Use Plan Mode when you need repository inspection and a proposed implementation without edits. Switch to Build Mode only when changes are authorized. This separation prevents a research request from unexpectedly modifying the worktree.

### Define a specialist agent

An agent file uses YAML front matter followed by its instructions. The front matter controls how OpenCode runs the agent; the body is the role prompt.

Minimal example:

```markdown
---
description: Creates reproducible documentation from completed engineering sessions.
mode: subagent
permission:
  edit: allow
  bash: ask
  external_directory: allow
---

You are a specialist documentation agent. Inspect the session evidence,
write a reviewable draft, and report what was verified.
```

The important design choices are:

- `mode: subagent` makes the specialist available for delegation without replacing the primary coding agent.
- `description` gives the agent a clear purpose and helps it get selected for matching tasks.
- `permission` limits what the specialist can do. Ask before shell commands when the command may have side effects.
- The prompt states output boundaries, safety rules, evidence requirements, and verification responsibilities.

### Define a reusable skill

Skills are directories containing a file named exactly `SKILL.md`. The skill front matter needs a lowercase hyphen-separated name and a useful trigger description:

```markdown
---
name: example-skill
description: Performs a reproducible repository operation. Use when asked to perform that operation.
---

# Example Skill

Describe the procedure, prerequisites, safety constraints, and verification.
```

The description should contain the words a user is likely to use. The body should explain what to do, not merely describe the topic. Include commands, expected results, failure handling, and boundaries around secrets or destructive operations.

### The `create-jekyll-post` pair

The documented specialist consists of one global agent and one global skill:

```text
~/.config/opencode/
├── agents/create-jekyll-post.md
└── skills/create-jekyll-post/SKILL.md
```

The agent is responsible for the workflow. It establishes the audience and outcome, reads the session and repository evidence, creates the draft, validates the result, and reports uncertainty.

The skill is the reusable procedure. It defines the fixed website checkout, draft-only behavior, evidence-first writing, privacy checks, Jekyll front matter, optional image handling, and validation rules.

This division is deliberate. The agent describes who is performing the work. The skill describes how the work must be performed consistently.

### Set safe output boundaries

The documentation agent writes only to the local website checkout (shown here with the example path `~/src/team-vrock/team-vrock.github.io`):

```text
<website-checkout>/_drafts/
<website-checkout>/assets/posts/YYYY-MM-DD/
```

It does not write to live `_posts/`, publish a post, move a draft, or create a central index. This provides a review boundary: the agent can prepare content frequently, while publication remains a human decision.

The current website uses this layout for a draft:

```text
team-vrock.github.io/
├── _drafts/
│   └── YYYY-MM-DD-title.md
└── assets/
    └── posts/
        └── YYYY-MM-DD/
            └── image.png
```

### Capture evidence before writing

The agent should not reconstruct a guide from memory. It should inspect:

- Conversation history and the session timeline.
- Commands actually executed.
- Relevant repository files and commits.
- CI logs and OBS build results, for example from the [OBS packaging workflow](/post/2026/09/02/automated-opensuse-rpm-packaging-with-github-and-obs.html).
- Configuration and version information.
- Final status and known limitations.

For every important claim, distinguish the evidence type:

| Evidence type | Meaning |
| --- | --- |
| Verified | A command or test was executed and its result was observed. |
| Observed | A log, file, or external status was inspected. |
| Inferred | A conclusion was derived from observed evidence. |
| Proposed | A command or recommendation was not executed in the session. |

Never invent output. Time-sensitive results, such as CI or OBS status, should include the command and observation date so the reader knows that the result can change.

### Write reproducible post front matter

The agent uses the site's existing Jekyll conventions:

```yaml
---
layout: post
title: "Descriptive Technical Title"
date: 2026-09-02 22:30:00 +0000
categories: post
tags: [opencode, ai-agents, coding, skills, automation, documentation]
author: Tobias Geiser
excerpt_separator: <!--more-->
---
```

If a post has a feature image, add `image:` only after the file has been supplied or generated and validated:

```yaml
image: "/assets/posts/2026-09-02/post-image.png"
```

The current image policy targets a square `512x512` PNG. The agent should omit the field when no image capability is configured or when a supplied image is missing. It must not create a fake placeholder.

### Preview a draft

The website uses Ruby and Jekyll. Select the repository's Ruby version through `rbenv` before invoking Bundler, from your website checkout:

```bash
cd ~/src/team-vrock/team-vrock.github.io
eval "$(rbenv init - bash)"
rbenv local 3.3.12
bundle exec jekyll serve --drafts --future --livereload
```

The flags have distinct purposes:

- `--drafts` includes files from `_drafts/`.
- `--future` includes documents whose front-matter date is later than the current time.
- `--livereload` refreshes the browser after changes.

The site's theme renders posts below `/post/`. A draft may therefore be available at:

```text
http://127.0.0.1:4000/post/YYYY/MM/DD/post-slug.html
```

If port 4000 is busy:

```bash
bundle exec jekyll serve --drafts --future --livereload \
  --host 127.0.0.1 --port 4010
```

### Validate before publication

The agent validates the draft without publishing it. For a full preview build, use:

```bash
cd ~/src/team-vrock/team-vrock.github.io
eval "$(rbenv init - bash)"
rbenv local 3.3.12
bundle exec jekyll build --drafts --future
```

Check that:

- YAML front matter parses.
- Code fences are balanced.
- Commands include required tools and permissions.
- Placeholders are explained.
- Destructive commands are clearly labeled.
- Links and asset references resolve.
- No passwords, tokens, private keys, cookies, or internal credentials appear.
- A referenced image exists and is exactly `512x512`.

Only after human review should a selected draft be moved into the live `_posts/` directory. Run the normal site build after that decision.

### Security model for coding agents

Agent permissions should follow the task rather than the user's maximum capability. A documentation agent may need to read external repositories and write to a fixed draft directory, but it does not need permission to publish, push, or modify unrelated projects.

Useful rules include:

- Ask before shell commands with external side effects.
- Deny destructive commands unless explicitly authorized.
- Keep credentials in environment-specific secret stores.
- Do not place provider API keys in `opencode.json` committed to Git.
- Do not expose private MCP endpoints or authentication headers in public documentation.
- Review agent and skill changes like code because prompts influence tool use.
- Restart OpenCode after changing global configuration, agents, or skills.

The same principle applies to coding agents that edit application repositories: inspect first, make the smallest correct change, run targeted verification, and report failures instead of hiding them.

### Maintain the configuration

Treat agents and skills as operational code:

1. Keep global definitions in `~/.config/opencode/` and back them up securely.
2. Review changes to prompts and permissions.
3. Test the agent on a small completed session before relying on it for a large report.
4. Keep generated posts in `_drafts/` until reviewed.
5. Update the skill when the website layout, Ruby version, asset convention, or validation commands change.
6. Record which model and configuration produced an important artifact when provenance matters.

The configuration is not a replacement for engineering judgment. It is a way to make good operating procedures easier to repeat.

## Troubleshooting

### The skill is not found

Confirm the directory and filename:

```bash
test -f ~/.config/opencode/skills/create-jekyll-post/SKILL.md
test -f ~/.config/opencode/agents/create-jekyll-post.md
```

Restart OpenCode after creating or modifying either file.

### The draft URL returns 404

Start with `--drafts --future`, then use the theme's `/post/` prefix. A future-dated draft is skipped without `--future`.

### Jekyll cannot install gems

Use the Ruby version selected by `rbenv` and install the required development tools before running Bundler:

```bash
eval "$(rbenv init - bash)"
rbenv local 3.3.12
gem install bundler
bundle install
```

Native gems require a compiler and Ruby development headers. Follow the site's [rbenv setup guide](/post/2026/07/19/install-jekyll-with-rbenv-on-opensuse.html) for distribution-specific prerequisites.

### The generated article contains unsupported claims

Return to the session evidence. Mark the statement as inferred or proposed, add the missing verification command, or remove it. A useful guide is honest about what was and was not tested.

## Summary

The coding-oriented OpenCode setup is intentionally small:

- `opencode.json` selects the default coding model and agent.
- Agent files define specialized roles and permission boundaries.
- Skill files encode reusable procedures.
- The `create-jekyll-post` agent and skill turn verified engineering sessions into draft-only Jekyll documentation.
- `rbenv`, Bundler, and Jekyll provide a repeatable local preview.
- Human review remains the gate for publication.

This structure lets an AI coding assistant contribute to implementation and documentation without making drafts indistinguishable from approved publications.
