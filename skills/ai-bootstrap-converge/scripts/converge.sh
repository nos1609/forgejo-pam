#!/bin/sh
set -eu

mode="Audit"
target="."
template="${AI_BOOTSTRAP_TEMPLATE:-}"
source_ref=""
include_claude=0
force_managed=0
json=0
operations_file=""
template_scratch=""
agents_begin_marker='<!-- AI AGENT INSTRUCTIONS BEGIN -->'
agents_end_marker='<!-- AI AGENT INSTRUCTIONS END -->'

usage() {
  cat <<'USAGE'
Usage: converge.sh --mode audit|plan|apply|verify --target <repo> --template <template-path-or-git-url> [--source-ref <ref>] [--include-claude] [--force-managed-exact] [--json]
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$template_scratch" ] && [ -d "$template_scratch" ]; then
    rm -rf "$template_scratch"
  fi
  if [ -n "$operations_file" ] && [ -f "$operations_file" ]; then
    rm -f "$operations_file"
  fi
}
trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode|-Mode)
      [ "$#" -ge 2 ] || die "--mode requires a value"
      case "$2" in
        audit|Audit) mode="Audit" ;;
        plan|Plan) mode="Plan" ;;
        apply|Apply) mode="Apply" ;;
        verify|Verify) mode="Verify" ;;
        *) die "unsupported mode: $2" ;;
      esac
      shift 2
      ;;
    --target|-Target)
      [ "$#" -ge 2 ] || die "--target requires a value"
      target=$2
      shift 2
      ;;
    --template|-Template)
      [ "$#" -ge 2 ] || die "--template requires a value"
      template=$2
      shift 2
      ;;
    --source-ref|-SourceRef)
      [ "$#" -ge 2 ] || die "--source-ref requires a value"
      source_ref=$2
      shift 2
      ;;
    --include-claude|-IncludeClaude)
      include_claude=1
      shift
      ;;
    --force-managed-exact|-ForceManagedExact)
      force_managed=1
      shift
      ;;
    --json|-Json)
      json=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ -d "$target" ] || die "target path does not exist: $target"
target=$(cd "$target" && pwd -P)

resolve_template() {
  [ -n "$template" ] || die "template is required; pass --template or set AI_BOOTSTRAP_TEMPLATE"
  if [ -d "$template" ]; then
    (cd "$template" && pwd -P)
    return
  fi
  case "$template" in
    -*) die "remote template value must not start with '-': $template" ;;
  esac
  case "$source_ref" in
    -*) die "source ref must not start with '-': $source_ref" ;;
  esac
  command -v git >/dev/null 2>&1 || die "template is not a directory and git is unavailable"
  template_scratch=$(mktemp -d "${TMPDIR:-/tmp}/ai-bootstrap-template.XXXXXX")
  if [ -n "$source_ref" ]; then
    if ! git clone --depth 1 --branch "$source_ref" -- "$template" "$template_scratch" >/dev/null 2>&1; then
      rm -rf "$template_scratch"
      template_scratch=$(mktemp -d "${TMPDIR:-/tmp}/ai-bootstrap-template.XXXXXX")
      git clone -- "$template" "$template_scratch" >/dev/null 2>&1 || die "git clone failed for template: $template"
      git -C "$template_scratch" checkout "$source_ref" >/dev/null 2>&1 || die "git checkout failed for template ref: $source_ref"
    fi
  else
    git clone --depth 1 -- "$template" "$template_scratch" >/dev/null 2>&1 || die "git clone failed for template: $template"
  fi
  printf '%s\n' "$template_scratch"
}

template_root=$(resolve_template)

path_present() {
  [ -e "$1" ] || [ -L "$1" ]
}

