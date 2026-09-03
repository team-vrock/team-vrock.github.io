# Skills Are Not Prompts — Designing a Dynamic Capability System for AI Agents

Many AI agent frameworks describe skills as reusable prompts.

That is useful.

It is also too limited.

If a skill is only a block of text that gets injected into the model context, then it is basically a prompt template with a better name.

A serious agent skill should represent something larger:

- knowledge
- instructions
- tools
- permissions
- retrieval strategy
- context requirements
- validation rules
- runtime behavior

In other words:

A skill should be a **capability package**.

That changes how agent systems can be designed.

---

# The Problem With Prompt-Only Skills

Imagine an agent with a Kubernetes skill.

A prompt-only implementation might look like this:

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

That is fine as documentation.

But what does the skill actually do?

Nothing.

The runtime still needs to know:

- whether `kubectl` should be available
- which cluster the agent may access
- whether write operations are allowed
- which project files are relevant
- whether Helm should also be loaded
- how much context the skill can consume
- which other skills it depends on

The prompt is only one part of the capability.

---

# A Skill Should Describe What It Needs

A more useful definition might look like this:

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

Now the skill is not merely telling the model how to behave.

It tells the runtime how to prepare the environment.

That is much more interesting.

---

# Skills Should Be Discoverable Without Being Loaded

An agent may have hundreds of available skills.

Loading them all would destroy context efficiency.

Instead, the runtime needs a lightweight skill catalog.

For example:

```yaml
skills:

  - name: rust
    description: Rust implementation, Cargo, ownership and lifetimes

  - name: kubernetes-debugging
    description: Diagnose Kubernetes workloads and cluster failures

  - name: terraform
    description: Terraform configuration and infrastructure workflows

  - name: github-actions
    description: GitHub Actions workflow creation and troubleshooting
```

These descriptions are cheap.

The complete skill definitions remain unloaded.

The model or runtime can first decide:

```text
Which skills are relevant?
```

Then load only those.

This separates:

```text
skill discovery
```

from:

```text
skill activation
```

That distinction is essential for scale.

---

# Skills Should Be Loaded Dynamically

Suppose the user asks:

```text
Why is this pod restarting?
```

The runtime might initially activate:

```text
kubernetes-debugging
```

The agent inspects the workload and discovers:

```text
Back-off restarting failed container
```

It then examines the application logs and finds:

```text
connection refused: postgres:5432
```

Now another skill may become useful:

```text
postgresql
```

If the database runs through an operator:

```text
cloudnative-pg
```

could also be loaded.

The active capability set evolves with the task:

```text
Start
  |
  v
Kubernetes
  |
  v
PostgreSQL
  |
  v
CloudNativePG
```

The system does not need to predict the full problem before work begins.

It can expand its capabilities while investigating.

---

# Dynamic Loading Needs Dynamic Unloading

Loading skills dynamically is only half of the solution.

Without unloading, the context still grows continuously.

Suppose the database problem is resolved and the agent moves on to an ingress issue.

The PostgreSQL skill may no longer be useful.

The active skill set could change from:

```text
kubernetes
postgresql
cloudnative-pg
```

to:

```text
kubernetes
ingress-nginx
tls
```

This is closer to how operating systems manage memory.

Capabilities are loaded when needed.

Then evicted when they stop being useful.

---

# Skill Scope Matters

Not every skill should be available everywhere.

Skills can come from several scopes.

For example:

```text
workspace
global
builtin
```

A useful precedence model is:

```text
workspace > global > builtin
```

This means a project can override general behavior.

Suppose a built-in Rust skill says:

```text
Run cargo fmt before committing.
```

But a specific repository has a custom formatter workflow.

The workspace-level skill should win.

This makes local project knowledge more authoritative than generic defaults.

---

# Why Workspace Skills Matter

Generic agent knowledge is useful.

Project-specific knowledge is usually more important.

A workspace skill could describe rules such as:

```yaml
skill:
  name: repository-conventions

  instructions: |
    Use cargo nextest instead of cargo test.

    Do not edit generated files under src/generated.

    API changes require updating docs/api.md.

    Use conventional commits.
```

These are not general programming rules.

They belong to the repository.

Keeping them in the workspace has several advantages:

- version control
- visibility
- team ownership
- predictable behavior
- portability between agent runtimes

The project becomes able to describe how an agent should work inside it.

