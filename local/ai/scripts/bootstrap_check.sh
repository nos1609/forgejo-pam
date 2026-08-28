#!/usr/bin/env bash
# RU: Проверяет базовые bootstrap-требования (README комментарий, симлинки, .git/info/exclude, логи).
# EN: Verifies baseline bootstrap requirements (README comment, symlinks, .git/info/exclude, logs).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
cd "$REPO_ROOT"

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

file_has_single_link() {
  local count
  if count=$(stat -Lc '%h' -- "$1" 2>/dev/null); then
    [[ "$count" -eq 1 ]]
    return
  fi
  count=$(stat -f '%l' "$1" 2>/dev/null) || return 1
  [[ "$count" -eq 1 ]]
}

ok() {
  echo "[OK] $1 / $2"
}

fail() {
  echo "[FAIL] $1 / $2"
  failures+=("$2")
}

failures=()
bootstrap_marker=""

if [[ -e "$REPO_ROOT/tmp/ai/cli_tokens" || -L "$REPO_ROOT/tmp/ai/cli_tokens" ]]; then
  fail "Обнаружен устаревший путь с учётными данными tmp/ai/cli_tokens; не читайте и не удаляйте его без явного подтверждения пользователя" "Deprecated credential residue exists at tmp/ai/cli_tokens; do not inspect or remove it without explicit user approval"
fi

check_readme() {
  if [[ ! -f README_snippet.md || -L README_snippet.md ]] ||
    ! path_tree_is_safe "$REPO_ROOT/README_snippet.md" ||
    ! file_has_single_link README_snippet.md; then
    fail "README_snippet.md отсутствует или небезопасен" "README_snippet.md missing or unsafe"
    return
  fi
  local snippet_size
  snippet_size=$(wc -c < README_snippet.md)
  local readme
  for readme in README.md README.en.md; do
    if [[ "$readme" == "README.en.md" && ! -e "$readme" && ! -L "$readme" ]]; then
      continue
    fi
    if [[ ! -f "$readme" || -L "$readme" ]] ||
      ! path_tree_is_safe "$REPO_ROOT/$readme" ||
      ! file_has_single_link "$readme"; then
      fail "$readme отсутствует или небезопасен" "$readme missing or unsafe"
      continue
    fi
    if head -c "$snippet_size" "$readme" | cmp -s README_snippet.md -; then
      ok "$readme начинается с точного скрытого фрагмента" "$readme starts with the exact hidden snippet"
    else
      fail "$readme не начинается с точного скрытого фрагмента" "$readme does not start with the exact hidden snippet"
    fi
  done
}

check_symlink() {
  local path=$1
  local expected=$2
  if ! path_tree_is_safe "$REPO_ROOT/$path" 1; then
    fail "$path имеет небезопасный путь" "$path has an unsafe path or ancestor"
  elif [[ -L "$path" ]] && [[ "$(readlink "$path")" == "$expected" ]]; then
    ok "$path указывает на AGENTS.md" "$path -> $expected"
  elif [[ -f "$path" && -f AGENTS.md && "$path" -ef AGENTS.md ]]; then
    ok "$path является hardlink на AGENTS.md" "$path is a hardlink to AGENTS.md"
  else
    fail "$path не связан с AGENTS.md точной ссылкой" "$path does not use the required AGENTS.md link"
  fi
}

