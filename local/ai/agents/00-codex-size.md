# Codex size gate / 32 KiB limit

- RU: Codex CLI автоподключает AGENTS.md/AGENTS.override.md, но читает только первые ~32 KiB (project_doc_max_bytes по умолчанию).
- EN: Codex CLI auto-loads AGENTS.md/AGENTS.override.md, but only the first ~32 KiB are guaranteed (default project_doc_max_bytes).
- RU: Поэтому P0 правила держим в корневом AGENTS.md, а подробности — в local/ai/agents/*.md.
- EN: Keep P0 rules in root AGENTS.md; move details into local/ai/agents/*.md.

## Практика / Practice
- RU: Корневой `AGENTS.md` держать как “контракт сессии” (P0) + порядок чтения, без длинных таблиц/FAQ.
  EN: Keep root `AGENTS.md` as the session contract (P0) + reading order, without long tables/FAQ.
- RU: `AGENTS.override.md` тоже под тем же лимитом — держать коротким (дельты + ссылки).
  EN: `AGENTS.override.md` has the same limit — keep it short (deltas + links).
- RU: Для областей/подпапок использовать `subdir/AGENTS.md` для локальных правил.
  EN: For sub-areas, use `subdir/AGENTS.md` files for local rules.
- RU: При сжатии контекста установленный и доверенный хук Codex автоматически выполняет цикл `PreCompact -> PostCompact -> однократная инъекция`; журнал диалога и пакеты хранятся вне репозитория в `~/.codex/context_packs/`.
  EN: During compaction, an installed and trusted Codex context-pack hook automatically runs `PreCompact -> PostCompact -> one-shot injection`; its ledger and packs live outside the repository under `~/.codex/context_packs/`.
- RU: Не требуй локальный генератор пакета восстановления или пользовательский промпт сжатия. Используй такое расширение только при наличии реального файла и явной проектной инструкции.
  EN: Do not require a repo-local recovery-pack generator or custom compaction prompt. Use such an extension only when the file exists and project instructions explicitly enable it.

## Ссылки / Links
- Docs: https://developers.openai.com/codex/guides/agents-md
