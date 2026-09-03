---
layout: post
title: "LLM Memory Is Not Chat History, Part 1: Designing Memory for AI Agents"
date: 2026-09-05 10:00:00 +0000
categories: post
tags: [ai, ai-agents, llm, agents, architecture]
author: Tobias Geiser
image: "/assets/posts/2026-09-05/ai-memory.png"
header: "/assets/posts/2026-09-05/ai-memory-header.png"
excerpt_separator: <!--more-->
---

Most AI agents today do not really remember anything. They have context. That is not the same thing. A typical agent takes the current conversation, adds some system instructions, injects a few retrieved documents, sends everything to an LLM, and calls that "memory". It works surprisingly well for short interactions — and breaks down surprisingly fast. This post is about treating memory as its own system, not as a bigger prompt.
<!--more-->

**TL;DR:** A chat log is a history, not a memory. Useful agent memory is selective, scoped, sourced, versioned, and forgettable. The model should help decide what to remember — it should never own the memory.

This is Part 1 of a five-part series on designing AI agent infrastructure. [Part 2]({% post_url 2026-09-06-context-is-a-budget-part-2 %}) covers context as a budget, [Part 3]({% post_url 2026-09-12-skills-are-not-prompts-part-3 %}) covers skills as capability packages, [Part 4]({% post_url 2026-09-13-stop-writing-prompts-start-writing-specifications-part-4 %}) covers specification-driven prompting, and [Part 5]({% post_url 2026-09-20-stop-writing-prompts-start-writing-specifications-part-5 %}) covers execution loops, guardrails, and templates.

## Context Is Temporary. Memory Is Persistent.

An LLM only knows what is inside its current context window. Once something leaves that window, it effectively stops existing unless the application brings it back. That makes the context window closer to working memory than long-term memory.

A useful agent therefore needs at least two different concepts:

- **Working context** — the information required for the current task: the conversation, files being edited, tool results, recent commands, active goals, temporary intermediate decisions.
- **Persistent memory** — information that may still be useful later: user preferences, architecture decisions, project conventions, known infrastructure details, previous failures and their fixes, recurring workflows, relationships between entities.

Trying to keep both inside the same chat log creates problems very quickly. The simplest memory implementation is:

1. Save every message.
2. Send previous messages back to the model.
3. Stop when the context window is full.

That is easy to build, and it is the wrong abstraction. Imagine an engineering agent that has been working on a Kubernetes platform for six months. Its raw conversation history contains old cluster names, temporary debugging ideas, failed hypotheses, deprecated configuration, credentials that should no longer matter, discussions unrelated to the current task, and decisions that were later reversed. More history does not produce better answers — at some point it produces noise.

The important question is therefore not *how much the agent can remember*. It is *how well the agent can decide what to remember*.

## A Practical Memory Model

For an agent platform, I would split memory into several categories.

**Session memory** contains information relevant to the current interaction — current task, open files, recent tool outputs, temporary plans, unresolved questions. It is short-lived and high-detail, and it can be discarded or heavily compressed when the session ends.

**User memory** contains stable preferences about the person using the system:

```yaml
editor: vscode
os: opensuse-tumbleweed
preferred_shell: zsh
response_style: concise
```

This prevents users from repeating themselves constantly. But user memory needs strict limits — agents should avoid silently constructing enormous personal profiles. Only information that genuinely improves future work should be retained.

**Project memory** is often more important than user memory for coding and DevOps agents:

```yaml
project:
  name: example-agent
  language: rust
  frontend: tauri

architecture:
  profiles:
    - plan
    - interactive
    - autopilot

skill_precedence:
  - workspace
  - global
  - builtin
```

These are decisions an agent should not have to rediscover every session. Project memory essentially becomes the institutional knowledge of the agent.

## Decisions Are More Important Than Conversations

One of the most useful memory types is decision memory. A conversation may contain hundreds of messages before a decision is reached; the agent usually does not need those hundreds of messages later. It needs the outcome:

