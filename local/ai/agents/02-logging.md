# Логирование / Logging

## Правила / Rules
- RU: **Hard-gate:** перед КАЖДЫМ ответом создай запись в `local/ai/<assistant>/requests.log` отдельной командой. Содержательный ответ запрещён, пока запись не создана.
  EN: **Hard gate:** before EVERY reply, create an entry in `local/ai/<assistant>/requests.log` via a separate command. Do not send a substantive reply until the entry exists.
- RU: Если основной журнал отсутствует, небезопасен, отслеживается Git или недоступен для записи, обязательно используй резервный журнал `tmp/ai/<assistant>/requests.log`.
  EN: If the primary log is missing, unsafe, tracked by Git, or not writable, you MUST use the `tmp/ai/<assistant>/requests.log` fallback.
- RU: Если более приоритетное правило запрещает оба пути, разрешено ровно одно минимальное техническое сообщение для запроса доступа. После восстановления доступа сначала запиши это сообщение, затем продолжай работу.
  EN: If a higher-priority rule blocks both paths, exactly one minimal technical message may request access. After access is restored, log that message first, then continue.
- RU: Формат JSONL (1 событие = 1 строка).
  EN: JSONL format (1 event = 1 line).
- RU: Таймстемпы: ISO 8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`).
  EN: Timestamps: ISO 8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`).
- RU: Назначение: audit + context replay. Секреты не логировать.
  EN: Purpose: audit + context replay. Do not log secrets.

## Пути / Paths
- `local/ai/<assistant>/sessions.log`
- `local/ai/<assistant>/requests.log`
- `tmp/ai/<assistant>/requests.log` — обязательный временный резервный журнал для недоступного или небезопасного основного журнала / mandatory temporary fallback for an unavailable or unsafe primary log

## Минимальные поля / Minimal fields
- `sessions.log`: `session_id`, `started_at`, `assistant`, `language`, `gender`, `logging_precision`
- `requests.log`: `timestamp`, `request_id`, `assistant`, `summary`, `tools`, `status`

## Примечания / Notes
- RU: Дополнительные поля допустимы, но обязательные имена не заменяй синонимами.
  EN: Additional fields are allowed, but do not replace required names with aliases.

## Логирование обращений / Logging Requests
- **RU:** Зафиксируй назначение журналов (аудит и восстановление контекста) в проектной документации.
  **EN:** Record the log purpose (audit and context replay) in project documentation.
- **RU:** Логирование обязательно. Отключить hard-gate может только более приоритетное указание; договорённости проекта его не отменяют.
  **EN:** Logging is mandatory. Only a higher-priority instruction can disable the hard gate; project agreements cannot waive it.
- **RU:** Структура JSONL: `sessions.log` — `session_id`, `started_at`, `assistant`, `language`, `gender`, `logging_precision`; `requests.log` — `timestamp`, `request_id`, `assistant`, `summary`, `tools`, `status`, опционально `error_details`.
  **EN:** JSONL fields: `sessions.log` — `session_id`, `started_at`, `assistant`, `language`, `gender`, `logging_precision`; `requests.log` — `timestamp`, `request_id`, `assistant`, `summary`, `tools`, `status`, with optional `error_details`.
- **RU:** Поле `started_at` содержит время начала сессии в ISO 8601 UTC; не переименовывай его в `timestamp`.
  **EN:** `started_at` contains the session start time in ISO 8601 UTC; do not rename the field to `timestamp`.
- **RU:** `local/ai/project_addenda.md` использовать как эталонную форму: матрица окружений (ОС/права/инструменты), разрешённые/запрещённые действия, детализация логов и политика аутентификации без секретов.
  **EN:** Use `local/ai/project_addenda.md` as the reference form for the environment matrix (OS/permissions/tools), allowed and disallowed actions, logging detail, and authentication policy without secrets.
- **RU:** После подтверждения рабочего языка и рода фиксируй старт сессии в `local/ai/<имя ассистента>/sessions.log`; при hand-off добавляй `handoff_from`/`handoff_to`.
  **EN:** After confirming language and grammatical gender, record the session start in `local/ai/<assistant-name>/sessions.log`; add `handoff_from`/`handoff_to` for a handoff.
