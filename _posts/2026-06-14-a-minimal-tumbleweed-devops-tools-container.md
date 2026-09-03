---
layout: post
title: "A Minimal Tumbleweed DevOps Tools Container"
date: 2026-06-14 10:00:00 +0000
categories: post
tags: [opensuse, docker, devops, terraform, tooling]
author: Tobias Geiser
image: "/assets/posts/2026-06-14/devops-tumbleweed.png"
header: "/assets/posts/2026-06-14/devops-tumbleweed-header.png"
excerpt_separator: <!--more-->
---

Every cloud CLI has its own install ritual, its own release channel, and its own way of breaking your host a little. I stopped installing them on the host entirely. Instead there is one small openSUSE Tumbleweed container that carries the whole toolchain — Terraform, OpenTofu, PowerShell, Azure CLI, Google Cloud CLI, GitHub CLI, and the AI coding CLIs — pinned, checksum-verified, and running as a non-root user. Any machine with Docker becomes an identical workstation in one build.
<!--more-->

**TL;DR:** One Dockerfile on `opensuse/tumbleweed`, every tool downloaded at a pinned version and verified against SHA256 sums, corporate CA certificates injected at build time, everything running as a non-root user with XDG paths. Tool configs persist through three host-side volume mounts. The two real failures along the way: a dead Google Cloud CLI download endpoint, and root-owned config directories created by an earlier careless run.

## Overview

This post builds a disposable-but-reproducible DevOps workstation container. It is for you if:

- You work across several machines (or CI runners) and want the same tool versions everywhere.
- You refuse to let cloud CLIs scatter themselves over your host system.
- You sit behind TLS-intercepting proxies or private CAs that break stock toolchains.

The tool list in the image I ship:

| Tool | Purpose |
|---|---|
| Terraform / OpenTofu | infrastructure as code |
| PowerShell | Azure-flavored scripting |
| Azure CLI / Google Cloud CLI | cloud operations |
| GitHub CLI | repository and PR work |
| Oh My Posh | prompt theming |
| Gemini CLI, Codex CLI, OpenCode CLI, Copilot CLI | AI coding assistants |

## Architecture

Three decisions shape the image:

1. **Pinned downloads, verified checksums.** Every binary tool is fetched at an explicit version from its official release URL and checked against the vendor's SHA256SUMS (or a pinned digest where the vendor publishes none). No package-manager surprises, no silent upgrades.
2. **Certificates baked in.** Private CA certificates are copied into `/etc/pki/trust/anchors/` and activated with `update-ca-certificates` at build time, and every SSL-aware runtime is pointed at the system bundle via environment variables.
3. **Non-root with XDG paths.** The container runs as a `devops` user, and all tool configuration lives under `$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$XDG_CACHE_HOME` — which are just three host-mounted directories, so logins and settings survive container rebuilds.

![Multi-stage DevOps container build pipeline: base builder, checksum-verified downloads, non-root user security, and minimal runtime image.](/assets/posts/2026-06-14/devops-container-build.png){: style="max-width: 100%; min-width: 100%; height: auto"}

## Prerequisites

- Docker (or Podman) with buildx for `TARGETARCH` support.
- Optional: your private CA certificates as `.pem` files, if you sit behind TLS inspection.
- Three host directories for persisting tool config (created below).

## Walkthrough

### Lay out the project

```text
~/src/docker-devops-tools/
├── Dockerfile
├── devops-entrypoint
├── certs/               # your *.pem CA certificates
└── README.md
```

The base is the minimal Tumbleweed image:

```dockerfile
# syntax=docker/dockerfile:1
FROM registry.opensuse.org/opensuse/tumbleweed:latest
```

### Pin every version as a build arg

Versions live at the top of the Dockerfile so a bump is a one-line change:

```dockerfile
ARG TERRAFORM_VERSION=1.15.8
ARG OPENTOFU_VERSION=1.12.4
ARG POWERSHELL_VERSION=7.6.3
ARG AZURE_CLI_VERSION=2.88.0
ARG GOOGLE_CLOUD_CLI_VERSION=576.0.0
ARG GH_VERSION=2.96.0
```

### Verify checksums on every download

Each tool follows the same pattern — download, verify against the vendor's published sums, install, delete the archive. Terraform as the example:

```dockerfile
RUN set -eux; \
    arch="${TARGETARCH:-$(uname -m)}"; \
    case "${arch}" in amd64|x86_64) tool_arch=amd64 ;; arm64|aarch64) tool_arch=arm64 ;; *) exit 1 ;; esac; \
    cd /tmp; \
    file="terraform_${TERRAFORM_VERSION}_linux_${tool_arch}.zip"; \
    base_url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"; \
    curl -fsSLO "${base_url}/${file}"; \
    curl -fsSLO "${base_url}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    grep " ${file}$" "terraform_${TERRAFORM_VERSION}_SHA256SUMS" | sha256sum -c -; \
    unzip -q "${file}" -d /usr/local/bin; \
    rm -f "${file}" "terraform_${TERRAFORM_VERSION}_SHA256SUMS"
```

`TARGETARCH` makes the image build natively for both x86_64 and arm64. For the Google Cloud CLI, Google publishes no per-file sums for the tarballs I use, so the digests are pinned in the Dockerfile itself:

```dockerfile
ARG GOOGLE_CLOUD_CLI_AMD64_SHA256=<sha256-amd64>
ARG GOOGLE_CLOUD_CLI_ARM64_SHA256=<sha256-arm64>
```

The Azure CLI goes into its own virtualenv so pip never fights the distro Python:

```dockerfile
RUN python3 -m venv /opt/azure-cli; \
    /opt/azure-cli/bin/python -m pip install --no-cache-dir "azure-cli==${AZURE_CLI_VERSION}"; \
    ln -sf /opt/azure-cli/bin/az /usr/local/bin/az
```

