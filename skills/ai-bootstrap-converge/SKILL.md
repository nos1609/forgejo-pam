---
name: ai-bootstrap-converge
description: Use when installing, updating, auditing, planning, applying, or verifying the ai-code-assistant-bootstrap framework in a target repository. Enforces the mandatory assistant instruction scaffold from a template repo while preserving existing project-owned README content, local AI context, logs, overrides, and user instructions.
---

# AI Bootstrap Converge

This skill enforces the AI assistant bootstrap framework in a target repository.

Do not treat the framework as optional after this skill is invoked. The repository must converge to the required scaffold: root instructions, module files, scripts, bundled repo skills, instruction links, README marker, local exclude hygiene, and verification rules.

Your job is to converge the target repository to that required framework while preserving project-owned content. Never blindly copy a template tree over the target.

## Workflow

1. Identify the target repository.
2. Identify the template source repository or git URL. If none is explicit, prefer `AI_BOOTSTRAP_TEMPLATE`; otherwise ask for the template path/ref.
3. Read `references/file-policy.md` before deciding whether a file is managed, patch-only, ensure-if-missing, link-target, or local-only.
4. Use `scripts/converge.ps1` on Windows/PowerShell targets or `scripts/converge.sh` on POSIX targets, resolving `scripts/` from this skill directory.
   - `Audit`: inspect current state and report drift.
   - `Plan`: show convergence operations.
   - `Apply`: apply safe operations only.
   - `Verify`: fail if required invariants are still missing or drifting.
5. Report framework setup separately from preserved project-owned content and unresolved conflicts.

## Mandatory Posture

- Never ask whether the bootstrap framework should exist after this skill is invoked. It should.
- Ask only when convergence would overwrite or merge project-owned content.
- Preserve existing README content, `local/ai/chat_context.md`, `local/ai/project_addenda.md`, session history, logs, summaries, context packs, `.codex/**`, and `AGENTS.override.md`.
- Do not edit tracked `.gitignore` in target repositories for local runtime hygiene. Update `.git/info/exclude`.
- Do not overwrite existing protected files. Insert or update only the explicitly allowed snippet/lines.
- Replace drifting framework-owned files with the required version. Preserve project-owned instruction files and report link conflicts instead of overwriting them.

## Command Examples

```powershell
$skill = Join-Path (Get-Location) 'skills\ai-bootstrap-converge'
$target = 'C:\path\to\target-repo'
$template = 'C:\path\to\ai-code-assistant-bootstrap'
pwsh -NoProfile -File "$skill\scripts\converge.ps1" -Mode Audit  -Target $target -Template $template
pwsh -NoProfile -File "$skill\scripts\converge.ps1" -Mode Plan   -Target $target -Template $template
pwsh -NoProfile -File "$skill\scripts\converge.ps1" -Mode Apply  -Target $target -Template $template
pwsh -NoProfile -File "$skill\scripts\converge.ps1" -Mode Verify -Target $target -Template $template
```

```sh
skill="$(pwd)/skills/ai-bootstrap-converge"
sh "$skill/scripts/converge.sh" --mode audit --target /path/to/repo --template /path/to/ai-code-assistant-bootstrap
sh "$skill/scripts/converge.sh" --mode plan --target /path/to/repo --template /path/to/ai-code-assistant-bootstrap
sh "$skill/scripts/converge.sh" --mode apply --target /path/to/repo --template /path/to/ai-code-assistant-bootstrap
sh "$skill/scripts/converge.sh" --mode verify --target /path/to/repo --template /path/to/ai-code-assistant-bootstrap
```

For git sources:

```powershell
pwsh -NoProfile -File "$skill\scripts\converge.ps1" -Mode Plan -Target $target -Template https://example.invalid/ai-code-assistant-bootstrap.git -SourceRef main
```

## Operation Semantics

- `EnsureManagedFile`: create missing framework-owned files and replace drifting copies with the required version.
- `EnsureAgentsInstructions`: create missing `AGENTS.md`, or update/move its marked managed block to the top while preserving project-owned rules outside the block. Upgrade a recognized legacy unmarked block in place. Treat malformed or duplicate markers as a conflict. `-ForceManagedExact` is reserved for an explicitly approved complete `AGENTS.md` replacement.
- `EnsureIfMissing`: create placeholder/sample files only when absent.
- `EnsureSnippetPresent`: insert or move the exact `README_snippet.md` content to the top. Replace one recognized previous top protocol comment while preserving the README body; treat misplaced or duplicate protocol markers as conflicts.
- `EnsureExcludeLines`: when the target is the Git worktree root, remove only the exact obsolete scaffold-wide entries, add required runtime-only paths to the resolved common exclude, and preserve every unrelated line. Never modify parent Git metadata for a nested target.
- `EnsureInstructionLink`: create symlink/hardlink to `AGENTS.md`; report conflict when an existing instruction file contains different project-owned content.
- `EnsureSkillDiscoveryLink`: create `.agents/skills/ai-bootstrap-converge` and `.claude/skills/ai-bootstrap-converge` only as symlinks to `../../skills/ai-bootstrap-converge`; never duplicate files there.
- `ReportLocalOnlyTracked`: report every mutable runtime/local-only path tracked by Git, including readiness, context, addenda, history, logs, summaries, and context packs. Removing paths from the index requires explicit user approval.
- `ReportLegacyCredentialResidue`: report `tmp/ai/cli_tokens` when present without reading or removing it. Cleanup requires explicit user approval.

Read `references/workflow.md` for detailed review and reporting expectations.

## Validation

After editing this skill, run:

```powershell
Invoke-Pester skills\ai-bootstrap-converge\tests
shellcheck skills/ai-bootstrap-converge/scripts/converge.sh
uv run --with pyyaml python <path-to-skill-creator>\scripts\quick_validate.py skills\ai-bootstrap-converge
plugin-eval analyze skills\ai-bootstrap-converge --format markdown
```

Use OpenAI's Codex docs when changing behavior tied to AGENTS.md discovery, `.agents/skills`, or `.codex/config.toml`; current relevant references are `https://developers.openai.com/codex/skills`, `https://developers.openai.com/codex/guides/agents-md`, and `https://developers.openai.com/codex/config-reference#configtoml`.
