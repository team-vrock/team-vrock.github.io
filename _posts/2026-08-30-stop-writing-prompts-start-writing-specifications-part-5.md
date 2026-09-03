---
layout: post
title: "Stop Writing Prompts, Part 5: Loops, Guardrails, and Templates"
date: 2026-08-30 10:00:00 +0000
categories: post
tags: [ai, ai-agents, llm, agents, architecture]
author: Tobias Geiser
image: "/assets/posts/2026-08-30/ai-spec-templates.png"
header: "/assets/posts/2026-08-30/ai-spec-templates-header.png"
excerpt_separator: <!--more-->
---

A specification tells the model what "done" means — but the real leverage comes from how the agent works *toward* done. In this part I look at the execution side of specification-driven work: investigation before modification, plan–execute–verify, build-test-fix and goal loops, the guardrails that keep autonomous agents from optimizing the wrong thing, and the templates I actually use for everyday tasks, debugging, and autonomous agents.
<!--more-->

**TL;DR:** Turn single-pass generation into iterative loops: investigate, then change, then verify, and keep going until acceptance criteria are met. Guard every goal with constraints, invariants, and authority boundaries — otherwise a capable agent will happily disable health checks or delete tests to make its metric pass. Specify process rather than "thinking", demand evidence over guesses, and reuse templates so the smallest specification that removes the important ambiguity wins.

This is Part 5 of a five-part series on designing AI agent infrastructure. [Part 1]({% post_url 2026-08-16-llm-memory-is-not-chat-history-part-1 %}) covered persistent memory, [Part 2]({% post_url 2026-08-22-context-is-a-budget-part-2 %}) covered context as a budget, [Part 3]({% post_url 2026-08-23-skills-are-not-prompts-part-3 %}) covered skills as capability packages, and [Part 4]({% post_url 2026-08-29-stop-writing-prompts-start-writing-specifications-part-4 %}) covered the layered specification itself.

## Investigate Before Changing

For complex tasks, I want an explicit investigation phase before anything is modified:

```text
Before making changes:

1. Inspect the relevant implementation.
2. Identify how the current behavior works.
3. Find existing tests and conventions.
4. Determine the smallest reasonable change.
5. Then implement.
```

This is much more reliable than immediately saying "implement X". It creates a simple loop:

![The investigate-first loop: observe the current state, understand how it works, make the smallest reasonable change, and verify the result.](/assets/posts/2026-08-30/ai-observe-verify-loop.png){: style="max-width: 100%; min-width: 100%; height: auto"}

That loop is far more important than most clever prompting tricks.

## Plan, Execute, Verify

For larger tasks, I like a three-stage pattern:

```text
PLAN
  |
  v
EXECUTE
  |
  v
VERIFY
```

The plan does not need to be twenty pages long. It exists to ensure the model understands the problem before modifying things:

```text
First inspect the current implementation and create a short plan.

Then implement the change.

Finally verify the result against every acceptance criterion.
```

This is particularly useful when the model has tools.

But planning can also become a trap. Agents sometimes love planning more than doing — you ask for a feature and receive forty-seven steps, none of them executed. Planning should therefore have a purpose:

```text
Create a short implementation plan after inspecting the relevant code.

Do not stop after planning. Continue directly with implementation
unless you discover a blocking ambiguity.
```

That keeps the plan as an intermediate artifact, not the final product.

## The Build-Test-Fix Loop

For software engineering, one of the strongest patterns is:

![The build-test-fix loop: failures at the build or test stage feed a diagnose-and-fix cycle and re-enter the flow instead of stopping the run.](/assets/posts/2026-08-30/ai-build-test-fix-loop.png){: style="max-width: 100%; min-width: 100%; height: auto"}

The important instruction is:

```text
Do not stop at the first error.

If the build or tests fail because of your changes, diagnose the
failure, fix it, and run the verification again.
```

This converts a single-pass model into an iterative engineering loop.

## Goal Loops

An even more general version is a goal loop. Instead of specifying every action, define a goal and repeatedly check progress:

```text
while goal_not_reached:

    inspect_current_state()

    choose_next_action()

    execute_action()

    evaluate_result()
```

For example:

```text
Goal:

All integration tests must pass.

Continue investigating and correcting the implementation until the
tests pass or you identify a genuine external blocker.

Do not weaken or remove tests simply to make them pass.
```

That final constraint matters. Otherwise the technically shortest path to "tests pass" may be deleting the tests. Congratulations — perfect optimization, wrong objective.

## Goals Need Guardrails

Goal-based agents are powerful precisely because they choose actions themselves, which also makes badly specified goals dangerous. Suppose the goal is:

```text
Make the deployment succeed.
```

One possible solution: disable health checks. Technically the deployment now succeeds. The system may still be broken. A better goal is:

```text
Make the deployment reach Ready state while preserving the current
health checks and resource limits.
```

The lesson is simple: a goal tells the agent what to optimize. Constraints tell it which shortcuts are unacceptable.

## Define Invariants

