# Context Is a Budget — Designing Efficient AI Agent Context

Large context windows are useful.

They are also dangerously easy to waste.

When building AI agents, it is tempting to keep adding information to the prompt:

- system instructions
- conversation history
- tool descriptions
- tool results
- repository context
- project rules
- user preferences
- skills
- agent definitions
- retrieved memories
- documentation
- logs
- plans

Eventually the model receives everything.

And somehow understands less.

A modern AI agent therefore needs more than a large context window.

It needs **context management**.

The real problem is not:

> How much context can the model accept?

It is:

> What is worth spending context on right now?

That turns context into an engineering resource.

A budget.

---

## Context Windows Are Not Free

Suppose a model supports a 200,000-token context window.

At first glance, that sounds enormous.

But an agent can consume it surprisingly quickly.

Imagine a coding session containing:

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

We are already at:

```text
169,000 tokens
```

And the model has not produced its next answer yet.

Long-running agents make this worse.

Every tool call can add more output.

Every code search adds snippets.

Every file read adds content.

Every agent handoff adds instructions.

Simply having a large context window does not mean all of that information belongs there.

---

## Context Quality Matters More Than Context Size

More context can improve performance.

But only when the additional information is relevant.

Irrelevant context creates several problems:

- important instructions become harder to find
- outdated information remains visible
- duplicated data increases token usage
- conflicting instructions become more likely
- tool results overwhelm the conversation
- latency increases
- cost increases
- reasoning quality can degrade

The goal should therefore not be maximum context.

It should be **maximum useful information per token**.

That is a very different optimization target.

---

# The Context Stack

I find it useful to think about an agent prompt as a stack of layers.

Something like:

```text
+-------------------------------------+
| System Policy                       |
+-------------------------------------+
| Agent / Profile Instructions        |
+-------------------------------------+
| Project Instructions                |
+-------------------------------------+
| Dynamically Loaded Skills           |
+-------------------------------------+
| Relevant Memory                     |
+-------------------------------------+
| Current Conversation                |
+-------------------------------------+
| Tool Results                        |
+-------------------------------------+
| Retrieved Files / Knowledge         |
+-------------------------------------+
| Current User Request                |
+-------------------------------------+
```

Not every layer should always be present.

That is important.

A good agent runtime should assemble context dynamically for each turn.

---

# System Prompts Should Be Small and Stable

System prompts tend to grow.

A new edge case appears.

Another paragraph gets added.

Then another rule.

Eventually the system prompt becomes a miniature operating manual.

This is usually a mistake.

The core system prompt should contain things that are:

- globally true
- security relevant
- fundamental to agent behavior
- difficult or dangerous to override
- applicable to almost every request

For example:

```text
You are a software engineering agent.

Do not modify files outside the active workspace.

Inspect existing code before making architectural changes.

Never expose secrets from environment variables.

Use available tools instead of inventing their output.
```

That makes sense globally.

This does not:

```text
When working with Helm charts for Project Foobar,
always place environment-specific overrides in...
```

That belongs in project instructions or a skill.

The system prompt should define the operating system of the agent.

It should not contain every application installed on it.

---

# Agents Should Not Be Giant Prompts Either

Many agent frameworks define agents as large blocks of instructions.

For example:

```yaml
agent:
  name: planner
  prompt: |
    You are an expert software architect...
    ...
    400 lines later...
```

This works.

But it does not scale well.

Instead, an agent definition should describe its role and behavior.

For example:

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

The runtime can then load additional capabilities only when required.

This separates:

**who the agent is**

from:

**what the agent currently needs to know**.

That distinction becomes extremely important once agents can use dozens or hundreds of skills.

---

# Skills Should Be Dynamically Loaded

Suppose an engineering agent has access to these skills:

```text
Kubernetes
Terraform
Ansible
Docker
Podman
React
Rust
Python
PostgreSQL
AWS
Azure
GCP
GitHub Actions
GitLab CI
Argo CD
Helm
OpenTelemetry
Prometheus
Grafana
```

Loading every skill into every prompt would be absurd.

A request like:

```text
Fix this Rust lifetime error.
```

does not need:

```text
AWS deployment conventions
Helm chart guidelines
Prometheus alerting rules
React frontend conventions
```

Skills should therefore be loaded dynamically.

The agent first determines which capabilities are relevant.

Then the runtime injects them.

For example:

```text
User Request
     |
     v
Intent Detection
     |
     v
Skill Selection
     |
     +------> Rust
     |
     +------> Repository Guidelines
     |
     +------> Testing
```

Only those skills enter the working context.

---

# Skill Discovery Is Different From Skill Loading

This introduces another problem.

How does the model know which skills exist without loading them all?

