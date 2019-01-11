---
layout: post
title:  "Protect your git repositories"
date:   2019-01-06 14:54:00 +0100
categories: post
image:  "/assets/img/git.png"
tags: git
author: Tobias Geiser
excerpt_separator: <!--more-->
---

In this post I want to show you how you can protect your git repositories with 2-factor authentication and signed commits.
<!--more-->

### Requirements
* GnuPG [http://www.gnupg.org](http://www.gnupg.org)
* OpenSSH [http://www.openssh.org](http://www.openssh.org)
* Github [http://www.github.com](http://www.github.com) or Gitlab account [http://www.gitlab.com](http://www.gitlab.com)

![ToDo 1](/assets/posts/2019-01-06/todo_1.png)

### Generate key pair
{% highlight shell %}
gpg --full-generate-key --expert

gpg (GnuPG) 2.2.12; Copyright (C) 2018 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Please select what kind of key you want:
   (1) RSA and RSA (default)
   (2) DSA and Elgamal
   (3) DSA (sign only)
   (4) RSA (sign only)
   (7) DSA (set your own capabilities)
   (8) RSA (set your own capabilities)
   (9) ECC and ECC
  (10) ECC (sign only)
  (11) ECC (set your own capabilities)
  (13) Existing key
Your selection? 9
{% endhighlight %}

You can select 9 to generate a key for signing and encryption.

{% highlight shell %}
Please select which elliptic curve you want:
   (1) Curve 25519
   (3) NIST P-256
   (4) NIST P-384
   (5) NIST P-521
   (6) Brainpool P-256
   (7) Brainpool P-384
   (8) Brainpool P-512
   (9) secp256k1
Your selection? 1
{% endhighlight %}

Ed25519 is the most recommended public-key algorithm today.[ [1](/keyword/ed25519.html) ]

{% highlight console %}
Please specify how long the key should be valid.
         0 = key does not expire
      <n>  = key expires in n days
      <n>w = key expires in n weeks
      <n>m = key expires in n months
      <n>y = key expires in n years
Key is valid for? 2y
{% endhighlight %}

{% highlight console %}                        
GnuPG needs to construct a user ID to identify your key.

Real name: John Fischer
Email address: john.fischer@example.com
Comment:                               
You selected this USER-ID:
    "John Fischer <john.fischer@example.com>"

Change (N)ame, (C)omment, (E)mail or (O)kay/(Q)uit?
{% endhighlight %}

Enter your contact details.

{% highlight console %}
┌──────────────────────────────────────────────────────┐
│ Please enter the passphrase to                       │
│ protect your new key                                 │
│                                                      │
│ Passphrase: ________________________________________ │
│                                                      │
│       <OK>                              <Cancel>     │
└──────────────────────────────────────────────────────┘

We need to generate a lot of random bytes. It is a good idea to perform
some other action (type on the keyboard, move the mouse, utilize the
disks) during the prime generation; this gives the random number
generator a better chance to gain enough entropy.
We need to generate a lot of random bytes. It is a good idea to perform
some other action (type on the keyboard, move the mouse, utilize the
disks) during the prime generation; this gives the random number
generator a better chance to gain enough entropy.
gpg: key D58143D2057441FC marked as ultimately trusted
gpg: directory '/Users/jfischer/.gnupg/openpgp-revocs.d' created
gpg: revocation certificate stored as 
'/Users/jfischer/.gnupg/openpgp-revocs.d/BB10190FBF89500808554D4AD58143D2057441FC.rev'
public and secret key created and signed.

pub   ed25519 2019-01-06 [SC]
      BB10190FBF89500808554D4AD58143D2057441FC
uid                      John Fischer <john.fischer@example.com>
sub   cv25519 2019-01-06 [E]

{% endhighlight %}

Now you have generated your key pair.




Then you need to enable 2-factor authentication on your git account:\\
[Configuring two-factor authentication on Github](https://help.github.com/articles/configuring-two-factor-authentication/)\\
[Configuring two-factor authentication on Gitlab](https://docs.gitlab.com/ee/user/profile/account/two_factor_authentication.html)


### Import key pair
To import your private key execute:
{% highlight bash %}
gpg --import private.key
{% endhighlight %}


![ToDo 1](/assets/posts/2019-01-06/todo_1.png)


To import your private key execute:
{% highlight bash %}
gpg --import private.key
{% endhighlight %}

After the import you need to trust the key:
{% highlight bash %}
gpg --edit-key {KEY} trust quit
# enter 5<RETURN>
# enter y<RETURN>
{% endhighlight %}


To show your keys execute:
{% highlight bash %}
gpg --list-keys
{% endhighlight %}

![ToDo 2](/assets/posts/2019-01-06/todo_2.png)

Each post automatically takes the first block of text, from the beginning of the content to the first occurrence of excerpt_separator, and sets it in the post’s data hash. Take the above example of an index of posts. Perhaps you want to include a little hint about the post’s content by adding the first paragraph of each of your posts:


Each post automatically takes the first block of text, from the beginning of the content to the first occurrence of excerpt_separator, and sets it in the post’s data hash. Take the above example of an index of posts. Perhaps you want to include a little hint about the post’s content by adding the first paragraph of each of your posts:
Each post automatically takes the first block of text, from the beginning of the content to the first occurrence of excerpt_separator, and sets it in the post’s data hash. Take the above example of an index of posts. Perhaps you want to include a little hint about the post’s content by adding the first paragraph of each of your posts:
Each post automatically takes the first block of text, from the beginning of the content to the first occurrence of excerpt_separator, and sets it in the post’s data hash. Take the above example of an index of posts. Perhaps you want to include a little hint about the post’s content by adding the first paragraph of each of your posts:
Each post automatically takes the first block of text, from the beginning of the content to the first occurrence of excerpt_separator, and sets it in the post’s data hash. Take the above example of an index of posts. Perhaps you want to include a little hint about the post’s content by adding the first paragraph of each of your posts:

### References
[2018-11-29 - SURVEILLANCE SELF-DEFENSE - A Deep Dive on End-to-End Encryption: How Do Public Key Encryption Systems Work](https://ssd.eff.org/en/module/deep-dive-end-end-encryption-how-do-public-key-encryption-systems-work)\\
[2018-01-09 - RISAN - Upgrade Your -  SSH key to ED25519](https://medium.com/risan/upgrade-your-ssh-key-to-ed25519-c6e8d60d3c54)\\
[2017-10-04 - KUDELSKI SECURITY - How to defeat ED25519 and EDDSA using faults](https://research.kudelskisecurity.com/2017/10/04/defeating-eddsa-with-faults/)\\
[2017-09-27 -  EXONUM - Our choice of digital signature algorithm](https://exonum.com/blog/09-27-17-digital-signature/)