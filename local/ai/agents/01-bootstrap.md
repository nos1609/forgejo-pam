# Протокол начала сессии и bootstrap / Initial Session Protocol and bootstrap
#
# RU: Обязательный протокол начала сессии и приведения агентского каркаса в
#     исправное состояние. Детали вынесены из `AGENTS.md` из-за лимита Codex.
# EN: Mandatory startup and agent-scaffold convergence protocol. Details were
#     moved out of `AGENTS.md` because of the Codex instruction-size limit.

## Сигнал и ускоренный старт / Trigger & accelerated start
- RU: Если есть `AGENTS.md` и `local/ai/chat_context.md` — выполнить порядок чтения из `AGENTS.md` (раздел “Reading order”).
  EN: If `AGENTS.md` and `local/ai/chat_context.md` exist, follow the reading order in `AGENTS.md` (“Reading order” section).
- RU: Если `local/ai/bootstrap.ready` начинается с `true` и в `local/ai/chat_context.md` статус `completed` — bootstrap не запускать повторно; коротко подтвердить пропуск.
  EN: If `local/ai/bootstrap.ready` starts with `true` and `local/ai/chat_context.md` says `completed`, do not re-run bootstrap; briefly confirm you are skipping it.
- RU: При пропуске bootstrap убедиться, что `last_verified_at` и `agents_md_hash` в chat context актуальны; иначе — перепроверить bootstrap.
  EN: When skipping bootstrap, ensure `last_verified_at` and `agents_md_hash` in chat context are up to date; otherwise re-run bootstrap checks.
- RU: Если readiness отсутствует, устарел или не подтверждён, выполнить все шаги bootstrap без обсуждения обязательности каркаса. Запрашивать решение только при риске перезаписать пользовательские инструкции.
  EN: If readiness is missing, stale, or unverified, execute every bootstrap step without debating whether the scaffold is required. Ask only before overwriting user-owned instructions.

## Предполетный чек-лист / Pre-flight checklist
- [ ] RU: Прочитать `local/ai/chat_context.md` (источник истины по договорённостям).
      EN: Read `local/ai/chat_context.md` (source of truth for agreements).
- [ ] RU: До любой команды определить `sandbox_mode`, `network_access`, `approval_policy` и разрешённые пути записи по `local/ai/agents/03-sandbox.md`. Если политика не разрешает запись, выполнить только чтение и запросить ровно необходимый доступ; обязательность каркаса не обсуждать.
      EN: Before any command, determine `sandbox_mode`, `network_access`, `approval_policy`, and allowed write paths from `local/ai/agents/03-sandbox.md`. If policy blocks writes, perform read-only checks and request only the required access; do not debate whether the scaffold is mandatory.
- [ ] RU: Подтвердить ключевые договорённости из `local/ai/chat_context.md`.
      EN: Acknowledge key agreements from `local/ai/chat_context.md`.
- [ ] RU: Прочитать `local/ai/project_addenda.md` (если есть) и учесть указания.
      EN: Read `local/ai/project_addenda.md` if present and follow guidance.
- [ ] RU: Если в репозитории уже есть дополнительные инструкции (например, `README.md`, `README.en.md`) — прочитать и учесть.
      EN: If the repo already has extra instructions (for example, `README.md`, `README.en.md`), read and follow them.
- [ ] RU: Проверить корень Git через `git rev-parse --show-toplevel`; не изменять Git metadata родительского репозитория для вложенного каталога.
      EN: Resolve the Git root with `git rev-parse --show-toplevel`; do not modify parent Git metadata for a nested directory.
- [ ] RU: Применить обязательный агентский каркас в разрешённых проектом путях. Посторонние артефакты и эксперименты писать только в `tmp/ai/**`.
      EN: Apply the mandatory agent scaffold in project-authorized paths. Write unrelated artifacts and experiments only under `tmp/ai/**`.
- [ ] RU: Проверить только наличие `tmp/ai/cli_tokens`. Если путь существует, не читать содержимое; сообщить об устаревшем остатке с учётными данными и удалять его только после явного подтверждения пользователя.
      EN: Check only whether `tmp/ai/cli_tokens` exists. If it does, do not read its contents; report deprecated credential residue and remove it only after explicit user approval.
