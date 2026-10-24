<!-- Upstream snapshot. Refresh from the source; do not edit manually. -->

> Source: https://codeberg.org/forgejo/security-announcements/issues/56
> Retrieved: 2026-10-05
> Source HTML SHA-256: `c75aa0de2764a56b5abb2a2adf99e90ef91ae7f13c9d723cc3251038110ecae3`
> Converted with: markitdown 0.1.5 CLI

Codeberg has changed its Terms of Use. [View complete changes](https://codeberg.org/Codeberg/org/compare/17bdb39b0c1ecd0e423f3ba592650ce57fcdfbf5..71149c7fc95ccfeae36109b5cddca339e4aa1473?files=TermsOfUse.md#diff-d760d688bb9b929b62db808bfc76abe4493d095a).

1. LLM-generated content is being restricted. [View change](https://codeberg.org/Codeberg/org/commit/71149c7fc95ccfeae36109b5cddca339e4aa1473) or [read the blog post](https://blog.codeberg.org/protecting-our-floss-commons-from-llms.html)
2. Cryptocurrency projects are no longer allowed. [View change](https://codeberg.org/Codeberg/org/commit/f383b648fd733ab88083dc390b91e77cd7589980)

 Dismiss

This website requires JavaScript.

[![Logo](/assets/img/svg/cb-logo.svg)
![Logo](/assets/img/svg/cb-logo-mono.svg)](/)[Explore](/explore/repos)
[About](https://docs.codeberg.org/getting-started/what-is-codeberg/#what-is-codeberg-e.v.%3F)
[FAQ](https://docs.codeberg.org/getting-started/faq/)
[Help](https://docs.codeberg.org)
[Donate](https://donate.codeberg.org)

[Register](/user/sign_up)
[Sign in](/user/login?redirect_to=%2fforgejo%2fsecurity-announcements%2fissues%2f56)

![forgejo/security-announcements](/repo-avatars/cf1f2319693f9ef1fb68964ca398edd1552033db4c8ec418cad35a6195cae607)

[forgejo](/forgejo)/[security-announcements](/forgejo/security-announcements)

Watch

[263](/forgejo/security-announcements/watchers)

Star
[48](/forgejo/security-announcements/stars)

[Issues](/forgejo/security-announcements/issues)
[Activity](/forgejo/security-announcements/activity)

# CVE-2026-20896: needs to be addressed manually in v15 LTS #56

[New issue](/forgejo/security-announcements/issues/new)

Closed

opened 2026-07-15 11:04:17 +02:00 by [0ko](/0ko)
·
1 comment

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=128 "0ko")](/0ko)

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=64 "0ko")](/0ko)

[0ko](/0ko)
commented [2026-07-15 11:04:17 +02:00](#issue-6286769)

Owner

Copy link

> **Note**
>
> This issue only affects container deployments that use reverse proxy for user authentication.

You're affected if you're:

* using Forgejo v15 LTS and intend to stay on Forgejo v15 LTS
* **and** using a containerized deployment (e.g. Docker or Podman)
* **and** have `[service].ENABLE_REVERSE_PROXY_AUTHENTICATION` configuration option set to `true`
* **and** have **not** overridden the `[security].REVERSE_PROXY_TRUSTED_PROXIES` configuration option, which is set to `*` by default in container images
* **and** Forgejo web port (`:3000` by default) is exposed to untrusted networks, allowing to bypass the reverse proxy (*this point was added later*)

Deployments using the official Forgejo Helm chart are not affected.

A fix for CVE-2026-20896 [has been merged](https://codeberg.org/forgejo/forgejo/pulls/12782) into Forgejo v16.0.0, to be released tomorrow. However, it is a breaking configuration change, and it will not be included in any upcoming Forgejo v15 LTS patches.

If you're affected, you need to override the default `[security].REVERSE_PROXY_TRUSTED_PROXIES` config option to include your reverse proxy's IP address, as you also would when upgrading to Forgejo v16 to address the breaking change

* with environment variable:

```
FORGEJO__security__REVERSE_PROXY_TRUSTED_PROXIES=127.0.0.0/8,::1/128,172.16.X.X/X
```

* or in the `app.ini` configuration file

```
[security]
...
REVERSE_PROXY_TRUSTED_PROXIES=127.0.0.0/8,::1/128,172.16.X.X/X
...
```

It's also possible to turn off reverse proxy authentication temporarily:

* with environment variable:

```
FORGEJO__service__ENABLE_REVERSE_PROXY_AUTHENTICATION=false
```

* or in the `app.ini` configuration file

```
[service]
...
ENABLE_REVERSE_PROXY_AUTHENTICATION=false
...
```

For more information, see [forgejo/forgejo!12782](/forgejo/forgejo/pulls/12782).

> [!note]
> This issue only affects container deployments that use reverse proxy for user authentication.
You're affected if you're:
\* using Forgejo v15 LTS and intend to stay on Forgejo v15 LTS
\* \*\*and\*\* using a containerized deployment (e.g. Docker or Podman)
\* \*\*and\*\* have `[service].ENABLE\_REVERSE\_PROXY\_AUTHENTICATION` configuration option set to `true`
\* \*\*and\*\* have \*\*not\*\* overridden the `[security].REVERSE\_PROXY\_TRUSTED\_PROXIES` configuration option, which is set to `\*` by default in container images
\* \*\*and\*\* Forgejo web port (`:3000` by default) is exposed to untrusted networks, allowing to bypass the reverse proxy (\_this point was added later\_)
Deployments using the official Forgejo Helm chart are not affected.
A fix for CVE-2026-20896 [has been merged](https://codeberg.org/forgejo/forgejo/pulls/12782) into Forgejo v16.0.0, to be released tomorrow. However, it is a breaking configuration change, and it will not be included in any upcoming Forgejo v15 LTS patches.
If you're affected, you need to override the default `[security].REVERSE\_PROXY\_TRUSTED\_PROXIES` config option to include your reverse proxy's IP address, as you also would when upgrading to Forgejo v16 to address the breaking change
\* with environment variable:
```sh
FORGEJO\_\_security\_\_REVERSE\_PROXY\_TRUSTED\_PROXIES=127.0.0.0/8,::1/128,172.16.X.X/X
```
\* or in the `app.ini` configuration file
```ini
[security]
...
REVERSE\_PROXY\_TRUSTED\_PROXIES=127.0.0.0/8,::1/128,172.16.X.X/X
...
```
It's also possible to turn off reverse proxy authentication temporarily:
\* with environment variable:
```sh
FORGEJO\_\_service\_\_ENABLE\_REVERSE\_PROXY\_AUTHENTICATION=false
```
\* or in the `app.ini` configuration file
```ini
[service]
...
ENABLE\_REVERSE\_PROXY\_AUTHENTICATION=false
...
```
For more information, see forgejo/forgejo!12782.

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=64 "0ko")](/0ko)

[0ko](/0ko)
added the [Forgejo](/forgejo/security-announcements/issues?labels=578248)  label [2026-07-15 11:04:17 +02:00](#issuecomment-19252472)

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=64 "0ko")](/0ko)

[0ko](/0ko)
locked and limited conversation to collaborators [2026-07-15 11:04:23 +02:00](#issuecomment-19252493)

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=128 "0ko")](/0ko)

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=64 "0ko")](/0ko)

