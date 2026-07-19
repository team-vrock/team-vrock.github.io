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

Protecting Git repositories starts with disciplined account security, reliable key management, signed changes, and repository-level controls. This article outlines a practical baseline for teams that want to reduce risk without adding unnecessary process overhead.
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
ssh-keygen -t ed25519 -C "workstation@example.invalid"
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
{% endhighlight %}

### Enable multi-factor authentication

Turn on MFA before adding new keys or enforcing repository controls.

* [GitHub: Configuring two-factor authentication](https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa/configuring-two-factor-authentication)
* [GitLab: Two-factor authentication](https://docs.gitlab.com/user/profile/account/two_factor_authentication/)

### Repository controls

* Require pull request reviews on protected branches.
* Require status checks before merge.
* Require signed commits where supported.
* Restrict who can push to release branches.
* Review deploy keys and personal access tokens regularly.

### Operational checklist

* Define whether SSH signing, GPG signing, or both are required.
* Keep account recovery and multi-factor authentication documentation current.
* Verify key-generation and signing commands on supported workstation platforms.
* Review branch protection, deploy keys, and access tokens on a regular schedule.

### References

* [GitHub: About commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
* [GitHub: Signing commits with SSH keys](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
* [OpenSSH: Release notes](https://www.openssh.com/releasenotes.html)
