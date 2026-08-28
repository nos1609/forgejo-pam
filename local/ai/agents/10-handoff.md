# Взаимодействие ассистентов и handoff / Inter-assistant protocol & handoff
#
# RU: Что передавать между ассистентами и как делать handoff, чтобы не терять договорённости.
# EN: What to pass between assistants and how to hand off without losing agreements.

## Пакет контекста / Context package
- RU: Источник истины для передачи работы — актуальные `local/ai/chat_context.md`, `local/ai/session_history.md`, `local/ai/project_addenda.md` и последняя сводка сессии, а не память агента.
  EN: The handoff source of truth is the current `local/ai/chat_context.md`, `local/ai/session_history.md`, `local/ai/project_addenda.md`, and latest session summary, not agent memory.
- RU: Установленный и доверенный хук пакета контекста Codex автоматически сохраняет точные запросы пользователя и полные финальные ответы, исключая внутренние рассуждения, промежуточные сообщения и вывод инструментов; при сжатии выполняет `PreCompact -> PostCompact` и однократно вводит ограниченный пакет. Локальное обогащение из репозитория необязательно.
  EN: An installed and trusted Codex context-pack hook automatically records exact user requests and complete final answers while excluding reasoning, commentary, and tool output; on compaction it runs `PreCompact -> PostCompact` and injects a bounded pack once. Repo-local enrichment is optional.
- RU: Если хук или готовый пакет недоступен, передать перечисленные файлы-источники истины и сводку сессии. Не воссоздавать отсутствующие генераторы; неполный или устаревший контекст отметить явно.
  EN: If the hook or a ready pack is unavailable, pass the listed source-of-truth files and session summary. Do not recreate missing generators; state incomplete or stale context explicitly.
- RU: Перед подключением другого ассистента передать актуальные инструкции и рабочий контекст.
  EN: Before involving another assistant, share the active instructions and current working context.
- RU: Напомнить про `local/ai/<assistant>/{sessions.log,requests.log}` и проверить, что записи действительно создаются.
  EN: Remind about `local/ai/<assistant>/{sessions.log,requests.log}` and confirm entries are actually being written.
- RU: Если требуется несколько CLI/команд — согласовать одним запросом полный список команд (по строке) и обоснование (см. `local/ai/agents/03-sandbox.md`).
  EN: If multiple CLIs/commands are needed, align once on the full per-line command list and justification (see `local/ai/agents/03-sandbox.md`).
- RU: При распределении задач между ассистентами фиксировать роли и очередь (кто консультирует, кто проверяет), чтобы избегать конфликтов.
  EN: When splitting work across assistants, record roles and ordering (who consults, who reviews) to avoid conflicts.
- RU: По завершении консультации записать выводы в `local/ai/session_history.md`; при изменении договорённостей или ограничений обязательно обновить `local/ai/chat_context.md`.
  EN: After a consultation, record findings in `local/ai/session_history.md`; update `local/ai/chat_context.md` whenever agreements or constraints change.
- RU: Про лимит инструкций: помнить про ~32 KiB и держать P0 в корне (см. `local/ai/agents/00-codex-size.md`).
  EN: Size limit reminder: keep P0 in root and mind ~32 KiB limits (see `local/ai/agents/00-codex-size.md`).

## Handoff‑чеклист / Handoff checklist
- RU: Отмечать выполнение в `local/ai/session_history.md`.
  EN: Record completion in `local/ai/session_history.md`.

| Пункт / Item | RU | EN |
| --- | --- | --- |
| Контекст / Context | `AGENTS.md`, `local/ai/project_addenda.md`, `local/ai/chat_context.md`, релевантные фрагменты `local/ai/session_history.md`. | `AGENTS.md`, `local/ai/project_addenda.md`, `local/ai/chat_context.md`, and relevant `local/ai/session_history.md` entries. |
| Окружение / Environment | Текущие `sandbox_mode`, `network_access`, `approval_policy`. | Current `sandbox_mode`, `network_access`, `approval_policy`. |
| Эскалации / Escalations | Активные/ожидаемые согласования (что можно/нельзя делать сейчас). | Active/pending approvals (what is allowed now). |
| Последние шаги / Last steps | Что было сделано, что осталось, какие проверки ожидаются. | What was done, what remains, what checks are pending. |
| Логи / Logs | Подтвердить, что обновляется `local/ai/<assistant>/{sessions.log,requests.log}`. | Confirm `local/ai/<assistant>/{sessions.log,requests.log}` is updated. |
| Temp dirs / Temp dirs | Разрешено ли создавать tool temp dirs; кто чистит; где лежат (`tmp/ai/**`). | Whether tool temp dirs may be created; who cleans; where they live (`tmp/ai/**`). |

## Артефакты консультаций / Consultation artifacts
- RU: Сырые логи внешних инструментов складывать в `tmp/ai/consultation_runs/`, обработанные контексты/выжимки — в `tmp/ai/assistant_contexts/` (без секретов).
  EN: Store raw external-tool logs under `tmp/ai/consultation_runs/` and processed contexts/summaries under `tmp/ai/assistant_contexts/` (no secrets).
