---
layout: post
title: "Notes on Ubuntu LXC labs"
date: 2018-04-23 16:16:01 +0100
categories: post
image: "/assets/img/ubuntu.png"
tags: ubuntu
author: Tobias Geiser
excerpt_separator: <!--more-->
---

This draft collects practical notes for building a small Ubuntu LXC lab. It is intentionally unpublished until the commands, screenshots, and current Ubuntu version are reviewed.
<!--more-->

### Goal

Create a repeatable local lab that can be used for testing Linux services, configuration management, and automation workflows without creating full virtual machines for every experiment.

### Topics to cover

* Host prerequisites and package installation
* Container creation and lifecycle commands
* Network configuration options
* Storage layout and snapshot strategy
* Common troubleshooting commands
* When to use LXC instead of Docker or a full VM

### Example commands to verify

{% highlight shell %}
sudo apt update
sudo apt install lxc lxc-templates bridge-utils
lxc-create -n lab-ubuntu -t download -- --dist ubuntu --release noble --arch amd64
lxc-start -n lab-ubuntu
lxc-attach -n lab-ubuntu
{% endhighlight %}

### Before publishing

* Update examples to the currently supported Ubuntu LTS release.
* Add tested networking guidance.
* Replace placeholder command output with verified output.
* Add a short conclusion with recommended use cases.
