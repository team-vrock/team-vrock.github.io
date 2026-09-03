---
layout: post
title: "Context Is a Budget, Part 2: Designing Efficient AI Agent Context"
date: 2026-09-06 10:00:00 +0000
categories: post
tags: [ai, ai-agents, llm, agents, architecture]
author: Tobias Geiser
image: "/assets/posts/2026-09-06/ai-context.png"
header: "/assets/posts/2026-09-06/ai-context-header.png"
excerpt_separator: <!--more-->
---

Large context windows are useful — and dangerously easy to waste. When building AI agents, it is tempting to keep adding to the prompt: system instructions, history, tool descriptions, tool results, repository context, project rules, user preferences, skills, memories, documentation, logs, plans. Eventually the model receives everything and somehow understands less. This post treats context as what it really is: an engineering resource with a budget.
<!--more-->

**TL;DR:** The real question is not *how much context the model can accept* but *what is worth spending context on right now*. Manage context with explicit token budgets, dynamic loading and unloading, filtered tool results, deduplication with source authority, and rebuild the context every turn instead of accumulating it.

This is Part 2 of a five-part series on designing AI agent infrastructure. [Part 1]({% post_url 2026-09-05-llm-memory-is-not-chat-history-part-1 %}) covered persistent memory, [Part 3]({% post_url 2026-09-12-skills-are-not-prompts-part-3 %}) covers skills as capability packages, [Part 4]({% post_url 2026-09-13-stop-writing-prompts-start-writing-specifications-part-4 %}) covers specification-driven prompting, and [Part 5]({% post_url 2026-09-20-stop-writing-prompts-start-writing-specifications-part-5 %}) covers execution loops, guardrails, and templates.

## Context Windows Are Not Free

Suppose a model supports a 200,000-token context window. At first glance that sounds enormous, but an agent can consume it surprisingly quickly. Imagine a coding session containing:

```text
System prompt                 8,000 tokens
Tool definitions             12,000 tokens
Agent instructions            6,000 tokens
Skills                        8,000 tokens
Repository context           35,000 tokens
Conversation history         30,000 tokens
Previous tool results        40,000 tokens
Documentation                20,000 tokens
Current task                 10,000 tokens
```

That is 169,000 tokens — and the model has not produced its next answer yet. Long-running agents make it worse: every tool call can add output, every code search adds snippets, every file read adds content, every agent handoff adds instructions. Having a large context window does not mean all of that information belongs there.

More context can improve performance, but only when the additional information is relevant. Irrelevant context makes important instructions harder to find, keeps outdated information visible, duplicates data, increases the chance of conflicting instructions, lets tool results overwhelm the conversation, and increases latency, cost, and reasoning degradation. The goal is not maximum context — it is **maximum useful information per token**.

## The Context Stack

I find it useful to think about an agent prompt as a stack of layers:

![The context stack: every prompt is assembled from layers — system policy, profile and project instructions, dynamically loaded skills, relevant memory, the current conversation, tool results, retrieved knowledge, and the user request.](/assets/posts/2026-09-06/ai-context-stack.png){: style="max-width: 100%; min-width: 100%; height: auto"}

Not every layer should always be present — that is the important part. A good agent runtime assembles context dynamically for each turn.

## System Prompts Should Be Small and Stable

System prompts tend to grow: a new edge case appears, another paragraph gets added, then another rule, until the prompt becomes a miniature operating manual. That is usually a mistake. The core system prompt should contain things that are globally true, security relevant, fundamental to agent behavior, difficult or dangerous to override, and applicable to almost every request:

```text
You are a software engineering agent.

Do not modify files outside the active workspace.

Inspect existing code before making architectural changes.

Never expose secrets from environment variables.

Use available tools instead of inventing their output.
```

Project-specific guidance does not belong there. "When working with Helm charts for Project Foobar, always place environment-specific overrides in…" belongs in project instructions or a skill. The system prompt defines the operating system of the agent; it should not contain every application installed on it.

