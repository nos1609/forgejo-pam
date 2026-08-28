<!-- AI AGENT INSTRUCTIONS BEGIN -->
# Инструкции ассистентам / Local agent instructions

> Version: 2026-01-20
> RU: Этот файл намеренно короткий (P0). Детали — в `local/ai/agents/*.md`.
> EN: This file is intentionally short (P0). Details live under `local/ai/agents/*.md`.

## P0 rules / P0 правила
- RU: Сначала прочитай `local/ai/chat_context.md` — это источник истины по договорённостям сессии.
  EN: Read `local/ai/chat_context.md` first; it is the source of truth for session agreements.
- RU: **Hard-gate логирования:** перед КАЖДЫМ ответом отдельной командой создай запись в `local/ai/<assistant>/requests.log`.
  EN: **Logging hard gate:** before EVERY reply, use a separate command to append an entry to `local/ai/<assistant>/requests.log`.
- RU: Если основной журнал ещё не создан, небезопасен, отслеживается Git или недоступен для записи, обязательно используй `tmp/ai/<assistant>/requests.log` до исправления основного пути.
  EN: If the primary log is missing, unsafe, tracked by Git, or not writable, you MUST use `tmp/ai/<assistant>/requests.log` until the primary path is fixed.
- RU: Если более приоритетное правило запрещает оба пути, разрешено ровно одно минимальное техническое сообщение для запроса доступа. После восстановления доступа сначала залогируй это сообщение; содержательная работа без записи запрещена.
  EN: If a higher-priority rule blocks both paths, exactly one minimal technical message may request access. After access is restored, log that message first; substantive work without an entry remains forbidden.
- RU: Артефакты/эксперименты писать только в `tmp/ai/**` (и никуда больше) без явного запроса.
  EN: Write artifacts/experiments only under `tmp/ai/**` (and nowhere else) unless explicitly asked.
- RU: Интеграция агентского каркаса: запрещено изменять `README.md` / `README.en.md` любым образом, кроме добавления в самое начало точного скрытого сниппета из `README_snippet.md` (если политика разрешает). Любые другие изменения README запрещены, кроме явно запрошенных пользователем изменений README для нужд проекта.
  EN: Agent-scaffold integration: DO NOT modify `README.md` / `README.en.md` in any way except inserting the exact hidden snippet from `README_snippet.md` at the very top (if policy allows). All other README changes are FORBIDDEN unless the user explicitly requests README edits for the project.
- RU: Init/converge не изменяют проектный `.gitignore`; для локального состояния они используют `.git/info/exclude`. Меняй `.gitignore` только по явному запросу владельца репозитория.
  EN: Init/converge do not edit the project `.gitignore`; they use `.git/info/exclude` for local state. Edit `.gitignore` only when the repository owner explicitly requests it.
- RU: Windows: для симлинков требуется Admin/Developer Mode; если симлинки недоступны — используй hardlink (копии запрещены, чтобы не было дрейфа).
  EN: Windows: symlinks require Admin/Developer Mode; if symlinks are unavailable, use hardlinks (no copies to avoid drift).
- RU: Не создавать тестовые папки в корне репозитория; для проверок использовать `tmp/ai/**`.
  EN: Do not create test folders in the repo root; use `tmp/ai/**` for tests.

## Modules / Разделы
- local/ai/agents/00-codex-size.md — 32 KiB limit and strategy
- local/ai/agents/01-bootstrap.md — initial session protocol + mandatory bootstrap
- local/ai/agents/02-logging.md — JSONL logging policy
- local/ai/agents/03-sandbox.md — sandbox/network/approval rules
- local/ai/agents/04-formatting.md — response formatting + checks
- local/ai/agents/05-upstream.md — upstream sync
- local/ai/agents/06-instructions.md — assistant instruction files + symlinks
- local/ai/agents/07-profile.md — language/gender/profile agreements
- local/ai/agents/08-checks.md — tests/linters/verification
- local/ai/agents/09-closure.md — session closure protocol
- local/ai/agents/10-handoff.md — inter-assistant protocol + handoff checklist
- local/ai/agents/11-cli-bootstrap.md — CLI readiness + safe usage
- local/ai/agents/12-general.md — general requirements (P1+)

## Reading order / Порядок чтения
1) `local/ai/chat_context.md` (source of truth / источник истины)
2) `local/ai/agents/01-bootstrap.md` (initial session protocol)
3) `local/ai/agents/02-logging.md` + `local/ai/agents/07-profile.md`
4) Work: `local/ai/agents/12-general.md`, `local/ai/agents/03-sandbox.md`, `local/ai/agents/11-cli-bootstrap.md`, `local/ai/agents/08-checks.md`, `local/ai/agents/04-formatting.md`
5) Handoff/closure: `local/ai/agents/10-handoff.md`, `local/ai/agents/09-closure.md`
<!-- AI AGENT INSTRUCTIONS END -->
