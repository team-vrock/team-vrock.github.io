---
layout: post
title: "Install Jekyll with rbenv on Linux"
date: 2026-07-19 00:00:00 +0100
categories: post
image: "/assets/posts/2026-07-19/rbenv-linux.png"
tags: [jekyll, ruby, linux, debian, ubuntu, redhat, opensuse, arch]
author: Tobias Geiser
excerpt_separator: <!--more-->
---

Installing Jekyll into your system Ruby is how you end up with gem conflicts, broken system tools, and upgrades that hurt. I stopped doing that. Every Jekyll repository I maintain pins its own Ruby version with `rbenv`, so Bundler and Jekyll stay isolated, CI and local machines build the same thing, and a distribution update can no longer take the website down.
<!--more-->

## Overview

System Ruby installations are shared by the operating system and package tooling, which makes them a poor place to install Jekyll and its native gems. This guide sets up `rbenv` and `ruby-build` so that:

- Ruby is compiled and managed per user, independently of distribution packages.
- A project pins its Ruby version in a `.ruby-version` file.
- Bundler and Jekyll run from the project bundle through `bundle exec`.

The guide shows a step-by-step setup for Debian, Ubuntu, Red Hat-family distributions, openSUSE, and Arch Linux using `rbenv`, `ruby-build`, Bundler, and Jekyll.

## Prerequisites

- A workstation running Debian, Ubuntu, Fedora, RHEL/CentOS Stream/Rocky/AlmaLinux, openSUSE, or Arch Linux.
- `sudo` access to install distribution packages.
- A Jekyll project repository with a `Gemfile`. The guide uses Ruby `3.3.12` as the example version; replace it with the version your project requires.

## Walkthrough

### 1. Install Linux packages

Install the compiler, headers, and libraries required by `ruby-build` before compiling Ruby.

For Debian and Ubuntu, install the build tools and development libraries with `apt`. `rustc` is included so Ruby can be built with YJIT support, which `ruby-build` enables when a Rust compiler is available.

```bash
sudo apt update
sudo apt install git curl build-essential autoconf patch rustc libssl-dev libyaml-dev libreadline-dev zlib1g-dev libgmp-dev libncurses-dev libffi-dev libgdbm-dev libdb-dev uuid-dev libsqlite3-dev
```

For Fedora, Red Hat Enterprise Linux, CentOS Stream, Rocky Linux, and AlmaLinux, install the build tools and development libraries with `dnf`.

```bash
sudo dnf install git curl gcc make patch openssl-devel readline-devel zlib-devel libyaml-devel libffi-devel gdbm-devel ncurses-devel sqlite-devel
```

For openSUSE, install the build tools and development libraries with `zypper`.

```bash
sudo zypper refresh
sudo zypper install git curl gcc make patch zlib-devel libopenssl-devel readline-devel libyaml-devel libffi-devel gdbm-devel ncurses-devel sqlite3-devel
```

If your workstation uses a minimal development setup, also install the base development pattern.

```bash
sudo zypper install -t pattern devel_basis
```

For Arch Linux, install the build tools and development libraries with `pacman`.

```bash
sudo pacman -Syu
sudo pacman -S git curl base-devel openssl readline zlib libyaml libffi gdbm ncurses sqlite
```

### 2. Install rbenv and ruby-build

Install `rbenv` and `ruby-build` from your distribution repositories where available.

On Debian and Ubuntu:

```bash
sudo apt install rbenv ruby-build
```

On Fedora and Red Hat-family distributions:

```bash
sudo dnf install rbenv ruby-build
```

Depending on the distribution release, these packages may require EPEL or another additional repository.

On openSUSE:

```bash
sudo zypper install rbenv ruby-build
```

On Arch Linux:

```bash
sudo pacman -S rbenv ruby-build
```

Distribution packages can lag behind current Ruby releases. If `rbenv install 3.3.12` fails or `rbenv install --list` does not show the Ruby version you need, update the `ruby-build` definitions. When `ruby-build` is installed as the `rbenv` plugin, update it from Git:

```bash
git -C "$(rbenv root)/plugins/ruby-build" pull
```

When the distribution package owns the definitions instead, install a current release of `ruby-build` from its [GitHub releases](https://github.com/rbenv/ruby-build/releases) or use the `rbenv` installer to get plugin-based management.

### 3. Initialize rbenv for the current shell

Initialize `rbenv` for the current Bash session.

```bash
eval "$(rbenv init - bash)"
```

To make this persistent, add the initialization to `~/.bashrc`.

```bash
printf '%s\n' 'eval "$(rbenv init - bash)"' >> ~/.bashrc
```

Open a new shell or reload the file.

```bash
source ~/.bashrc
```

Confirm that `rbenv` is available.

```bash
rbenv --version
```

### 4. Install Ruby

Install the Ruby version used by the project.

```bash
rbenv install 3.3.12
```

Confirm the installed version is available.

```bash
rbenv versions
```

### 5. Select Ruby for the project with rbenv local

Run this command in the Jekyll project directory. It writes a `.ruby-version` file for the repository.

```bash
rbenv local 3.3.12
ruby -v
```

Use `rbenv local` when a project should consistently use the same Ruby version. Commit `.ruby-version` so every contributor and CI job selects the same Ruby.

### 6. Select Ruby for the shell with rbenv shell

Use `rbenv shell` when you need a temporary Ruby version for the current terminal session only.

```bash
rbenv shell 3.3.12
ruby -v
```

Clear the temporary override when it is no longer needed.

```bash
rbenv shell --unset
```

### 7. Install Bundler and project dependencies

Install Bundler for the selected Ruby version.

```bash
gem install bundler
```

Install the gems defined by the Jekyll project.

```bash
bundle install
```

Commit `Gemfile.lock` so builds are reproducible. If you want to keep the installed gems inside the repository checkout (for example to keep them out of the global gem directory), configure a local bundle path and add the directory to `.gitignore`:

```bash
bundle config set --local path vendor/bundle
bundle install
```

### 8. Build and serve the Jekyll site

Build the site first to catch configuration, theme, and dependency issues.

```bash
bundle exec jekyll build
```

Serve the site locally while working on content. Add `--livereload` so the browser refreshes when files change.

```bash
bundle exec jekyll serve --livereload
```

To include draft posts during local preview, add `--drafts`.

```bash
bundle exec jekyll serve --drafts --livereload
```

## Troubleshooting

### `rbenv install` reports the version is not available

The installed `ruby-build` definitions are older than the requested Ruby release. Update `ruby-build` as described in step 2 and retry `rbenv install --list`.

### The Ruby build fails with missing header errors

Compile errors that mention `openssl`, `readline`, or `zlib` usually mean a development package from step 1 is missing. Install the missing `-dev`/`-devel` package and rerun `rbenv install`. The build log printed by `ruby-build` names the failing component near the end of its output.

### `jekyll` or `bundle` runs against the wrong Ruby

Check the active selection before debugging Bundler or Jekyll:

```bash
rbenv version
ruby -v
which bundle
```

If `rbenv version` does not show the project version, run `rbenv local 3.3.12` in the project directory and open a new shell.

### The local server port is already in use

Jekyll serves on port 4000 by default. Pick another port when something else is listening:

```bash
bundle exec jekyll serve --livereload --host 127.0.0.1 --port 4010
```

## Summary

- Use `rbenv local` for repository-specific Ruby versions and commit `.ruby-version`.
- Use `rbenv shell` for short-lived terminal overrides.
- Run `ruby -v` before troubleshooting Bundler or Jekyll issues.
- Keep the Ruby version aligned with the version used by CI, and commit `Gemfile.lock`.
- Use `bundle exec` so Jekyll runs with the gems from the project bundle.
- Use `--livereload` during local writing sessions to refresh the browser automatically.