The same applies to agent definitions. Many frameworks define agents as large instruction blocks — 400 lines of prompt per agent. That works, but it does not scale. An agent definition should describe role and behavior, and let the runtime load capabilities only when required:

```yaml
profile:
  name: plan

  role: architecture_and_planning

  permissions:
    filesystem: read
    shell: read_only

  behavior:
    implementation: false
    planning: true
```

This separates *who the agent is* from *what the agent currently needs to know* — a distinction that becomes critical once agents can use dozens of skills.

## Load Skills and Tools Dynamically

Suppose an engineering agent has access to Kubernetes, Terraform, Ansible, Docker, React, Rust, Python, PostgreSQL, AWS, Azure, GCP, GitHub Actions, Helm, Prometheus, and Grafana skills. Loading every skill into every prompt would be absurd: a request like "Fix this Rust lifetime error" needs none of the AWS deployment conventions or Prometheus alerting rules.

Skills should be loaded dynamically — the agent determines which capabilities are relevant, then the runtime injects them. Discovery is separate from loading: a lightweight skill catalog with cheap name-and-description entries can expose hundreds of skills, while full definitions load only when selected. That gives you `discover -> load` instead of `load everything -> hope the model ignores most of it`. [Part 3]({% post_url 2026-09-12-skills-are-not-prompts-part-3 %}) designs this capability system in depth.

Tool definitions deserve the same treatment. A sophisticated agent environment exposes filesystem, shell, Git, GitHub, Kubernetes, cloud, database, browser, ticketing, observability, and deployment tools — if every schema loads into every request, tool definitions alone consume tens of thousands of tokens. A better architecture uses tool groups:

```yaml
tool_groups:

  coding:
    - filesystem
    - shell
    - git

  kubernetes:
    - kubectl
    - helm
    - cluster_logs

  github:
    - issues
    - pull_requests
    - actions
```

The runtime activates groups based on the task. A simple code-edit request receives only filesystem, shell, and git — the Kubernetes APIs never enter the model context.

## Tool Calls Are Context Producers

Calling a tool does not just perform an action; it produces context. Consider `kubectl get pods -A -o yaml` — the command may return 50,000 tokens when the agent needed five lines. Agent runtimes should therefore treat tool output as data requiring processing, not automatically as prompt content:

```text
Raw Tool Output -> Parsing -> Filtering -> Relevant Result -> Agent Context
```

Instead of keeping the full dump, the runtime might extract:

```yaml
problematic_pods:
  - namespace: payments
    name: api-7f79db
    status: CrashLoopBackOff
    restarts: 42
```

The raw result stays available in logs; the model gets the useful part. The most effective optimization avoids large results entirely: instead of returning a 40,000-token file, return a reference — resource id, path, size — and let the agent request the relevant section (`read lines 420-510`). That is a lazy-loading model: the context contains pointers instead of copies.

Tool results also need lifetimes. In the sequence *inspect file → modify → run tests → inspect compiler output → fix → tests pass*, the compiler error from step 4 becomes irrelevant once step 6 succeeds. Marking results with a relevance and an expiry condition (`expires_when: build_succeeds`) lets the runtime remove solved problems from working context.

## Compress — But Preserve Recoverability

Eventually even well-managed context grows, and compression becomes necessary. But compression should not mean "summarize the entire conversation" — that destroys useful detail. Different information types compress differently.

A conversation where the user proposes option A, rejects options B and C, and chooses A with modification X becomes:

```yaml
decision:
  selected: A
  modification: X

rejected:
  - B
  - C
```

The useful state survives; the discussion is gone. Five hundred lines of compiler output become a structured build status with the failing file, line, and error. Whole source files become a structural representation — module responsibilities and interfaces — with exact code loaded only when necessary.

Compression is lossy, so the original data must remain available:

