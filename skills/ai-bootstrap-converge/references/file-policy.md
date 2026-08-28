# File Policy

Classify target repository files before changing them.

| Class | Paths | Convergence rule |
| --- | --- | --- |
| `patch-managed` | `AGENTS.md` | Required root instruction entrypoint. Create when missing. Update or move the single `AI AGENT INSTRUCTIONS` marked block to the top and preserve project rules outside it. Upgrade a recognized legacy unmarked block. Malformed or duplicate markers are a conflict. Complete replacement requires explicit force approval. |
| `managed-exact` | `README_snippet.md`, `local/ai/agents/**`, `local/ai/scripts/**`, `skills/ai-bootstrap-converge/**` | Required framework. Create when missing. Replace differing content automatically during Apply; these paths are authoritative. Do not delete unrelated extra files merely because they are absent from the source. |
| `discovery-link` | `.agents/skills/ai-bootstrap-converge`, `.claude/skills/ai-bootstrap-converge` | Agent-specific discovery paths. They must be symlinks to `../../skills/ai-bootstrap-converge` when present. Never duplicate skill files here. If symlink creation is unavailable, report it and keep the canonical `skills/**` package only. |
| `patch-only` | `README.md`, `README.en.md` | Project-owned. Insert or move the exact hidden snippet from `README_snippet.md` to the top. Replace one recognized previous top protocol comment while preserving the body. Misplaced or duplicate protocol markers are conflicts. Never rewrite the body. |
| `exclude-patch` | `.git/info/exclude` | Local Git hygiene. Modify it only when the target exactly matches `git rev-parse --show-toplevel`; never write parent Git metadata for a nested target. Remove only exact obsolete scaffold-wide entries, add the framework's required runtime-only lines, and preserve unrelated lines. Init/converge never modify the target `.gitignore`. |
| `link-target` | `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `.qwen/QWEN.md`, `GEMINI.md`, `QWEN.md`; Claude links only when present in the template or requested | Must point to `AGENTS.md` through symlink or hardlink. Existing different content is a conflict, not something to silently overwrite. |
| `ensure-if-missing` | `local/ai/bootstrap.ready`, `local/ai/chat_context.md`, `local/ai/project_addenda.md`, `local/ai/session_history.md`, `local/ai/<assistant>/README.md`, `local/ai/<assistant>/requests.log`, `local/ai/<assistant>/sessions.log` | Create from template only when absent. If present, preserve it. |
| `local-only` | `AGENTS.override.md`, `.codex/**`, `tmp/ai/**`, `local/ai/bootstrap.ready`, `local/ai/chat_context.md`, `local/ai/project_addenda.md`, `local/ai/session_history.md`, `local/ai/session_summaries/**`, `local/ai/context_packs/**`, `local/ai/ai-nest/**`, `local/ai/<assistant>/*.log`, `local/ai/<assistant>/*.session` | Must be ignored/local in target repositories. Create missing placeholders, preserve existing state, and report any tracked path. Never hide the mandatory scaffold. |
| `never` | secrets, tokens, tool homes, user IDE settings, unrelated project files | Never create, overwrite, or delete. |
| `legacy-residue` | `tmp/ai/cli_tokens` | Report existence without reading contents. Do not copy, overwrite, or remove it without explicit user approval. Verify remains incomplete while it exists. |

Keep project-specific instructions outside the marked managed block in `AGENTS.md`, or place them in `AGENTS.override.md`, `local/ai/project_addenda.md`, or the appropriate local context file. Preserve protected project content and report ambiguous marker damage as a conflict.

Reject unknown hardlinks before any read-modify-write operation. `AGENTS.md` may share an inode only with the declared instruction-link paths; preserve those known links when replacing its managed content.
