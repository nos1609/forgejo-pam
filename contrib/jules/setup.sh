#!/usr/bin/bash
# Jules environment setup for forgejo-pam. In Jules: repository > Configuration >
# Initial Setup, enter "bash contrib/jules/setup.sh", then Run and Snapshot.
# Keeps assistant state out of commits the same way local checkouts do (via
# .git/info/exclude, never .gitignore) and installs the checks this repository uses.
set -euo pipefail
sudo=""
[ "$(id -u)" -eq 0 ] || sudo="sudo"

exclude=$(git rev-parse --git-path info/exclude)
mkdir -p "$(dirname "$exclude")"
while IFS= read -r line; do
    grep -qxF -- "$line" "$exclude" 2>/dev/null || printf '%s\n' "$line" >>"$exclude"
done <<'LIST'
AGENTS.override.md
**/__pycache__/
*.py[cod]
local/ai/bootstrap.ready
local/ai/chat_context.md
local/ai/project_addenda.md
local/ai/session_history.md
local/ai/context_packs/
local/ai/session_summaries/*
!local/ai/session_summaries/README.md
local/ai/*/requests.log
local/ai/*/sessions.log
local/ai/*/*.session
local/ai/ai-nest/
tmp/ai/
LIST

$sudo apt-get update -qq
$sudo apt-get install -y -qq shellcheck >/dev/null
$sudo env GOBIN=/usr/local/bin go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.12

# The checks below are the ones that do not need Fedora: the RPM itself is
# validated by the COPR build of the pull request.
git diff --check
mapfile -t shell_scripts < <(git ls-files '*.sh')
[ "${#shell_scripts[@]}" -eq 0 ] || shellcheck "${shell_scripts[@]}"
mapfile -t py_scripts < <(git ls-files '*.py')
[ "${#py_scripts[@]}" -eq 0 ] || python3 -m py_compile "${py_scripts[@]}"
[ ! -d .github/workflows ] || actionlint
echo "forgejo-pam: Jules environment ready"
