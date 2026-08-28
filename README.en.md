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