The Node-based CLIs install globally for the build user with pinned versions:

```dockerfile
RUN npm install --global \
    "@google/gemini-cli@${GEMINI_CLI_VERSION}" \
    "@openai/codex@${CODEX_CLI_VERSION}" \
    "opencode-ai@${OPENCODE_CLI_VERSION}" \
    "@github/copilot@${COPILOT_CLI_VERSION}"
```

### Inject your CA certificates

If your network intercepts TLS, stock images fail everywhere with certificate errors. Copy your PEM files in and activate them *before* any download step:

```dockerfile
COPY certs/ /etc/pki/trust/anchors/
RUN /usr/sbin/update-ca-certificates
```

Then make every runtime trust the system bundle explicitly:

```dockerfile
ENV SSL_CERT_FILE=/etc/ssl/ca-bundle.pem \
    REQUESTS_CA_BUNDLE=/etc/ssl/ca-bundle.pem \
    CURL_CA_BUNDLE=/etc/ssl/ca-bundle.pem \
    NODE_EXTRA_CA_CERTS=/etc/ssl/ca-bundle.pem \
    GIT_SSL_CAINFO=/etc/ssl/ca-bundle.pem \
    NPM_CONFIG_CAFILE=/etc/ssl/ca-bundle.pem
```

This one block fixes Python `requests`, curl, Node, git, and npm in one go.

### Run as a non-root user with XDG paths

Create the user, pre-create the XDG tree, and keep tools pointing inside the home directory:

```dockerfile
ARG USERNAME=devops
ARG USER_UID=1000
ARG USER_GID=1000

ENV HOME=/home/${USERNAME} \
    XDG_CONFIG_HOME=/home/${USERNAME}/.config \
    XDG_DATA_HOME=/home/${USERNAME}/.local/share \
    XDG_CACHE_HOME=/home/${USERNAME}/.cache \
    GH_CONFIG_DIR=/home/${USERNAME}/.config/gh \
    AZURE_CONFIG_DIR=/home/${USERNAME}/.config/azure \
    CLOUDSDK_CONFIG=/home/${USERNAME}/.config/gcloud

RUN groupadd --gid "${USER_GID}" "${USERNAME}"; \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}"
USER ${USERNAME}
WORKDIR /workspace
```

Build the `USER_UID`/`USER_GID` args to match your host user and bind mounts become permission-free.

The entrypoint only makes sure the config directories exist, then hands over:

```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_CACHE_HOME}" \
  "${GH_CONFIG_DIR}" "${AZURE_CONFIG_DIR}" "${CLOUDSDK_CONFIG}"
exec "$@"
```

### Build and verify

```bash
docker build --pull -t devops-tools:tumbleweed .
```

Then smoke-test every tool:

```bash
docker run --rm devops-tools:tumbleweed terraform version
docker run --rm devops-tools:tumbleweed tofu --version
docker run --rm devops-tools:tumbleweed az version
docker run --rm devops-tools:tumbleweed gcloud --version
docker run --rm devops-tools:tumbleweed gh --version
```

### Persist tool configuration

Mount the three XDG directories from the host (plus your workdir), using `:Z` so SELinux relabeling works:

```bash
mkdir -p \
  ~/.config/docker/devops \
  ~/.local/share/docker/devops \
  ~/.cache/docker/devops

docker run --rm -it \
  -v ~/.config/docker/devops:/home/devops/.config:Z \
  -v ~/.local/share/docker/devops:/home/devops/.local/share:Z \
  -v ~/.cache/docker/devops:/home/devops/.cache:Z \
  -v "$PWD:/workspace:Z" \
  -w /workspace \
  devops-tools:tumbleweed
```

Log in once (`az login`, `gcloud auth login`, `gh auth login`) and every later container — rebuilt, on another machine, in CI — starts authenticated.

## Troubleshooting

### The Google Cloud CLI download dies mid-build

The original download URL for the gcloud tarball started failing builds intermittently. The working endpoint is the direct downloads host:

```text
https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-<version>-linux-<arch>.tar.gz
```

The Dockerfile downloads with `--http1.1`, verifies the pinned digest, and retries up to five times with a short sleep — flaky mirrors should not fail a build.

**Pro tip:** when a vendor endpoint misbehaves, pin the checksum anyway. A retry loop without verification only guarantees you get *something*.

### Permission denied on the config mounts

If Docker ever auto-created the host config directories as root, the non-root container cannot write them and fails at startup. Fix ownership on the host:

```bash
sudo chown -R "$(id -u):$(id -g)" \
  ~/.config/docker/devops \
  ~/.local/share/docker/devops \
  ~/.cache/docker/devops
```

Without passwordless sudo, repair from inside Docker instead:

```bash
docker run --rm --user root --entrypoint bash \
  -v ~/.config/docker/devops:/home/devops/.config:Z \
  devops-tools:tumbleweed \
  -lc 'chown -R 1000:1000 /home/devops/.config'
```

## Summary

- One Tumbleweed image replaces a dozen host installs; every machine runs identical versions.
- Pin versions as build args and verify vendor SHA256 sums; pin digests yourself where the vendor publishes none.
- Inject private CAs at build time and point all runtimes at the system bundle.
- Non-root user + XDG paths + three volume mounts = persistent logins across rebuilds.
- Retry flaky vendor endpoints, but never without checksum verification.

## References

- [openSUSE Tumbleweed container images](https://registry.opensuse.org/)
- [OpenTofu releases](https://github.com/opentofu/opentofu/releases)
- [Google Cloud CLI install archives](https://cloud.google.com/sdk/docs/install)
