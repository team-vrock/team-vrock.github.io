---
layout: post
title: "Protect your Git repositories"
date: 2019-01-06 14:54:00 +0100
categories: post
image: "/assets/posts/2019-01-06/git-repo-sec.png"
tags: [git, github, gitlab, openssh, gpg, security]
author: Tobias Geiser
excerpt_separator: <!--more-->
---

Most repository breaches never touch Git itself. They walk in through a phished account, a leaked token, or a CI workflow with too many permissions — and by the time anyone notices, the attacker has write access to `main`. This guide is the baseline I use to make that harder: account security, key management, signed changes, branch rules, CI hardening, and a review checklist that keeps it all honest.
<!--more-->

The post is dated 2019 because it preserves the original article URL. Last reviewed: September 2, 2026. The recommendations and links below have been reviewed and updated for current GitHub, GitLab, OpenSSH, and GnuPG workflows.

## Overview

Repository protection is a layered problem. A strong transport does not help if the account is compromised, a leaked token grants write access, or an unprotected branch allows force pushes. This guide covers the layers in the order they should be built up:

- Account security and multi-factor authentication.
- Per-device SSH authentication keys and commit signing.
- Branch protection and review enforcement.
- CI/CD authentication hardening and least-privilege tokens.
- Secret detection, incident response, and workstation hygiene.
- A recurring review and recovery checklist.

The controls apply to both GitHub and GitLab. Where the platforms differ, both variants are named.

## Prerequisites

- A GitHub or GitLab account with permission to manage repository settings.
- Git, OpenSSH, and optionally GnuPG installed on your workstation.
- Administrator access to the organization or project when you configure branch rules, runners, and secret scanning.
- A FIDO2 security key or passkey if you want phishing-resistant authentication.

## Walkthrough

### 1. Protect the account first

Repository protection starts with the account and workstation, not with Git alone. A useful baseline should include:

- Enable phishing-resistant multi-factor authentication where possible, preferably a FIDO2 security key or passkey.
- Keep recovery codes outside the workstation and test account recovery before an incident.
- Use a separate account for automation instead of a personal account.
- Grant organization and repository access through groups or teams, not individually where practical.
- Review active sessions, OAuth applications, personal access tokens, deploy keys, and SSH keys regularly.
- Remove access promptly when a person, workstation, token, or integration is no longer trusted.

References:

