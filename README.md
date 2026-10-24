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

[![Статус сборки COPR](https://copr.fedorainfracloud.org/coprs/nos1609/forgejo-pam/package/forgejo/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/nos1609/forgejo-pam/)

Публичная упаковка Forgejo с системной PAM-аутентификацией для EPEL 10 и
Fedora 45. Репозиторий содержит RPM spec и небольшую дельту к Fedora dist-git,
но не содержит исходное дерево Forgejo.

- Репозиторий: `forgejo-pam`.
- RPM-пакет: `forgejo`.
- Версия Forgejo: `15.0.10`.
- Основа Fedora: commit `7e49254f963a7c488c654af213fee4e3e6b2c815`.
- Публичное зеркало: [GitHub](https://github.com/nos1609/forgejo-pam).
- Сборки: [COPR `nos1609/forgejo-pam`](https://copr.fedorainfracloud.org/coprs/nos1609/forgejo-pam/).

## Фактический статус

На 23 октября 2026 года пакет успешно собран в чистых COPR-контурах
`epel-10-x86_64` и `fedora-45-x86_64`, build `11196643`. Контур Fedora 45
соответствует ветке Fedora `f45`, где находится тот же Forgejo `15.0.10`.
Fedora 45 на эту дату ещё в цикле выпуска (в Bodhi — `frozen`), поэтому эту
сборку нельзя называть выпуском для текущей стабильной Fedora 44.

Репозиторий и COPR не изменяют работающий экземпляр Forgejo. Успешная сборка
также не доказывает PAM-вход, git-over-SSH и откат после миграции базы данных на
конкретном сервере.

## Дельта упаковки

Пакет добавляет:

- build tag Forgejo `pam` и зависимость от `libpam`;
- `CAP_SETUID` и `CAP_SETGID` для systemd-службы;
- локальный SELinux-модуль для `unix_chkpwd`;
- управляемый ACL чтения `/etc/shadow` с удалением только собственного ACL;
- исправление генерации секрета в `forgejo-init`;
- суффикс RPM release `pam1`, который отделяет сборку от Fedora и EPEL.

Эта дельта расширяет права службы. Перед установкой изучите
[`docs/architecture.md`](docs/architecture.md) и
[`docs/operations.md`](docs/operations.md).

## Установка

Сначала подключите репозиторий и найдите NVR с суффиксом `pam1` и dist tag
целевого дистрибутива:

```bash
sudo dnf copr enable nos1609/forgejo-pam
dnf --showduplicates list forgejo
```

Установите пакет только после подготовки резервной копии и плана отката.
Указывайте проверенный NVR, а не имя пакета: dnf выбирает наибольшую версию, и
сборка Fedora с более высоким release, например `15.0.10-2.fc45`, вытеснит
`15.0.10-1.pam1` без PAM-дельты.

```bash
sudo dnf install forgejo-<версия>-<release>.pam1.<dist>
rpm -q forgejo
dnf repoquery --installed --qf '%{from_repo}\n' forgejo
```

Ожидаются NVR с `pam1` и репозиторий
`copr:copr.fedorainfracloud.org:nos1609:forgejo-pam`. На 23 октября 2026 года
для EL10 это `forgejo-15.0.10-1.pam1.el10`. Проверка RPM до установки, проверки
после неё и откат приведены в `docs/operations.md`.

## Ветки и публикация

- `main` — источник COPR и основная ветка публикации;
- `rawhide` — синхронная ветка для следующего переноса на Fedora Rawhide;
- Forgejo — первичный Git-репозиторий;
- GitHub — публичное зеркало и контур CodeRabbit/CodeQL.

Обе ветки сейчас используют одну основу Fedora `f45`. Их нужно разделить, когда
Fedora `rawhide` и `f45` начнут содержать разные package commits.

`.coderabbit.yaml` задаёт правила рецензии, но сам по себе не выдаёт внешнему
сервису доступ. Для автоматической рецензии установите
[GitHub App CodeRabbit](https://github.com/apps/coderabbitai) только на этот
репозиторий. CodeQL проверяет GitHub Actions workflow; Dependabot отслеживает
версии используемых Actions. Эти проверки не анализируют исходный код Forgejo,
которого в этом репозитории нет.

## Документы

- [`docs/README.md`](docs/README.md) — статус и приоритет документов;
- [`docs/architecture.md`](docs/architecture.md) — путь исходников и границы
  доверия;
- [`docs/operations.md`](docs/operations.md) — сборка, установка, проверка и
  откат;
- [`docs/acceptance-traceability.md`](docs/acceptance-traceability.md) — связь
  требований с проверками;
- [`docs/WRITING_STANDARD.md`](docs/WRITING_STANDARD.md) — стандарт текста;
- [`SECURITY.md`](SECURITY.md) — порядок закрытого сообщения об уязвимости;
- [`NOTICE.md`](NOTICE.md) — происхождение и лицензионные границы.

## Лицензия и происхождение

Собственные материалы проекта доступны по лицензии MIT. Она не меняет лицензии
Fedora dist-git, патчей к исходному коду, Forgejo и его зависимостей. Полная
граница указана в `NOTICE.md`; лицензии собираемого RPM перечисляет
`forgejo.spec`.

Исходная упаковка: [Fedora Forgejo dist-git](https://src.fedoraproject.org/rpms/forgejo).
