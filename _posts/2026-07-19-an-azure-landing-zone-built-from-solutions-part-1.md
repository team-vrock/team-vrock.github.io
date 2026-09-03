---
layout: post
title: "An Azure Landing Zone Built from Solutions, Part 1: Architecture"
date: 2026-07-19 10:00:00 +0000
categories: post
tags: [azure, terraform, opentofu, landing-zone, iac, cloud, github-actions, ci]
author: Tobias Geiser
image: "/assets/posts/2026-07-19/azure-landing-zone.png"
header: "/assets/posts/2026-07-19/azure-landing-zone-header.png"
excerpt_separator: <!--more-->
---

Landing zones have a habit of becoming monoliths: one giant Terraform root, one giant state file, one giant argument about who is allowed to run `apply`. Mine started as a monolith too. This post shows the structure it evolved into — small, separately-versioned *solutions*, wired together by a config file with an explicit dependency graph — and why each decision was made.
<!--more-->

**TL;DR:** The landing zone is a set of solution directories (governance, hub, spoke, DNS, app platform), each with its own remote state and version-pinned references into a shared module collection. A root `config.json` declares which solutions are enabled and what they depend on. OpenTofu runs everything via OIDC federation — no long-lived service principal secrets. [Part 2]({% post_url 2026-07-26-an-azure-landing-zone-built-from-solutions-part-2 %}) covers the GitHub Actions orchestration that applies the graph in order.

This is Part 1 of a two-part series.

## Overview

This is an opinionated Azure landing zone built with OpenTofu and the `azurerm` provider. It is aimed at small teams that want CAF-style structure (hub/spoke, governance, policy baselines) without adopting the full Azure Landing Zones accelerator machinery.

The repository layout:

```text
<repository>/
├── config.json              # solution graph: enabled + depends_on
├── common/
│   ├── backend.hcl          # shared remote backend config
│   └── config.json          # shared values (OpenTofu version, backend container)
├── docs/                    # governance/policy mapping notes
├── .devcontainer/           # dev container with toolchain provisioning
├── .github/workflows/       # plan / apply / verify orchestration (Part 2)
└── solutions/
    ├── core-governance/
    ├── core-hub/
    ├── core-spoke/
    ├── core-dns/
    ├── core-dns-public/
    └── appl-containerapps/
```

![Modular Azure Landing Zone hierarchy: root management group, platform services (connectivity, identity), workload landing zones, and isolated sandboxes.](/assets/posts/2026-07-19/azure-landing-zone-hierarchy.png){: style="max-width: 100%; min-width: 100%; height: auto"}

## Architecture

### Solutions, not stacks

Every capability is a *solution*: a directory with its own Terraform root and its own state. Each solution follows the same internal shape:

```text
solutions/<solution>/
├── backend.tf      # points at common/backend.hcl
├── providers.tf    # azurerm/azuread provider config
├── versions.tf     # provider + OpenTofu version constraints
├── variables.tf
├── main.tf         # composes shared modules
├── outputs.tf
├── config/         # per-solution values
└── README.md       # generated docs (terraform-docs)
```

The payoff of separate state: a broken spoke deployment cannot lock or corrupt governance state, plans stay small and readable, and each solution can be applied independently when its dependencies allow it.

### The dependency graph

The root `config.json` is the single place that describes the whole zone. Placeholders stand for your own tenant and service principal:

```json
{
  "tenant_id": "<TENANT_ID>",
  "client_id": "<SP_CLIENT_ID>",
  "backend_container_name": "<backend-container>",
  "tofu_version": "1.12.4",
  "solutions": {
    "core-governance":   { "enabled": true,  "depends_on": [] },
    "core-hub":          { "enabled": true,  "depends_on": ["core-governance"] },
    "core-spoke":        { "enabled": true,  "depends_on": ["core-hub"] },
    "core-dns":          { "enabled": true,  "depends_on": ["core-hub"] },
    "core-dns-public":   { "enabled": true,  "depends_on": ["core-hub"] },
    "appl-containerapps":{ "enabled": false, "depends_on": ["core-spoke", "core-dns"] }
  }
}
```

Read it as a graph: governance first, then the hub network, then spokes and DNS in parallel, then the app platform once both exist. `enabled` lets you stage solutions in without deleting code. The semantics I wanted were simple: run configured solutions in dependency order, and run anything *not* listed after all its dependencies, in any order.

### Shared modules, pinned versions

Solutions do not define raw resources; they compose modules from a shared collection repository, pinned by version:

```hcl
module "network" {
  source  = "git@github.com:<org>/<module-collection>.git//core-network"
  version = "v1.0.7"
}
```

What lives where is a deliberate split:

- **core-governance** composes monitoring, policy, and subscription-settings modules — budgets with alert recipients, Defender for chosen resource types, policy assignments.
- **core-hub** composes admin, network, and security modules: hub VNet with subnets, private link/endpoint subnets, Recovery Services Vault with immutability settings, peerings.
- **core-spoke** composes network and security for workload networks peered into the infrastructure subscription.

### Where policy composition lives

The governance solution went through a design decision worth sharing. The shared module collection originally embedded tenant-specific choices: required tag names, allowed locations, partner Lighthouse tenant IDs, and the CIS benchmark assignment. That mixed *engine* with *policy*.

The resolution: keep the generic assignment engine in the shared module, but move policy **composition and parameters** into the landing zone repository. CAF/WAF choices are landing-zone decisions, and keeping them next to the platform they affect makes policy changes reviewable in context. As part of that update the CIS assignment moved from `CIS Microsoft Azure Foundations Benchmark v2.0.0` to the current `CIS Azure Foundations v3.0.0` built-in (as of July 2026), and the Microsoft cloud security benchmark assignment was refreshed too.

### Authentication without secrets

Everything runs with OIDC federation: GitHub Actions (and local runs) authenticate to Azure with `id-token: write` and a federated credential on the service principal — no client secret in any config file or CI variable. The `tenant_id`/`client_id` in `config.json` are identifiers, not credentials.

**Pro tip:** the repository ships a dev container that provisions the toolchain (OpenTofu, az CLI) on create, so "works on my machine" stops being a state you can drift into.

## Walkthrough

### Add a new solution

1. Create `solutions/<solution>/` with the standard file set; point `backend.tf` at `common/backend.hcl`.
2. Pin the shared modules you compose in `versions.tf`/`main.tf`.
3. Register it in the root `config.json` with `enabled: false` first, plus its `depends_on`.
4. Open a PR that touches only this solution directory (the CI in Part 2 is path-filtered and expects one solution per change).
5. Enable it in a follow-up change once its dependencies are deployed.

### Keep the toolchain honest

`common/config.json` pins the OpenTofu version used by CI, and each solution pins provider ranges (`azurerm >= 4.57.0`, `>= 1.12.4, < 2.0`). When you upgrade, bump the shared pin and let the verify workflow prove every solution still plans cleanly.

## Summary

- Split the landing zone into solutions with separate state; the graph lives in one config file.
- Compose pinned shared modules; keep tenant-specific policy decisions out of them.
- Use OIDC federation end to end; the config carries identifiers, never secrets.
- Stage solutions with `enabled: false` and one-solution-per-PR discipline.

## References

- [Part 2: Dependency-Ordered CI with GitHub Actions]({% post_url 2026-07-26-an-azure-landing-zone-built-from-solutions-part-2 %})
- [Cloud Adoption Framework: Azure landing zones](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- [OpenTofu documentation](https://opentofu.org/docs/)
