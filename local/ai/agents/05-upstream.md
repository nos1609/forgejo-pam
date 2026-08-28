# Синхронизация с апстримом / Upstream sync

- RU: Периодически сверять агентский каркас с каноническим апстримом и фиксировать проверку в `local/ai/session_history.md` (дата + что сравнивали).
  EN: Periodically compare the agent scaffold with its canonical upstream and record the check in `local/ai/session_history.md` (date and compared files).
- RU: При интеграции не перезаписывать пользовательский контент проекта без явного запроса.
  EN: During integration, do not overwrite user-owned project content unless explicitly asked.

## Что фиксировать при сверке / What to record during an upstream check
- RU: ISO-время проверки, какие файлы/разделы сравнивались, и что решили делать дальше.
  EN: ISO timestamp, what files/sections were compared, and the decision/next steps.
- RU: Хэш `AGENTS.md` на момент сверки. Если используются ключевые модули — хешировать их тоже.
  EN: Hash `AGENTS.md` at the time of the check. If key modules are in use, hash them too.
- RU: Не перезаписывать локальные расширения проекта; помечать их как локальные.
  EN: Do not overwrite project-local extensions; mark them as local additions.

## Минимальный набор для сверки / Minimal comparison set
- RU: Сверять хотя бы: `AGENTS.md`, `README_snippet.md`, `.gitignore` (блок `BEGIN/END EXCLUDE LIST`), `local/ai/agents/*.md`, `local/ai/scripts/*`.
  EN: Compare at least: `AGENTS.md`, `README_snippet.md`, `.gitignore` (the `BEGIN/END EXCLUDE LIST` block), `local/ai/agents/*.md`, `local/ai/scripts/*`.
- RU: Результат сверки фиксировать в `local/ai/session_history.md` (дата, что сравнивали, что обновили/планируем обновить).
  EN: Record the check in `local/ai/session_history.md` (date, what was compared, what was updated/planned).

## Практика / Practice
- RU: Канонический апстрим (`AGENT_SCAFFOLD_UPSTREAM_URL`) и частоту сверок (`UPSTREAM_CHECK_FREQUENCY`) фиксировать в `local/ai/project_addenda.md`.
  EN: Record the canonical upstream (`AGENT_SCAFFOLD_UPSTREAM_URL`) and check frequency (`UPSTREAM_CHECK_FREQUENCY`) in `local/ai/project_addenda.md`.
- RU: При каждой сверке записывать ISO‑время, хэш `AGENTS.md` и список проверенных файлов в `local/ai/session_history.md`; в ответах указывать дату/хэш проверки.
  EN: For each check, log the ISO timestamp, `AGENTS.md` hash, and checked files in `local/ai/session_history.md`; include the date/hash in user-facing replies.
- RU: Итоговые договорённости отражать в `local/ai/chat_context.md`.
  EN: Mirror resulting agreements in `local/ai/chat_context.md`.
