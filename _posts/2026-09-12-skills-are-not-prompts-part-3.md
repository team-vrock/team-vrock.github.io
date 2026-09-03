---
layout: post
title: "Skills Are Not Prompts, Part 3: Designing a Dynamic Capability System for AI Agents"
date: 2026-09-12 10:00:00 +0000
categories: post
tags: [ai, ai-agents, llm, agents, architecture]
author: Tobias Geiser
image: "/assets/posts/2026-09-12/ai-robot.png"
header: "/assets/posts/2026-09-12/ai-robot-header.png"
excerpt_separator: <!--more-->
---

Many AI agent frameworks describe skills as reusable prompts. That is useful — and too limited. If a skill is only a block of text injected into the model context, it is basically a prompt template with a better name. A serious agent skill should represent something larger: knowledge, instructions, tools, permissions, retrieval strategy, context requirements, validation rules, and runtime behavior. A skill should be a **capability package** — and that changes how agent systems can be designed.
<!--more-->

**TL;DR:** A skill should tell the runtime how to prepare the environment — which tools to activate, which permissions to grant, which context to retrieve — not just how the model should behave. Skills need discovery, dynamic loading and unloading, dependencies, scopes, versioning, validation, budgets, conflict resolution, and trust boundaries. Think packages, not prompts.

This is Part 3 of a five-part series on designing AI agent infrastructure. [Part 1]({% post_url 2026-09-05-llm-memory-is-not-chat-history-part-1 %}) covered persistent memory and [Part 2]({% post_url 2026-09-06-context-is-a-budget-part-2 %}) covered context as a budget; [Part 4]({% post_url 2026-09-13-stop-writing-prompts-start-writing-specifications-part-4 %}) covers specification-driven prompting and [Part 5]({% post_url 2026-09-20-stop-writing-prompts-start-writing-specifications-part-5 %}) covers execution loops, guardrails, and templates.

## The Problem With Prompt-Only Skills

Imagine an agent with a Kubernetes skill. A prompt-only implementation looks like this:

```yaml
skill:
  name: kubernetes
  prompt: |
    You are an expert Kubernetes engineer.

    Follow Kubernetes best practices.

    Inspect workloads before making changes.

    Prefer declarative configuration.

    Use kubectl carefully.
```

That is fine as documentation. But what does the skill actually *do*? Nothing. The runtime still needs to know whether `kubectl` should be available, which cluster the agent may access, whether write operations are allowed, which project files are relevant, whether Helm should also be loaded, how much context the skill consumes, and which other skills it depends on. The prompt is only one part of the capability.

A more useful definition tells the runtime how to prepare the environment:

```yaml
skill:
  name: kubernetes-debugging

  description: >
    Diagnose Kubernetes workloads,
    deployments, services and cluster issues.

  instructions: |
    Start with observation before modification.
    Prefer narrow queries over cluster-wide dumps.
    Verify current state before recommending changes.

  tools:
    required:
      - kubectl

    optional:
      - helm
      - logs

  permissions:
    kubernetes:
      read: true
      write: false

  context:
    retrieve:
      - cluster_version
      - namespace
      - workload_manifest
      - recent_events

  dependencies:
    - yaml

  budget:
    max_tokens: 12000
```

Now the skill is not merely instructing the model — it is telling the runtime what to make available. That is the shift this whole post is about.

## Discovery Versus Activation

An agent may have hundreds of available skills, and loading them all would destroy context efficiency. Instead, the runtime needs a lightweight skill catalog:

```yaml
skills:

  - name: rust
    description: Rust implementation, Cargo, ownership and lifetimes

  - name: kubernetes-debugging
    description: Diagnose Kubernetes workloads and cluster failures

  - name: terraform
    description: Terraform configuration and infrastructure workflows
```

Descriptions are cheap; complete definitions remain unloaded. The model or runtime first decides which skills are relevant, then loads only those. This separates **skill discovery** from **skill activation** — a distinction that is essential for scale.

Activation is also dynamic. Suppose the user asks "Why is this pod restarting?" The runtime activates `kubernetes-debugging`, the agent finds `Back-off restarting failed container`, inspects the application logs, and finds `connection refused: postgres:5432`. Now a `postgresql` skill becomes useful — and if the database runs through an operator, `cloudnative-pg` too. The active capability set evolves while investigating; the system does not need to predict the full problem before work begins.