canonical_existing_path() {
  _canonical_input=$1
  if [ -d "$_canonical_input" ]; then
    (cd "$_canonical_input" 2>/dev/null && pwd -P)
    return
  fi
  _canonical_parent=$(cd "$(dirname "$_canonical_input")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$_canonical_parent" "$(basename "$_canonical_input")"
}

template_path_is_safe() {
  _template_path=$1
  path_present "$_template_path" || return 1
  [ ! -L "$_template_path" ] || return 1
  _template_canonical=$(canonical_existing_path "$_template_path") || return 1
  case "$_template_canonical" in
    "$template_root"|"$template_root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

template_file_is_safe() {
  [ -f "$1" ] && [ ! -L "$1" ] && template_path_is_safe "$1"
}

template_directory_is_safe() {
  _template_directory=$1
  [ -d "$_template_directory" ] && [ ! -L "$_template_directory" ] || return 1
  template_path_is_safe "$_template_directory" || return 1
  [ -z "$(find "$_template_directory" -type l -print 2>/dev/null)" ]
}

validate_template_sources() {
  for _template_rel in AGENTS.md README_snippet.md .gitignore local/ai/bootstrap.ready; do
    _template_path=$template_root/$_template_rel
    if path_present "$_template_path" && ! template_file_is_safe "$_template_path"; then
      die "template source is not a regular non-symlink file inside the canonical template root: $_template_rel"
    fi
  done
  for _template_rel in local/ai local/ai/agents local/ai/scripts skills/ai-bootstrap-converge; do
    _template_path=$template_root/$_template_rel
    if path_present "$_template_path" && ! template_directory_is_safe "$_template_path"; then
      die "template source is not a non-symlink directory inside the canonical template root: $_template_rel"
    fi
  done
  if [ -f "$template_root/AGENTS.md" ] && ! awk -v begin="$agents_begin_marker" -v end="$agents_end_marker" '
    {
      line=$0
      sub(/\r$/, "", line)
      if (NR == 1) first=line
      if (line == begin) { begin_count++; begin_line=NR }
      if (line == end) { end_count++; end_line=NR }
      if (line !~ /^[[:space:]]*$/) last_nonblank=NR
    }
    END {
      valid=(first == begin && begin_count == 1 && end_count == 1 && end_line > begin_line && end_line == last_nonblank)
      exit(valid ? 0 : 1)
    }
  ' "$template_root/AGENTS.md"; then
    die "template AGENTS.md must contain exactly one complete managed instruction block spanning the file"
  fi
}

validate_template_sources
operations_file=$(mktemp "${TMPDIR:-/tmp}/ai-bootstrap-ops.XXXXXX")

emit() {
  _emit_status=$1
  _emit_type=$2
  _emit_path=$3
  _emit_safe=$4
  _emit_detail=$5
  printf '%s\t%s\t%s\t%s\t%s\n' "$_emit_status" "$_emit_type" "$_emit_path" "$_emit_safe" "$_emit_detail" >> "$operations_file"
}

same_file() {
  [ -f "$1" ] && [ -f "$2" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    [ "$(sha256sum "$1" | awk '{print $1}')" = "$(sha256sum "$2" | awk '{print $1}')" ]
  else
    cmp -s "$1" "$2"
  fi
}

same_file_identity() {
  [ -f "$1" ] && [ -f "$2" ] || return 1
  command -v stat >/dev/null 2>&1 || return 1
  if _first_identity=$(stat -Lc '%d:%i' "$1" 2>/dev/null) && _second_identity=$(stat -Lc '%d:%i' "$2" 2>/dev/null); then
    [ "$_first_identity" = "$_second_identity" ]
    return
  fi
  _first_identity=$(stat -f '%d:%i' "$1" 2>/dev/null) || return 1
  _second_identity=$(stat -f '%d:%i' "$2" 2>/dev/null) || return 1
  [ "$_first_identity" = "$_second_identity" ]
}

file_link_count() {
  _link_count_path=$1
  if _link_count=$(stat -Lc '%h' -- "$_link_count_path" 2>/dev/null); then
    printf '%s\n' "$_link_count"
    return 0
  fi
  stat -f '%l' "$_link_count_path" 2>/dev/null
}

file_has_single_link() {
  _single_link_count=$(file_link_count "$1") || return 1
  [ "$_single_link_count" -eq 1 ]
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
  _agents_path=$1
  _agents_count=$(file_link_count "$_agents_path") || return 1
  _known_count=0
  for _known_rel in $(instruction_link_paths); do
    _known_path=$target/$_known_rel
    if [ ! -L "$_known_path" ] && target_path_is_safe "$_known_path" 1 && same_file_identity "$_known_path" "$_agents_path"; then
      _known_count=$((_known_count + 1))
    fi
  done
  [ "$_agents_count" -eq $((_known_count + 1)) ]
}

replace_agents_file() {
  _agents_source=$1
  _agents_destination=$target/AGENTS.md
  agents_hardlinks_are_known "$_agents_destination" || return 1

  _known_links=$(mktemp "${TMPDIR:-/tmp}/ai-bootstrap-known-links.XXXXXX")
  for _known_rel in $(instruction_link_paths); do
    _known_path=$target/$_known_rel
    if [ ! -L "$_known_path" ] && target_path_is_safe "$_known_path" 1 && same_file_identity "$_known_path" "$_agents_destination"; then
      printf '%s\n' "$_known_path" >> "$_known_links"
    fi
  done

  _agents_tmp=$(mktemp "$target/.ai-bootstrap-agents.XXXXXX")
  if ! cp "$_agents_source" "$_agents_tmp"; then
    rm -f "$_known_links" "$_agents_tmp"
    return 1
  fi
  if _agents_mode=$(stat -Lc '%a' -- "$_agents_destination" 2>/dev/null); then
    chmod "$_agents_mode" "$_agents_tmp"
  elif _agents_mode=$(stat -f '%Lp' "$_agents_destination" 2>/dev/null); then
    chmod "$_agents_mode" "$_agents_tmp"
  fi
  if ! mv -f "$_agents_tmp" "$_agents_destination"; then
    rm -f "$_known_links" "$_agents_tmp"
    return 1
  fi

  _link_rebuild_failed=0
  while IFS= read -r _known_path; do
    [ -n "$_known_path" ] || continue
    _known_parent=$(dirname "$_known_path")
    if ! _known_tmp=$(mktemp "$_known_parent/.ai-bootstrap-link.XXXXXX"); then
      _link_rebuild_failed=1
      break
    fi
    rm -f "$_known_tmp"
    if ! ln "$_agents_destination" "$_known_tmp" || ! mv -f "$_known_tmp" "$_known_path"; then
      rm -f "$_known_tmp"
      _link_rebuild_failed=1
      break
    fi
  done < "$_known_links"
  rm -f "$_known_links"
  [ "$_link_rebuild_failed" -eq 0 ]
}

apply_agents_replacement() {
  _agents_source=$1
  if ! replace_agents_file "$_agents_source"; then
    emit "BLOCKED" "EnsureAgentsInstructions" "AGENTS.md" "false" "AGENTS.md has an unknown hardlink or could not be replaced without mutating another path."
    return 1
  fi
  return 0
}

path_tree_is_safe() {
  _safe_root=$1
  _safe_path=$2
  _safe_allow_leaf_link=${3:-0}
  case "$_safe_path" in
    "$_safe_root"/*) ;;
    *) return 1 ;;
  esac
  _target_relative=${_safe_path#"$_safe_root"/}
  _target_current=$_safe_root
  _target_old_ifs=$IFS
  IFS=/
  for _target_component in $_target_relative; do
    case "$_target_component" in
      ""|.) continue ;;
      ..)
        IFS=$_target_old_ifs
        return 1
        ;;
    esac
    _target_next=$_target_current/$_target_component
    if [ -L "$_target_next" ] && { [ "$_safe_allow_leaf_link" -ne 1 ] || [ "$_target_next" != "$_safe_path" ]; }; then
      IFS=$_target_old_ifs
      return 1
    fi
    if [ -e "$_target_next" ] && [ "$_target_next" != "$_safe_path" ] && [ ! -d "$_target_next" ]; then
      IFS=$_target_old_ifs
      return 1
    fi
    _target_current=$_target_next
  done
  IFS=$_target_old_ifs
  return 0
}

target_path_is_safe() {
  path_tree_is_safe "$target" "$1" "${2:-0}"
}

allow_target_mutation() {
  _mutation_path=$1
  _mutation_type=$2
  _mutation_rel=$3
  _mutation_allow_leaf_link=${4:-0}
  if target_path_is_safe "$_mutation_path" "$_mutation_allow_leaf_link"; then
    return 0
  fi
  emit "BLOCKED" "$_mutation_type" "$_mutation_rel" "false" "Target mutation blocked: destination or ancestor is a symlink or escapes the canonical target root."
  return 1
}

copy_exact() {
  src=$1
  dst=$2
  target_path_is_safe "$dst" || return 1
  dst_dir=$(dirname "$dst")
  mkdir -p "$dst_dir"
  copy_tmp=$(mktemp "$dst_dir/.ai-bootstrap.XXXXXX")
  if ! cp -p "$src" "$copy_tmp"; then
    rm -f "$copy_tmp"
    return 1
  fi
  if ! mv -f "$copy_tmp" "$dst"; then
    rm -f "$copy_tmp"
    return 1
  fi
}

ensure_managed_file() {
  rel=$1
  src=$template_root/$rel
  dst=$target/$rel
  [ -f "$src" ] || return 0
  allow_target_mutation "$dst" "EnsureManagedFile" "$rel" || return 0
  if [ -f "$dst" ] && ! file_has_single_link "$dst"; then
    emit "BLOCKED" "EnsureManagedFile" "$rel" "false" "Managed destination has an unknown hardlink; refusing to accept or replace shared file content."
    return 0
  fi
  if path_present "$dst" && [ ! -f "$dst" ]; then
    emit "CONFLICT" "EnsureManagedFile" "$rel" "false" "A directory or non-regular path exists where the managed file is required; preserve it for manual recovery."
  elif [ ! -f "$dst" ]; then
    emit "MISSING" "EnsureManagedFile" "$rel" "true" "Create from template."
    if [ "$mode" = "Apply" ]; then
      copy_exact "$src" "$dst"
    fi
  elif same_file "$src" "$dst"; then
    emit "OK" "EnsureManagedFile" "$rel" "false" "Matches template."
  else
    emit "DRIFT" "EnsureManagedFile" "$rel" "true" "Replace the framework-owned file with the required version."
    if [ "$mode" = "Apply" ]; then
      copy_exact "$src" "$dst"
    fi
  fi
  return 0
}

managed_files() {
  if [ -f "$template_root/README_snippet.md" ]; then
    printf '%s\n' 'README_snippet.md'
  fi
  for root in local/ai/agents local/ai/scripts skills/ai-bootstrap-converge; do
    if [ -d "$template_root/$root" ]; then
      (cd "$template_root" && find "$root" -type f | sort)
    fi
  done
}

ensure_agents_instructions() {
  rel=AGENTS.md
  src=$template_root/$rel
  dst=$target/$rel
  [ -f "$src" ] || return 0
  allow_target_mutation "$dst" "EnsureAgentsInstructions" "$rel" || return 0
  if path_present "$dst" && [ ! -f "$dst" ]; then
    emit "CONFLICT" "EnsureAgentsInstructions" "$rel" "false" "A directory or non-regular path exists where AGENTS.md is required; preserve it for manual recovery."
    return 0
  fi
  if [ ! -f "$dst" ]; then
    emit "MISSING" "EnsureAgentsInstructions" "$rel" "true" "Create from template."
    if [ "$mode" = "Apply" ]; then
      copy_exact "$src" "$dst"
    fi
    return 0
  fi
  if ! agents_hardlinks_are_known "$dst"; then
    emit "BLOCKED" "EnsureAgentsInstructions" "$rel" "false" "AGENTS.md has a hardlink outside the known instruction-link set; refusing to read-modify-write it."
    return 0
  fi
  marker_counts=$(awk -v begin="$agents_begin_marker" -v end="$agents_end_marker" '
    {
      line=$0
      sub(/\r$/, "", line)
      if (line == begin) begin_count++
      if (line == end) end_count++
    }
    END { print begin_count + 0, end_count + 0 }
  ' "$dst")

  if [ "$marker_counts" = "1 1" ]; then
    block_tmp=$(mktemp "${TMPDIR:-/tmp}/ai-bootstrap-agents-block.XXXXXX")
    if ! awk -v begin="$agents_begin_marker" -v end="$agents_end_marker" '
      {
        line=$0
        sub(/\r$/, "", line)
        if (line == begin) { inside=1; seen_begin=1 }
        if (inside) print
        if (line == end && inside) { seen_end=1; exit }
      }
      END { exit(seen_begin && seen_end ? 0 : 1) }
    ' "$dst" > "$block_tmp"; then
      rm -f "$block_tmp"
      emit "CONFLICT" "EnsureAgentsInstructions" "$rel" "false" "Managed instruction markers are incomplete, duplicated, or out of order; preserve the file for manual recovery."
      return 0
    fi

    if cmp -s "$src" "$block_tmp" && awk -v begin="$agents_begin_marker" '
      {
        line=$0
        sub(/\r$/, "", line)
        if (line == begin) { seen_begin=1; exit(found_content ? 1 : 0) }
        if (line !~ /^[[:space:]]*$/) found_content=1
      }
      END { if (!seen_begin) exit 1 }
    ' "$dst"; then
      rm -f "$block_tmp"
      emit "OK" "EnsureAgentsInstructions" "$rel" "false" "Required instruction block is current and at the top."
      return 0
    fi
    rm -f "$block_tmp"

    if [ "$force_managed" -eq 1 ]; then
      emit "DRIFT" "EnsureAgentsInstructions" "$rel" "true" "Replace the complete file because force was set."
      if [ "$mode" = "Apply" ]; then
        apply_agents_replacement "$src" || true
      fi
      return 0
    fi

    emit "DRIFT" "EnsureAgentsInstructions" "$rel" "true" "Update and move the managed instruction block to the top while preserving project rules outside it."
    if [ "$mode" = "Apply" ]; then
      tmp=$(mktemp "${TMPDIR:-/tmp}/ai-bootstrap-agents.XXXXXX")
      awk -v begin="$agents_begin_marker" -v end="$agents_end_marker" '
        NR==FNR { source[++source_count]=$0; next }
        {
          line=$0
          sub(/\r$/, "", line)
          if (state == 0 && line == begin) { state=1; next }
          if (state == 1) {
            if (line == end) state=2
            next
          }
          if (state == 0) before[++before_count]=$0
          else after[++after_count]=$0
        }
        END {
          for (i=1; i<=source_count; i++) print source[i]
          before_first=1
          while (before_first <= before_count && before[before_first] ~ /^[[:space:]]*$/) before_first++
          before_last=before_count
          while (before_last >= before_first && before[before_last] ~ /^[[:space:]]*$/) before_last--
          after_first=1
          while (after_first <= after_count && after[after_first] ~ /^[[:space:]]*$/) after_first++
          after_last=after_count
          while (after_last >= after_first && after[after_last] ~ /^[[:space:]]*$/) after_last--
          if (before_first <= before_last || after_first <= after_last) print ""
          for (i=before_first; i<=before_last; i++) print before[i]
          if (before_first <= before_last && after_first <= after_last) print ""
          for (i=after_first; i<=after_last; i++) print after[i]
        }
      ' "$src" "$dst" > "$tmp"
      apply_agents_replacement "$tmp" || true
      rm -f "$tmp"
    fi
    return 0
  fi

  if [ "$marker_counts" != "0 0" ]; then
    if [ "$force_managed" -eq 1 ]; then
      emit "DRIFT" "EnsureAgentsInstructions" "$rel" "true" "Replace the complete file because force was set."
      if [ "$mode" = "Apply" ]; then
        apply_agents_replacement "$src" || true
      fi
    else
      emit "CONFLICT" "EnsureAgentsInstructions" "$rel" "false" "Managed instruction markers are incomplete, duplicated, or out of order; preserve the file for manual recovery."
    fi
    return 0
  fi

  if awk '
    {
      line=$0
      sub(/\r$/, "", line)
      if (NR == 1) {
        if (line != "# Инструкции ассистентам / Local agent instructions" && line != "# Инструкции ассистентам (шаблон) / Local agent instructions (template)") exit 1
        state=1
        next
      }
      if (state == 1 && line == "## P0 rules / P0 правила") { state=2; next }
      if (state == 2 && line == "## Modules / Разделы") { state=3; next }
      if (state == 3 && line == "## Reading order / Порядок чтения") { state=4; expected=1; next }
      if (state == 4) {
        prefix=expected ") "
        if (index(line, prefix) != 1) exit 1
        expected++
        if (expected == 6) { complete=1; state=5 }
      }
    }
    END { exit(complete ? 0 : 1) }
  ' "$dst"; then
    emit "DRIFT" "EnsureAgentsInstructions" "$rel" "true" "Upgrade the legacy instruction block while preserving project rules after it."
    if [ "$mode" = "Apply" ]; then
      tmp=$(mktemp "${TMPDIR:-/tmp}/ai-bootstrap-agents.XXXXXX")
      awk '
        NR==FNR { source[++source_count]=$0; next }
        {
          line=$0
          sub(/\r$/, "", line)
          if (state == 0) {
            if (line == "## Reading order / Порядок чтения") { state=1; expected=1 }
            next
          }
          if (state == 1) {
            prefix=expected ") "
            if (index(line, prefix) == 1) {
              expected++
              if (expected == 6) state=2
            }
            next
          }
          body[++body_count]=$0
        }
        END {
          for (i=1; i<=source_count; i++) print source[i]
          first=1
          while (first <= body_count && body[first] ~ /^[[:space:]]*$/) first++
          last=body_count
          while (last >= first && body[last] ~ /^[[:space:]]*$/) last--
          if (first <= last) print ""
          for (i=first; i<=last; i++) print body[i]
        }
      ' "$src" "$dst" > "$tmp"
      apply_agents_replacement "$tmp" || true
      rm -f "$tmp"
    fi
    return 0
  fi

  if [ "$force_managed" -eq 1 ]; then
    emit "DRIFT" "EnsureAgentsInstructions" "$rel" "true" "Replace the complete file because force was set."
    if [ "$mode" = "Apply" ]; then
      apply_agents_replacement "$src" || true
    fi
    return 0
  fi

  emit "MISSING" "EnsureAgentsInstructions" "$rel" "true" "Insert the required instruction block at the top while preserving existing project rules."
  if [ "$mode" = "Apply" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/ai-bootstrap-agents.XXXXXX")
    cat "$src" > "$tmp"
    printf '\n' >> "$tmp"
    cat "$dst" >> "$tmp"
    apply_agents_replacement "$tmp" || true
    rm -f "$tmp"
  fi
  return 0
}

ensure_if_missing() {
  rel=$1
  src=$template_root/$rel
  dst=$target/$rel
  [ -f "$src" ] || return 0
  allow_target_mutation "$dst" "EnsureIfMissing" "$rel" || return 0
  if [ -f "$dst" ] && ! file_has_single_link "$dst"; then
    emit "BLOCKED" "EnsureIfMissing" "$rel" "false" "Runtime destination has an unknown hardlink; preserve it for manual recovery."
    return 0
  fi
  if path_present "$dst" && [ ! -f "$dst" ]; then
    emit "CONFLICT" "EnsureIfMissing" "$rel" "false" "A directory or non-regular path exists where a file is required; preserve it for manual recovery."
  elif [ -f "$dst" ]; then
    emit "OK" "EnsureIfMissing" "$rel" "false" "Existing project/local file preserved."
  else
    emit "MISSING" "EnsureIfMissing" "$rel" "true" "Create placeholder/sample from template."
    if [ "$mode" = "Apply" ]; then
      copy_exact "$src" "$dst"
    fi
  fi
  return 0
}

ensure_if_missing_files() {
  for rel in local/ai/bootstrap.ready local/ai/chat_context.md local/ai/project_addenda.md local/ai/session_history.md; do
    if [ -f "$template_root/$rel" ]; then
      printf '%s\n' "$rel"
    fi
  done
  if [ -d "$template_root/local/ai" ]; then
    find "$template_root/local/ai" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r dir; do
      name=$(basename "$dir")
      case "$name" in
        agents|scripts|context_packs|session_summaries) continue ;;
      esac
      for file in README.md requests.log sessions.log; do
        if [ -f "$dir/$file" ]; then
          printf 'local/ai/%s/%s\n' "$name" "$file"
        fi
      done
    done
  fi
}

readme_snippet() {
  if [ -f "$template_root/README_snippet.md" ]; then
    cat "$template_root/README_snippet.md"
  fi
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

previous_readme_protocol_is_safe() {
  _previous_readme=$1
  _current_snippet=$2
  _previous_trigger_count=$(awk -v trigger='AI AGENT PROTOCOL TRIGGER' '
    {
      rest=$0
      while ((position=index(rest, trigger)) > 0) {
        count++
        rest=substr(rest, position + length(trigger))
      }
    }
    END { print count + 0 }
  ' "$_previous_readme")
  [ "$_previous_trigger_count" -eq 1 ] || return 1
  protocol_comment_has_signature "$_current_snippet" || return 1
  protocol_comment_has_signature "$_previous_readme"
}

ensure_readme_snippet() {
  rel=$1
  snippet_file=$2
  [ -s "$snippet_file" ] || return 0
  path=$target/$rel
  allow_target_mutation "$path" "EnsureSnippetPresent" "$rel" || return 0
  if [ -f "$path" ] && ! file_has_single_link "$path"; then
    emit "BLOCKED" "EnsureSnippetPresent" "$rel" "false" "README has an unknown hardlink; refusing to patch shared file content."
    return 0
  fi
  if path_present "$path" && [ ! -f "$path" ]; then
    emit "CONFLICT" "EnsureSnippetPresent" "$rel" "false" "A directory or non-regular path exists where README is required; preserve it for manual recovery."
    return 0
  fi
  if [ ! -f "$path" ]; then
    emit "MISSING" "EnsureSnippetPresent" "$rel" "true" "Create README containing required hidden snippet."
    if [ "$mode" = "Apply" ]; then
      mkdir -p "$(dirname "$path")"
      cat "$snippet_file" > "$path"
      printf '\n' >> "$path"
    fi
    return 0
  fi
  exact_count=$(awk '
    NR==FNR { s=s $0 "\n"; next }
    { t=t $0 "\n" }
    END {
      rest=t
      while (length(s) > 0 && (position=index(rest, s)) > 0) {
        count++
        rest=substr(rest, position + length(s))
      }
      print count + 0
    }
  ' "$snippet_file" "$path")

  if [ "$exact_count" -eq 1 ] && awk 'NR==FNR { s=s $0 "\n"; next } { t=t $0 "\n" } END { exit(index(t, s) == 1 ? 0 : 1) }' "$snippet_file" "$path"; then
    emit "OK" "EnsureSnippetPresent" "$rel" "false" "Snippet is already at the top."
  elif [ "$exact_count" -gt 1 ]; then
    emit "CONFLICT" "EnsureSnippetPresent" "$rel" "false" "The exact protocol snippet appears more than once; preserve the README for manual recovery."
  elif [ "$exact_count" -eq 1 ]; then
    emit "DRIFT" "EnsureSnippetPresent" "$rel" "true" "Move existing snippet to the top without changing README body."
    if [ "$mode" = "Apply" ]; then
      tmp=$(mktemp "$(dirname "$path")/.ai-bootstrap-readme.XXXXXX")
      awk '
        function trim_newlines(value) {
          while (substr(value, 1, 1) == "\n" || substr(value, 1, 1) == "\r") value=substr(value, 2)
          while (substr(value, length(value), 1) == "\n" || substr(value, length(value), 1) == "\r") value=substr(value, 1, length(value) - 1)
          return value
        }
        NR==FNR { s=s $0 "\n"; next }
        { t=t $0 "\n" }
        END {
          pos=index(t, s)
          if (pos == 0) exit 1
          before=substr(t, 1, pos - 1)
          after=substr(t, pos + length(s))
          project=trim_newlines(before after)
          printf "%s", s
          if (length(project) > 0) printf "\n%s\n", project
        }
      ' "$snippet_file" "$path" > "$tmp"
      mv "$tmp" "$path"
    fi
  else
    trigger_count=$(awk -v trigger='AI AGENT PROTOCOL TRIGGER' '
      {
        rest=$0
        while ((position=index(rest, trigger)) > 0) {
          count++
          rest=substr(rest, position + length(trigger))
        }
      }
      END { print count + 0 }
    ' "$path")
    if [ "$trigger_count" -gt 0 ]; then
      if ! previous_readme_protocol_is_safe "$path" "$snippet_file"; then
        emit "CONFLICT" "EnsureSnippetPresent" "$rel" "false" "The protocol marker is misplaced, duplicated, or lacks the complete historical signature; preserve the README for manual recovery."
        return 0
      fi

      emit "DRIFT" "EnsureSnippetPresent" "$rel" "true" "Replace the previous top protocol snippet without changing the README body."
      if [ "$mode" = "Apply" ]; then
        tmp=$(mktemp "$(dirname "$path")/.ai-bootstrap-readme.XXXXXX")
        awk '
          function trim_newlines(value) {
            while (substr(value, 1, 1) == "\n" || substr(value, 1, 1) == "\r") value=substr(value, 2)
            while (substr(value, length(value), 1) == "\n" || substr(value, length(value), 1) == "\r") value=substr(value, 1, length(value) - 1)
            return value
          }
          NR==FNR { s=s $0 "\n"; next }
          { t=t $0 "\n" }
          END {
            comment_end=index(t, "-->")
            body=trim_newlines(substr(t, comment_end + 3))
            printf "%s", s
            if (length(body) > 0) printf "\n%s\n", body
          }
        ' "$snippet_file" "$path" > "$tmp"
        mv "$tmp" "$path"
      fi
      return 0
    fi

    emit "MISSING" "EnsureSnippetPresent" "$rel" "true" "Insert required hidden snippet at the top."
    if [ "$mode" = "Apply" ]; then
      tmp=$(mktemp "$(dirname "$path")/.ai-bootstrap-readme.XXXXXX")
      awk '
        function trim_newlines(value) {
          while (substr(value, 1, 1) == "\n" || substr(value, 1, 1) == "\r") value=substr(value, 2)
          while (substr(value, length(value), 1) == "\n" || substr(value, length(value), 1) == "\r") value=substr(value, 1, length(value) - 1)
          return value
        }
        NR==FNR { s=s $0 "\n"; next }
        { t=t $0 "\n" }
        END {
          body=trim_newlines(t)
          printf "%s", s
          if (length(body) > 0) printf "\n%s\n", body
        }
      ' "$snippet_file" "$path" > "$tmp"
      mv "$tmp" "$path"
    fi
  fi
  return 0
}

exclude_lines() {
  {
    if [ -f "$template_root/.gitignore" ]; then
      awk '
        /BEGIN EXCLUDE LIST/ { inside=1; next }
        /END EXCLUDE LIST/ { inside=0; next }
        inside {
          sub(/^[[:space:]]*#[[:space:]]?/, "")
          if ($0 !~ /^[[:space:]]*$/) print $0
        }
      ' "$template_root/.gitignore"
    fi
    printf '%s\n' ".codex/" "AGENTS.override.md"
  } | awk '!seen[$0]++'
}

legacy_scaffold_exclude_lines() {
  printf '%s\n' \
    '.gemini/' \
    '.claude/' \
    '.github/copilot-instructions.md' \
    '.qwen/' \
    'AGENTS.md' \
    'CLAUDE.md' \
    'GEMINI.md' \
    'local/ai/' \
    'QWEN.md' \
    'README_snippet.md'
}

rewrite_exclude_without_legacy_lines() {
  _exclude_path=$1
  [ -f "$_exclude_path" ] || return 0
  _exclude_tmp=$(mktemp "$(dirname "$_exclude_path")/.ai-bootstrap-exclude.XXXXXX") || return 1
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
  ' "$_exclude_path" > "$_exclude_tmp" || {
    rm -f "$_exclude_tmp"
    return 1
  }
  mv -f "$_exclude_tmp" "$_exclude_path"
}

append_exclude_line_atomically() {
  _exclude_path=$1
  _exclude_line=$2
  _exclude_dir=$(dirname "$_exclude_path")
  mkdir -p "$_exclude_dir"
  _exclude_tmp=$(mktemp "$_exclude_dir/.ai-bootstrap-exclude.XXXXXX") || return 1
  if [ -f "$_exclude_path" ]; then
    awk '{ print }' "$_exclude_path" > "$_exclude_tmp" || {
      rm -f "$_exclude_tmp"
      return 1
    }
  fi
  printf '%s\n' "$_exclude_line" >> "$_exclude_tmp"
  mv -f "$_exclude_tmp" "$_exclude_path"
}

ensure_exclude_lines() {
  git_top_level=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null) || {
    emit "SKIP" "EnsureExcludeLines" ".git/info/exclude" "false" "Target is not the root of a Git worktree; parent Git metadata is not modified."
    return
  }
  git_top_level=$(canonical_existing_path "$git_top_level") || {
    emit "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "false" "Could not canonicalize the Git worktree root."
    return
  }
  if [ "$git_top_level" != "$target" ]; then
    emit "SKIP" "EnsureExcludeLines" ".git/info/exclude" "false" "Target is not the root of a Git worktree; parent Git metadata is not modified."
    return
  fi
  git_common=$(git -C "$target" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    emit "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "false" "Could not resolve the canonical git common directory."
    return
  }
  exclude=$(git -C "$target" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null) || {
    emit "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "false" "Could not resolve the git exclude path."
    return
  }
  git_common=$(canonical_existing_path "$git_common") || {
    emit "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "false" "Could not canonicalize the git common directory."
    return
  }
  if ! path_tree_is_safe "$git_common" "$exclude"; then
    emit "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "false" "Git exclude path or ancestor is a symlink or escapes the canonical git common directory."
    return
  fi
  if [ -f "$exclude" ] && ! file_has_single_link "$exclude"; then
    emit "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "false" "Git exclude has an unknown hardlink; refusing to mutate shared file content."
    return
  fi
  legacy_present=0
  for legacy_line in $(legacy_scaffold_exclude_lines); do
    if [ -f "$exclude" ] && grep -Fx -- "$legacy_line" "$exclude" >/dev/null 2>&1; then
      legacy_present=1
      emit "DRIFT" "EnsureExcludeLines" ".git/info/exclude" "true" "Remove obsolete scaffold-wide line: $legacy_line"
    fi
  done
  if [ "$legacy_present" -eq 1 ] && [ "$mode" = "Apply" ]; then
    if ! rewrite_exclude_without_legacy_lines "$exclude"; then
      emit "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "false" "Could not atomically remove obsolete scaffold-wide exclude lines."
      return
    fi
  fi
  exclude_lines | while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -f "$exclude" ] && grep -Fx -- "$line" "$exclude" >/dev/null 2>&1; then
      emit "OK" "EnsureExcludeLines" ".git/info/exclude" "false" "Line present: $line"
    else
      emit "MISSING" "EnsureExcludeLines" ".git/info/exclude" "true" "Append line: $line"
      if [ "$mode" = "Apply" ]; then
        if ! append_exclude_line_atomically "$exclude" "$line"; then
          emit "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "false" "Could not atomically append line: $line"
        fi
      fi
    fi
  done
  return 0
}

link_ok() {
  path=$1
  expected=$2
  agent=$target/AGENTS.md
  [ -e "$path" ] || [ -L "$path" ] || return 1
  if [ -L "$path" ]; then
    link_target=$(readlink "$path")
    [ "$link_target" = "$expected" ]
  elif [ -f "$path" ] && [ -f "$agent" ]; then
    same_file_identity "$path" "$agent"
  else
    return 1
  fi
}

ensure_instruction_link() {
  rel=$1
  rel_target=$2
  path=$target/$rel
  agent=$target/AGENTS.md
  allow_target_mutation "$path" "EnsureInstructionLink" "$rel" 1 || return 0
  if path_present "$agent" && { [ ! -f "$agent" ] || [ -L "$agent" ]; }; then
    emit "BLOCKED" "EnsureInstructionLink" "$rel" "false" "Canonical AGENTS.md is not a regular file; do not create or accept an instruction link."
    return 0
  fi
  if link_ok "$path" "$rel_target"; then
    emit "OK" "EnsureInstructionLink" "$rel" "false" "Points to or matches AGENTS.md."
  elif [ -e "$path" ] || [ -L "$path" ]; then
    emit "CONFLICT" "EnsureInstructionLink" "$rel" "false" "Existing instruction file differs; preserve and merge before replacing."
  else
    emit "MISSING" "EnsureInstructionLink" "$rel" "true" "Create symlink or hardlink to AGENTS.md."
    if [ "$mode" = "Apply" ]; then
      mkdir -p "$(dirname "$path")"
      if ! ln -s "$rel_target" "$path" 2>/dev/null; then
        if path_present "$path"; then
          emit "BLOCKED" "EnsureInstructionLink" "$rel" "false" "Destination appeared while creating the symlink; preserve it for review."
        elif ! ln -P "$agent" "$path" 2>/dev/null; then
          emit "BLOCKED" "EnsureInstructionLink" "$rel" "false" "Could not create symlink or hardlink to AGENTS.md."
        fi
      fi
    fi
  fi
  return 0
}

symlink_ok() {
  path=$1
  expected=$2
  [ -L "$path" ] || return 1
  link_target=$(readlink "$path")
  [ "$link_target" = "$expected" ]
}

ensure_skill_discovery_link() {
  rel=$1
  rel_target=$2
  path=$target/$rel
  allow_target_mutation "$path" "EnsureSkillDiscoveryLink" "$rel" 1 || return 0
  if symlink_ok "$path" "$rel_target"; then
    emit "OK" "EnsureSkillDiscoveryLink" "$rel" "false" "Symlink points to canonical skills/ai-bootstrap-converge."
  elif [ -e "$path" ] || [ -L "$path" ]; then
    emit "CONFLICT" "EnsureSkillDiscoveryLink" "$rel" "false" "Path exists but is not the required symlink; do not duplicate skill files here."
  else
    emit "MISSING" "EnsureSkillDiscoveryLink" "$rel" "true" "Create symlink to ../../skills/ai-bootstrap-converge."
    if [ "$mode" = "Apply" ]; then
      mkdir -p "$(dirname "$path")"
      if ! ln -s "$rel_target" "$path" 2>/dev/null; then
        emit "BLOCKED" "EnsureSkillDiscoveryLink" "$rel" "false" "Could not create directory symlink."
      fi
    fi
  fi
  return 0
}

instruction_links() {
  cat <<'LINKS'
.github/copilot-instructions.md	../AGENTS.md
.gemini/GEMINI.md	../AGENTS.md
.qwen/QWEN.md	../AGENTS.md
GEMINI.md	AGENTS.md
QWEN.md	AGENTS.md
LINKS
  if [ "$include_claude" -eq 1 ] || [ -e "$template_root/.claude/CLAUDE.md" ] || [ -e "$template_root/CLAUDE.md" ]; then
    printf '%s\t%s\n' ".claude/CLAUDE.md" "../AGENTS.md"
    printf '%s\t%s\n' "CLAUDE.md" "AGENTS.md"
  fi
}

report_local_only_tracked() {
  [ -e "$target/.git" ] || return 0
  git -C "$target" ls-files -- \
    AGENTS.override.md \
    .codex/ \
    tmp/ai/ \
    local/ai/bootstrap.ready \
    local/ai/chat_context.md \
    local/ai/project_addenda.md \
    local/ai/session_history.md \
    local/ai/session_summaries/ \
    ':!local/ai/session_summaries/README.md' \
    local/ai/context_packs/ \
    local/ai/ai-nest/ \
    'local/ai/*/requests.log' \
    'local/ai/*/sessions.log' \
    'local/ai/*/*.session' 2>/dev/null | while IFS= read -r path; do
      [ -n "$path" ] && emit "NEEDS_DECISION" "ReportLocalOnlyTracked" "$path" "false" "Local-only/runtime path is tracked by git. Remove from index only after explicit user approval."
    done
}

report_legacy_credential_residue() {
  if path_present "$target/tmp/ai/cli_tokens"; then
    emit "NEEDS_DECISION" "ReportLegacyCredentialResidue" "tmp/ai/cli_tokens" "false" "Deprecated credential residue exists. Do not inspect or remove it without explicit user approval."
  fi
}

snippet_tmp=$(mktemp "${TMPDIR:-/tmp}/ai-bootstrap-snippet.XXXXXX")
readme_snippet > "$snippet_tmp"

ensure_agents_instructions
managed_files | while IFS= read -r rel; do ensure_managed_file "$rel"; done
ensure_if_missing_files | while IFS= read -r rel; do ensure_if_missing "$rel"; done
ensure_readme_snippet "README.md" "$snippet_tmp"
ensure_readme_snippet "README.en.md" "$snippet_tmp"
rm -f "$snippet_tmp"
ensure_exclude_lines
instruction_links | while IFS="$(printf '\t')" read -r rel rel_target; do
  [ -n "$rel" ] && ensure_instruction_link "$rel" "$rel_target"
done
ensure_skill_discovery_link ".agents/skills/ai-bootstrap-converge" "../../skills/ai-bootstrap-converge"
ensure_skill_discovery_link ".claude/skills/ai-bootstrap-converge" "../../skills/ai-bootstrap-converge"
report_local_only_tracked
report_legacy_credential_residue

if [ "$json" -eq 1 ]; then
  awk -F '\t' 'BEGIN { print "[" } {
    gsub(/\\/,"\\\\",$3); gsub(/"/,"\\\"",$3); gsub(/\\/,"\\\\",$5); gsub(/"/,"\\\"",$5);
    printf "%s{\"Status\":\"%s\",\"Type\":\"%s\",\"Path\":\"%s\",\"Safe\":%s,\"Detail\":\"%s\"}", sep, $1, $2, $3, $4, $5;
    sep=","
  } END { print "]" }' "$operations_file"
else
  printf '%-10s %-24s %-45s %s\n' "Status" "Type" "Path" "Detail"
  sort "$operations_file" | awk -F '\t' '{ printf "%-10s %-24s %-45s %s\n", $1, $2, $3, $5 }'
fi

if [ "$mode" = "Verify" ]; then
  if awk -F '\t' '$1 == "MISSING" || $1 == "DRIFT" || $1 == "CONFLICT" || $1 == "BLOCKED" || $1 == "NEEDS_DECISION" { found=1 } END { exit(found ? 0 : 1) }' "$operations_file"; then
    exit 1
  fi
fi

if [ "$mode" = "Apply" ]; then
  if awk -F '\t' '$1 == "CONFLICT" || $1 == "BLOCKED" { found=1 } END { exit(found ? 0 : 1) }' "$operations_file"; then
    exit 2
  fi
fi