---

# Skills Should Live Close to the Work

One model I like is storing project-local skills inside a dedicated directory.

For example:

```text
.ocuci/
  skills/
    rust.yaml
    release.yaml
    kubernetes.yaml
```

When a workspace is opened, the runtime discovers those files.

That means skills travel with the project.

They can be reviewed just like code.

They can also evolve through pull requests.

This is much better than hiding critical agent behavior inside a centralized UI database nobody remembers to update.

---

# Skill Definitions Should Be Declarative

Skills should describe capabilities rather than implementation details.

For example:

```yaml
skill:
  name: release

  description: Create and validate project releases.

  tools:
    required:
      - git
      - github

  permissions:
    git:
      read: true
      write: true

    github:
      releases: write

  context:
    retrieve:
      - changelog
      - git_tags
      - release_workflow

  instructions: |
    Never overwrite an existing tag.
    Verify tests before creating a release.
```

The runtime decides how to satisfy those requirements.

That keeps skill definitions portable.

A different agent harness could implement the same capability using different underlying tools.

---

# Tools and Skills Are Not the Same Thing

This distinction is important.

A tool performs an operation.

A skill tells the agent how and when to use capabilities.

For example:

```text
Tool:
kubectl
```

versus:

```text
Skill:
kubernetes-debugging
```

The tool may provide operations such as:

```text
get
describe
logs
apply
delete
```

The skill provides knowledge like:

```text
what to inspect first
which commands are safe
which context is useful
how results should be interpreted
```

A skill may use several tools.

A tool may be used by several skills.

They form a many-to-many relationship.

---

# Skills Can Compose Other Skills

Complex capabilities should not require duplicating instructions.

Suppose:

```text
kubernetes-release
```

needs:

```text
kubernetes
helm
git
```

The skill can declare dependencies:

```yaml
skill:
  name: kubernetes-release

  dependencies:
    - kubernetes
    - helm
    - git
```

The runtime resolves the dependency graph.

Conceptually:

```text
kubernetes-release
      |
      +---- kubernetes
      |
      +---- helm
      |
      +---- git
```

This creates reusable capability building blocks.

---

# Dependency Resolution Needs Limits

Recursive skill loading can become dangerous.

Imagine:

```text
skill A -> skill B
skill B -> skill C
skill C -> skill A
```

Or a skill graph that activates fifty dependencies.

The runtime needs safeguards.

For example:

```yaml
skill_runtime:
  max_depth: 4
  max_active_skills: 12
```

It should also detect cycles.

Otherwise a seemingly small capability request can explode into massive context usage.

---

# Skills Should Be Able to Request Context

A skill often knows what information is useful.

The runtime should let it declare this.

For example:

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

A Terraform skill might request:

```yaml
context:
  preferred:
    - terraform_files
    - provider_versions
    - state_backend_config
```

A Kubernetes troubleshooting skill might request:

```yaml
context:
  preferred:
    - deployment
    - pods
    - recent_events
    - container_logs
```

This turns skills into context orchestration modules.

They influence not only what the model knows, but also what the runtime retrieves.

---

# Skills Should Be Able to Request Tools

Likewise, a skill should describe the tools it expects.

For example:

```yaml
tools:
  required:
    - filesystem
    - shell

  optional:
    - git
```

If the required capability is unavailable, the runtime should know before the agent begins.

Instead of letting the model repeatedly attempt impossible actions, it can report:

```text
Required tool unavailable: kubectl
```

That improves reliability significantly.

---

# Skills Should Carry Permissions

Tool availability and tool permission are different things.

A Kubernetes skill may have access to `kubectl`.

That does not mean it should be allowed to run:

```bash
kubectl delete namespace production
```

Permissions should therefore be explicit.

For example:

```yaml
permissions:
  kubernetes:
    read: true
    create: false
    update: false
    delete: false
```

A deployment skill could request stronger permissions:

```yaml
permissions:
  kubernetes:
    read: true
    create: true
    update: true
    delete: false
```

This makes capability activation auditable.

---

# Skills Can Escalate Permissions

Sometimes a task genuinely requires more access.

The agent could start in read-only mode.

If a modification becomes necessary, the skill requests escalation.

For example:

```text
Current capability:
Kubernetes read-only

Requested capability:
update Deployment payments/api
```

The runtime or user can approve that specific escalation.

