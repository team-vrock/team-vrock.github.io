# LLM Memory Is Not Chat History — Designing Memory for AI Agents

Most AI agents today do not really remember anything.

They have context.

That is not the same thing.

A typical agent takes the current conversation, adds some system instructions, maybe injects a few retrieved documents, sends everything to an LLM, and calls that “memory”.

It works surprisingly well for short interactions.

It also breaks down surprisingly fast.

Once agents run for hours, days, or across multiple sessions, a simple chat history becomes a terrible memory system. It grows too large, contains too much irrelevant information, repeats outdated assumptions, and forces the model to constantly re-read things it should already “know”.

If we want agents that feel persistent and useful, we need to treat memory as its own system.

Not as a bigger prompt.

---

## Context Is Temporary. Memory Is Persistent.

An LLM only knows what is inside its current context window.

Once something leaves that window, it effectively stops existing unless the application brings it back.

That makes the context window closer to working memory than long-term memory.

A useful agent therefore needs at least two different concepts:

**Working context**

The information required to perform the current task.

Examples:

- the current conversation
- files being edited
- tool results
- recent commands
- active goals
- temporary intermediate decisions

**Persistent memory**

Information that may still be useful later.

Examples:

- user preferences
- architecture decisions
- project conventions
- known infrastructure details
- previous failures and their fixes
- recurring workflows
- relationships between entities

Trying to keep both inside the same chat log creates problems very quickly.

---

## Why Storing the Whole Conversation Is a Bad Idea

The simplest memory implementation is:

1. save every message
2. send previous messages back to the model
3. stop when the context window is full

This is easy to build.

It is also the wrong abstraction.

Imagine an engineering agent that has been working on a Kubernetes platform for six months.

Its raw conversation history may contain:

- old cluster names
- temporary debugging ideas
- failed hypotheses
- deprecated configuration
- credentials that should no longer be relevant
- discussions unrelated to the current task
- decisions that were later reversed

More history does not necessarily produce better answers.

At some point it produces noise.

The important question is therefore not:

> How much can the agent remember?

It is:

> How well can the agent decide what to remember?

---

## Memory Should Be Selective

Human memory is selective for a reason.

An agent should not permanently store every shell command, every failed thought, or every sentence the user writes.

Instead, the system should extract things that are likely to matter again.

For example:

```text
User prefers openSUSE Tumbleweed for desktop systems.
```

That may be worth keeping.

This probably is not:

```text
User ran `ls -la` at 14:32.
```

Likewise, this is valuable:

```text
Project decision:
Skills are loaded in the following precedence order:

workspace -> global -> built-in
```

While this is likely temporary:

```text
Try changing the timeout to 15 seconds.
```

A useful memory layer therefore needs some form of classification.

---

## A Practical Memory Model

For an agent platform, I would split memory into several categories.

### Session Memory

Session memory contains information relevant to the current interaction.

It is short-lived and high-detail.

Examples:

- current task
- open files
- recent tool outputs
- temporary plans
- unresolved questions

This memory can be discarded or heavily compressed when the session ends.

---

### User Memory

User memory contains stable preferences and recurring information about the person using the system.

Examples:

```yaml
editor: vscode
os: opensuse-tumbleweed
preferred_shell: zsh
response_style: concise
```

This prevents users from having to repeat themselves constantly.

But user memory needs strict limits.

Agents should avoid silently constructing enormous personal profiles.

Only information that genuinely improves future work should be retained.

---

### Project Memory

For coding and DevOps agents, project memory is often more important than user memory.

Examples:

```yaml
project:
  name: ocuci
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

These are decisions an agent should not have to rediscover every session.

Project memory essentially becomes the institutional knowledge of the agent.

---

## Decisions Are More Important Than Conversations

One of the most useful memory types is decision memory.

A conversation may contain hundreds of messages before a decision is reached.

The agent usually does not need those hundreds of messages later.

It needs the outcome.

For example:

```yaml
decision:
  topic: queued_messages
  result: cancel_existing_queue
  reason: avoid stale instructions executing after context changes
  date: 2026-08-29