The answer is a lightweight skill index.

Instead of injecting complete skill definitions:

```yaml
skills:
  - name: kubernetes
    description: Kubernetes architecture, workloads and troubleshooting

  - name: rust
    description: Rust development, Cargo, lifetimes and ownership

  - name: git
    description: Git workflows, branching and repository operations
```

The descriptions are cheap.

The runtime can expose perhaps hundreds of skill descriptors.

The full skill content is loaded only when selected.

That gives us two stages:

```text
discover -> load
```

instead of:

```text
load everything -> hope the model ignores most of it
```

---

# Dynamic Loading Should Apply to Tools Too

Tool definitions can consume a surprising amount of context.

A sophisticated agent environment might expose:

```text
filesystem tools
shell tools
Git tools
GitHub tools
Kubernetes tools
cloud APIs
database tools
browser tools
ticketing tools
observability tools
deployment tools
```

If every tool schema is loaded into every request, tool definitions alone can consume tens of thousands of tokens.

That is wasteful.

A better architecture uses tool groups.

For example:

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

The runtime activates tool groups based on the task.

A simple code-edit request may receive only:

```text
filesystem
shell
git
```

The Kubernetes APIs never enter the model context.

---

# Tool Calls Are Context Producers

Calling a tool does not just perform an action.

It produces context.

That distinction matters.

Consider:

```bash
kubectl get pods -A -o yaml
```

The command may return 50,000 tokens.

The agent probably needed five lines.

This means agent runtimes should treat tool output as data requiring processing.

Not automatically as prompt content.

---

# Tool Results Need Filters

A tool result can go through several stages:

```text
Raw Tool Output
      |
      v
Parsing
      |
      v
Filtering
      |
      v
Relevant Result
      |
      v
Agent Context
```

For example, instead of keeping:

```text
kubectl get pods -A -o yaml
```

the runtime might extract:

```yaml
problematic_pods:
  - namespace: payments
    name: api-7f79db
    status: CrashLoopBackOff
    restarts: 42
```

The full raw result can remain available in logs.

The model only needs the useful part.

---

# Tools Should Return References When Possible

One of the most effective context optimizations is avoiding large results entirely.

Instead of returning a 40,000-token file:

```text
tool -> complete file content
```

return:

```yaml
resource:
  id: file_83
  path: src/agent/runtime.rs
  size: 184223
```

The agent can then request the relevant section:

```text
read lines 420-510
```

This creates a lazy-loading model.

The context contains pointers to information instead of copies of everything.

That architecture scales much better.

---

# Tool Results Need Lifetimes

Not every tool result deserves to survive forever.

Imagine this sequence:

```text
1. inspect file
2. modify file
3. run tests
4. inspect compiler output
5. fix error
6. tests pass
```

Once step 6 succeeds, the compiler error from step 4 becomes mostly irrelevant.

Keeping it in the active context wastes space.

Tool results should therefore have lifetimes.

Something like:

```yaml
result:
  type: compiler_error
  relevance: temporary
  expires_when:
    - build_succeeds
```

That allows the agent runtime to remove solved problems from working context.

---

# Context Compression

Eventually even well-managed context grows.

At that point we need compression.

But compression should not mean:

```text
summarize the entire conversation
```

That tends to destroy useful detail.

Instead, compression should operate on different information types differently.

---

## Conversation Compression

A conversation like:

```text
User proposes option A.
Agent suggests option B.
User rejects B.
Agent suggests C.
User chooses A with modification X.
```

can become:

```yaml
decision:
  selected: A
  modification: X

rejected:
  - B
  - C
```

We preserved the useful state.

We removed the discussion.

---

## Tool Output Compression

Instead of retaining:

```text
500 lines of compiler output
```

store:

```yaml
build:
  status: failed
  errors:
    - file: runtime.rs
      line: 482
      error: mismatched types
```

---

## Repository Compression

Instead of injecting entire files:

```text
src/runtime.rs
src/tools.rs
src/context.rs
src/memory.rs
```

the system can construct a structural representation:

```yaml
runtime:
  responsibilities:
    - agent execution
    - tool dispatch

context:
  responsibilities:
    - prompt assembly
    - token budgeting

memory:
  responsibilities:
    - persistent memory
    - retrieval
```

Then load exact code only when necessary.

---

# Compression Must Preserve Recoverability

Compression is lossy.

That means the original data should remain available.

A good architecture looks like:

```text
Raw History
    |
    +-------> persistent log
    |
    v
Compressed State
    |
    v
Working Context
```

If the model later needs detail, it can retrieve the original information.

This is similar to how databases work.

Indexes do not replace data.

They make finding the data efficient.

---