Loading without unloading still grows the context. Once the database problem is resolved and the agent moves on to an ingress issue, the active set changes from `kubernetes, postgresql, cloudnative-pg` to `kubernetes, ingress-nginx, tls`. This is closer to how operating systems manage memory: capabilities load when needed and get evicted when they stop being useful.

## Scopes: Workspace Beats Global Beats Builtin

Not every skill should be available everywhere. Skills come from several scopes — workspace, global, builtin — with a precedence model:

```text
workspace > global > builtin
```

A project can override general behavior. If a built-in Rust skill says "run cargo fmt before committing" but a specific repository has a custom formatter workflow, the workspace-level skill wins. Local project knowledge should be more authoritative than generic defaults.

Workspace skills matter because project-specific knowledge is usually more important than generic agent knowledge:

```yaml
skill:
  name: repository-conventions

  instructions: |
    Use cargo nextest instead of cargo test.

    Do not edit generated files under src/generated.

    API changes require updating docs/api.md.

    Use conventional commits.
```

These are not general programming rules — they belong to the repository. Keeping them in the workspace gives you version control, visibility, team ownership, predictable behavior, and portability between agent runtimes. One model I like is storing project-local skills in a dedicated directory:

```text
.agent/skills/
  rust.yaml
  release.yaml
  kubernetes.yaml
```

When a workspace is opened, the runtime discovers those files. Skills travel with the project, can be reviewed like code, and evolve through pull requests — much better than hiding critical agent behavior inside a centralized UI database nobody remembers to update.

Skill definitions should stay declarative — describe the capability, not the implementation. A release skill declares that it requires git and GitHub tools, write permissions for releases, and changelog/tag/workflow context, plus instructions like "never overwrite an existing tag". The runtime decides how to satisfy those requirements, which keeps definitions portable: a different agent harness could implement the same capability with different underlying tools.

## Tools, Permissions, and Dependencies

A tool performs an operation; a skill tells the agent how and when to use capabilities. `kubectl` is a tool with operations like get, describe, logs, apply, delete. `kubernetes-debugging` is a skill holding knowledge like what to inspect first, which commands are safe, which context is useful, and how to interpret results. A skill may use several tools and a tool may serve several skills — a many-to-many relationship.

Complex capabilities should not duplicate instructions. A `kubernetes-release` skill declares dependencies:

```yaml
skill:
  name: kubernetes-release

  dependencies:
    - kubernetes
    - helm
    - git
```

The runtime resolves the dependency graph — and needs limits, because recursive loading can explode. A cycle (`A → B → C → A`) or a graph that activates fifty dependencies turns a small capability request into massive context usage. Runtime safeguards like `max_depth: 4` and `max_active_skills: 12`, plus cycle detection, keep that from happening.

Because a skill often knows what information is useful, it should be able to request context:

```yaml
context:
  required:
    - Cargo.toml

  preferred:
    - relevant_source_files
    - compiler_output

  avoid:
    - target_directory
```

A Terraform skill asks for terraform files, provider versions, and state backend config; a Kubernetes troubleshooting skill asks for deployments, pods, recent events, and container logs. Skills become context orchestration modules — they influence not only what the model knows but what the runtime retrieves. The same goes for tools: if a required tool is unavailable, the runtime should report `Required tool unavailable: kubectl` before the agent begins, instead of letting the model repeatedly attempt impossible actions.

Tool availability and tool permission are different things. Having `kubectl` does not mean being allowed to run `kubectl delete namespace production`:

```yaml
permissions:
  kubernetes:
    read: true
    create: false
    update: false
    delete: false
```

A deployment skill could request stronger permissions, and capability activation becomes auditable. Sometimes a task genuinely requires more access: the agent starts read-only and requests escalation when a modification becomes necessary ("Current: Kubernetes read-only. Requested: update Deployment payments/api"), approved by the runtime or the user. That is much safer than giving every agent full cluster access from the start.

## Versioning, Validation, and Provenance

Skills evolve, and projects may depend on specific behavior — so skill definitions need versions (`version: 2.3`) and version constraints (`requires: kubernetes ">=3.0 <4.0"`). Without versioning, changing a global skill silently changes the behavior of dozens of projects: the agent equivalent of upgrading a library without a lockfile.

