---
layout: post
title: "Stop Writing Prompts, Part 4: From Prompts to Specifications"
date: 2026-09-13 10:00:00 +0000
categories: post
tags: [ai, ai-agents, llm, agents, architecture]
author: Tobias Geiser
image: "/assets/posts/2026-09-13/ai-prompt.png"
header: "/assets/posts/2026-09-13/ai-prompt-header.png"
excerpt_separator: <!--more-->
---

Most people working with LLMs are still hunting for the perfect prompt. They add "think step by step", "you are an expert", "double-check your work" — and sometimes that helps. But once you use language models for real engineering work, something becomes obvious: the difference between a mediocre result and a good result is rarely a magic sentence. It is the quality of the specification. This post is about turning vague intent into a task definition an agent can actually execute.
<!--more-->

**TL;DR:** A good LLM request looks less like a prompt and more like a task definition: what should be achieved, what already exists, which constraints apply, what must not change, how success is measured, and how the model verifies its work. Structure requests in layers — goal, context, requirements, constraints, non-goals, acceptance criteria, verification, execution policy — and scale the effort to the risk of the task.

This is Part 4 of a five-part series on designing AI agent infrastructure. [Part 1]({% post_url 2026-09-05-llm-memory-is-not-chat-history-part-1 %}) covered persistent memory, [Part 2]({% post_url 2026-09-06-context-is-a-budget-part-2 %}) covered context as a budget, [Part 3]({% post_url 2026-09-12-skills-are-not-prompts-part-3 %}) covered skills as capability packages, and [Part 5]({% post_url 2026-09-20-stop-writing-prompts-start-writing-specifications-part-5 %}) covers execution loops, guardrails, and specification templates.

## The Prompt Is Not the Goal

Consider this request:

```text
Create authentication for my API.
```

This is technically a prompt. It is also almost useless as a specification. The model has to invent a large number of things:

```text
Authentication mechanism?
Sessions or JWT?
Existing identity provider?
Refresh tokens?
Authorization model?
API framework?
Database?
Existing architecture?
Security requirements?
Compatibility requirements?
```

The model will fill those gaps. Sometimes correctly. Sometimes creatively. And "creatively" is usually not what I want from an authentication implementation.

A better request starts with the actual goal:

```text
Goal:

Add authentication to the existing REST API so that users can log in
using our existing Keycloak instance.

The API should validate access tokens and expose the authenticated
user ID to request handlers.
```

Now the model knows what success looks like.

## Describe the End State, Not the Steps

One of the most effective techniques is simply putting the goal first. Instead of telling the model which commands to execute, describe the desired end state:

```text
Goal:

After this change, a new developer should be able to clone the
repository, run one command, and have the complete development
environment running locally.
```

That is significantly more useful than:

```text
Create a Docker Compose file.
```

Why? Because Docker Compose might not actually be the complete solution. The first request describes the outcome; the second describes an implementation idea. That distinction matters.

The same trap appears when you name the solution yourself. Suppose I write:

```text
Use Redis to make this faster.
```

I have already chosen the solution. The model will probably try to make Redis work even if the actual bottleneck is somewhere else. A better specification would be:

```text
Goal:

Reduce the average response time of this endpoint from approximately
900 ms to below 200 ms.

Before changing the architecture, identify where the current latency
comes from.

Do not introduce additional infrastructure unless it provides a
measurable benefit.
```

Now the model is solving the problem, not merely implementing my guess. This is especially important when working with agents: agents are far more useful when they can investigate before they execute.

## A Good Specification Has Layers

For serious tasks, I normally think about the request in several layers:

![The 8 layers of a task specification: Goal, Context, Requirements, Constraints, Non-Goals, Acceptance Criteria, Verification, and Execution Policy.](/assets/posts/2026-09-13/ai-spec-layers.png){: style="max-width: 100%; min-width: 100%; height: auto"}

Not every task needs every section, but this structure removes a huge amount of ambiguity. The rest of this post walks through each layer.

## Goal

The goal describes the desired end state. It should answer: *what should be true when the task is finished?*

```text
Goal:

Add automatic provider failover to the LLM runtime.

If the primary provider becomes unavailable because of a transient
error, the request should continue using the next configured provider.
```

