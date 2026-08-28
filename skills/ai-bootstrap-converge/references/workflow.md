# Workflow Details

## Audit

Audit is read-only. It must answer:

- Which required framework files are missing?
- Which managed files differ from the template?
- Which bundled repo skills are missing or drifting?
- Which agent-specific skill discovery links are missing, wrong, or blocked by platform permissions?
- Which protected files need allowed patch operations?
- Which instruction links are missing or wrong?
- Which local-only/runtime paths are tracked by git?
- Which required `.git/info/exclude` lines are missing?
- Does the deprecated `tmp/ai/cli_tokens` credential path still exist?

## Plan

Plan emits operations without writing. Group results by:

- Safe operations: can be applied without losing project-owned content.
- Conflicts: require explicit user decision.
- Informational drift: tracked local-only files, missing optional links, or environment-specific limits.

## Apply

Apply executes safe operations only:

- create missing managed files;
- replace drifting framework-owned files with the required version;
- insert, update, or move the marked `AGENTS.md` instruction block while preserving existing project rules;
- create ensure-if-missing files only when absent;
- insert, move, or update the recognized top README protocol snippet without changing the project body;
- remove exact obsolete scaffold-wide exclude lines and add missing runtime-only lines;
- create missing instruction links/hardlinks.

Apply must skip protected-file and ambiguous-marker conflicts. A complete `AGENTS.md` replacement requires an explicit user request and `-ForceManagedExact`.
Apply must block unknown hardlinks and must preserve declared instruction hardlinks when updating `AGENTS.md`.

## Verify

Verify fails when required invariants are still unmet:

- missing mandatory managed files;
- missing README snippet;
- missing exclude lines;
- missing or wrong instruction links;
- tracked local-only runtime files;
- deprecated `tmp/ai/cli_tokens` credential residue;
- framework-owned file drift.

Use `Verify` after `Apply`. Report the exact failing paths.