# Deduplication Is More Important Than It Looks

Agent prompts frequently contain the same information multiple times.

For example:

```text
System prompt:
Use pnpm.

Project instructions:
This repository uses pnpm.

README:
Install with pnpm.

Previous conversation:
Remember, we use pnpm.

Memory:
Package manager = pnpm.
```

We just spent tokens telling the model the same thing five times.

This happens constantly in agent systems.

---

# Semantic Deduplication

Exact string matching is not enough.

These statements mean approximately the same thing:

```text
Use pnpm for dependencies.

The project package manager is pnpm.

Do not use npm; this repository uses pnpm.
```

A context builder should detect semantic duplication.

It can then produce one canonical statement:

```text
Package manager: pnpm. Do not use npm.
```

---

# Deduplication Needs Authority

But deduplication becomes dangerous when sources disagree.

Suppose we have:

```text
README:
Node 20

package.json:
Node >=22

Memory:
Node 20
```

We should not merge these blindly.

The runtime needs source priority.

For example:

```text
Current configuration
    >
Repository documentation
    >
Project memory
    >
Conversation history
```

The resulting context might become:

```text
Current project requirement: Node >=22.

Older memory stating Node 20 appears outdated.
```

This is much better than showing the model three conflicting facts and hoping it chooses correctly.

---

# Token Budgets Should Be Explicit

Most agent runtimes treat context size as something that happens accidentally.

I think context allocation should be intentional.

For example:

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

These numbers would obviously vary.

The important idea is that different context sources compete for limited space.

Without budgets, conversation history or tool output tends to consume everything.

---

# Reserved Output Matters

A common mistake is filling the entire context window with input.

If a model supports:

```text
128k tokens
```

you cannot necessarily send 128k tokens and still expect a large response.

The runtime should reserve space for:

- reasoning
- generated code
- tool calls
- final responses

So the actual usable input budget may be significantly lower.

Context management must account for both:

```text
input tokens + output tokens
```

not just input capacity.

---

# Context Priority

When the budget is exceeded, something needs to go.

That requires priorities.

For example:

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

This is much more predictable than simply removing the oldest messages.

Old information can still be critical.

Recent information can still be useless.

---

# Agent Handoffs Should Be Compressed

Multi-agent systems make context problems significantly worse.

Imagine:

```text
Planner
  -> Research Agent
      -> Coding Agent
          -> Review Agent
```

If every agent receives the complete history of every previous agent, context grows exponentially.

Instead, agents should exchange structured handoffs.

For example:

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

The coding agent receives what it needs.

Not everything the planner ever thought about.

---

# Agents Need Different Context Views

Different agents also need different slices of the same project.

A planning agent may need:

```text
architecture
requirements
dependencies
existing decisions
```

A coding agent needs:

```text
implementation files
tests
interfaces
style conventions
```

A review agent needs:

```text
diff
requirements
security rules
test results
```

They should not all receive identical context.

Agent specialization should apply to context retrieval as well as behavior.

---

# Skills Can Modify Context Strategy

Skills should do more than contain instructions.

They can also tell the runtime what information to retrieve.

A Kubernetes troubleshooting skill could declare:

```yaml
skill:
  name: kubernetes-debugging

  requires:
    tools:
      - kubectl

  context:
    retrieve:
      - cluster_version
      - affected_namespace
      - deployment_manifest
      - recent_events

  avoid:
    - unrelated_namespaces
```

A Rust skill might request:

```yaml
context:
  retrieve:
    - Cargo.toml
    - relevant_module
    - compiler_errors
```

This means skills become small context orchestration modules.

That is much more powerful than simply inserting another markdown prompt.

---

# Dynamic Skill Loading Can Be Recursive

Sometimes the initial skill is not enough.

For example:

```text
User asks:
Debug this Kubernetes deployment.
```

The runtime initially loads:

```text
kubernetes-debugging
```

During investigation, the agent discovers:

```text
The issue is probably related to Cilium network policy.
```

It can then dynamically load:

```text
cilium
network-policy
```

Later it discovers an AWS load balancer issue and loads:

```text
aws-elb
```

This creates an adaptive context system.

The agent starts small and expands only when needed.

---

# Unloading Is Just as Important as Loading

Dynamic loading without unloading still leads to context growth.

If the issue is no longer related to Cilium, that skill may no longer deserve context space.

The runtime should be able to say:

```text
loaded:
  kubernetes-debugging
  cilium

unloaded:
  generic-networking
```

Context should behave more like memory pages than an append-only log.

Load.

Use.

Evict.

Reload when necessary.

---

# Context Caching

Many context elements rarely change.

For example:

```text
system prompt
tool descriptions
project instructions
repository architecture summary
```