Good goals are outcome-oriented. Bad goals describe activities — "look at the provider implementation and improve it" has no measurable meaning.

## Context

The model needs enough context to understand the environment:

```text
Context:

The application is written in Rust.

Providers implement the `Provider` trait.

Provider configuration is loaded from `providers.yaml`.

The runtime currently selects exactly one provider for each session.
```

This saves the model from rediscovering fundamental architecture. But context should still be relevant — dumping the entire repository into the prompt is not automatically better. Good context answers one question: *what does the model need to know before starting?*

## Requirements

Requirements describe behavior that must exist:

```text
Requirements:

- Providers have an explicit priority.
- Failover only happens for transient provider failures.
- Authentication errors must not trigger failover.
- Rate limiting should trigger the next provider.
- Successful failover must be visible in the runtime log.
```

Notice that these are not implementation instructions. They describe behavior, which leaves room for the model to find a clean implementation.

## Constraints

Constraints describe what the solution must respect:

```text
Constraints:

- Preserve the existing Provider trait if possible.
- Existing configuration files must remain valid.
- Do not add a new external dependency unless necessary.
- Do not change the public API.
```

Constraints are extremely important. Without them, models frequently "solve" problems by rewriting things that were never supposed to change.

## Non-Goals

This is one of the most underrated sections of a specification. Tell the model what it should *not* solve:

```text
Non-goals:

- Do not implement provider load balancing.
- Do not add automatic cost optimization.
- Do not change model selection.
- Do not redesign provider configuration.
```

LLMs tend to expand tasks. Ask for one feature and suddenly you have an architecture redesign. A non-goal prevents helpful enthusiasm from becoming scope creep.

## Acceptance Criteria

This may be the most powerful part. Acceptance criteria make the task measurable:

```text
Acceptance Criteria:

1. If Provider A returns a transient 503 error, Provider B receives
   the request.

2. If Provider A returns a 401 error, failover does not occur.

3. Existing single-provider configurations continue to work unchanged.

4. Automated tests cover both successful failover and non-retryable
   failures.

5. All existing tests still pass.
```

Now the model has a checklist. More importantly, it can verify its own work against that checklist.

## Verification

Do not assume the model will automatically verify everything. Tell it what verification means:

```text
Verification:

- Run the existing unit tests.
- Add tests for the new behavior.
- Run `cargo clippy`.
- Run `cargo fmt --check`.
- If any test fails, investigate before finishing.
```

This changes the workflow from `generate` into `generate -> verify`. That small difference dramatically improves coding-agent reliability.

## Execution Policy

For agents with tools, one more section becomes useful: define how much autonomy the agent has.

```text
Execution:

You may inspect and modify files inside the repository.

You may run tests and local development commands.

Do not create commits.

Do not modify CI configuration unless required by the acceptance
criteria.

Ask before performing destructive operations.
```

That is far clearer than hoping the agent guesses the right operational boundaries.

## Match the Specification to the Task

There is another failure mode: over-specification. You do not need a three-page task description to change a button label:

```text
Change the label from "Send" to "Submit".

Do not change styling or behavior.
```

That is enough. The amount of specification should roughly match the uncertainty and risk of the task:

```text
More ambiguity
+
more impact
+
more autonomy
=
more specification
```

## Summary

- The difference between mediocre and good LLM results is usually specification quality, not a magic phrase.
- Put the goal first and describe the desired end state — not an implementation guess.
- Structure serious requests in layers: goal, context, requirements, constraints, non-goals, acceptance criteria, verification, execution policy.
- Requirements describe behavior, constraints protect what must not change, and non-goals prevent scope creep.
- Acceptance criteria plus an explicit verification step turn a one-shot generator into a self-checking workflow.
- Scale specification effort to ambiguity, impact, and autonomy.

## References

- [Part 1: LLM Memory Is Not Chat History]({% post_url 2026-09-05-llm-memory-is-not-chat-history-part-1 %})
- [Part 2: Context Is a Budget]({% post_url 2026-09-06-context-is-a-budget-part-2 %})
- [Part 3: Skills Are Not Prompts]({% post_url 2026-09-12-skills-are-not-prompts-part-3 %})
- [Part 5: Loops, Guardrails, and Templates]({% post_url 2026-09-20-stop-writing-prompts-start-writing-specifications-part-5 %})