- [ ] RU: Поприветствовать пользователя и уточнить задачу, не переспрашивая уже зафиксированное.
      EN: Greet the user and clarify the task without re-asking what is already fixed.

## Быстрый старт / Quick start steps
- RU: Выполнять обязательные пункты самостоятельно. Запрашивать решение только при конфликте с пользовательскими инструкциями или запрете более приоритетного правила.
  EN: Execute mandatory steps autonomously. Ask only for a user-instruction conflict or when a higher-priority rule blocks the action.

- [ ] Step 1:
  - RU: Перечитать `local/ai/chat_context.md`; проверить `status`, `last_verified_at`, `agents_md_hash`.
  - EN: Re-read `local/ai/chat_context.md`; verify `status`, `last_verified_at`, `agents_md_hash`.
  - RU: В ответе указать дату/время последнего чтения `local/ai/chat_context.md`.
    EN: In the reply, state when `local/ai/chat_context.md` was last reviewed.
  - RU: Проверить, что язык зафиксирован; после интеграции внутренние файлы вести только на выбранном пользователем языке (см. `local/ai/agents/12-general.md`).
  - EN: Confirm the language is set; after integration, write internal files only in the user-selected language (see `local/ai/agents/12-general.md`).
- [ ] Step 1a (mandatory apply):
  - RU: Если readiness не подтверждён, запустить `local/ai/scripts/init.ps1` в PowerShell или `local/ai/scripts/init.sh` в Bash. Не продолжать при конфликте пользовательских инструкций.
  - EN: If readiness is not verified, run `local/ai/scripts/init.ps1` in PowerShell or `local/ai/scripts/init.sh` in Bash. Stop on a user-instruction conflict.
- [ ] Step 1b (pre‑reply logging):
  - RU: Перед КАЖДЫМ ответом: сначала записать запрос в `local/ai/<assistant>/requests.log`, затем отвечать.
  - EN: Before EVERY reply: first log the request in `local/ai/<assistant>/requests.log`, then respond.
  - RU: Если основной журнал отсутствует, небезопасен, отслеживается Git или недоступен для записи, использовать `tmp/ai/<assistant>/requests.log`.
  - EN: If the primary log is missing, unsafe, tracked by Git, or not writable, use `tmp/ai/<assistant>/requests.log`.
  - RU: Если более приоритетное правило запрещает оба пути, отправить ровно одно минимальное техническое сообщение для запроса доступа. После восстановления доступа сначала записать его; содержательную работу без журнала не выполнять.
  - EN: If a higher-priority rule blocks both paths, send exactly one minimal technical message to request access. Once access is restored, log it first; do not perform substantive work without a log entry.
- [ ] Step 1c (mandatory verify):
  - RU: Запустить `local/ai/scripts/bootstrap_check.ps1` или `local/ai/scripts/bootstrap_check.sh`. После успеха обновить `status`, `last_verified_at` и `agents_md_hash`.
  - EN: Run `local/ai/scripts/bootstrap_check.ps1` or `local/ai/scripts/bootstrap_check.sh`. After success, update `status`, `last_verified_at`, and `agents_md_hash`.
- RU: Если bootstrap_check недоступен — перечислить ручные проверки: README сниппет, instruction files/symlinks, `.git/info/exclude`, логи.
  EN: If bootstrap_check is unavailable, list the equivalent manual checks: README snippet, instruction files/symlinks, `.git/info/exclude`, logs.
- RU: При интеграции или обновлении агентского каркаса проверить, что `.git/info/exclude` содержит канонический список изменяемого локального состояния из управляемых init/converge-скриптов.
  EN: When integrating or updating the agent scaffold, verify that `.git/info/exclude` contains the canonical mutable-local-state list from the managed init/converge scripts.