[0ko](/0ko)
commented [[2026-07-15 20:35:40 +02:00](#issuecomment-19281668)](#issuecomment-19281668)

Author

Owner

Copy link

For people who were quick to see this in notifications or rely on email notifications: we have made a few corrections to the "You're affected if you're:" section:

* in bullet point 4, the wrong option was mentioned:

```
- [security]ENABLE_REVERSE_PROXY_AUTHENTICATION
+ [security]REVERSE_PROXY_TRUSTED_PROXIES
```

* added bullet point 5 - only affected deployments are the ones where Forgejo is directly accessible bypassing the reverse proxy. E.g. deployments with port-mapping like `127.0.0.1:3000:3000` or with firewall blocking all ports by default are not affected

For people who were quick to see this in notifications or rely on email notifications: we have made a few corrections to the "You're affected if you're:" section:
\* in bullet point 4, the wrong option was mentioned:
```diff
- [security]ENABLE\_REVERSE\_PROXY\_AUTHENTICATION
+ [security]REVERSE\_PROXY\_TRUSTED\_PROXIES
```
\* added bullet point 5 - only affected deployments are the ones where Forgejo is directly accessible bypassing the reverse proxy. E.g. deployments with port-mapping like `127.0.0.1:3000:3000` or with firewall blocking all ports by default are not affected

[![](/avatars/beef1e57d36304934b1fe40928510138?size=64 "SirHerpDerp")](/SirHerpDerp)

[SirHerpDerp](/SirHerpDerp)
referenced this issue from a commit [2026-07-15 23:59:53 +02:00](#issuecomment-19290695)

[chore: add information about CVE to [security].REVERSE\_PROXY\_TRUSTED\_PROXIES](/SirHerpDerp/docs/commit/c1c916934c9711ce7d3736489c92ffded57e56aa)

[![](/avatars/beef1e57d36304934b1fe40928510138?size=64 "SirHerpDerp")](/SirHerpDerp)

[SirHerpDerp](/SirHerpDerp)
[referenced this issue from forgejo/docs](/forgejo/docs/pulls/2062) [2026-07-16 00:04:52 +02:00](#issuecomment-19290893)

[**add information about CVE-2026-20896 to the cheat sheet** #2062](/forgejo/docs/pulls/2062)

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=64 "0ko")](/0ko)

[0ko](/0ko)
[referenced this issue from forgejo/forgejo](/forgejo/forgejo/pulls/13480) [2026-07-16 13:45:14 +02:00](#issuecomment-19319536)

[**[v15.0/forgejo]: feat(install): fix docker docs link to v15.0** #13480](/forgejo/forgejo/pulls/13480)

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=64 "0ko")](/0ko)

[0ko](/0ko)
[referenced this issue from forgejo/docs](/forgejo/docs/pulls/2063) [2026-07-16 14:13:11 +02:00](#issuecomment-19321270)

[**[v15.0] docs(admin): add security note for docker deployments** #2063](/forgejo/docs/pulls/2063)

[![](/avatars/44a59264e976fa585ed9f0a92abad9d7?size=64 "Gusted")](/Gusted)

[Gusted](/Gusted)
referenced this issue from a commit [2026-07-16 15:39:00 +02:00](#issuecomment-19336474)

[[v15.0/forgejo]: feat(install): fix docker docs link to v15.0 (#13480)](/forgejo/forgejo/commit/3531eb266c2fd359caefc8ffa62a655c7d9b20c5)

[![](/avatars/02cc343b8f0586b485a1fe7a0ca51958?size=64 "aaravrav")](/aaravrav)

[aaravrav](/aaravrav)
referenced this issue from a commit [2026-07-17 08:14:23 +02:00](#issuecomment-19393690)

[forgejo: 15.0.4 -> 15.0.5](/aaravrav/nixpkgs/commit/31833bb654f2778f8de6b78ebce5c25aed5e4c63)

[![](/avatars/44a59264e976fa585ed9f0a92abad9d7?size=64 "Gusted")](/Gusted)

[Gusted](/Gusted)
referenced this issue from a commit [2026-07-17 16:52:39 +02:00](#issuecomment-19474351)

[[v15.0] docs(admin): add security note for docker deployments (#2063)](/forgejo/docs/commit/fe2bc2a6d056af5b6070c309c801a67ded36b88d)

[![](/avatars/561ee781e72bbbfd2865db7b4ba4fbf50f64da3d3cb0f4e1897b6da25224a2a7?size=64 "Mathieu Fenniak")](/mfenniak)

[mfenniak](/mfenniak)
[referenced this issue from forgejo/forgejo](/forgejo/forgejo/issues/11070#issuecomment-19499095) [2026-07-18 02:57:42 +02:00](#issuecomment-19499098)

[**bug: Git operations fail due to missing urandom** #11070](/forgejo/forgejo/issues/11070)

[![](/avatars/4bc259616ea99a01dc0fedde7c7632d8?size=64 "update.freak")](/update.freak)

[update.freak](/update.freak)
[referenced this issue from forgejo/forgejo](/forgejo/forgejo/issues/11070#issuecomment-20086933) [2026-07-26 13:36:52 +02:00](#issuecomment-20086936)

[**bug: Git operations fail due to missing urandom** #11070](/forgejo/forgejo/issues/11070)

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=64 "0ko")](/0ko)

[0ko](/0ko)
closed this issue [2026-08-05 18:41:49 +02:00](#issuecomment-20583296)

[![](/avatars/620d4dd97d09d75b3103aa2ee879988d?size=64 "Jason Yundt")](/JasonYundt)

[JasonYundt](/JasonYundt)
referenced this issue from a commit [2026-08-08 14:29:35 +02:00](#issuecomment-20719655)

[forgejo: 15.0.4 -> 15.0.5](/JasonYundt/rust-sfml-missing-dependencies/commit/f1ba17f34db384f000d8f21ecf013748f246b184)

This discussion has been locked. Commenting is limited to contributors.

No Branch/Tag specified

Branches
Tags

No results found.

No results found.

**Labels**

Clear labels
Forgejo

Forgejo
Forgejo runnerUser research - Accessibility

Requires input about accessibility features, likely involves user testing.
User research - Blocked

Do not pick as-is! We are happy if you can help, but please coordinate with ongoing redesign in this area.
User research - Community

Community features, such as discovering other people's work or otherwise feeling welcome on a Forgejo instance.
User research - Config (instance)

Instance-wide configuration, authentication and other admin-only needs.
User research - Errors

How to deal with errors in the application and write helpful error messages.
User research - Filters

How filter and search is being worked with.
User research - Future backlog

The issue might be inspiring for future design work.
User research - Git workflow

AGit, fork-based and new Git workflow, PR creation etc
User research - Labels

Active research about Labels
User research - Moderation

Moderation Featuers for Admins are undergoing active User Research
User research - Needs input

Use this label to let the User Research team know their input is requested.
User research - Notifications/Dashboard

Research on how users should know what to do next.
User research - Rendering

Text rendering, markup languages etc
User research - Repo creation

Active research about the New Repo dialog.
User research - Repo units

The repo sections, disabling them and the "Add more" button.
User research - Security
User research - Settings (in-app)

How to structure in-app settings in the future?

No labels

[Forgejo](/forgejo/security-announcements/issues?labels=578248)
[Forgejo runner](/forgejo/security-announcements/issues?labels=578251)
[User research - Accessibility](/forgejo/security-announcements/issues?labels=223765)
[User research - Blocked](/forgejo/security-announcements/issues?labels=440466)
[User research - Community](/forgejo/security-announcements/issues?labels=440496)
[User research - Config (instance)](/forgejo/security-announcements/issues?labels=209569)
[User research - Errors](/forgejo/security-announcements/issues?labels=209666)
[User research - Filters](/forgejo/security-announcements/issues?labels=213431)
[User research - Future backlog](/forgejo/security-announcements/issues?labels=242877)
[User research - Git workflow](/forgejo/security-announcements/issues?labels=440463)
[User research - Labels](/forgejo/security-announcements/issues?labels=206178)
[User research - Moderation](/forgejo/security-announcements/issues?labels=208222)
[User research - Needs input](/forgejo/security-announcements/issues?labels=208223)
[User research - Notifications/Dashboard](/forgejo/security-announcements/issues?labels=208224)
[User research - Rendering](/forgejo/security-announcements/issues?labels=1054625)
[User research - Repo creation](/forgejo/security-announcements/issues?labels=211067)
[User research - Repo units](/forgejo/security-announcements/issues?labels=208298)
[User research - Security](/forgejo/security-announcements/issues?labels=158901)
[User research - Settings (in-app)](/forgejo/security-announcements/issues?labels=208225)

**Milestone**

Clear milestone

No items

No milestone

**Assignees**

Clear assignees

No assignees

**1 participant**

[![](/avatars/679e72b1ca263a192b488b84af24e10c4f32e2c3f46eb2baa7928c986ba460ef?size=64 "0ko")](/0ko)

**Notifications**

Subscribe

**Due date**

The due date is invalid or out of range. Please use the format "yyyy-mm-dd".

No due date set.

**Reference**

forgejo/security-announcements#56

Write
Preview

Loading…

Add table

|  |  |
| --- | --- |
| Rows |  |
| Columns |  |

Cancel
OK

Add a link

Url

Description

Hint: With a URL in your clipboard, you can paste directly into the editor to create a link.

Cancel
OK

Cancel
Save

Reference in a new issue

**Repository**

forgejo/security-announcements

**Title**

**Body**

Create issue

No description provided.

Delete branch "%!s()"

Deleting a branch is permanent. Although the deleted branch may continue to exist for a short time before it actually gets removed, it CANNOT be undone in most cases. Continue?

No
 Yes

![Logo](/assets/img/svg/cb-logo.svg)
![Logo](/assets/img/svg/cb-logo-mono.svg)

Powered by

[![Forgejo logo](/assets/img/svg/forgejo-wordmark.svg)
![Forgejo logo](/assets/img/svg/forgejo-wordmark-mono.svg)](https://forgejo.org)
with [modifications](/Codeberg-Infrastructure/forgejo)

**Codeberg**

* [Blog](https://blog.codeberg.org)
* [Documentation](https://docs.codeberg.org)
* [Community issues](/Codeberg/Community/issues)
* [Contributing](/Codeberg/Contributing)* [Report abuse](https://docs.codeberg.org/contact/#abuse)

**Association**

* [Who are we?](https://docs.codeberg.org/getting-started/what-is-codeberg/#what-is-codeberg-e.v.%3F)
* [Bylaws / Satzung](https://codeberg.org/codeberg/org/src/en/bylaws.md)
* [Donate](https://docs.codeberg.org/improving-codeberg/donate/)
* [Join / Support](https://join.codeberg.org)
* [Contact](https://docs.codeberg.org/contact/)

**Services**

* [Codeberg Pages](https://codeberg.page)
* [Codeberg Translate](https://translate.codeberg.org)
* [Woodpecker CI](https://docs.codeberg.org/ci/#using-codeberg's-instance-of-woodpecker-ci)
* [Forgejo API](/api/swagger)
* [Status page](https://status.codeberg.eu)

**Legal**

* [Imprint / Impressum](https://codeberg.org/codeberg/org/src/Imprint.md)
* [Privacy Policy](/codeberg/org/src/PrivacyPolicy.md)
* [Licenses](/assets/licenses.txt)
* [Terms of Use](/codeberg/org/src/TermsOfUse.md)

[Mastodon](https://social.anoxinon.de/%40Codeberg) |
Matrix Space
[(Web link)](https://matrix.to/#/#codeberg-space:matrix.org)

[Powered by Forgejo](https://forgejo.org)

English

Bahasa Indonesia
Dansk
Deutsch
English
Español
Esperanto
Filipino
Français
Italiano
Latviešu
Magyar nyelv
Nederlands
Plattdüütsch
Polski
Português de Portugal
Português do Brasil
Slovenščina
Suomi
Svenska
Türkçe
Čeština
Ελληνικά
Български
Русский
Українська
فارسی
日本語
简体中文
繁體中文（台灣）
繁體中文（香港）
한국어

Page: 112ms
Template: 41ms
