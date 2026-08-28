# Завершение сессии / Session closure
#
# RU: Протокол закрытия сессии. Использовать сразу, как только пользователь просит завершить.
# EN: Session close protocol. Use immediately when the user asks to end the session.

## Протокол / Protocol
0) RU: Если пользователь просит завершить сессию — не отвечать “ок/принято” отдельно; сразу выполнить шаги 1–7.
   EN: If the user asks to end the session, do not reply with a standalone “okay”; immediately proceed with steps 1–7.

1) RU: Получить явное подтверждение (“заверши сессию”) и без дополнительных уточнений перейти к шагу 2.
   EN: Get explicit confirmation (“finish the session”), then move to step 2 without extra questions.

2) RU: Перепроверить `local/ai/chat_context.md` и свежие записи в `local/ai/session_history.md`, чтобы договорённости не потерялись.
   EN: Re-check `local/ai/chat_context.md` and recent entries in `local/ai/session_history.md` to ensure agreements are captured.

2a) RU: Если в Codex установлен и доверен хук пакета контекста, не запускайте локальные генераторы репозитория вручную: при фактическом сжатии хук сам выполняет `PreCompact` и `PostCompact`. Отсутствие необязательного локального расширения не блокирует закрытие.
    EN: If the Codex context-pack hook is installed and trusted, do not invoke repo-local generators manually: on an actual compaction the hook runs `PreCompact` and `PostCompact` itself. Missing optional repo-local enrichment does not block closure.
2b) RU: Независимо от наличия хука переносимыми артефактами закрытия остаются сводка из шага 4 и запись в `local/ai/session_history.md`. Если хук недоступен, завершить эти шаги, явно отметить пробелы контекста и не создавать фиктивный пакет.
    EN: Regardless of hook availability, the portable closure artifact is the step 4 summary plus its `local/ai/session_history.md` entry. If the hook is unavailable, complete those steps, state any context gaps explicitly, and do not create a placeholder pack.

3) RU: Убедиться, что каталог `local/ai/session_summaries/` существует и не отслеживается Git.
   EN: Ensure `local/ai/session_summaries/` exists and is not tracked by Git.

4) RU: Сформировать `local/ai/session_summaries/<YYYYMMDDTHHMMSSZ>.md` со структурой:
   EN: Create `local/ai/session_summaries/<YYYYMMDDTHHMMSSZ>.md` with this layout:
   - RU: Контекст
     EN: Context
   - RU: Системные указания
     EN: System directives
   - RU: Ключевые файлы (`path:line` + комментарий)
     EN: Key files (`path:line` + note)
   - RU: Последние события
     EN: Recent events
   - RU: Проблемы и решения
     EN: Issues & fixes
   - RU: Рекомендации / Следующие шаги (чек‑лист)
     EN: Recommendations / Next steps (must be a checklist; no prose)
   - RU: Дополнительные материалы (выводы CLI/логи, например `tmp/ai/<tool>_*.txt`)
     EN: Additional materials (CLI outputs/logs, e.g. `tmp/ai/<tool>_*.txt`)
   - RU: Открытые вопросы
     EN: Open items

5) RU: Добавить запись в `local/ai/session_history.md` со ссылкой на сводку.
   EN: Append an entry to `local/ai/session_history.md` linking to the summary.

6) RU: В ответе пользователю указать путь к сводке и напомнить обновить контекст перед новой сессией (ничего не чистить автоматически).
   EN: In the reply, include the summary path and remind to refresh context before the next session (do not delete files automatically).

7) RU: Если диалог близок к лимиту контекста (примерно 75% окна), предупредить и предложить завершить сессию со сводкой.
   EN: If the conversation is approaching the context limit (around 75% of the window), warn the user and suggest closing with a summary.

8) RU: Нарушение шагов 0–7 считается невыполнением протокола; пользователь может потребовать повторного прохождения.
   EN: Missing any of steps 0–7 counts as a protocol breach; the user may request the protocol be rerun.