- [GitHub: Configuring two-factor authentication](https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa/configuring-two-factor-authentication)
- [GitLab: Two-factor authentication](https://docs.gitlab.com/user/profile/account/two_factor_authentication/)
- [GitHub: Reviewing your security log](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/reviewing-your-security-log)

### 2. Use a separate SSH key per device

Do not copy one private key between laptops, servers, and build agents. A separate key per device makes revocation and incident investigation possible.

For ordinary workstation authentication, generate an Ed25519 key:

```bash
ssh-keygen -t ed25519 -a 100 -C "workstation@example.invalid" -f ~/.ssh/id_ed25519_github
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_github
chmod 644 ~/.ssh/id_ed25519_github.pub
```

Use a strong passphrase. Load the key into `ssh-agent` only when needed:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_github
```

Create an SSH client configuration so the intended key is selected explicitly:

```sshconfig
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes
```

Test the connection:

```bash
ssh -T git@github.com
```

GitHub should identify the account associated with the public key. GitLab users can use the same key-generation process and add the public key under **Preferences -> SSH Keys**.

References:

- [OpenSSH: `ssh-keygen` manual](https://man.openbsd.org/ssh-keygen)
- [GitHub: Generating a new SSH key and adding it to the SSH agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent)
- [GitLab: Add an SSH key to your GitLab account](https://docs.gitlab.com/user/ssh/)

#### Prefer hardware-backed keys for high-value accounts

For administrator accounts, release maintainers, and other high-value identities, prefer a FIDO2 security key when the workstation and OpenSSH support it:

```bash
ssh-keygen -t ed25519-sk -O resident -C "workstation-key"
```

The private-key operation is performed by the security key and normally requires physical presence, such as touching the key. Enroll a separate recovery key because losing the only hardware key can lock the account.

Hardware-backed keys improve protection of the private-key operation, but they do not replace MFA, branch protection, recovery planning, or key revocation. Some environments do not support resident keys or FIDO2-backed SSH keys. In those environments, use a passphrase-protected Ed25519 key and document the exception.

References:

- [OpenSSH: `ssh-keygen` manual](https://man.openbsd.org/ssh-keygen)
- [FIDO Alliance: FIDO2](https://fidoalliance.org/fido2/)

### 3. Sign commits and tags

Authentication proves which account can access a repository. Commit signatures provide an additional authorship signal and make tampering more visible. Choose one signing method and document it for the team.

#### SSH commit signing

GitHub and GitLab support SSH commit signatures. Configure Git to use the SSH public key as the signing key:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```

Create a test commit in a disposable repository and verify the signature before enabling enforcement:

```bash
git init signing-test
cd signing-test
git config user.name "Example User"
git config user.email "user@example.invalid"
printf '%s\n' test > file.txt
git add file.txt
git commit -m "Test signed commit"
git log --show-signature -1
```

Add the public signing key to the hosting service as a **signing key**. An SSH key used only for authentication may not automatically be treated as a signing key by the hosting service.

When signing is configured correctly, the hosting service shows a **Verified** badge on the commit. If a commit shows as unverified although it was signed, the usual causes are a signing key that was uploaded only as an authentication key, or a committer email address that matches no verified email on the account.

#### GPG commit signing

GPG remains useful when the organization already operates a key lifecycle or requires OpenPGP signatures. Generate a key using the modern elliptic-curve defaults offered by the installed GnuPG version:

```bash
gpg --full-generate-key
gpg --list-secret-keys --keyid-format=long
```

Configure Git with the long key ID:

```bash
git config --global gpg.format openpgp
git config --global user.signingkey <LONG_GPG_KEY_ID>
git config --global commit.gpgsign true
git config --global tag.gpgSign true
```

Export only the public key for upload to GitHub or GitLab:

```bash
gpg --armor --export <LONG_GPG_KEY_ID> > public-signing-key.asc
```

Never upload or publish the secret key. Back it up through the organization's approved secure process and revoke it if the private key is exposed.

#### Sign pushes as well

Signing commits protects individual changes; signed pushes extend verification to everything that reaches a branch. Sign pushes explicitly with `git push --signed`, or enable it by default:

```bash
git config --global push.gpgSign true
```

The hosting service must be configured to verify push signatures before this becomes a control: GitHub rulesets can require signed commits, and GitLab push rules can reject unsigned commits on protected branches.

References:

- [GitHub: About commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
- [GitHub: Signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
- [GitLab: Signed commits](https://docs.gitlab.com/user/project/repository/signed_commits/)
- [GnuPG: `gpg` man page](https://gnupg.org/documentation/manpage.html)

### 4. Protect important branches

Treat `main`, release, and deployment branches as controlled interfaces. Configure branch protection or protected branches with at least:

- Pull requests required for changes.
- At least one independent approval for normal changes.
- Required CI checks before merge.
- Conversation resolution before merge.
- Force pushes disabled.
- Branch deletion disabled for protected branches.
- Direct pushes restricted to a small administrator group or disabled entirely.
- Signed commits required when the team can reliably maintain signing keys.
- A merge queue or linear-history rule when it matches the team's development model.

Two additional controls strengthen the review boundary:

- Add a `CODEOWNERS` file so changes to sensitive paths (workflows, deployment configuration, packaging) require approval from the responsible team.
- Use a GitHub ruleset or branch protection rule that applies to the actual default and release branches. Rulesets are the preferred GitHub control for new policy because they can be centrally managed and layered. Test the policy with a non-administrator account; administrators may bypass controls depending on the selected settings.

References:

- [GitHub: About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merging-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub: Managing rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merging-in-your-repository/managing-rulesets/about-rulesets)
- [GitLab: Protected branches](https://docs.gitlab.com/user/project/repository/branches/protected/)
- [GitLab: Protected environments](https://docs.gitlab.com/ci/environments/protected_environments/)

### 5. Harden CI/CD authentication

Start every workflow with least-privilege token permissions and increase them only for the specific job that needs more access:

```yaml
permissions:
  contents: read
```

For deployments to a cloud provider or external secret manager, prefer GitHub Actions OIDC over long-lived cloud access keys. The workflow requests an ephemeral identity token, and the target provider verifies claims such as repository, ref, workflow, and environment before issuing short-lived credentials. Scope the trust policy to the exact repository and protected branch or environment.

Use environment protection for high-impact deployments:

- Store deployment secrets in a protected environment rather than ordinary repository secrets.
- Require reviewers for the production environment.
- Restrict deployment branches and tags.
- Keep separate credentials and policies for development, staging, and production.
- Prefer short-lived credentials and rotate any unavoidable static secret.

Do not use `pull_request_target` or `workflow_run` to execute untrusted pull-request code with access to secrets. Run untrusted validation without privileged secrets, and keep deployment jobs restricted to trusted branches after review.

References:

- [GitHub: Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [GitHub: OpenID Connect](https://docs.github.com/en/actions/concepts/security/openid-connect)
- [GitHub: Using environments for deployment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [GitHub: Workflow syntax permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)
- [GitLab: OpenID Connect authentication using ID tokens](https://docs.gitlab.com/ee/ci/secrets/id_token_authentication.html)

### 6. Minimize tokens, keys, and integrations

Use the smallest access scope for every integration:

- Prefer GitHub fine-grained personal access tokens with repository-specific access and an expiration date.
- Prefer GitLab project access tokens or deploy tokens with only the required scopes.
- Use read-only deploy keys for read-only automation.
- Use write-capable deploy keys only when a narrowly scoped automation task requires them.
- Prefer short-lived cloud credentials through OIDC over long-lived cloud secrets in CI.
- Review OAuth applications, GitHub Apps, GitLab applications, webhooks, and runners periodically.
- Store tokens in the hosting provider's secret store or a dedicated secret manager, never in Git.

References:

- [GitHub: Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [GitHub: About GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps)
- [GitHub: OpenID Connect in cloud providers](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [GitLab: Project access tokens](https://docs.gitlab.com/user/project/settings/project_access_tokens/)
- [GitLab: OpenID Connect identity federation](https://docs.gitlab.com/ci/cloud_services/)

### 7. Secure CI and pull requests

CI can modify releases and infrastructure, so treat workflow files as privileged code:

- Review changes to `.github/workflows/` and `.gitlab-ci.yml` like application code.
- Do not expose secrets to workflows running untrusted fork code.
- Avoid checking out or executing pull-request code before deciding whether it is trusted.
- Set GitHub Actions `permissions` explicitly and grant only the scopes required by each job.
- Protect release environments with approvals and restricted branches.
- Pin third-party actions to immutable commit SHAs where the threat model requires it.
- Restrict self-hosted runners and do not reuse an untrusted runner for trusted deployments.
- Keep build artifacts separate from credentials and verify release artifacts before publication.

References:

- [GitHub: Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [GitHub: Using OpenID Connect with reusable workflows](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [GitLab: CI/CD YAML syntax](https://docs.gitlab.com/ci/yaml/)
- [GitLab: CI/CD security](https://docs.gitlab.com/ee/ci/security/)

### 8. Detect and remove secrets

Assume a secret committed to Git is compromised, even if the commit is later deleted. The response should be:

1. Revoke or rotate the credential immediately.
2. Identify where it was used and inspect access logs.
3. Remove it from the working tree and history only after rotation.
4. Add a prevention rule so it is not committed again.
5. Document the incident and verify that downstream systems no longer trust the old value.

Enable the hosting provider's secret scanning and push protection where available. Add local scanning to pre-commit or CI, but do not treat scanners as a replacement for credential rotation.

Also enable dependency review and dependency alerts (for example Dependabot on GitHub): vulnerable or malicious dependencies introduced through pull requests are a supply-chain risk that secret scanning does not cover.

References:

- [GitHub: About secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)
- [GitHub: Push protection](https://docs.github.com/en/code-security/secret-scanning/working-with-secret-scanning-and-push-protection/push-protection-for-repositories-and-organizations)
- [GitLab: Secret detection](https://docs.gitlab.com/user/application_security/secret_detection/)
- [GitLab: Push rules](https://docs.gitlab.com/user/project/repository/push_rules/)

### 9. Protect the workstation and keys

Repository security depends on the endpoint where keys are used:

- Keep the operating system, OpenSSH, Git, and GnuPG updated.
- Use full-disk encryption and a screen lock.
- Keep private keys encrypted with passphrases.
- Prefer hardware-backed FIDO2 or smart-card keys for high-value accounts.
- Restrict private-key permissions to the owning user.
- Back up recovery material separately from the primary workstation.
- Record which public key belongs to which device and owner.
- Revoke keys when a device is lost, resold, reinstalled without key preservation, or suspected compromised.

Check local SSH permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config ~/.ssh/id_* 2>/dev/null || true
chmod 644 ~/.ssh/*.pub 2>/dev/null || true
ssh-add -l
```

Do not blindly apply the wildcard commands on a system containing files with different intended ownership. Inspect the result afterwards.

References:

- [OpenSSH: Manual pages](https://www.openssh.com/manual.html)
- [OpenSSH: Release notes](https://www.openssh.com/releasenotes.html)
- [GnuPG: Operational commands](https://gnupg.org/documentation/manuals/gnupg/Operational-GPG-Commands.html)

### 10. Review and recovery checklist

Run this review at a fixed interval and after security-sensitive changes:

- Confirm the default branch and release branches are protected.
- Confirm required checks still run and cannot be bypassed unintentionally.
- Review repository collaborators, organization teams, outside collaborators, and bot accounts.
- Review SSH keys, signing keys, deploy keys, access tokens, OAuth apps, and GitHub/GitLab Apps.
- Verify secret scanning and dependency/security alerts are enabled.
- Confirm backups, recovery codes, key revocation instructions, and owner contacts are current.
- Test that a revoked key or token can no longer access the repository.
- Review CI workflow permissions and protected deployment environments.

Document the date, reviewer, scope, findings, and remediation owner. A security control that no one checks becomes an assumption rather than a control.

## Troubleshooting

### A signed commit shows as unverified

Check three things: the commit's author email must match a verified email on the account, the key used to sign must be uploaded as a **signing key** (not only as an authentication key), and `git log --show-signature -1` must show a valid signature locally before blaming the hosting service.

### `ssh -T` fails after rotating keys

Confirm that `~/.ssh/config` selects the new key with `IdentityFile` and `IdentitiesOnly yes`, that the public key was added to the account, and that the old key was removed from the hosting service. `ssh -vT git@github.com` shows which key the client offered.

### A branch protection rule seems to be bypassed

Administrators can be exempt from branch protection depending on the platform settings, and rulesets support explicit bypass lists. Test the policy with a non-administrator account and review the bypass actors before trusting the rule.

### A leaked secret was deleted from history but still works

Deleting a commit does not invalidate a credential; tokens can remain cached, mirrored, or already extracted. Rotate or revoke the credential first, then clean history, then review access logs.

## Summary

- Protect the account before the repository: phishing-resistant MFA, tested recovery, and prompt access removal.
- Use one SSH key per device, sign commits and pushes, and prefer hardware-backed keys for high-value identities.
- Treat important branches as controlled interfaces with required review, required checks, and no force pushes.
- Give CI the smallest possible permissions and prefer short-lived OIDC credentials over static cloud keys.
- Assume committed secrets are compromised; rotate first, clean history second.
- Run the review checklist on a schedule so controls stay controls instead of becoming assumptions.

## References

- [GitHub Security](https://docs.github.com/en/code-security)
- [GitHub Repository security best practices](https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository)
- [GitLab Application security](https://docs.gitlab.com/user/application_security/)
- [GitLab Repository](https://docs.gitlab.com/user/project/repository/)
- [OpenSSH](https://www.openssh.com/)
- [GnuPG](https://gnupg.org/)