This is much safer than giving every agent full cluster access from the beginning.

---

# Skills Need Versioning

Skills will evolve.

A project may depend on specific behavior.

That means skill definitions should have versions.

For example:

```yaml
skill:
  name: terraform
  version: 2.3
```

Or:

```yaml
requires:
  kubernetes: ">=3.0 <4.0"
```

Without versioning, changing a global skill can silently change the behavior of dozens of projects.

That is the agent equivalent of upgrading a library without a lockfile.

Usually not a great surprise.

---

# Skills Need Validation

A skill is executable behavior, even if it contains no traditional code.

It should therefore be validated.

Possible checks include:

```text
schema validation
dependency validation
tool availability
permission validation
cyclic dependency detection
token budget checks
duplicate skill names
invalid overrides
```

For example:

```text
Skill kubernetes-release requires github,
but github tool is unavailable.
```

This should be caught when the skill loads.

Not halfway through an operation.

---

# Skill Loading Should Be Observable

Users should be able to see which skills are active.

For example:

```text
Active Skills

✓ repository-conventions
✓ rust
✓ testing

Loaded dynamically

✓ sqlx

Available

○ kubernetes
○ docker
○ terraform
```

This helps explain agent behavior.

If the agent is using unexpected instructions, the first debugging question becomes:

```text
Which skill loaded those instructions?
```

Without observability, dynamic behavior quickly becomes mysterious.

---

# Skills Need Provenance

The runtime should know where each skill came from.

For example:

```text
repository-conventions
source: /workspace/project/.ocuci/skills/repository.yaml

rust
source: ~/.config/ocuci/skills/rust.yaml

git
source: builtin
```

If multiple skills share the same name, precedence becomes explicit.

This also makes debugging overrides much easier.

---

# Skills Should Be Reloadable

If skills live in project files, editing one should not require restarting the entire agent application.

A runtime can monitor skill directories and reload definitions when they change.

For example:

```text
.ocuci/skills/kubernetes.yaml changed

-> validate
-> reload
-> update capability index
```

Existing sessions may either:

```text
keep current version
```

or:

```text
adopt new version
```

depending on runtime policy.

That behavior should be explicit.

---

# Skills Should Not Pollute Context Permanently

A common implementation mistake is:

```text
load skill
-> append skill prompt to conversation
```

Now the skill remains in context forever.

Even if it is no longer active.

Instead, skill instructions should be part of the dynamically assembled prompt.

Conceptually:

```text
context =

system
+ active profile
+ active skills
+ task state
+ relevant memory
+ current conversation
```

On the next turn, the context is rebuilt.

If a skill is no longer active, it simply disappears.

This is much cleaner than trying to remove old messages from an append-only conversation.

---

# Skill Selection Can Be Model-Assisted

How should the runtime choose skills?

One option is deterministic routing.

For example:

```text
*.rs -> rust
Cargo.toml -> rust
*.tf -> terraform
Chart.yaml -> helm
```

This works well for obvious cases.

But many requests are semantic.

For example:

```text
The application works locally but connections fail between pods.
```

That could require:

```text
kubernetes
networking
cilium
```

An LLM can help rank candidate skills based on their descriptions.

A hybrid system is probably better:

```text
rules
+
task analysis
+
model-assisted ranking
```

The runtime remains in control.

The model helps decide relevance.

---

# Skill Selection Should Have a Confidence Threshold

Model-assisted routing should not load every vaguely related skill.

For example:

```yaml
candidate_skills:

  kubernetes:
    confidence: 0.96

  networking:
    confidence: 0.88

  cilium:
    confidence: 0.61

  terraform:
    confidence: 0.12
```

The runtime might initially load only:

```text
kubernetes
networking
```

Cilium can be loaded later if evidence points there.

This reduces unnecessary context growth.

---

# Skills Can Produce Temporary Subskills

Some capabilities may be generated from current project state.

Imagine opening a repository containing:

```text
.github/workflows/release.yml
```

The runtime could derive a temporary skill:

```text
project-release-workflow
```

containing:

```text
release trigger
required branches
artifact naming
deployment steps
```

This skill does not need to exist globally.

It exists because the current workspace provides enough structure to create it.

This introduces an interesting category:

```text
derived skills
```

Capabilities generated from current project knowledge.

---

# Skills Can Be Agent-Specific

Not every agent should use every skill.

Suppose a system has:

```text
Plan
Interactive
Autopilot
Review
```

A planning profile may use:

```text
architecture
requirements-analysis
risk-analysis
```

An implementation agent may use:

```text
rust
git
testing
```

A review agent may load:

```text
security-review
code-review
testing
```

The same workspace exposes the same skill catalog.

Different agents activate different subsets.

---

# Skills Can Change Agent Behavior

This is where skills become more powerful than knowledge modules.

A skill may influence execution policy.

For example:

```yaml
skill:
  name: production-operations

  behavior:
    require_confirmation:
      - destructive_action
      - deployment

    default_mode: read_only
```

Another skill could specify:

```yaml
behavior:
  test_after_edit: true
  commit_after_success: false
```

Now skills affect orchestration.

Not just model instructions.

---

# Skills Need Conflict Resolution

Eventually two skills will disagree.

For example:

```text
global git skill:
Always create commits after successful changes.
```

But:

```text
workspace policy:
Never commit automatically.
```

The runtime needs deterministic precedence.

For example:

```text
workspace
>
profile
>
global
>
builtin
```

The result should be:

```text
Automatic commits disabled.
```

It is dangerous to simply inject both instructions and hope the LLM resolves the conflict correctly.

---

# Conflict Resolution Should Happen Before the Prompt

This is a recurring architectural principle.

The model should not be responsible for resolving problems that the runtime can resolve deterministically.

If two skill definitions conflict, the runtime should produce one effective configuration.

For example:

```yaml
effective_policy:
  auto_commit: false
```

The model receives the resolved policy.

Not the entire disagreement.

---

# Skills Should Have Token Budgets

A badly designed skill can contain tens of thousands of tokens of documentation.

Dynamic loading does not help much if one skill consumes half the context window.

Skills should have context budgets.

For example:

```yaml
budget:
  instructions: 3000
  retrieved_context: 8000
  total: 12000
```

If the skill needs more information, it should retrieve incrementally.

This encourages compact skill design.

---

# Documentation Should Usually Be Retrieved, Not Embedded

Suppose a Kubernetes skill includes the entire Kubernetes documentation.

That is obviously inefficient.

The skill should instead know how to find relevant documentation.

For example:

```yaml
knowledge:
  sources:
    - kubernetes_docs

  retrieval:
    top_k: 5
```

Then the runtime retrieves only the relevant sections.

The skill contains retrieval strategy.

Not the entire knowledge base.

---

# Skills Are Part of the Agent Runtime

This leads to a broader architecture.

A capability system might look like this:

```text
                 +--------------------+
                 |    Skill Catalog   |
                 +----------+---------+
                            |
                            v
                 +--------------------+
                 |   Skill Resolver   |
                 +----------+---------+
                            |
             +--------------+--------------+
             |              |              |
             v              v              v
        Instructions       Tools         Context
             |              |              |
             +--------------+--------------+
                            |
                            v
                 +--------------------+
                 |   Active Runtime   |
                 +----------+---------+
                            |
                            v
                          Agent
```

The skill resolver does more than concatenate prompts.

It constructs the agent's capabilities for the current task.

---

# Skills Start Looking Like Packages

At this point the analogy becomes obvious.

A skill resembles a software package.

It has:

```text
name
version
dependencies
configuration
permissions
capabilities
documentation
```

It can be:

```text
installed
discovered
loaded
unloaded
updated
overridden
validated
```

That suggests agent skills need some of the same infrastructure software packages already have.

Perhaps eventually:

```text
skill registries
dependency locking
signatures
compatibility checks
```

Once skills become reusable and distributed, those problems will appear whether we like it or not.

---

# Skill Security Will Matter

Installing an agent skill is potentially more dangerous than installing documentation.

A skill might request:

```text
shell
filesystem writes
cloud access
GitHub access
production Kubernetes access
```

That means skills need trust boundaries.

A runtime should be able to show:

```text
Skill: production-deploy

Requests:

✓ Git repository read
✓ Git repository write
✓ Kubernetes read
✓ Kubernetes update
✗ Kubernetes delete
```

Users should understand what capability they are enabling.

---

# Skill Sources Need Trust Levels

A built-in skill may have one trust level.

A workspace skill another.

A downloaded third-party skill another.

For example:

```yaml
trust:

  builtin:
    level: trusted

  global:
    level: local

  workspace:
    level: project

  remote:
    level: untrusted
```