For more complex systems, I like defining invariants explicitly — things that must remain true throughout the task:

```text
Invariants:

- Existing API clients must remain compatible.
- Production credentials must never be modified.
- No data may be deleted.
- The service must remain deployable using the existing Helm chart.
```

This is stronger than describing the final result, because it limits the path the agent may take.

## Set Authority Boundaries

An LLM should know what it may decide itself:

```text
You may decide:

- internal function names
- file organization within the existing module
- test implementation details

Do not decide without confirmation:

- public API changes
- database schema migrations
- new external services
```

This is especially useful for autonomous agents. Otherwise every architectural detail has the same apparent authority.

## Specify Process, Not Reasoning

There is a subtle distinction here. You usually want to specify what process should happen, not what internal reasoning should look like. This is useful:

```text
Compare at least two viable approaches before selecting the
implementation.
```

This is mostly wishful prompting:

```text
Think deeply.

Think step-by-step.

Take a deep breath.
```

The former produces an observable process; the latter is ritual.

## Demand Evidence

For analytical tasks, force important claims to connect to evidence:

```text
For each identified problem:

- show the relevant file or configuration
- explain why it causes the behavior
- distinguish confirmed findings from hypotheses
```

This prevents the model from presenting guesses as discoveries. A troubleshooting agent should ideally behave like the upper chain in the illustration, where findings graduate from evidence through hypothesis and test to a conclusion — and never like the faded lower chain, where a guess flows straight into confidence:

![Evidence-based troubleshooting: findings move from evidence to hypothesis to tested conclusion, while the guess-straight-to-confidence path stays switched off.](/assets/posts/2026-08-30/ai-evidence-loop.png){: style="max-width: 100%; min-width: 100%; height: auto"}

A related pattern is asking the model to separate what it knows from what it assumes before implementing:

```text
Confirmed:
The application uses PostgreSQL.

Assumption:
The connection pool is causing the latency.

Unknown:
Whether connections are currently exhausted.
```

The model can then investigate the unknown — which prevents assumptions from silently becoming architecture.

## Use Examples Carefully

Examples can be extremely effective. If you want configuration output like this, showing it makes the desired structure obvious:

```yaml
providers:

  openai:
    priority: 10

  anthropic:
    priority: 20
```

But examples can also over-constrain. Show one implementation and the model may imitate it even when a better solution exists. Use examples primarily to define format, style, and behavior rather than accidentally forcing architecture.

Negative examples can be even better, because they draw the boundary explicitly:

```text
Good:

A small change to the existing provider resolver.

Avoid:

Introducing a new provider orchestration framework or rewriting the
entire provider abstraction.
```

Or simply:

```text
Do:

Reuse existing configuration.

Do not:

Create providers-v2.yaml.
```

## Make Priorities Explicit

Real requirements sometimes conflict, and the model should know which one wins:

```text
Priority:

1. Correctness
2. Backward compatibility
3. Simplicity
4. Performance
```

Now suppose the fastest implementation breaks compatibility — the agent has explicit guidance. Without priorities, models often optimize whichever requirement happens to be most salient.

## Define the Output

Another common mistake is specifying the task but not the output. Compare:

```text
Analyze this architecture.
```

with:

```text
Analyze this architecture.

Return:

1. The three biggest architectural risks.
2. Evidence for each risk.
3. Recommended changes.
4. Expected impact.
5. Anything that should explicitly remain unchanged.
```

The second request is much easier to evaluate. Output structure is part of the specification.

For agent workflows, I prefer end summaries that report state, not story:

```text
Completed:
- ...

Changed:
- ...

Verified:
- ...

Remaining:
- ...
```

rather than a long narrative explaining everything the agent did. The runtime already has logs. What I need at the end is state.

## Prompting Is Composable

Large agent systems should not rely on one enormous prompt. Different layers define different things:

```text
System Prompt
     |
     +--- basic operating rules

Profile
     |
     +--- execution behavior

Skill
     |
     +--- domain-specific capability

Project
     |
     +--- local conventions

Task Specification
     |
     +--- current goal and acceptance criteria
```

The final context is assembled from those layers, which means the user's task prompt can remain small. If the agent already knows the project uses Rust from workspace context, there is little value in repeating it — and if a skill already defines "run `cargo fmt` after editing Rust files", the user should not need to say it again.

Good agent architecture reduces the amount of prompting required. The best prompt is not the most detailed prompt. It is the smallest specification that removes the important ambiguity.

## Specification Refinement

Not every task can be fully specified in advance. Sometimes the first request is intentionally exploratory:

```text
Investigate why our Kubernetes API latency increased after the latest
deployment.

Do not make changes yet.

Identify the most likely causes and what evidence would confirm them.
```

The result of that investigation becomes input to the next specification:

![Specification refinement: investigation and learning tighten the specification before execution begins.](/assets/posts/2026-08-30/ai-refine-loop.png){: style="max-width: 100%; min-width: 100%; height: auto"}

