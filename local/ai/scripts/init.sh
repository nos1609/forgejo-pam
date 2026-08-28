#!/usr/bin/env bash
set -euo pipefail

# Скрипт применяет обязательные ссылки и локальные Git-исключения агентского каркаса.
# Applies mandatory agent-scaffold links and local Git exclusions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"

cd "${REPO_ROOT}"

path_present() {
  [[ -e "$1" || -L "$1" ]]
}

path_tree_is_safe_under() {
  local root=$1
  local path=$2
  local allow_leaf_link=${3:-0}
  [[ "$path" == "$root"/* ]] || return 1
  local relative=${path#"$root"/}
  local current=$root
  local component next
  local old_ifs=$IFS
  IFS=/
  for component in $relative; do
    [[ -z "$component" || "$component" == "." ]] && continue
    [[ "$component" != ".." ]] || { IFS=$old_ifs; return 1; }
    next=$current/$component
    if [[ -L "$next" && ! ( "$allow_leaf_link" -eq 1 && "$next" == "$path" ) ]]; then
      IFS=$old_ifs
      return 1
    fi
    if [[ -e "$next" && "$next" != "$path" && ! -d "$next" ]]; then
      IFS=$old_ifs
      return 1
    fi
    current=$next
  done
  IFS=$old_ifs
  return 0
}

path_tree_is_safe() {
  path_tree_is_safe_under "$REPO_ROOT" "$1" "${2:-0}"
}

required_runtime_exclude_entries() {
  printf '%s\n' \
    '.codex/' \
    'AGENTS.override.md' \
    'local/ai/bootstrap.ready' \
    'local/ai/chat_context.md' \
    'local/ai/project_addenda.md' \
    'local/ai/session_history.md' \
    'local/ai/context_packs/' \
    'local/ai/session_summaries/*' \
    '!local/ai/session_summaries/README.md' \
    'local/ai/*/requests.log' \
    'local/ai/*/sessions.log' \
    'local/ai/*/*.session' \
    'local/ai/ai-nest/' \
    'tmp/ai/'
}

file_link_count() {
  local path=$1
  local count
  if count=$(stat -Lc '%h' -- "$path" 2>/dev/null); then
    printf '%s\n' "$count"
    return 0
  fi
  stat -f '%l' "$path" 2>/dev/null
}

file_has_single_link() {
  local count
  count=$(file_link_count "$1") || return 1
  [[ "$count" -eq 1 ]]
}

instruction_link_paths() {
  printf '%s\n' \
    '.github/copilot-instructions.md' \
    '.claude/CLAUDE.md' \
    'CLAUDE.md' \
    '.gemini/GEMINI.md' \
    'GEMINI.md' \
    '.qwen/QWEN.md' \
    'QWEN.md'
}

agents_hardlinks_are_known() {
  local count known relative path
  count=$(file_link_count "$REPO_ROOT/AGENTS.md") || return 1
  known=0
  while IFS= read -r relative; do
    path=$REPO_ROOT/$relative
    if path_tree_is_safe "$path" 1 && [[ -f "$path" && ! -L "$path" && "$path" -ef "$REPO_ROOT/AGENTS.md" ]]; then
      known=$((known + 1))
    fi
  done < <(instruction_link_paths)
  [[ "$count" -eq $((known + 1)) ]]
}

link_failures=0
created_links=()

ensure_instruction_link() {
  local relative=$1
  local expected=$2
  local apply=${3:-0}
  local path=$REPO_ROOT/$relative
  if ! path_tree_is_safe "$path" 1; then
    echo "ERROR: $relative: destination or ancestor escapes the repository or is a link." >&2
    link_failures=$((link_failures + 1))
    return
  fi
  if [[ -L "$path" && "$(readlink "$path")" == "$expected" ]]; then
    return
  fi
  if [[ -f "$path" && "$path" -ef "$REPO_ROOT/AGENTS.md" ]]; then
    return
  fi
  if path_present "$path"; then
    echo "ERROR: $relative contains project-owned instructions; preserve and merge them before replacing the path." >&2
    link_failures=$((link_failures + 1))
    return
  fi
  if [[ "$apply" -ne 1 ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  if ln -s "$expected" "$path" 2>/dev/null || ln "$REPO_ROOT/AGENTS.md" "$path" 2>/dev/null; then
    created_links+=("$path")
  else
    echo "ERROR: could not create a symlink or hardlink for $relative." >&2
    link_failures=$((link_failures + 1))
  fi
}

ensure_skill_link() {
  local relative=$1
  local apply=${2:-0}
  local expected=../../skills/ai-bootstrap-converge
  local path=$REPO_ROOT/$relative
  if ! path_tree_is_safe "$path" 1; then
    echo "ERROR: $relative: destination or ancestor escapes the repository or is a link." >&2
    link_failures=$((link_failures + 1))
    return
  fi
  if [[ -L "$path" && "$(readlink "$path")" == "$expected" ]]; then
    return
  fi
  if path_present "$path"; then
    echo "ERROR: $relative exists but is not the required canonical skill symlink." >&2
    link_failures=$((link_failures + 1))
    return
  fi
  if [[ "$apply" -ne 1 ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  if ln -s "$expected" "$path" 2>/dev/null; then
    created_links+=("$path")
  else
    echo "ERROR: could not create the canonical skill symlink at $relative." >&2
    link_failures=$((link_failures + 1))
  fi
}

# Resolve all prerequisites before creating any link.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: Git worktree is required before bootstrap can set local exclusions." >&2
  exit 1
fi
GIT_TOP_LEVEL=$(git rev-parse --show-toplevel)
GIT_TOP_LEVEL=$(cd "$GIT_TOP_LEVEL" && pwd -P)
if [[ "$GIT_TOP_LEVEL" != "$REPO_ROOT" ]]; then
  echo "ERROR: Bootstrap root must be the Git worktree root; parent Git metadata was not modified." >&2
  exit 1
fi
if path_present "$REPO_ROOT/tmp/ai/cli_tokens"; then
  echo "ERROR: Deprecated credential residue exists at tmp/ai/cli_tokens. Do not inspect or remove it without explicit user approval." >&2
  exit 1
fi
EXCLUDE_FILE=$(git rev-parse --path-format=absolute --git-path info/exclude)
GIT_COMMON=$(git rev-parse --path-format=absolute --git-common-dir)
GIT_COMMON=$(cd "$GIT_COMMON" && pwd -P)
if ! path_tree_is_safe_under "$GIT_COMMON" "$EXCLUDE_FILE"; then
  echo "ERROR: Git exclude path or ancestor is a link or escapes the common Git directory." >&2
  exit 1
fi

tracked_runtime=$(git ls-files -- \
  AGENTS.override.md \
  .codex/ \
  tmp/ai/ \
  local/ai/bootstrap.ready \
  local/ai/chat_context.md \
  local/ai/project_addenda.md \
  local/ai/session_history.md \
  local/ai/context_packs/ \
  local/ai/session_summaries/ \
  ':!local/ai/session_summaries/README.md' \
  local/ai/ai-nest/ \
  'local/ai/*/requests.log' \
  'local/ai/*/sessions.log' \
  'local/ai/*/*.session' 2>/dev/null || true)
if [[ -n "$tracked_runtime" ]]; then
  echo "ERROR: mutable runtime paths are tracked by Git; converge them out of the index before init:" >&2
  printf '%s\n' "$tracked_runtime" >&2
  exit 1
fi

for source_path in AGENTS.md README_snippet.md; do
  if [[ ! -f "$source_path" || -L "$source_path" ]] || ! path_tree_is_safe "$REPO_ROOT/$source_path"; then
    echo "ERROR: $source_path must be a regular non-symlink file inside the repository." >&2
    exit 1
  fi
done
if ! agents_hardlinks_are_known; then
  echo "ERROR: AGENTS.md has a hardlink outside the known instruction-link set." >&2
  exit 1
fi
if ! awk '
  {
    line=$0
    sub(/\r$/, "", line)
    if (line == "<!-- AI AGENT INSTRUCTIONS BEGIN -->") { begin_count++; begin_line=NR }
    if (line == "<!-- AI AGENT INSTRUCTIONS END -->") { end_count++; end_line=NR }
  }
  END { exit(begin_count == 1 && end_count == 1 && begin_line == 1 && end_line > begin_line ? 0 : 1) }
' AGENTS.md; then
  echo "ERROR: AGENTS.md must contain one complete managed instruction block at the top." >&2
  exit 1
fi
if [[ ! -d skills/ai-bootstrap-converge || -L skills/ai-bootstrap-converge ]] || ! path_tree_is_safe "$REPO_ROOT/skills/ai-bootstrap-converge"; then
  echo "ERROR: skills/ai-bootstrap-converge must be a non-symlink directory inside the repository." >&2
  exit 1
fi
if [[ -n "$(find skills/ai-bootstrap-converge -type l -print -quit)" ]]; then
  echo "ERROR: skills/ai-bootstrap-converge must not contain symlinked children." >&2
  exit 1
fi
for readme in README.md README.en.md; do
  if path_present "$REPO_ROOT/$readme" && { [[ ! -f "$REPO_ROOT/$readme" ]] || [[ -L "$REPO_ROOT/$readme" ]]; }; then
    echo "ERROR: $readme must be a regular non-symlink file when present." >&2
    exit 1
  fi
done
snippet_size=$(wc -c < README_snippet.md)

readme_protocol_marker_is_safe() {
  local readme=$1
  local trigger_count
  trigger_count=$(awk -v trigger='AI AGENT PROTOCOL TRIGGER' '
    {
      rest=$0
      while ((position=index(rest, trigger)) > 0) {
        count++
        rest=substr(rest, position + length(trigger))
      }
    }
    END { print count + 0 }
  ' "$readme")
  [[ "$trigger_count" -eq 1 ]] || return 1
  protocol_comment_has_signature README_snippet.md || return 1
  protocol_comment_has_signature "$readme"
}

protocol_comment_has_signature() {
  awk '
    {
      line=$0
      sub(/\r$/, "", line)
      if (NR == 1 && line != "<!--") invalid=1
      if (!closed) {
        if (line == "AI AGENT PROTOCOL TRIGGER:") trigger_count++
        if (line == "SIGNAL: STARTUP_PROTOCOL_TRIGGER") signal_count++
        if (line == "TARGET: AGENTS.md") target_count++
        if (line == "ACTION: Follow startup protocol immediately") action_count++
        if (line == "-->") closed=1
      }
    }
    END {
      valid=!invalid && closed && trigger_count == 1 && signal_count == 1 && target_count == 1 && action_count == 1
      exit(valid ? 0 : 1)
    }
  ' "$1"
}

for readme in README.md README.en.md; do
  [[ -f "$readme" ]] || continue
  if head -c "$snippet_size" "$readme" | cmp -s README_snippet.md -; then
    continue
  fi
  if grep -F "AI AGENT PROTOCOL TRIGGER" "$readme" >/dev/null 2>&1 && ! readme_protocol_marker_is_safe "$readme"; then
    echo "ERROR: $readme contains a conflicting, misplaced, or incomplete historical agent protocol snippet; preserve the body and reconcile the snippet before continuing." >&2
    exit 1
  fi
done
runtime_destinations=()
for assistant in gemini qwen codex copilot claude; do
  runtime_destinations+=(
    "$REPO_ROOT/local/ai/$assistant/sessions.log"
    "$REPO_ROOT/local/ai/$assistant/requests.log"
  )
done
for destination in \
  "$REPO_ROOT/README.md" \
  "$REPO_ROOT/README.en.md" \
  "$REPO_ROOT/local/ai/bootstrap.ready" \
  "$REPO_ROOT/local/ai/chat_context.md" \
  "${runtime_destinations[@]}"; do
  if ! path_tree_is_safe "$destination"; then
    echo "ERROR: ${destination#"$REPO_ROOT"/}: destination or ancestor escapes the repository or is a link." >&2
    exit 1
  fi
  if [[ -f "$destination" ]] && ! file_has_single_link "$destination"; then
    echo "ERROR: ${destination#"$REPO_ROOT"/} is a hardlink; refusing to mutate shared file content." >&2
    exit 1
  fi
done

ensure_instruction_link .github/copilot-instructions.md ../AGENTS.md
ensure_instruction_link .claude/CLAUDE.md ../AGENTS.md
ensure_instruction_link CLAUDE.md AGENTS.md
ensure_instruction_link .gemini/GEMINI.md ../AGENTS.md
ensure_instruction_link GEMINI.md AGENTS.md
ensure_instruction_link QWEN.md AGENTS.md
ensure_instruction_link .qwen/QWEN.md ../AGENTS.md
ensure_skill_link .agents/skills/ai-bootstrap-converge
ensure_skill_link .claude/skills/ai-bootstrap-converge

if [[ "$link_failures" -gt 0 ]]; then
  echo "Bootstrap stopped before readiness changes because instruction conflicts remain." >&2
  exit 1
fi

ensure_instruction_link .github/copilot-instructions.md ../AGENTS.md 1
ensure_instruction_link .claude/CLAUDE.md ../AGENTS.md 1
ensure_instruction_link CLAUDE.md AGENTS.md 1
ensure_instruction_link .gemini/GEMINI.md ../AGENTS.md 1
ensure_instruction_link GEMINI.md AGENTS.md 1
ensure_instruction_link QWEN.md AGENTS.md 1
ensure_instruction_link .qwen/QWEN.md ../AGENTS.md 1
ensure_skill_link .agents/skills/ai-bootstrap-converge 1
ensure_skill_link .claude/skills/ai-bootstrap-converge 1
if [[ "$link_failures" -gt 0 ]]; then
  for created in "${created_links[@]}"; do
    rm -f -- "$created"
  done
  echo "Bootstrap could not create every required link; newly created links were rolled back." >&2
  exit 1
fi

# Pick ignore file: use the common Git exclude file, including linked worktrees.
mkdir -p "$(dirname "$EXCLUDE_FILE")"

legacy_exclude_entries=(
  '.gemini/'
  '.claude/'
  '.github/copilot-instructions.md'
  '.qwen/'
  'AGENTS.md'
  'CLAUDE.md'
  'GEMINI.md'
  'local/ai/'
  'QWEN.md'
  'README_snippet.md'
)

remove_legacy_exclude_entries() {
  [[ -f "$EXCLUDE_FILE" ]] || return 0
  local found=0 entry tmp
  for entry in "${legacy_exclude_entries[@]}"; do
    if grep -Fxq "$entry" "$EXCLUDE_FILE"; then
      found=1
      echo "Removed obsolete scaffold-wide exclude entry '$entry' from $EXCLUDE_FILE"
    fi
  done
  [[ "$found" -eq 1 ]] || return 0
  tmp=$(mktemp "$(dirname "$EXCLUDE_FILE")/.ai-bootstrap-exclude.XXXXXX")
  awk '
    $0 == ".gemini/" ||
    $0 == ".claude/" ||
    $0 == ".github/copilot-instructions.md" ||
    $0 == ".qwen/" ||
    $0 == "AGENTS.md" ||
    $0 == "CLAUDE.md" ||
    $0 == "GEMINI.md" ||
    $0 == "local/ai/" ||
    $0 == "QWEN.md" ||
    $0 == "README_snippet.md" { next }
    { print }
  ' "$EXCLUDE_FILE" > "$tmp"
  mv -f "$tmp" "$EXCLUDE_FILE"
}

remove_legacy_exclude_entries

ensure_exclude_entry() {
  local entry="$1"
  if [ -z "${EXCLUDE_FILE}" ]; then
    return
  fi
  if ! grep -Fxq "${entry}" "${EXCLUDE_FILE}"; then
    local tmp
    tmp=$(mktemp "$(dirname "$EXCLUDE_FILE")/.ai-bootstrap-exclude.XXXXXX")
    if [[ -f "$EXCLUDE_FILE" ]]; then
      awk '{ print }' "$EXCLUDE_FILE" > "$tmp"
    fi
    printf '%s\n' "$entry" >> "$tmp"
    mv -f "$tmp" "$EXCLUDE_FILE"
    echo "Added '${entry}' to ${EXCLUDE_FILE}"
  fi
}

while IFS= read -r entry; do
  ensure_exclude_entry "$entry"
done < <(required_runtime_exclude_entries)

apply_readme_snippet() {
  local readme=$1
  local required=${2:-0}
  local tmp_readme
  if [[ ! -f "$readme" ]]; then
    if [[ "$required" -eq 1 ]]; then
      cp README_snippet.md "$readme"
      printf '\n' >> "$readme"
    fi
    return 0
  fi
  if head -c "$snippet_size" "$readme" | cmp -s README_snippet.md -; then
    return 0
  fi
  if grep -F "AI AGENT PROTOCOL TRIGGER" "$readme" >/dev/null 2>&1; then
    if ! readme_protocol_marker_is_safe "$readme"; then
      echo "ERROR: $readme contains a conflicting, misplaced, or incomplete historical agent protocol snippet; preserve the body and reconcile the snippet before continuing." >&2
      exit 1
    fi
    tmp_readme=$(mktemp "$(dirname "$readme")/.ai-bootstrap-readme.XXXXXX")
    awk '
      function trim_newlines(value) {
        while (substr(value, 1, 1) == "\n" || substr(value, 1, 1) == "\r") value=substr(value, 2)
        return value
      }
      NR==FNR { snippet=snippet $0 "\n"; next }
      { text=text $0 "\n" }
      END {
        comment_end=index(text, "-->")
        body=trim_newlines(substr(text, comment_end + 3))
        printf "%s", snippet
        if (length(body) > 0) printf "\n%s", body
      }
    ' README_snippet.md "$readme" > "$tmp_readme"
    mv "$tmp_readme" "$readme"
    return 0
  fi
  tmp_readme=$(mktemp "$(dirname "$readme")/.ai-bootstrap-readme.XXXXXX")
  cat README_snippet.md > "$tmp_readme"
  printf '\n\n' >> "$tmp_readme"
  cat "$readme" >> "$tmp_readme"
  mv "$tmp_readme" "$readme"
}

# Добавляем точный скрытый фрагмент, не меняя существующее тело README.
# Insert the exact hidden snippet without changing the existing README body.
apply_readme_snippet README.md 1
apply_readme_snippet README.en.md

initialize_assistant_logs() {
  local assistant directory sessions requests
  for assistant in gemini qwen codex copilot claude; do
    directory="local/ai/$assistant"
    sessions="$directory/sessions.log"
    requests="$directory/requests.log"
    mkdir -p "$directory"
    if [[ ! -f "$sessions" ]]; then
      printf '{"session_id":"sample-%s-session","started_at":"YYYY-MM-DDTHH:MM:SSZ","assistant":"%s","language":"<lang>","gender":"<f/m/neutral>","logging_precision":"ISO8601Z"}\n' "$assistant" "$assistant" > "$sessions"
    fi
    if [[ ! -f "$requests" ]]; then
      printf '{"timestamp":"YYYY-MM-DDTHH:MM:SSZ","request_id":"sample-%s-req-001","assistant":"%s","summary":"placeholder summary","tools":[],"status":"success"}\n' "$assistant" "$assistant" > "$requests"
    fi
  done
}

initialize_assistant_logs

# Индикатор готовности / Readiness marker
READY_FILE="local/ai/bootstrap.ready"
mkdir -p local/ai
READY_TMP=$(mktemp "local/ai/.ai-bootstrap-ready.XXXXXX")
{
  echo "true"
  required_runtime_exclude_entries
} > "$READY_TMP"
mv -f "$READY_TMP" "$READY_FILE"
echo "local/ai/bootstrap.ready set"

# Убедимся, что в chat_context есть блок статуса / Ensure readiness block exists
CHAT_CONTEXT="local/ai/chat_context.md"
if [[ -f "$CHAT_CONTEXT" ]] && ! grep -Fq "## Статус готовности / Readiness status" "$CHAT_CONTEXT"; then
  tmp_context="$(mktemp "$(dirname "$CHAT_CONTEXT")/.ai-bootstrap-context.XXXXXX")"
  {
    cat <<'BLOCK'
## Статус готовности / Readiness status
- `status`: `pending`
- `last_verified_at`: `YYYY-MM-DDTHH:MM:SSZ`
- `agents_md_hash`: `sha256:<fill-after-bootstrap>`
- **RU:** После выполнения bootstrap-проверок обнови статус на `completed`, зафиксируй время (UTC) и актуальный хеш `AGENTS.md`; когда протокол пересматривается, перезапиши значения.
  **EN:** Once bootstrap checks pass, switch the status to `completed`, record the UTC timestamp, and store the current `AGENTS.md` hash; refresh the fields whenever the protocol is revisited.

BLOCK
    cat "$CHAT_CONTEXT"
  } > "$tmp_context"
  mv -f "$tmp_context" "$CHAT_CONTEXT"
  echo "Readiness block injected into $CHAT_CONTEXT"
fi

echo "Подготовка агентского каркаса завершена."
echo "Agent scaffold bootstrap complete."