A skill is executable behavior even if it contains no traditional code, so it should be validated when it loads: schema validation, dependency validation, tool availability, permission checks, cyclic dependency detection, token budget checks, duplicate names, invalid overrides. `Skill kubernetes-release requires github, but github tool is unavailable` should be caught at load time — not halfway through an operation.

Loading should be observable (active skills, dynamically loaded skills, available-but-unloaded), and provenance should be explicit: which file each skill came from — workspace, user config, or builtin — so precedence and overrides are debuggable. And if skills live in project files, editing one should not require restarting the agent: the runtime monitors skill directories, validates, reloads, and updates the capability index. Whether existing sessions keep the current version or adopt the new one is a runtime policy and should be explicit.

One implementation mistake to avoid:

```text
load skill -> append skill prompt to conversation
```

Now the skill stays in context forever, even when it is no longer active. Skill instructions should be part of the dynamically assembled prompt — system, active profile, active skills, task state, relevant memory, current conversation — rebuilt on every turn. If a skill is no longer active, it simply disappears. [Part 2]({% post_url 2026-09-06-context-is-a-budget-part-2 %}) covers that rebuild in depth.

## Selection: Rules Plus Model Ranking

How should the runtime choose skills? Deterministic routing works for obvious cases (`*.rs → rust`, `Chart.yaml → helm`), but many requests are semantic — "the application works locally but connections fail between pods" could require Kubernetes, networking, and Cilium knowledge. A hybrid of rules, task analysis, and model-assisted ranking works better: the runtime stays in control while the model helps decide relevance.

Model-assisted routing should respect a confidence threshold. If candidates score `kubernetes: 0.96`, `networking: 0.88`, `cilium: 0.61`, and `terraform: 0.12`, the runtime loads the first two and holds Cilium in reserve until evidence points there. That keeps unnecessary context growth down.

Some capabilities can even be derived from project state: a repository containing `.github/workflows/release.yml` gives the runtime enough structure to generate a temporary `project-release-workflow` skill covering trigger, branches, artifact naming, and deployment steps. Derived skills exist because the current workspace provides the structure — they do not need to exist globally.

Different agents should also activate different subsets of the same catalog: a planning profile uses architecture, requirements-analysis, and risk-analysis; an implementation agent uses rust, git, and testing; a review agent loads security-review, code-review, and testing. Skills can even change behavior, not just knowledge — a `production-operations` skill requiring confirmation for destructive actions and defaulting to read-only, or a skill setting `test_after_edit: true`. At that point skills influence orchestration, not just model instructions.

## Resolve Conflicts Before the Prompt

Eventually two skills will disagree: a global git skill says "always commit after successful changes" while a workspace policy says "never commit automatically". The runtime needs deterministic precedence — workspace over profile over global over builtin — producing one effective configuration (`auto_commit: false`) that the model receives. It is dangerous to inject both instructions and hope the LLM resolves the conflict correctly. This is a recurring principle: the model should not be responsible for resolving problems the runtime can resolve deterministically.

Skills also need token budgets — a badly designed skill with tens of thousands of tokens of documentation defeats dynamic loading if one skill consumes half the context window:

```yaml
budget:
  instructions: 3000
  retrieved_context: 8000
  total: 12000
```

If the skill needs more information, it should retrieve incrementally. Documentation in particular should usually be retrieved, not embedded: a Kubernetes skill should declare knowledge sources and a retrieval strategy (`top_k: 5`), not ship the entire Kubernetes documentation.

## Skills Are Packages — Treat Them Like It

The analogy becomes obvious. A skill has a name, version, dependencies, configuration, permissions, capabilities, and documentation. It can be installed, discovered, loaded, unloaded, updated, overridden, and validated. That suggests agent skills eventually need the same infrastructure software packages already have: registries, dependency locking, signatures, compatibility checks.

![AI skill capability package lifecycle: discovery catalog, dynamic activation, scoped tools and permissions, token budgeting, and sandboxed execution.](/assets/posts/2026-09-12/ai-skill-lifecycle.png){: style="max-width: 100%; min-width: 100%; height: auto"}