```

This is far more useful than replaying twenty messages discussing queue behavior.

Decision memory also helps avoid one of the most irritating agent behaviours:

Reopening questions that have already been settled.

---

## Memory Needs History

A common mistake is treating stored memories as immutable facts.

They are not.

Architecture evolves.

Preferences change.

Infrastructure gets replaced.

Instead of overwriting memory blindly, systems should ideally preserve some history.

For example:

```yaml
- key: runtime
  value: docker
  valid_from: 2025-01
  valid_until: 2026-03

- key: runtime
  value: podman
  valid_from: 2026-03
```

This allows the agent to understand not only what is true now, but also what used to be true.

That matters when reading old logs, commits, incidents, or documentation.

---

## Memory Should Have Confidence

Not everything the agent stores should be treated as equally reliable.

Consider these statements:

```text
The production cluster runs Kubernetes 1.35.
```

versus:

```text
I think the old staging cluster might still be on Kubernetes 1.32.
```

A useful memory layer should preserve that difference.

One possible representation:

```yaml
fact:
  value: "staging cluster runs Kubernetes 1.32"
  confidence: 0.55
  source: conversation
```

The agent can then verify low-confidence memories before relying on them.

Without this, guesses slowly turn into “facts”.

That is dangerous.

---

## Memory Needs Sources

Every important memory should ideally know where it came from.

Possible sources include:

- user statements
- documentation
- Git repositories
- configuration files
- monitoring systems
- previous agent sessions
- tool results

For example:

```yaml
memory:
  value: "production uses Cilium"
  source:
    type: repository
    path: infrastructure/kubernetes/cilium.yaml
```

Source tracking makes memory auditable.

It also makes updating it easier.

If the source file changes, the system knows which memories may need revalidation.

---

## Retrieval Is the Hard Part

Saving memories is easy.

Retrieving the right memories is much harder.

If an agent has 50,000 stored memories, injecting all of them into every prompt defeats the purpose.

The retrieval layer needs to select only what is useful for the current task.

That selection could combine several signals.

### Semantic relevance

Vector search works well for finding memories related to a topic.

For example:

```text
How did we configure authentication for the API?
```

may retrieve memories containing:

```text
OIDC
OAuth
Keycloak
JWT
```

even if the exact wording differs.

---

### Recency

Recent information may be more relevant than old information.

But recency alone is dangerous.

An architecture decision from two years ago may still be more important than yesterday's debugging session.

---

### Importance

Some memories should carry higher priority.

For example:

```yaml
importance: critical
```

might be appropriate for:

```text
Never deploy directly to production.
All production changes go through GitOps.
```

---

### Scope

Memory should also be scoped.

A memory may belong to:

```text
user
organization
workspace
project
repository
session
agent
```

An agent working in Project A should not accidentally retrieve assumptions from Project B.

---

## Memory Should Not Automatically Become Prompt Text

This is another important distinction.

The memory database and the model context are not the same thing.

An agent may retrieve twenty relevant memories.

It does not necessarily need to paste all twenty into the prompt.

The system can first transform them into a smaller working representation.

For example:

```text
Relevant project constraints:

- Production deployments use Argo CD.
- Direct kubectl changes are prohibited.
- Cilium provides cluster networking.
- Authentication is handled by Keycloak.
```

The raw memories remain stored.

The model receives a concise summary.

This dramatically reduces token usage and context pollution.

---

## Agents Should Be Able to Forget

Memory systems often focus entirely on remembering.

Forgetting is equally important.

Information should be removable when it becomes:

- incorrect
- obsolete
- irrelevant
- sensitive
- duplicated

Some memories could expire automatically.

For example:

```yaml
expires_after: 7d
```

might make sense for temporary incident information.

Other memories should remain indefinitely.

```yaml
retention: permanent
```

could apply to important architecture decisions.

Forgetting should therefore be an explicit part of the design.

---

## Memory Transfer Between Agents

Multi-agent systems introduce another interesting problem.

Suppose a planning agent creates an implementation strategy.

A coding agent then performs the work.

Should the coding agent receive the entire planning conversation?

Probably not.

Instead, the planning agent should transfer a structured handoff.

For example:

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

This is much cleaner than sending an entire transcript.

Agent-to-agent communication should look more like structured memory transfer than forwarded chat history.

---

## Logs Are Not Memory Either

Logs and memory serve different purposes.

Logs answer:

> What happened?

Memory answers:

> What should the agent know now?

An agent system should retain both.

A detailed execution log might contain:

```text
12:01 tool call
12:01 shell command
12:02 compiler error
12:03 file edited
12:04 tests passed
```

The resulting memory might simply be:

```text
The build requires LLVM 20 or newer.
```

The memory is the useful conclusion.

The log remains available when deeper investigation is required.

---

## A Possible Architecture

A practical agent memory system could look something like this:

```text
                 +-------------------+
                 |       User        |
                 +---------+---------+
                           |
                           v
                 +-------------------+
                 |      Agent        |
                 +---------+---------+
                           |
            +--------------+--------------+
            |                             |
            v                             v
   +------------------+          +------------------+
   | Working Context  |          | Memory Retrieval |
   +------------------+          +--------+---------+
                                          |
                                          v
                                 +------------------+
                                 |   Memory Store   |
                                 +--------+---------+
                                          |
             +----------------------------+---------------------------+
             |                |               |                      |
             v                v               v                      v
       User Memory      Project Memory   Decisions            Agent Memory
