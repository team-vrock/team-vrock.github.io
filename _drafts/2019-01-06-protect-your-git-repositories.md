---
layout: post
title: "Protect your Git repositories"
date: 2019-01-06 14:54:00 +0100
categories: post
image: "/assets/img/git.png"
tags: git
author: Tobias Geiser
excerpt_separator: <!--more-->
---

This draft outlines a practical baseline for protecting Git repositories with account security, signed commits, and disciplined key handling. It remains unpublished until the screenshots and current platform guidance are refreshed.
<!--more-->

### Security baseline

Repository protection starts with the account and workstation, not with Git alone. A useful baseline should include:

* Multi-factor authentication on GitHub or GitLab
* Unique SSH keys per workstation or security token
* Signed commits for sensitive repositories
* Protected branches and reviewed pull requests
* Recovery codes stored outside the workstation

### Generate a signing key

For modern systems, Ed25519 is a good default for SSH keys. For commit signing, GitHub also supports SSH signing keys, which can be simpler than maintaining a separate GPG workflow.

{% highlight shell %}
ssh-keygen -t ed25519 -C "name@example.com"
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
{% endhighlight %}

### Enable multi-factor authentication

Turn on MFA before adding new keys or enforcing repository controls.

* [GitHub: Configuring two-factor authentication](https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa/configuring-two-factor-authentication)
* [GitLab: Two-factor authentication](https://docs.gitlab.com/user/profile/account/two_factor_authentication/)

### Repository controls to document

* Require pull request reviews on protected branches.
* Require status checks before merge.
* Require signed commits where supported.
* Restrict who can push to release branches.
* Review deploy keys and personal access tokens regularly.

### Before publishing

* Decide whether the final article should focus on SSH signing, GPG signing, or both.
* Update screenshots for the current GitHub and GitLab interfaces.
* Verify all commands on Linux and macOS.
* Add a short checklist readers can copy into repository documentation.

### References

* [GitHub: About commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
* [GitHub: Signing commits with SSH keys](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
* [OpenSSH: Release notes](https://www.openssh.com/releasenotes.html)