```text
Raw History -----> persistent log
    |
    v
Compressed State
    |
    v
Working Context
```

If the model later needs detail, it can retrieve the original. This is how databases work: indexes do not replace data, they make finding it efficient.

## Deduplication Needs Authority

Agent prompts frequently contain the same information several times — the system prompt says "use pnpm", the project instructions say "this repository uses pnpm", the README says "install with pnpm", the conversation says "remember, we use pnpm", and a memory says "package manager = pnpm". Five statements, one fact, five times the tokens. This happens constantly in agent systems.

Exact string matching is not enough, because "Use pnpm for dependencies" and "Do not use npm; this repository uses pnpm" mean approximately the same thing. A context builder should detect semantic duplication and produce one canonical statement: "Package manager: pnpm. Do not use npm."

Deduplication becomes dangerous when sources disagree:

```text
README:        Node 20
package.json:  Node >=22
Memory:        Node 20
```

The runtime should not merge these blindly — it needs source priority:

```text
Current configuration > Repository documentation > Project memory > Conversation history
```

The resulting context states the authoritative requirement and notes the outdated memory, instead of showing the model three conflicting facts and hoping it chooses correctly.

## Budgets, Priorities, and Reserved Output

Most runtimes treat context size as something that happens accidentally. I think allocation should be intentional:

```yaml
context_budget:

  total: 128000

  system:
    max: 8000

  tools:
    max: 12000

  skills:
    max: 16000

  conversation:
    max: 20000

  retrieved_code:
    max: 40000

  memory:
    max: 8000

  reserved_output:
    min: 24000
```

The numbers obviously vary. The idea is that different context sources compete for limited space — without budgets, conversation history or tool output tends to consume everything.

Two related rules. First, reserve output space: if a model supports 128k tokens, you cannot necessarily send 128k tokens and still expect a large response. The runtime must account for input *and* output tokens — reasoning, generated code, tool calls, and final responses all need room. Second, when the budget is exceeded, something needs to go, and that requires priorities:

```text
1. Security policy
2. Current user request
3. Active task state
4. Relevant code
5. Project rules
6. Relevant memory
7. Recent conversation
8. Historical tool output
9. Old conversation
```

This is far more predictable than dropping the oldest messages. Old information can be critical; recent information can be useless.

## Handoffs and Views

Multi-agent systems make context problems significantly worse. If every agent in a planner → research → coding → review chain receives the complete history of every previous agent, context grows exponentially. Agents should exchange structured handoffs instead:

```yaml
handoff:

  objective:
    implement provider fallback

  decisions:
    - use ordered provider priority
    - retry only transient failures

  constraints:
    - preserve current API
    - no config breaking changes

  relevant_files:
    - src/providers/mod.rs
    - src/config/providers.rs

  unresolved:
    - whether fallback should preserve conversation IDs
```

Different agents also need different slices of the same project. A planning agent needs architecture, requirements, dependencies, and existing decisions; a coding agent needs implementation files, tests, interfaces, and style conventions; a review agent needs the diff, requirements, security rules, and test results. Agent specialization should apply to context retrieval as well as behavior.

Skills can even orchestrate context themselves — a Kubernetes troubleshooting skill declaring that it requires `kubectl`, wants cluster version, affected namespace, manifests, and recent events retrieved, and wants unrelated namespaces avoided. Dynamic loading can be recursive (start with Kubernetes debugging, discover a Cilium network policy issue, load the Cilium skill), and unloading matters as much as loading: if the issue is no longer about Cilium, that skill no longer deserves context space. Context should behave like memory pages, not an append-only log: load, use, evict, reload when necessary.

## Cache Carefully

Many context elements rarely change — system prompt, tool descriptions, project instructions, repository architecture summary. Where model APIs support prompt caching, that significantly reduces repeated processing; independent of providers, the runtime can cache summaries, parsed repository structure, skill indexes, tool metadata, embeddings, and retrieval results.