- [ ] Step 2 (README rule):
  - RU: Следовать P0 правилу из `AGENTS.md`: запрещено изменять `README.md` / `README.en.md` любым образом, кроме добавления точного скрытого сниппета из `README_snippet.md` в самое начало (если политика разрешает).
  - EN: Follow the P0 rule in `AGENTS.md`: DO NOT modify `README.md` / `README.en.md` in any way except inserting the exact hidden snippet from `README_snippet.md` at the very top (if policy allows).
  - RU: Если README нет — создать минимальный README и вставить сниппет; чужой текст не копировать.
  - EN: If no README exists, create a minimal README and insert the snippet; do not copy unrelated content.
- [ ] Step 3 (instruction links):
  - RU: Убедиться, что ссылки/файлы инструкций указывают на `AGENTS.md`.
  - EN: Ensure instruction links/files point to `AGENTS.md`.
  - `local/ai/agents/06-instructions.md` (список обязательных файлов).
  - RU: Windows: симлинки могут требовать Admin/Developer Mode; если симлинки недоступны — использовать hardlink (без копирования, чтобы не было дрейфа).
  - EN: Windows: symlinks require Admin/Developer Mode; if symlinks are unavailable, use hardlinks (no copies to avoid drift).
- [ ] Step 4 (exclude):
  - RU: Если текущий каталог является корнем Git, применить через init/converge канонические исключения для изменяемых локальных файлов к пути `git rev-parse --git-path info/exclude`.
  - EN: If the current directory is the Git root, apply canonical runtime exclusions through init/converge to the path from `git rev-parse --git-path info/exclude`.
- [ ] Step 5 (logs):
  - RU: Проверить `local/ai/<assistant>/{sessions.log,requests.log}` (JSONL, ISO8601Z).
  - EN: Verify `local/ai/<assistant>/{sessions.log,requests.log}` (JSONL, ISO8601Z).
  - RU: Для `gemini`, `qwen`, `codex`, `copilot`, `claude` создать отсутствующие каталоги и файлы до первой записи.
    EN: Create missing log directories and files for `gemini`, `qwen`, `codex`, `copilot`, and `claude` before the first write.
- [ ] Step 6 (record):
  - RU: Зафиксировать итоги в `local/ai/session_history.md`.
  - EN: Record key outcomes in `local/ai/session_history.md`.

- [ ] Step 7 (README check):
  - RU: Если есть `README.md` / `README.en.md` — прочитать их на предмет repo-specific ограничений/инструкций (это дополняет, но не переопределяет `local/ai/chat_context.md`).
  - EN: If `README.md` / `README.en.md` exist, read them for repo-specific constraints/instructions (this complements but does not override `local/ai/chat_context.md`).

- [ ] Step 8 (cleanup):
  - RU: Если создавались временные каталоги инструментов — удалить их (см. `local/ai/agents/03-sandbox.md`).
  - EN: If any tool temp dirs were created, remove them (see `local/ai/agents/03-sandbox.md`).

## Первичная настройка агентского каркаса / Agent scaffold bootstrap
- RU: Проверить правило README (см. Step 2 выше).
  EN: Confirm the README rule (see Step 2 above).
- RU: Создать/обновить файлы инструкций ассистентов так, чтобы они указывали на `AGENTS.md` (см. `local/ai/agents/06-instructions.md`).
  EN: Create/refresh assistant instruction files so they point to `AGENTS.md` (see `local/ai/agents/06-instructions.md`).
- RU: Убедиться, что `.git/info/exclude` скрывает только изменяемое локальное состояние и не скрывает инструкции, скрипты, skill или весь `.github/`.
  EN: Ensure `.git/info/exclude` hides mutable local state only and does not hide instructions, scripts, the skill, or the entire `.github/` directory.
  - RU: Причина: `.github/workflows/*` должны оставаться в репозитории, иначе GitHub Actions перестанут работать.
    EN: Reason: `.github/workflows/*` must remain tracked, otherwise GitHub Actions will stop working.
- RU: В корне Git применить канонический список изменяемого локального состояния через init/converge к пути `git rev-parse --git-path info/exclude`.
  EN: At the Git root, apply the canonical mutable-local-state list through init/converge to the path from `git rev-parse --git-path info/exclude`.
- RU: После завершения — обновить `local/ai/chat_context.md`, зафиксировав выполненные шаги.
  EN: After bootstrap, update `local/ai/chat_context.md` to document what was done.