Remote skills could require additional approval before accessing sensitive tools.

Otherwise a malicious repository could simply include:

```text
.ocuci/skills/helpful.yaml
```

and quietly instruct the agent to exfiltrate secrets.

That would be an impressively stupid security model.

Unfortunately, it would also be very easy to build.

---

# Workspace Skills Are Executable Configuration

This is the right mental model.

Files such as:

```text
.ocuci/skills/*.yaml
```

should be treated more like:

```text
GitHub Actions
Terraform
Ansible
CI configuration
```

than like:

```text
README.md
```

They influence runtime behavior.

Therefore they deserve:

```text
review
validation
permissions
version control
trust boundaries
```

---

# Skills Should Be Testable

If a skill changes agent behavior, we should be able to test it.

For example:

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

We can also test policy resolution:

```yaml
tests:

  - workspace:
      auto_commit: false

    global:
      auto_commit: true

    expected:
      auto_commit: false
```

Agent configuration should not have to be mystical.

Much of it can be tested deterministically.

---

# Skills Should Produce Telemetry

A runtime can learn a lot from tracking skill usage.

For example:

```text
Skill                  Loads     Useful Tool Calls

rust                    482            731
kubernetes              201            488
terraform                74            109
generic-debugging       933             22
```

That last one might be a problem.

If a skill loads constantly but rarely contributes anything useful, it may be too broad.

Telemetry can help improve skill descriptions and routing.

---

# Skill Loading Can Become Self-Optimizing

Over time, the runtime could learn patterns such as:

```text
kubernetes-debugging
+
cilium
```

frequently appearing together.

Or:

```text
rust
+
sqlx
```

The system could improve candidate ranking.

But I would be careful here.

Learning should influence suggestions.

It should not silently override deterministic project policy.

Predictability matters more than cleverness in infrastructure systems.

---

# The Difference Between a Skill and an Agent

The distinction can now be stated fairly clearly.

An agent defines:

```text
who is acting
```

A skill defines:

```text
what the agent can do
```

A tool defines:

```text
how an action is executed
```

Memory defines:

```text
what the system remembers
```

Context defines:

```text
what the agent knows right now
```

These concepts overlap.

They should not be collapsed into one giant prompt.

---

# A Possible Runtime Flow

A request might move through the system like this:

```text
User Request
     |
     v
Profile Selection
     |
     v
Skill Discovery
     |
     v
Candidate Ranking
     |
     v
Dependency Resolution
     |
     v
Permission Resolution
     |
     v
Tool Activation
     |
     v
Context Retrieval
     |
     v
Context Budgeting
     |
     v
Skill Activation
     |
     v
Agent Execution
     |
     v
Tool Calls
     |
     v
Dynamic Skill Changes
     |
     v
Result
```

The important part is that skill selection happens before context assembly.

Skills help determine what context should exist.

---

# This Also Solves the Giant System Prompt Problem

Many agent systems eventually build enormous system prompts because every new capability adds instructions.

A dynamic skill system reverses that trend.

Instead of:

```text
one giant agent
+
everything it might ever need
```

we get:

```text
small core agent
+
task-specific capabilities
```

That produces smaller prompts.

It also creates cleaner boundaries.

And perhaps most importantly, it makes agent behavior easier to understand.

---

# My Preferred Model

I increasingly think of an agent runtime as something similar to an operating system.

The model is the execution engine.

The context window is working memory.

Tools are system calls.

Memory is persistent storage.

Profiles define execution behavior.

And skills are dynamically loaded capability modules.

The runtime decides what gets loaded.

The model should not carry the entire environment inside its prompt.

That is not intelligence.

That is just very expensive configuration management.

---

# Final Thoughts

Calling a reusable prompt a skill is fine for simple systems.

But once agents become long-running, tool-using, project-aware systems, that abstraction becomes too weak.

A real skill system should support:

- discovery
- dynamic loading
- unloading
- dependencies
- project overrides
- tool requirements
- permissions
- context retrieval
- token budgets
- validation
- versioning
- conflict resolution
- provenance
- trust levels
- telemetry

The most important shift is conceptual.

Skills should not simply tell the model more things.

They should change what the **runtime makes available to the model**.

That turns skills from prompt fragments into genuine capabilities.

And I suspect that capability management will become one of the defining architectural layers of serious AI agent systems.