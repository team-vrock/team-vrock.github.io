---
layout: post
title: "An Azure Landing Zone Built from Solutions, Part 2: Dependency-Ordered CI"
date: 2026-07-19 10:00:00 +0000
categories: post
tags: [azure, terraform, opentofu, landing-zone, iac, cloud, github-actions, ci]
author: Tobias Geiser
image: "/assets/posts/2026-07-19/azure-ci-pipeline.png"
header: "/assets/posts/2026-07-19/azure-ci-pipeline-header.png"
excerpt_separator: <!--more-->
---

Part 1 ended with a dependency graph sitting in `config.json`. This part is about executing it: how the landing zone runs plans on pull requests, applies solutions in topological order, and verifies everything on every merge to `main` — and what happened the first time the governance solution hit a management group with a freshly assigned role.
<!--more-->

**TL;DR:** Pull requests plan exactly one changed solution (enforced). Manual `workflow_dispatch` workflows plan/apply the whole graph in `depends_on` order via a single orchestrator job, because GitHub Actions cannot build dynamic `needs` from runtime config. `verify` runs on every push to `main`. Authentication is OIDC. The troubleshooting section covers the classic 403 you get right after assigning a role at management-group scope.

This is Part 2 of a two-part series. [Part 1]({% post_url 2026-07-12-an-azure-landing-zone-built-from-solutions-part-1 %}) covers the architecture.

## Overview

Three workflows, each delegating to a reusable workflow in the shared module-collection repository:

| Workflow | Trigger | Purpose |
|---|---|---|
| `main.yml` | push/PR touching `solutions/**` | plan the changed solution, review gates, apply on merge |
| `terraform-all-plan.yml` / `terraform-all-apply.yml` | `workflow_dispatch` | plan/apply *all enabled solutions* in dependency order |
| `terraform-all-verify.yml` | push to `main` | re-check the whole graph: configs parse, dependencies resolve, plans are clean |

All of them federate with `permissions: id-token: write` and inherit repository secrets — Azure credentials are never stored, only the federated service principal's client ID.

![Dependency-ordered Azure solutions CI pipeline: pull request trigger, dependency graph resolution, wave-based parallel execution, and automated verification.](/assets/posts/2026-07-19/azure-solutions-ci-pipeline.png){: style="max-width: 100%; min-width: 100%; height: auto"}

## Walkthrough

### Keep PRs to one solution

The push/PR workflow is path-filtered to `solutions/**` and the reusable workflow **fails if more than one solution changed**. That sounds strict, and it is — deliberately. One solution per change keeps plans reviewable, keeps blast radius obvious, and makes the single-orchestrator design below tractable. If you need to change two solutions, you open two PRs in dependency order.

```yaml
on:
  push:
    branches: [main]
    paths: ['solutions/**.tf', 'solutions/**.tfvars']
  pull_request:
    branches: [main]
    paths: ['solutions/**.tf', 'solutions/**.tfvars']

permissions:
  id-token: write
  contents: write
  pull-requests: write

jobs:
  remote-tofu-workflow:
    secrets: inherit
    uses: <org>/<module-collection>/.github/workflows/terraform-main.yml@main
```

### Order the graph with one orchestrator job

The "all solutions" workflows read the root `config.json`, discover `solutions/*` on disk, and build an execution order:

1. Parse `solutions.<name>.depends_on` for every configured solution.
2. Fail early on a `depends_on` pointing at a missing solution name, a solution without a directory, or a circular dependency.
3. Topologically sort the configured solutions.
4. Run the dependency graph first, in order.
5. Run any solution that exists on disk but is *not* listed in config afterwards, in any order.

The whole run happens in a **single orchestrator job**. The tempting alternative — generating a job matrix with per-solution `needs` — does not work: GitHub Actions cannot express dynamic `needs` relationships computed from runtime config. A sequential loop inside one job is the honest implementation, and for a landing zone with a handful of solutions the runtime difference is irrelevant.

```yaml
name: "OpenTofu All Plan"
on: [workflow_dispatch]
permissions:
  id-token: write
  contents: read
jobs:
  plan:
    secrets: inherit
    uses: <org>/<module-collection>/.github/workflows/terraform-all-plan.yml@main
```

### Verify on every merge

`terraform-all-verify.yml` runs on push to `main` and re-validates the entire graph: config files parse, the dependency graph is acyclic and complete, and every enabled solution still plans. It is the safety net for the moment someone merges a module-collection bump that only shows its damage two solutions downstream.

**Pro tip:** when a plan looks wrong, check whether the module is even active in that solution's workspace first. I chased a "missing policy changes" mystery that turned out to be a policy module never referenced by the solution's tfvars — the plan was correct, my expectation was not.

### Federate, don't embed credentials

Each workflow authenticates with OIDC: GitHub presents a token, Azure's federated credential on the service principal accepts it. The only repo-level input is the client ID. Rotate nothing, leak nothing.

## Troubleshooting

### 403 Forbidden at the management group — with Owner already assigned

The governance solution assigns policies and role definitions at management-group scope. After wiring everything up, `apply` failed with:

```text
Error: ... 403 Forbidden ... scope: /providers/Microsoft.Management/managementGroups/<ROOT_MGMT_GROUP>
```

The confusing part: the portal already showed the GitHub OIDC service principal as **Owner** on that management group. Two things were going on:

1. **Account vs. principal confusion.** The interactive account I used to check in the portal had only subscription-level roles, so some of my manual verification commands failed with 403 even though the *service principal* was fine. Always check permissions for the exact identity the pipeline uses.
2. **RBAC propagation delay.** Even after granting Owner to the SP at management-group scope, Azure RBAC changes take time to propagate. Applies that worked minutes later failed right after the assignment. Fix: wait and retry (minutes, occasionally longer at high scopes), and treat "assigned in portal but 403 in API" as a propagation symptom, not a misconfiguration.

**Gotcha:** if your pipeline identity only ever had subscription-level roles, no amount of portal staring helps — management-group scope assignments are a separate grant.

### One change per PR feels limiting

It is the most common pushback. The trade is deliberate: strict single-solution PRs keep the reusable workflow simple, make `needs`-free orchestration viable, and force dependency order into the review process where humans can see it. When you genuinely need coordinated multi-solution changes, the manual all-plan/all-apply workflows are the escape hatch.

## Summary

- PR workflow = one changed solution, path-filtered, enforced by the reusable workflow.
- All-solutions runs = single orchestrator job, topological order from `depends_on`, early failure on cycles and missing references.
- Verify on every merge to `main` keeps the whole graph honest.
- OIDC federation everywhere; the only stored value is a client ID.
- 403 at management-group scope right after a role grant is usually RBAC propagation delay — retry before re-architecting.

## References

- [Part 1: Architecture]({% post_url 2026-07-12-an-azure-landing-zone-built-from-solutions-part-1 %})
- [GitHub Actions: reusable workflows](https://docs.github.com/actions/sharing-automations/reusing-workflows)
- [Azure: workload identity federation for GitHub Actions](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
