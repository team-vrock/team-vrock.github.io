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

An Ubuntu LXC lab provides a lightweight environment for validating Linux services, configuration management, and automation workflows before applying changes to shared infrastructure.
<!--more-->

### Goal

Create a repeatable local lab that can be used for testing Linux services, configuration management, and automation workflows without creating full virtual machines for every experiment.

### Implementation areas

* Host prerequisites and package installation
* Container creation and lifecycle commands
* Network configuration options
* Storage layout and snapshot strategy
* Common troubleshooting commands
* When to use LXC instead of Docker or a full VM

### Initial setup commands

{% highlight shell %}
sudo apt update
sudo apt install lxc lxc-templates bridge-utils
lxc-create -n lab-ubuntu -t download -- --dist ubuntu --release noble --arch amd64
lxc-start -n lab-ubuntu
lxc-attach -n lab-ubuntu
{% endhighlight %}

### Operational checklist

* Confirm the Ubuntu LTS release used for new containers.
* Document the selected networking model and address allocation approach.
* Capture storage and snapshot practices for repeatable lab recovery.
* Define when LXC is appropriate compared with Docker or full virtual machines.