Security comes with that. Installing a skill is potentially more dangerous than installing documentation — a skill might request shell access, filesystem writes, cloud access, or production Kubernetes access. A runtime should show exactly what capability the user is enabling:

```text
Skill: production-deploy

Requests:

✓ Git repository read
✓ Git repository write
✓ Kubernetes read
✓ Kubernetes update
✗ Kubernetes delete
```

Skill sources need trust levels — builtin is trusted, global is local, workspace is project-level, remote is untrusted. Remote skills should require additional approval before touching sensitive tools. Otherwise a malicious repository could include a helpful-looking skill file and quietly instruct the agent to exfiltrate secrets. That would be an impressively stupid security model — and unfortunately very easy to build. Workspace skills are **executable configuration**, closer to GitHub Actions, Terraform, or Ansible than to a README, and deserve review, validation, permissions, version control, and trust boundaries.

If a skill changes agent behavior, it should be testable:

```yaml
tests:

  - request: "Fix this Rust compiler error"
    expect_skills:
      - rust

  - request: "Why is this pod restarting?"
    expect_skills:
      - kubernetes-debugging

  - request: "Update README wording"
    reject_skills:
      - kubernetes
```

Policy resolution is testable the same way: workspace says `auto_commit: false`, global says `auto_commit: true`, expected result is `false`. Agent configuration should not be mystical. Telemetry rounds it out — tracking loads versus useful tool calls per skill exposes overly broad skills (a skill with 933 loads and 22 useful calls has a routing problem), and over time the runtime could learn which skills frequently appear together. But learning should influence suggestions, never silently override deterministic project policy. Predictability matters more than cleverness in infrastructure systems.

## Skill Versus Agent Versus Tool

The distinctions can now be stated clearly. An agent defines *who is acting*. A skill defines *what the agent can do*. A tool defines *how an action is executed*. Memory defines *what the system remembers*. Context defines *what the agent knows right now* — see [Part 1]({% post_url 2026-09-05-llm-memory-is-not-chat-history-part-1 %}) and [Part 2]({% post_url 2026-09-06-context-is-a-budget-part-2 %}). These concepts overlap, and they should not be collapsed into one giant prompt.

A request moves through the runtime like this:

```text
User Request -> Profile Selection -> Skill Discovery -> Candidate Ranking
   -> Dependency Resolution -> Permission Resolution -> Tool Activation
   -> Context Retrieval -> Context Budgeting -> Skill Activation
   -> Agent Execution -> Tool Calls -> Dynamic Skill Changes -> Result
```

The important part: skill selection happens *before* context assembly, because skills help determine what context should exist. This also solves the giant system prompt problem — instead of one giant agent plus everything it might ever need, you get a small core agent plus task-specific capabilities. Smaller prompts, cleaner boundaries, and behavior that is easier to understand.

## Summary

I increasingly think of an agent runtime as similar to an operating system: the model is the execution engine, the context window is working memory, tools are system calls, memory is persistent storage, profiles define execution behavior, and skills are dynamically loaded capability modules. The runtime decides what gets loaded. The model should not carry the entire environment inside its prompt — that is not intelligence, that is very expensive configuration management.

Calling a reusable prompt a skill is fine for simple systems. But once agents become long-running, tool-using, project-aware systems, that abstraction becomes too weak. A real skill system supports discovery, dynamic loading and unloading, dependencies, project overrides, tool requirements, permissions, context retrieval, budgets, validation, versioning, conflict resolution, provenance, trust levels, and telemetry. The most important shift is conceptual: skills should not simply tell the model more things — they should change what the **runtime makes available to the model**. That turns skills from prompt fragments into genuine capabilities, and I suspect capability management will become one of the defining architectural layers of serious AI agent systems.

## References

- [Part 1: LLM Memory Is Not Chat History]({% post_url 2026-09-05-llm-memory-is-not-chat-history-part-1 %})
- [Part 2: Context Is a Budget]({% post_url 2026-09-06-context-is-a-budget-part-2 %})
- [Part 4: From Prompts to Specifications]({% post_url 2026-09-13-stop-writing-prompts-start-writing-specifications-part-4 %})
- [Part 5: Loops, Guardrails, and Templates]({% post_url 2026-09-20-stop-writing-prompts-start-writing-specifications-part-5 %})