Repeatedly reconstructing or transmitting them can be inefficient.

Where model APIs support it, prompt caching can significantly reduce repeated processing.

Even without provider-level caching, the agent runtime can cache:

- summaries
- parsed repository structure
- skill indexes
- tool metadata
- embeddings
- memory retrieval results

The important part is invalidation.

A cached repository summary that survives major code changes becomes misinformation.

Which means caching needs version awareness.

---

# Content Addressing Helps

One useful design is to identify context artifacts by content hash.

For example:

```yaml
artifact:
  path: src/runtime.rs
  hash: sha256:81a6...
```

If the hash has not changed, previously computed metadata may still be valid.

That can apply to:

```text
file summaries
embeddings
symbol indexes
dependency graphs
```

This avoids recomputing expensive context representations unnecessarily.

---

# Context Should Be Observable

A developer using an AI agent should be able to inspect what the model actually received.

Otherwise debugging becomes guesswork.

A useful UI could show:

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

And ideally:

```text
Loaded Skills:
✓ Rust
✓ Testing
✓ Repository Guidelines

Available but not loaded:
- Kubernetes
- Terraform
- GitHub Actions
```

This would make agent behavior dramatically easier to understand.

---

# Why Did the Agent Know This?

Observability should go one step further.

If the model says:

```text
This repository uses PostgreSQL 18.
```

the interface should ideally be able to trace that statement back to:

```text
docker-compose.yml
line 24
```

or:

```text
Project memory
created 2026-08-12
```

This creates provenance.

And provenance is essential once context is assembled dynamically from many sources.

---

# Context Engineering Is Infrastructure

Prompt engineering is often described as writing better instructions.

That is only a small part of building serious agents.

Once an agent has:

```text
tools
skills
memory
agents
repositories
external knowledge
long-running sessions
```

the main challenge becomes context orchestration.

The runtime must continuously answer questions such as:

```text
What information exists?

Which information is relevant?

Which source is authoritative?

What should be loaded?

What should be removed?

What can be summarized?

What must remain exact?

What is duplicated?

What has become outdated?

What should another agent receive?
```

That is infrastructure.

---

# A Possible Context Pipeline

Putting everything together, an agent turn could look like this:

```text
User Request
     |
     v
Task Classification
     |
     v
Agent / Profile Selection
     |
     v
Skill Discovery
     |
     v
Tool Selection
     |
     v
Memory Retrieval
     |
     v
Repository Retrieval
     |
     v
Deduplication
     |
     v
Conflict Resolution
     |
     v
Compression
     |
     v
Token Budgeting
     |
     v
Context Assembly
     |
     v
LLM
     |
     v
Tool Calls
     |
     v
Result Filtering
     |
     +---------------------+
     |                     |
     v                     v
Continue Context       Persistent Logs
     |
     v
Memory Extraction
```

Notice what the LLM is not doing.

It is not receiving the entire world.

The runtime decides what part of the world the LLM needs.

---

# Context Should Be Rebuilt, Not Accumulated

This may be the most important architectural change.

Traditional chat systems treat context as an append-only sequence:

```text
message
message
message
message
message
```

Agent systems should instead construct context from state.

Every turn can rebuild the optimal context:

```text
system
+
current profile
+
relevant skills
+
current task
+
relevant memory
+
required code
+
recent useful events
```

Old information does not remain simply because it once entered the conversation.

This transforms context from history into a **computed view**.

I think that is the right abstraction.

---

# The Database Analogy

The more I work with agent architectures, the more context begins to look like a database query.

The complete system may contain millions of pieces of information.

The model should receive something closer to:

```sql
SELECT relevant_information
FROM everything
WHERE useful_for_current_task = true
ORDER BY importance DESC
LIMIT context_budget;
```

Obviously the implementation is more complicated.

But conceptually this is exactly the problem.

The context window is not the database.

It is the query result.

---

# Final Thoughts

Models will continue getting larger context windows.

That is useful.

But increasing the context window from:

```text
128k
```

to:

```text
1M
```

does not eliminate context engineering.

It may actually make bad context management easier to hide.

A good agent runtime should actively manage:

- system prompts
- agents and profiles
- skills
- tools
- tool outputs
- memory
- repository context
- conversation history
- dynamic loading
- unloading
- compression
- deduplication
- source authority
- token budgets
- agent handoffs

The goal is not to put everything into the model.

The goal is to give the model the **smallest context that contains everything it needs**.

That leads to cheaper requests, faster responses, fewer contradictions, cleaner agent handoffs, and often better reasoning.

Memory determines what an agent can know across time.

Context management determines what it can think about right now.

And for serious AI agents, both need to be designed deliberately.