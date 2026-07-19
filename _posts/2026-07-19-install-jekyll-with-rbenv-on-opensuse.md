---
layout: post
title: "Install Jekyll with rbenv on openSUSE"
date: 2026-07-19 00:00:00 +0100
categories: post
image: "/assets/img/logo.png"
tags: [jekyll, ruby, opensuse]
author: Tobias Geiser
excerpt_separator: <!--more-->
---

Jekyll projects are easier to maintain when each repository defines its own Ruby version. `rbenv` provides a clean way to install Ruby, select the version per project, and keep Bundler and Jekyll isolated from the system Ruby.
<!--more-->

This guide shows a step-by-step setup for openSUSE using `rbenv`, `ruby-build`, Bundler, and Jekyll.

### 1. Install openSUSE packages

Install the compiler, headers, and libraries required by `ruby-build` before compiling Ruby.

```bash
sudo zypper refresh
sudo zypper install git curl gcc make patch zlib-devel libopenssl-devel readline-devel libyaml-devel libffi-devel gdbm-devel ncurses-devel sqlite3-devel
```

If your workstation uses a minimal development setup, also install the base development pattern.

```bash
sudo zypper install -t pattern devel_basis
```

### 2. Install rbenv and ruby-build

Install `rbenv` into your home directory and add `ruby-build` as a plugin.

```bash
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
```

### 3. Initialize rbenv for the current shell

Add `rbenv` to the current shell session and initialize it for Bash.

```bash
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
```

To make this persistent, add the same initialization to `~/.bashrc`.

```bash
printf '%s\n' 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
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

Use `rbenv local` when a project should consistently use the same Ruby version.

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

### 8. Build and serve the Jekyll site

Build the site first to catch configuration, theme, and dependency issues.

```bash
bundle exec jekyll build
```

Serve the site locally while working on content.

```bash
bundle exec jekyll serve
```

To include draft posts during local preview, add `--drafts`.

```bash
bundle exec jekyll serve --drafts
```

### Operational notes

* Use `rbenv local` for repository-specific Ruby versions.
* Use `rbenv shell` for short-lived terminal overrides.
* Run `ruby -v` before troubleshooting Bundler or Jekyll issues.
* Keep the Ruby version aligned with the version used by CI.
* Use `bundle exec` so Jekyll runs with the gems from the project bundle.