The important part is invalidation. A cached repository summary that survives major code changes becomes misinformation, which means caching needs version awareness. Content addressing helps: identify context artifacts by hash (`sha256:81a6...` for `src/runtime.rs`), and reuse previously computed summaries, embeddings, symbol indexes, and dependency graphs only while the hash is unchanged.

## Context Should Be Observable

A developer using an AI agent should be able to inspect what the model actually received — otherwise debugging becomes guesswork. A useful UI shows the usage breakdown:

```text
Context Usage: 74,320 / 128,000

System               5,320
Agent                 2,410
Skills                6,800
Tools                 9,220
Memory                3,900
Conversation          11,750
Repository            28,400
Tool Results           6,520
```

Plus which skills are loaded versus merely available. Observability should go one step further: when the model states "This repository uses PostgreSQL 18", the interface should trace that statement back to `docker-compose.yml`, line 24, or to a project memory created on a specific date. That is provenance — essential once context is assembled dynamically from many sources.

## Context Engineering Is Infrastructure

Prompt engineering is often described as writing better instructions. That is only a small part of building serious agents. Once an agent has tools, skills, memory, sub-agents, repositories, external knowledge, and long-running sessions, the main challenge becomes context orchestration. The runtime must continuously answer: what information exists, which is relevant, which source is authoritative, what should be loaded, removed, summarized, kept exact, deduplicated, refreshed, and passed to another agent.

An agent turn could run through a pipeline like this:

```text
User Request -> Task Classification -> Profile Selection -> Skill Discovery
   -> Tool Selection -> Memory Retrieval -> Repository Retrieval
   -> Deduplication -> Conflict Resolution -> Compression
   -> Token Budgeting -> Context Assembly -> LLM -> Tool Calls
   -> Result Filtering -> Continue Context / Persistent Logs -> Memory Extraction
```

Notice what the LLM is *not* doing: it is not receiving the entire world. The runtime decides which part of the world the LLM needs.

## Rebuild, Do Not Accumulate

This may be the most important architectural change. Traditional chat systems treat context as an append-only sequence of messages. Agent systems should instead construct context from state — every turn rebuilds the optimal context from system, current profile, relevant skills, current task, relevant memory, required code, and recent useful events. Old information does not remain just because it once entered the conversation. Context stops being history and becomes a **computed view**.

The more I work with agent architectures, the more context looks like a database query:

```sql
SELECT relevant_information
FROM everything
WHERE useful_for_current_task = true
ORDER BY importance DESC
LIMIT context_budget;
```

The implementation is more complicated, but conceptually that is exactly the problem. The context window is not the database. It is the query result.

## Summary

Models will keep getting larger context windows, and that is useful — but going from 128k to 1M tokens does not eliminate context engineering; it makes bad context management easier to hide. A good agent runtime actively manages system prompts, profiles, skills, tools and their outputs, memory, repository context, conversation history, loading and unloading, compression, deduplication, source authority, budgets, and handoffs.

The goal is not to put everything into the model. The goal is to give the model the **smallest context that contains everything it needs** — cheaper requests, faster responses, fewer contradictions, cleaner handoffs, and usually better reasoning. Memory determines what an agent can know across time; context management determines what it can think about right now. Both need to be designed deliberately.

## References

- [Part 1: LLM Memory Is Not Chat History]({% post_url 2026-09-05-llm-memory-is-not-chat-history-part-1 %})
- [Part 3: Skills Are Not Prompts]({% post_url 2026-09-12-skills-are-not-prompts-part-3 %})
- [Part 4: From Prompts to Specifications]({% post_url 2026-09-13-stop-writing-prompts-start-writing-specifications-part-4 %})
- [Part 5: Loops, Guardrails, and Templates]({% post_url 2026-09-20-stop-writing-prompts-start-writing-specifications-part-5 %})