```

The important point is that the model does not directly own the memory.

The application does.

The model is used to interpret, retrieve, summarize, and potentially create memories.

But memory itself is infrastructure.

---

## What Should the LLM Do?

The LLM is still extremely useful inside this architecture.

It can help determine:

- whether information is worth storing
- what category it belongs to
- which memories are relevant
- whether memories contradict each other
- how to summarize them
- whether new information supersedes old information

For example, after a session the model could produce:

```yaml
new_memories:
  - type: decision
    key: profile_storage
    value: yaml
    importance: high

  - type: project_fact
    key: skill_location
    value: .ocuci
    importance: high

discard:
  - temporary debugging output
  - failed UI experiment
```

This is a much better use of an LLM than simply asking it to summarize the entire conversation.

---

## The Biggest Risk: Memory Corruption

Persistent agent memory creates a new class of failure.

A wrong answer today may become a wrong memory tomorrow.

And once stored, that wrong information can affect hundreds of future interactions.

This creates feedback loops.

For example:

```text
Agent guesses that service X runs on port 8443.
```

The system stores it.

Three weeks later another agent retrieves it as established knowledge.

Now the original guess has become infrastructure “fact”.

Memory therefore needs validation mechanisms.

Important memories should ideally be backed by authoritative sources whenever possible.

For engineering agents, configuration files and repositories should outrank conversational assumptions.

---

## Memory Should Be Observable

If an agent uses persistent memory, users should be able to inspect it.

I would consider this a fundamental design requirement.

You should be able to ask:

```text
What do you remember about this project?
```

and get a useful answer.

Even better, the UI should expose:

- stored memories
- memory source
- creation time
- confidence
- scope
- last usage
- edit/delete controls

Invisible memory may feel magical at first.

Eventually it becomes impossible to debug.

And debugging an AI agent that remembers something incorrectly is already strange enough without hiding the memory system too.

---

## My Preferred Model

For the agent systems I design, I increasingly think about memory as four separate layers:

### Context

What the model needs right now.

### Memory

What may be useful again later.

### Knowledge

External information that can be retrieved from repositories, documentation, databases, or APIs.

### History

A complete record of what actually happened.

They overlap, but they should not be treated as interchangeable.

A conversation belongs primarily to history.

A stable project decision belongs to memory.

A Kubernetes manifest belongs to knowledge.

The subset required to solve the current problem becomes context.

That separation makes the entire architecture much easier to reason about.

---

## Final Thoughts

Long context windows are impressive.

They are also not a replacement for memory.

Giving an agent a million-token context window does not solve the fundamental problem.

It simply allows the agent to forget more slowly.

Useful AI agents need memory systems that can:

- extract important information
- discard noise
- maintain scope
- track sources
- preserve confidence
- handle changes over time
- retrieve selectively
- transfer knowledge between agents
- allow inspection and deletion

In other words, building persistent AI agents is not primarily a prompt-engineering problem.

It is a data architecture problem.

And once agents start operating across projects, tools, repositories, and long-running workflows, memory may become one of the most important parts of the entire system.