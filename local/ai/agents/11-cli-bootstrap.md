# Подготовка CLI / CLI bootstrap
#
# RU: Минимальные правила безопасного запуска внешних CLI.
# EN: Minimal rules for safely running external CLIs.

## Перед первым использованием / Before first use
- RU: Всегда сначала выполнить `<tool> --help` и зафиксировать ключевые флаги и режимы в `local/ai/session_history.md`.
  EN: Always run `<tool> --help` first and record key flags and modes in `local/ai/session_history.md`.
- RU: Для сжатия контекста Codex используй установленный и доверенный хук пакета контекста; он сам обслуживает жизненный цикл, а локальные скрипты репозитория необязательны.
  EN: For Codex compaction, use the installed and trusted context-pack hook; it owns the lifecycle and does not require repo-local scripts.
- RU: Запросы CLI передавать одной строкой (как один аргумент) на языке пользователя; дополнительные параметры добавлять только после сверки со справкой и согласования с пользователем.
  EN: Pass CLI prompts as a single-line argument in the user’s language; add extra parameters only after checking `--help` and aligning with the user.
- RU: Если CLI завершился с ошибкой, сохранить вывод и шаги восстановления в `local/ai/session_history.md`, чтобы не повторять проблему.
  EN: If a CLI crashed, capture output and recovery steps in `local/ai/session_history.md` so others do not repeat it.
  - RU: Таймаут ожидания ответа CLI: до ~60 секунд; если `429`/rate limit — повторять только после таймаута или по явному согласию.
    EN: CLI wait timeout: up to ~60 seconds; if you hit `429`/rate limits, retry only after timeout or with explicit consent.

## Восстановление контекста / Context recovery
- RU: Сам хук запускается через `python3` в Linux/macOS или `py -3` в Windows. Это зависимость установленной среды выполнения плагина, а не требование иметь генератор в каждом репозитории.
  EN: The hook itself runs through `python3` on Linux/macOS or `py -3` in Windows. This is an installed plugin runtime dependency, not a requirement for every repository to carry a generator.
- RU: Если хук недоступен или пропускает ошибку, используй `local/ai/chat_context.md` и последнюю сводку сессии, явно укажи пробелы. Не блокируй обычную работу только из-за отсутствия локального генератора.
  EN: If the hook is unavailable or fails open, use `local/ai/chat_context.md` and the latest session summary, stating any gaps explicitly. Do not block normal work solely because a repo-local generator is absent.

## Ключи/токены / Keys & tokens
- RU: Не угадывать переменные окружения/пути к токенам; спросить пользователя и следовать `local/ai/project_addenda.md` (если есть).
  EN: Do not guess env vars/paths for tokens; ask the user and follow `local/ai/project_addenda.md` if present.
- RU: Сначала используйте штатную аутентификацию подписки или интерактивной сессии, если инструмент её поддерживает. Запрашивайте API-ключ только когда выбранная команда или API действительно его требует и пользователь одобрил этот способ.
  EN: Prefer supported subscription or interactive-session authentication. Request an API key only when the selected command or API requires it and the user approved that method.
- RU: Никогда не записывайте значение ключа в репозиторий, команду, журнал, отчёт или историю сессии.
  EN: Never place a key value in the repository, command line, log, report, or session history.
- RU: Если инструмент хранит токены или конфигурацию вне репозитория, согласуйте способ аутентификации и зафиксируйте его без путей и значений секретов в `local/ai/chat_context.md`.
  EN: If a tool stores tokens or configuration outside the repo, align on the authentication method and record it in `local/ai/chat_context.md` without secret paths or values.

## Временные каталоги / Temp directories
- RU: В `tmp/ai/**` направлять только несекретные кэши и временные данные CLI, затем очищать их (см. `local/ai/agents/03-sandbox.md`). Не перенаправлять туда аутентифицированный профиль или хранилище токенов.
  EN: Route only non-secret CLI caches and temporary data under `tmp/ai/**`, then clean them up (see `local/ai/agents/03-sandbox.md`). Do not redirect an authenticated profile or token store there.

## Ограничения окружения / Environment constraints
- RU: При ограничениях изолированной среды или сети явно попросить пользователя выполнить команду локально и зафиксировать это в `local/ai/chat_context.md`.
  EN: If sandbox or network constraints block execution, ask the user to run the command locally and record it in `local/ai/chat_context.md`.
- RU: Не добавлять ссылки на отсутствующие файлы промпта сжатия. Пользовательский промпт допустим только при наличии реального файла.
  EN: Do not reference missing compaction-prompt files. A custom prompt is valid only when the referenced file exists.