- **RU:** Если каталог `local/ai/<имя ассистента>` или нужные файлы отсутствуют, создай их перед первой записью.
  **EN:** If `local/ai/<assistant-name>` or the required log files are missing, create them before the first entry.
- **RU:** Веди оба журнала как JSONL. Для времени используй ISO 8601 UTC: `started_at` в `sessions.log`, `timestamp` в `requests.log`.
  **EN:** Keep both logs as JSONL. Use ISO 8601 UTC for `started_at` in `sessions.log` and `timestamp` in `requests.log`.
- **RU:** Фиксируй КАЖДОЕ обращение в `local/ai/<имя ассистента>/requests.log`: краткое `summary`, использованные инструменты и текущий статус. Не записывай чувствительные данные.
  **EN:** Record EVERY interaction in `local/ai/<assistant-name>/requests.log`: include a short `summary`, tools used, and current status. Omit sensitive data.
- **RU:** Используй таблицу ниже как шпаргалку по файлам и полям. Если проект требует дополнительных полей (`duration_ms`, `error_details_redacted` и т.п.) — добавь их и зафиксируй изменения в `local/ai/chat_context.md`.
  **EN:** Use the table below as a cheat sheet for files and fields; extend it with project-specific columns (`duration_ms`, `error_details_redacted`, etc.) and record changes in `local/ai/chat_context.md`.

| Событие / Event | Файл / File | Обязательные поля / Required fields |
| --- | --- | --- |
| Старт сессии / Session start | `local/ai/<assistant>/sessions.log` | `session_id`, `started_at`, `assistant`, `language`, `gender`, `logging_precision` |
| Индивидуальный запрос / Individual request | `local/ai/<assistant>/requests.log` | `timestamp`, `request_id`, `assistant`, `summary`, `tools`, `status` |
| Ошибка / Error entry | `local/ai/<assistant>/requests.log` | обязательные поля запроса, `status=error`, `error_details` без чувствительных данных |

- **RU:** Логируй только необходимые поля: идентификатор запроса, тип ассистента, отметку времени и минимальный контекст; пользовательский ввод и ответы маскируй/анонимизируй, удаляя PII и секреты.
  **EN:** Capture only the required fields: request ID, assistant type, timestamp, and minimal context; mask or anonymize user inputs and responses, stripping PII and secrets.
- **RU:** Если CLI не может безопасно писать в `local/ai`, используй резервный журнал в `tmp/ai`. Запрос доступа без предварительной записи допустим только по узкому исключению hard-gate выше.
  **EN:** If the CLI cannot write safely under `local/ai`, use the `tmp/ai` fallback. An unlogged access request is allowed only by the narrow hard-gate exception above.
- **RU:** После восстановления основного пути перенеси только минимальные поля пропущенных технических событий. Не копируй секреты или полный пользовательский ввод.
  **EN:** After the primary path is restored, reconcile only the minimal fields for missed technical events. Do not copy secrets or full user input.
- **RU:** Устанавливай сроки хранения и процессы ротации, обеспечивай возможность удаления записей по запросу пользователя.
  **EN:** Define retention periods and rotation processes, and keep a path to delete entries on user request.
- **RU:** Перед анализом логов убеждайся, что обработка чувствительных данных соответствует политике безопасности и действующим законам.
  **EN:** Before analyzing logs, ensure handling of sensitive data complies with the security policy and applicable regulations.
- **RU:** Если обращаешься к другому ассистенту, требуй вести `local/ai/<имя>/{requests.log,sessions.log}` по тем же правилам и подтверждай создание записей.
  **EN:** When you call another assistant, require the same logging under `local/ai/<name>/{requests.log,sessions.log}` and confirm that entries exist.
- **RU:** Перед отправкой ответа убедись, что текущий запрос уже записан в основной или резервный журнал; если записи нет, добавь её отдельной командой немедленно.
  **EN:** Before sending a reply, ensure the current interaction is in the primary log or mandatory fallback; if missing, append it immediately with a dedicated command.
- **RU:** **ВАЖНО:** Выполняй команду журналирования отдельным вызовом доступного shell-инструмента. Другие команды запускай по действующим правилам разрешений.
  **EN:** **IMPORTANT:** Execute the logging command as a separate call through the available shell tool. Run other commands under the active approval rules.