```yaml
decision:
  topic: queued_messages
  result: cancel_existing_queue
  reason: avoid stale instructions executing after context changes
  date: 2026-08-29
```

This is far more useful than replaying twenty messages discussing queue behavior. Decision memory also prevents one of the most irritating agent behaviours: reopening questions that have already been settled.

## Memory Needs History, Confidence, and Sources

A common mistake is treating stored memories as immutable facts. They are not. Architecture evolves, preferences change, infrastructure gets replaced. Instead of overwriting memory blindly, systems should preserve history:

```yaml
- key: runtime
  value: docker
  valid_from: 2025-01
  valid_until: 2026-03

- key: runtime
  value: podman
  valid_from: 2026-03
```

That lets the agent understand not only what is true now, but also what used to be true — which matters when reading old logs, commits, incidents, or documentation.

Not everything the agent stores should be treated as equally reliable, either. Compare "the production cluster runs Kubernetes 1.35" with "I think the old staging cluster might still be on Kubernetes 1.32". A useful memory layer preserves that difference:

```yaml
fact:
  value: "staging cluster runs Kubernetes 1.32"
  confidence: 0.55
  source: conversation
```

The agent can then verify low-confidence memories before relying on them. Without this, guesses slowly turn into "facts". That is dangerous.

Finally, every important memory should know where it came from:

```yaml
memory:
  value: "production uses Cilium"
  source:
    type: repository
    path: infrastructure/kubernetes/cilium.yaml
```

Possible sources include user statements, documentation, Git repositories, configuration files, monitoring systems, previous agent sessions, and tool results. Source tracking makes memory auditable, and it makes updating easier: if the source file changes, the system knows which memories may need revalidation.

## Retrieval Is the Hard Part

Saving memories is easy; retrieving the right memories is much harder. If an agent has 50,000 stored memories, injecting all of them into every prompt defeats the purpose. The retrieval layer needs to combine several signals:

- **Semantic relevance.** Vector search finds memories related to a topic even when the wording differs — a question about authentication configuration can surface memories containing OIDC, OAuth, Keycloak, and JWT.
- **Recency.** Recent information may be more relevant — but recency alone is dangerous. An architecture decision from two years ago may still outrank yesterday's debugging session.
- **Importance.** Some memories carry higher priority. `importance: critical` is appropriate for "Never deploy directly to production. All production changes go through GitOps."
- **Scope.** A memory may belong to a user, organization, workspace, project, repository, session, or agent. An agent working in Project A should not accidentally retrieve assumptions from Project B.

And one more distinction: the memory database and the model context are not the same thing. The agent may retrieve twenty relevant memories without pasting all twenty into the prompt. The system can first transform them into a smaller working representation:

```text
Relevant project constraints:

- Production deployments use Argo CD.
- Direct kubectl changes are prohibited.
- Cilium provides cluster networking.
- Authentication is handled by Keycloak.
```

The raw memories remain stored; the model receives a concise summary. That dramatically reduces token usage and context pollution — a theme [Part 2]({% post_url 2026-09-06-context-is-a-budget-part-2 %}) develops further.

## Forgetting, Handoffs, and Logs

Memory systems focus entirely on remembering. Forgetting is equally important. Information should be removable when it becomes incorrect, obsolete, irrelevant, sensitive, or duplicated. Some memories can expire automatically — `expires_after: 7d` makes sense for temporary incident information — while `retention: permanent` suits important architecture decisions. Forgetting must be an explicit part of the design.

Multi-agent systems introduce another problem. Suppose a planning agent creates an implementation strategy and a coding agent performs the work. Should the coding agent receive the entire planning conversation? Probably not. The planning agent should transfer a structured handoff:

```yaml
task:
  goal: add provider failover

constraints:
  - preserve OpenAI-compatible API
  - no breaking config changes

decisions:
  strategy: priority-based fallback

files:
  - src/providers/
  - config/providers.yaml
```

Agent-to-agent communication should look more like structured memory transfer than forwarded chat history.