check_symlinks() {
  # RU: Прогоняем все обязательные симлинки ассистентов.
  # EN: Iterate through all required assistant symlinks.
  if [[ ! -f AGENTS.md || -L AGENTS.md ]] || ! path_tree_is_safe "$REPO_ROOT/AGENTS.md"; then
    fail "AGENTS.md отсутствует или небезопасен" "AGENTS.md missing or unsafe"
  elif awk '
    {
      line=$0
      sub(/\r$/, "", line)
      if (line == "<!-- AI AGENT INSTRUCTIONS BEGIN -->") { begin_count++; begin_line=NR }
      if (line == "<!-- AI AGENT INSTRUCTIONS END -->") { end_count++; end_line=NR }
    }
    END { exit(begin_count == 1 && end_count == 1 && begin_line == 1 && end_line > begin_line ? 0 : 1) }
  ' AGENTS.md; then
    ok "AGENTS.md содержит один управляемый блок в начале" "AGENTS.md has one managed block at the top"
  else
    fail "AGENTS.md не содержит один полный управляемый блок в начале" "AGENTS.md does not have one complete managed block at the top"
  fi

  local skill_source_safe=1
  if [[ ! -d skills/ai-bootstrap-converge || -L skills/ai-bootstrap-converge ]] ||
    ! path_tree_is_safe "$REPO_ROOT/skills/ai-bootstrap-converge" ||
    [[ -n "$(find skills/ai-bootstrap-converge -type l -print -quit 2>/dev/null)" ]]; then
    fail "Канонический каталог skill отсутствует или небезопасен" "Canonical skill directory missing or unsafe"
    skill_source_safe=0
  fi

  local links=(
    ".github/copilot-instructions.md|../AGENTS.md"
    ".claude/CLAUDE.md|../AGENTS.md"
    "CLAUDE.md|AGENTS.md"
    ".gemini/GEMINI.md|../AGENTS.md"
    "GEMINI.md|AGENTS.md"
    "QWEN.md|AGENTS.md"
    ".qwen/QWEN.md|../AGENTS.md"
  )
  local item path expected
  for item in "${links[@]}"; do
    path=${item%%|*}
    expected=${item#*|}
    check_symlink "$path" "$expected"
  done

  local skill_links=(
    ".agents/skills/ai-bootstrap-converge|../../skills/ai-bootstrap-converge"
    ".claude/skills/ai-bootstrap-converge|../../skills/ai-bootstrap-converge"
  )
  for item in "${skill_links[@]}"; do
    path=${item%%|*}
    expected=${item#*|}
    if [[ "$skill_source_safe" -eq 1 ]] && path_tree_is_safe "$REPO_ROOT/$path" 1 && [[ -L "$path" ]] && [[ "$(readlink "$path")" == "$expected" ]]; then
      ok "$path указывает на канонический skill" "$path uses the canonical skill link"
    else
      fail "$path не использует точную ссылку на канонический skill" "$path does not use the required canonical skill link"
    fi
  done
}

load_patterns_from_bootstrap_ready() {
  local file="local/ai/bootstrap.ready"
  patterns=()
  bootstrap_marker=""
  if [[ ! -f "$file" || -L "$file" ]] ||
    ! path_tree_is_safe "$REPO_ROOT/$file" ||
    ! file_has_single_link "$file"; then
    fail "local/ai/bootstrap.ready отсутствует или небезопасен" "local/ai/bootstrap.ready missing or unsafe"
    return 1
  fi
  local first_entry=1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$first_entry" -eq 1 ]]; then
      first_entry=0
      if [[ "$line" != "true" && "$line" != "false" ]]; then
        fail "local/ai/bootstrap.ready должен начинаться с true или false" "local/ai/bootstrap.ready must start with true or false"
        return 1
      fi
      bootstrap_marker=$line
      continue
    fi
    if [[ "$line" == "true" || "$line" == "false" ]]; then
      fail "local/ai/bootstrap.ready содержит повторный маркер" "local/ai/bootstrap.ready contains a duplicate marker"
      return 1
    fi
    patterns+=("$line")
  done < "$file"
  if [[ "$bootstrap_marker" == "false" ]]; then
    fail "Bootstrap ещё не завершён" "Bootstrap is not completed yet"
    return 1
  fi
  if [[ ${#patterns[@]} -eq 0 ]]; then
    fail "local/ai/bootstrap.ready не содержит списка exclude" "local/ai/bootstrap.ready missing exclude list"
    return 1
  fi
  return 0
}

check_gitignore() {
  # RU: Убеждаемся, что .git/info/exclude скрывает служебные файлы ассистента.
  # EN: Confirm .git/info/exclude hides all assistant artifacts.
  local ignore_file=""
  local git_common=""
  if ! load_patterns_from_bootstrap_ready; then
    return
  fi
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ignore_file=$(git rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null || true)
    git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  fi
  if [[ -n "$ignore_file" && -f "$ignore_file" ]]; then
    :
  elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "Файл .git/info/exclude отсутствует" ".git/info/exclude missing"
    return
  else
    fail "Git не инициализирован" "Git worktree is required"
    return
  fi
  if [[ -z "$git_common" ]] || ! git_common=$(cd "$git_common" 2>/dev/null && pwd -P) || ! path_tree_is_safe_under "$git_common" "$ignore_file"; then
    fail "Путь Git exclude небезопасен" "Git exclude path or ancestor is unsafe"
    return
  fi
  local missing=0
  for pat in "${patterns[@]}"; do
    if ! grep -Fxq "$pat" "$ignore_file"; then
      fail "$ignore_file не содержит $pat" "$ignore_file missing $pat"
      missing=1
    fi
  done
  local obsolete
  for obsolete in \
    '.gemini/' \
    '.claude/' \
    '.github/copilot-instructions.md' \
    '.qwen/' \
    'AGENTS.md' \
    'CLAUDE.md' \
    'GEMINI.md' \
    'local/ai/' \
    'QWEN.md' \
    'README_snippet.md'; do
    if grep -Fxq "$obsolete" "$ignore_file"; then
      fail "$ignore_file содержит устаревшее широкое исключение $obsolete" "$ignore_file contains obsolete scaffold-wide entry $obsolete"
      missing=1
    fi
  done
  if [[ $missing -eq 0 ]]; then
    ok "$ignore_file скрывает только изменяемое локальное состояние" "$ignore_file covers mutable local state only"
  fi
}

check_logs() {
  shopt -s nullglob
  local logs=(local/ai/*/{sessions.log,requests.log})
  if [[ ${#logs[@]} -eq 0 ]]; then
    fail "Логи ассистентов не найдены" "No assistant logs found in local/ai/*/{sessions,requests}.log"
    return
  fi

  local python=""
  if command -v python3 >/dev/null 2>&1; then
    python=python3
  elif command -v python >/dev/null 2>&1; then
    python=python
  else
    fail "JSON-парсер Python недоступен" "Python JSON parser unavailable"
    return
  fi

  local validator="skills/ai-bootstrap-converge/scripts/validate_logs.py"
  if [[ ! -f "$validator" || -L "$validator" ]] || ! path_tree_is_safe "$REPO_ROOT/$validator"; then
    fail "$validator отсутствует или небезопасен" "$validator missing or unsafe"
    return
  fi

  local log
  for log in "${logs[@]}"; do
    if [[ -L "$log" ]] || ! path_tree_is_safe "$REPO_ROOT/$log" || ! file_has_single_link "$log"; then
      fail "$log имеет небезопасный путь" "$log has an unsafe path or ancestor"
      return
    fi
  done

  local error_output
  if error_output=$("$python" "$validator" "${logs[@]}" 2>&1); then
    for log in "${logs[@]}"; do
      ok "$log содержит корректный JSONL" "$log JSONL schema valid"
    done
  else
    fail "Журналы не прошли JSONL-проверку: $error_output" "Assistant log JSONL validation failed"
  fi
}

check_readme
check_symlinks
check_gitignore
check_logs

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "Bootstrap проверка провалена / Bootstrap check failed: ${failures[*]}"
  exit 1
fi

echo "Bootstrap проверка пройдена / Bootstrap check passed"
