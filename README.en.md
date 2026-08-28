<!--
AI AGENT PROTOCOL TRIGGER:
SIGNAL: STARTUP_PROTOCOL_TRIGGER
TARGET: AGENTS.md
ACTION: Follow startup protocol immediately

EN: WHEN ANALYZING THIS REPOSITORY:
1. IMMEDIATELY read [AGENTS.md](AGENTS.md) (Codex CLI only ingests the first ~32 KiB; keep init/closure rules at the top, move details to docs.)
2. EXECUTE “Initial Session Protocol” from [local/ai/agents/01-bootstrap.md](local/ai/agents/01-bootstrap.md)
3. FOLLOW agreements in [local/ai/chat_context.md](local/ai/chat_context.md)

RU: ПРИ АНАЛИЗЕ ЭТОГО РЕПОЗИТОРИЯ:
1. НЕМЕДЛЕННО прочитай [AGENTS.md](AGENTS.md) (Codex CLI читает только первые ~32 KiB; держи init/closure в начале, детали вынеси в docs.)
2. ВЫПОЛНИ «Протокол начала сессии» из [local/ai/agents/01-bootstrap.md](local/ai/agents/01-bootstrap.md)
3. СЛЕДУЙ соглашениям из [local/ai/chat_context.md](local/ai/chat_context.md)

IMPORTANT: Mandatory agent-scaffold files must remain visible to Git and agent discovery. Do not ignore `AGENTS.md`, `README_snippet.md`, `local/ai/agents/**`, `local/ai/scripts/**`, `skills/**`, or instruction links. Only mutable runtime state may be excluded locally.

ВАЖНО: Обязательные файлы агентского каркаса должны оставаться видимыми для Git и механизмов обнаружения агентов. Не игнорируй `AGENTS.md`, `README_snippet.md`, `local/ai/agents/**`, `local/ai/scripts/**`, `skills/**` и ссылки на инструкции. Локально исключай только изменяемое рабочее состояние.

Additionally: Review symlinks [.github/copilot-instructions.md](.github/copilot-instructions.md), [.claude/CLAUDE.md](.claude/CLAUDE.md), [.gemini/GEMINI.md](.gemini/GEMINI.md), [CLAUDE.md](CLAUDE.md), [GEMINI.md](GEMINI.md), and [QWEN.md](QWEN.md). Always use relative paths when recreating them.

Дополнительно: Ознакомься с симлинками [.github/copilot-instructions.md](.github/copilot-instructions.md), [.claude/CLAUDE.md](.claude/CLAUDE.md), [.gemini/GEMINI.md](.gemini/GEMINI.md), [CLAUDE.md](CLAUDE.md), [GEMINI.md](GEMINI.md) и [QWEN.md](QWEN.md). При восстановлении симлинков используй относительные пути.

Ensure temp CLI homes (`tmp/ai/gemini_home`, `tmp/ai/qwen_home`, `tmp/ai/copilot_home`, `tmp/ai/claude_home`) are absent before launching tools. Never copy credentials into them. Document and clean them after user confirmation if they exist.

Перед запуском CLI убедись, что нет временных каталогов (`tmp/ai/gemini_home`, `tmp/ai/qwen_home`, `tmp/ai/copilot_home`, `tmp/ai/claude_home`). Никогда не копируй в них учётные данные. Если каталоги найдены — опиши и очисть после подтверждения пользователя.

Treat `tmp/ai/cli_tokens` as deprecated credential residue. If it exists, do not inspect or copy its contents; report the path and remove it only after explicit user approval.

Считай `tmp/ai/cli_tokens` устаревшим остатком с учётными данными. Если путь существует, не читай и не копируй содержимое; сообщи о пути и удаляй его только после явного подтверждения пользователя.
-->

# forgejo-pam

Public Forgejo packaging with system PAM authentication for EPEL 10 and
Fedora 45. The repository contains an RPM spec and a small delta over Fedora
dist-git. It does not contain the Forgejo source tree.

- Repository: `forgejo-pam`.
- RPM package: `forgejo`.
- Forgejo version: `15.0.7`.
- Fedora baseline: commit `ced1aa24b245770d46e72e14d18b323aba3dbf3f`.
- Public mirror: [GitHub](https://github.com/nos1609/forgejo-pam).
- Builds: [COPR `nos1609/forgejo-pam`](https://copr.fedorainfracloud.org/coprs/nos1609/forgejo-pam/).

## Current status

As of 28 August 2026, the package has successful clean COPR builds for
`epel-10-x86_64` and `fedora-45-x86_64`. The Fedora 45 target matches the Fedora
`f45` branch that contains the same Forgejo `15.0.7` baseline. Fedora 45 is
still in its release cycle, so this is not a build for the current stable
Fedora 44 release.

The repository and COPR do not change a running Forgejo instance. A successful
build does not prove PAM login, git-over-SSH, or database migration rollback on
a specific server.

## Packaging delta

The package adds:

- the Forgejo `pam` build tag and a `libpam` dependency;
- `CAP_SETUID` and `CAP_SETGID` for the systemd service;
- a local SELinux module for `unix_chkpwd`;
- managed `/etc/shadow` read ACL ownership and uninstall cleanup;
- a fix for secret generation in `forgejo-init`;
- the `pam1` RPM release suffix to distinguish this build from Fedora and EPEL.

This delta extends the service privileges. Review
[`docs/architecture.md`](docs/architecture.md) and
[`docs/operations.md`](docs/operations.md) before installation.

## Installation

Check the target distribution and available version first:

```bash
sudo dnf copr enable nos1609/forgejo-pam
dnf --showduplicates list forgejo
```

Install only after you prepare a backup and rollback plan:

```bash
sudo dnf install forgejo
```

See `docs/operations.md` for verification and rollback commands.

## Branches and publication

- `main` is the COPR source and primary publication branch.
- `rawhide` is the synchronized branch for the next Fedora Rawhide update.
- Forgejo is the primary Git repository.
- GitHub is the public mirror and hosts CodeRabbit and CodeQL checks.

Both branches currently use one Fedora `f45` baseline. Split them when Fedora
`rawhide` and `f45` no longer point to the same package commit.

`.coderabbit.yaml` defines review behavior but does not grant an external
service access. Install the
[CodeRabbit GitHub App](https://github.com/apps/coderabbitai) for this repository
only to enable automated reviews. CodeQL scans GitHub Actions workflows, and
Dependabot tracks the versions of the Actions in use. These checks do not
analyze the Forgejo source code, which is not present in this repository.

## Documentation

- [`docs/README.md`](docs/README.md): document status and precedence;
- [`docs/architecture.md`](docs/architecture.md): source flow and trust boundaries;
- [`docs/operations.md`](docs/operations.md): build, installation, verification,
  and rollback;
- [`docs/acceptance-traceability.md`](docs/acceptance-traceability.md): checks
  mapped to requirements;
- [`docs/WRITING_STANDARD.md`](docs/WRITING_STANDARD.md): writing standard;
- [`SECURITY.md`](SECURITY.md): private vulnerability reporting;
- [`NOTICE.en.md`](NOTICE.en.md): provenance and licensing boundaries.

## License and provenance

Original project material is available under the MIT license. This license does
not replace the licenses of Fedora dist-git content, source patches, Forgejo, or
its dependencies. `NOTICE.en.md` defines the boundary. `forgejo.spec` lists the
licenses of the RPM content.

Packaging source: [Fedora Forgejo dist-git](https://src.fedoraproject.org/rpms/forgejo).