Logs and memory serve different purposes, too. Logs answer *what happened*; memory answers *what should the agent know now*. A detailed execution log might contain a tool call, a shell command, a compiler error, a file edit, and a passing test — and the resulting memory might simply be: "The build requires LLVM 20 or newer." The memory is the useful conclusion. The log remains available when deeper investigation is required. Retain both.

## Architecture: The Application Owns the Memory

A practical agent memory system could look like this:

![The agent memory architecture: the user talks to the agent, which combines a short-lived working context with retrieval from an application-owned memory store holding user, project, decision, and agent memory.](/assets/posts/2026-09-05/ai-memory-architecture.png){: style="max-width: 100%; min-width: 100%; height: auto"}

The important point: the model does not directly own the memory — the application does. The LLM is still extremely useful inside this architecture. It can determine whether information is worth storing, what category it belongs to, which memories are relevant, whether memories contradict each other, how to summarize them, and whether new information supersedes old. After a session, the model could produce:

```yaml
new_memories:
  - type: decision
    key: profile_storage
    value: yaml
    importance: high

  - type: project_fact
    key: skill_location
    value: .agent/skills
    importance: high

discard:
  - temporary debugging output
  - failed UI experiment
```

That is a much better use of an LLM than asking it to summarize the entire conversation.

## The Biggest Risk: Memory Corruption

Persistent agent memory creates a new class of failure: a wrong answer today becomes a wrong memory tomorrow, and once stored, that wrong information can affect hundreds of future interactions. The feedback loop looks like this: the agent guesses that service X runs on port 8443, the system stores it, and three weeks later another agent retrieves it as established knowledge. The original guess has become infrastructure "fact".

Memory therefore needs validation mechanisms. Important memories should be backed by authoritative sources whenever possible — for engineering agents, configuration files and repositories should outrank conversational assumptions.

Observability is part of the same defense. If an agent uses persistent memory, users should be able to inspect it. Asking "what do you remember about this project?" should produce a useful answer, and the UI should expose stored memories, their source, creation time, confidence, scope, last usage, and edit/delete controls. Invisible memory may feel magical at first; eventually it becomes impossible to debug — and debugging an agent that remembers something incorrectly is strange enough without hiding the memory system too.

## Four Layers: Context, Memory, Knowledge, History

For the agent systems I design, I increasingly think about memory as four separate layers:

- **Context** — what the model needs right now.
- **Memory** — what may be useful again later.
- **Knowledge** — external information retrievable from repositories, documentation, databases, or APIs.
- **History** — a complete record of what actually happened.

They overlap, but they should not be treated as interchangeable. A conversation belongs primarily to history. A stable project decision belongs to memory. A Kubernetes manifest belongs to knowledge. The subset required to solve the current problem becomes context. That separation makes the entire architecture much easier to reason about.

## Summary

Long context windows are impressive, and they are not a replacement for memory. Giving an agent a million-token context window does not solve the fundamental problem — it allows the agent to forget more slowly. Useful AI agents need memory systems that can:

- extract important information and discard noise
- maintain scope and track sources
- preserve confidence and handle changes over time
- retrieve selectively
- transfer knowledge between agents
- allow inspection and deletion

Building persistent AI agents is not primarily a prompt-engineering problem. It is a data architecture problem. And once agents operate across projects, tools, repositories, and long-running workflows, memory may become one of the most important parts of the entire system.

## References

- [Part 2: Context Is a Budget]({% post_url 2026-09-06-context-is-a-budget-part-2 %})
- [Part 3: Skills Are Not Prompts]({% post_url 2026-09-12-skills-are-not-prompts-part-3 %})
- [Part 4: From Prompts to Specifications]({% post_url 2026-09-13-stop-writing-prompts-start-writing-specifications-part-4 %})
- [Part 5: Loops, Guardrails, and Templates]({% post_url 2026-09-20-stop-writing-prompts-start-writing-specifications-part-5 %})