For very complex projects, I like treating the specification itself as an artifact. Start with the goal, then let the model help discover requirements, constraints, unknowns, risks, and acceptance criteria — and review the resulting specification before implementation. This works particularly well for architecture changes, new features, infrastructure migrations, API redesigns, and agent development. Essentially, the LLM helps transform an idea into an executable specification:

![Specification-driven development: each stage reduces ambiguity, from idea through goal, specification, plan, implementation, and verification to review.](/assets/posts/2026-08-30/ai-spec-pipeline.png){: style="max-width: 100%; min-width: 100%; height: auto"}

Each stage reduces ambiguity, and the LLM becomes much more reliable because each step has clearer boundaries.

## Templates

### Medium-Sized Engineering Tasks

```text
# Goal

Describe the desired end state.


# Context

Relevant architecture, files, technologies and current behavior.


# Requirements

- Required behavior
- Required behavior
- Required behavior


# Constraints

- Things that must remain compatible
- Things that must not change
- Technical restrictions


# Non-goals

- Explicitly excluded work
- Related problems that should not be solved


# Acceptance Criteria

1. Observable success condition
2. Observable success condition
3. Existing behavior still works


# Execution

Inspect the existing implementation before making changes.

Prefer the smallest change that satisfies the requirements.

Follow existing project conventions.

Do not stop after planning.


# Verification

Run the relevant tests and checks.

If verification fails because of your changes, diagnose and fix the
problem before finishing.


# Final Response

Report:

- what changed
- what was verified
- any remaining limitations
```

You do not need every section every time, but this beats "please implement this feature" by a wide margin.

### Everyday Tasks

```text
Goal:
...

Requirements:
- ...
- ...

Do not:
- ...

Done when:
- ...
```

That alone solves a large percentage of bad prompting.

### Debugging

```text
Goal:

Determine the root cause of ...


Current symptoms:

...


Known facts:


Investigate:

1. Inspect the current state.
2. Gather evidence.
3. Separate confirmed findings from hypotheses.
4. Test the most likely hypothesis first.

Do not make changes until the root cause is reasonably established.

When proposing a fix, explain how it addresses the observed evidence.
```

### Autonomous Agents

```text
Goal:

...


Constraints:


Acceptance Criteria:


You may:

- inspect files
- modify files
- run local commands
- run tests


You may not:

- modify external infrastructure
- push commits
- change public APIs


Loop:

1. Inspect the current state.
2. Choose the smallest useful next action.
3. Execute it.
4. Evaluate the result.
5. Continue until the acceptance criteria are satisfied.

If an action fails, investigate and adapt.

Do not weaken the acceptance criteria in order to finish.
```

That final sentence is worth keeping. Agents are remarkably good at satisfying metrics literally. Sometimes too good.

## The Wrong Way to Prompt

A weak prompt often looks like this:

```text
You are the world's best senior software engineer.

Think step by step.

Analyze everything carefully.

Write clean production-quality code.

Never make mistakes.

Implement authentication.
```

It contains a lot of confidence and almost no information. A stronger request is only slightly longer:

```text
Goal:

Add authentication to the existing FastAPI application using our
existing Keycloak deployment.

Requirements:

- Validate JWT access tokens.
- Expose the authenticated user ID to route handlers.
- Return 401 for invalid or expired tokens.

Constraints:

- Do not implement user/password storage in this application.
- Keep the current API routes compatible.

Done when:

- protected routes reject unauthenticated requests
- valid Keycloak tokens work
- automated tests cover both cases

Inspect the existing authentication code before implementing.
```

No magic persona. No motivational speech. Just a useful specification.

## Less Ambiguity, Not More Confidence

When models perform badly, users often respond with stronger language:

```text
Be VERY careful.

Make absolutely sure.

You MUST get this right.
```

But the underlying task is still ambiguous. The model does not need to be threatened with more capital letters. It needs better information.

## Summary

- Turn generation into loops: observe, understand, change, verify — and keep iterating until the acceptance criteria are met.
- Keep plans as intermediate artifacts and forbid stopping after planning.
- Guard goals with constraints, invariants, and authority boundaries; a goal without guardrails invites destructive shortcuts.
- Specify observable process, demand evidence, and keep facts, assumptions, and unknowns separate.
- Examples define format and style; negative examples define boundaries. Make requirement priorities explicit and specify the output structure.
- Compose context from system, profile, skill, project, and task layers — the best task prompt is the smallest specification that removes the important ambiguity.
- The model does not need more confidence. It needs less ambiguity.

## References

- [Part 1: LLM Memory Is Not Chat History]({% post_url 2026-08-16-llm-memory-is-not-chat-history-part-1 %})
- [Part 2: Context Is a Budget]({% post_url 2026-08-22-context-is-a-budget-part-2 %})
- [Part 3: Skills Are Not Prompts]({% post_url 2026-08-23-skills-are-not-prompts-part-3 %})
- [Part 4: From Prompts to Specifications]({% post_url 2026-08-29-stop-writing-prompts-start-writing-specifications-part-4 %})
