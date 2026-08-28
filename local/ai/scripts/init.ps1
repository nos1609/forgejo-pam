#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\\..\\..")).Path
Set-Location $repoRoot
$script:IsWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$script:IsMacOSPlatform = $false
if (-not $script:IsWindowsPlatform) {
    $uname = Get-Command uname -ErrorAction SilentlyContinue
    if ($uname) { $script:IsMacOSPlatform = ((& $uname.Source -s 2>$null) -eq "Darwin") }
}

function Test-PathInsideRoot {
    param([string]$Path, [switch]$AllowLeafLink, [string]$Root = $repoRoot)
    $root = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath($Path)
    $comparison = if ($script:IsWindowsPlatform) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($candidate.Equals($root, $comparison)) { return $true }
    $prefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, $comparison)) {
        return $false
    }
    $relative = $candidate.Substring($prefix.Length)
    $parts = @($relative -split '[\\/]+' | Where-Object { $_ -and $_ -ne "." })
    $current = $root
    for ($index = 0; $index -lt $parts.Count; $index++) {
        if ($parts[$index] -eq "..") { return $false }
        $current = Join-Path $current $parts[$index]
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        $isLeaf = $index -eq ($parts.Count - 1)
        $linkType = if ($item.PSObject.Properties.Name -contains "LinkType") { [string]$item.LinkType } else { "" }
        if ($linkType -and -not ($AllowLeafLink -and $isLeaf)) { return $false }
        if (-not $isLeaf -and -not $item.PSIsContainer) { return $false }
    }
    return $true
}

function Test-SameFileIdentity([string]$first, [string]$second) {
    if ($script:IsWindowsPlatform) {
        if ([System.IO.Path]::GetPathRoot($first) -ne [System.IO.Path]::GetPathRoot($second)) { return $false }
        $firstId = & fsutil file queryfileid $first 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $secondId = & fsutil file queryfileid $second 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $firstMatch = [regex]::Match(($firstId -join " "), '0x[0-9a-fA-F]+')
        $secondMatch = [regex]::Match(($secondId -join " "), '0x[0-9a-fA-F]+')
        return $firstMatch.Success -and $secondMatch.Success -and $firstMatch.Value -eq $secondMatch.Value
    }
    $stat = Get-Command stat -ErrorAction SilentlyContinue
    if (-not $stat) { return $false }
    if ($script:IsMacOSPlatform) {
        $firstId = & $stat.Source -f '%d:%i' $first 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $secondId = & $stat.Source -f '%d:%i' $second 2>$null
    } else {
        $firstId = & $stat.Source -Lc '%d:%i' -- $first 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $secondId = & $stat.Source -Lc '%d:%i' -- $second 2>$null
    }
    return $LASTEXITCODE -eq 0 -and ([string]$firstId).Trim() -eq ([string]$secondId).Trim()
}

function Get-HardLinkCount([string]$Path) {
    if ($script:IsWindowsPlatform) {
        $links = @(& fsutil hardlink list $Path 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }
        return @($links | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
    }
    $stat = Get-Command stat -ErrorAction SilentlyContinue
    if (-not $stat) { return $null }
    $value = if ($script:IsMacOSPlatform) {
        & $stat.Source -f '%l' $Path 2>$null
    } else {
        & $stat.Source -Lc '%h' -- $Path 2>$null
    }
    if ($LASTEXITCODE -ne 0) { return $null }
    $count = 0
    if (-not [int]::TryParse(([string]$value).Trim(), [ref]$count)) { return $null }
    return $count
}

function Get-KnownInstructionPaths {
    return @(
        '.github/copilot-instructions.md',
        '.claude/CLAUDE.md',
        'CLAUDE.md',
        '.gemini/GEMINI.md',
        'GEMINI.md',
        '.qwen/QWEN.md',
        'QWEN.md'
    ) | ForEach-Object { Join-Path $repoRoot $_ }
}

function Test-AgentsHardlinksKnown {
    $agents = Join-Path $repoRoot 'AGENTS.md'
    $count = Get-HardLinkCount $agents
    if ($null -eq $count) { return $false }
    $known = 0
    foreach ($path in Get-KnownInstructionPaths) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and (Get-ItemLinkType $item) -eq 'HardLink' -and
            (Test-PathInsideRoot $path -AllowLeafLink) -and (Test-SameFileIdentity $path $agents)) {
            $known++
        }
    }
    return $count -eq ($known + 1)
}

function Write-TextAtomic {
    param([string]$Path, [string]$Text)

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $temporary = Join-Path $parent ('.ai-bootstrap-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporary, $Text, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Write-LinesAtomic {
    param([string]$Path, [string[]]$Lines)

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $temporary = Join-Path $parent ('.ai-bootstrap-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllLines($temporary, $Lines, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

$linkFailures = New-Object System.Collections.Generic.List[string]
$createdLinks = New-Object System.Collections.Generic.List[string]

function Get-ItemLinkType([System.IO.FileSystemInfo]$Item) {
    if ($Item.PSObject.Properties.Name -contains "LinkType") { return [string]$Item.LinkType }
    return ""
}

function Ensure-InstructionLink {
    param([string]$Relative, [string]$Expected, [switch]$Apply)
    $path = Join-Path $repoRoot $Relative
    if (-not (Test-PathInsideRoot $path -AllowLeafLink)) {
        $script:linkFailures.Add("${Relative}: destination or ancestor escapes the repository or is a link") | Out-Null
        return
    }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        $linkType = Get-ItemLinkType $item
        if ($linkType -eq "SymbolicLink" -and ([string]$item.Target).Replace("\", "/") -eq $Expected.Replace("\", "/")) { return }
        if ($linkType -eq "HardLink" -and (Test-SameFileIdentity $item.FullName (Join-Path $repoRoot "AGENTS.md"))) { return }
        $script:linkFailures.Add("$Relative contains project-owned instructions; preserve and merge them before replacing the path") | Out-Null
        return
    }
    if (-not $Apply) { return }
    $parent = Split-Path -Parent $path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    try {
        New-Item -ItemType SymbolicLink -Path $path -Target $Expected -ErrorAction Stop | Out-Null
        $script:createdLinks.Add($path) | Out-Null
    } catch {
        try {
            New-Item -ItemType HardLink -Path $path -Target (Join-Path $repoRoot "AGENTS.md") -ErrorAction Stop | Out-Null
            $script:createdLinks.Add($path) | Out-Null
        } catch {
            $script:linkFailures.Add("Could not create a symlink or hardlink for $Relative") | Out-Null
        }
    }
}

function Ensure-SkillLink {
    param([string]$Relative, [switch]$Apply)
    $expected = "../../skills/ai-bootstrap-converge"
    $path = Join-Path $repoRoot $Relative
    if (-not (Test-PathInsideRoot $path -AllowLeafLink)) {
        $script:linkFailures.Add("${Relative}: destination or ancestor escapes the repository or is a link") | Out-Null
        return
    }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        if ((Get-ItemLinkType $item) -eq "SymbolicLink" -and ([string]$item.Target).Replace("\", "/") -eq $expected) { return }
        $script:linkFailures.Add("$Relative exists but is not the required canonical skill symlink") | Out-Null
        return
    }
    if (-not $Apply) { return }
    $parent = Split-Path -Parent $path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    try {
        New-Item -ItemType SymbolicLink -Path $path -Target $expected -ErrorAction Stop | Out-Null
        $script:createdLinks.Add($path) | Out-Null
    } catch {
        $script:linkFailures.Add("Could not create the canonical skill symlink at $Relative") | Out-Null
    }
}

# Resolve every prerequisite before creating links or changing readiness.
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { throw "Git worktree is required before bootstrap can set local exclusions." }
$insideWorktree = & $git.Source rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or ([string]$insideWorktree).Trim() -ne "true") {
    throw "Git worktree is required before bootstrap can set local exclusions."
}
$reportedTopLevel = & $git.Source rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$reportedTopLevel)) {
    throw "Could not resolve the Git worktree root."
}
$gitTopLevel = [System.IO.Path]::GetFullPath(([string]$reportedTopLevel).Trim())
$rootComparison = if ($script:IsWindowsPlatform) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (-not [string]::Equals([System.IO.Path]::GetFullPath($repoRoot), $gitTopLevel, $rootComparison)) {
    throw "Bootstrap root must be the Git worktree root; parent Git metadata was not modified."
}
$legacyCredentialPath = Join-Path $repoRoot 'tmp/ai/cli_tokens'
if ($null -ne (Get-Item -LiteralPath $legacyCredentialPath -Force -ErrorAction SilentlyContinue)) {
    throw 'Deprecated credential residue exists at tmp/ai/cli_tokens. Do not inspect or remove it without explicit user approval.'
}
$reportedExclude = & $git.Source rev-parse --path-format=absolute --git-path info/exclude 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$reportedExclude)) {
    throw "Could not resolve the common Git exclude path."
}
$ignoreFile = [System.IO.Path]::GetFullPath(([string]$reportedExclude).Trim())
$reportedCommon = & $git.Source rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$reportedCommon)) {
    throw "Could not resolve the common Git directory."
}
$gitCommon = (Resolve-Path -LiteralPath ([string]$reportedCommon).Trim()).Path
if (-not (Test-PathInsideRoot $ignoreFile -Root $gitCommon)) {
    throw "Git exclude path or ancestor is a link or escapes the common Git directory."
}

$runtimePatterns = @(
    'AGENTS.override.md',
    '.codex/',
    'tmp/ai/',
    'local/ai/bootstrap.ready',
    'local/ai/chat_context.md',
    'local/ai/project_addenda.md',
    'local/ai/session_history.md',
    'local/ai/context_packs/',
    'local/ai/session_summaries/',
    ':!local/ai/session_summaries/README.md',
    'local/ai/ai-nest/',
    'local/ai/*/requests.log',
    'local/ai/*/sessions.log',
    'local/ai/*/*.session'
)
$trackedRuntime = @(& $git.Source -C $repoRoot ls-files -- $runtimePatterns 2>$null |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($trackedRuntime.Count -gt 0) {
    throw "Mutable runtime paths are tracked by Git; converge them out of the index before init: $($trackedRuntime -join ', ')"
}

foreach ($sourceRelative in @("AGENTS.md", "README_snippet.md")) {
    $sourcePath = Join-Path $repoRoot $sourceRelative
    $sourceItem = Get-Item -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue
    $sourceLinkType = if ($null -ne $sourceItem) { Get-ItemLinkType $sourceItem } else { "" }
    $allowedAgentsHardLink = $sourceRelative -eq "AGENTS.md" -and $sourceLinkType -eq "HardLink"
    $safeSourcePath = if ($allowedAgentsHardLink) { Test-PathInsideRoot $sourcePath -AllowLeafLink } else { Test-PathInsideRoot $sourcePath }
    if ($null -eq $sourceItem -or $sourceItem.PSIsContainer -or
        ($sourceLinkType -and -not $allowedAgentsHardLink) -or -not $safeSourcePath) {
        throw "$sourceRelative must be a regular non-symlink file inside the repository."
    }
}
if (-not (Test-AgentsHardlinksKnown)) {
    throw 'AGENTS.md has a hardlink outside the known instruction-link set.'
}
$agentsText = [System.IO.File]::ReadAllText((Join-Path $repoRoot "AGENTS.md"), [System.Text.Encoding]::UTF8)
$agentsBegin = "<!-- AI AGENT INSTRUCTIONS BEGIN -->"
$agentsEnd = "<!-- AI AGENT INSTRUCTIONS END -->"
$agentsBeginMatches = [regex]::Matches($agentsText, "(?m)^$([regex]::Escape($agentsBegin))\r?$")
$agentsEndMatches = [regex]::Matches($agentsText, "(?m)^$([regex]::Escape($agentsEnd))\r?$")
if ($agentsBeginMatches.Count -ne 1 -or $agentsEndMatches.Count -ne 1 -or
    $agentsBeginMatches[0].Index -ne 0 -or $agentsEndMatches[0].Index -le $agentsBeginMatches[0].Index) {
    throw "AGENTS.md must contain one complete managed instruction block at the top."
}
$skillSource = Join-Path $repoRoot "skills/ai-bootstrap-converge"
$skillItem = Get-Item -LiteralPath $skillSource -Force -ErrorAction SilentlyContinue
if ($null -eq $skillItem -or -not $skillItem.PSIsContainer -or (Get-ItemLinkType $skillItem) -or -not (Test-PathInsideRoot $skillSource)) {
    throw "skills/ai-bootstrap-converge must be a non-symlink directory inside the repository."
}
$linkedSkillChild = Get-ChildItem -LiteralPath $skillSource -Recurse -Force |
    Where-Object { Get-ItemLinkType $_ } |
    Select-Object -First 1
if ($null -ne $linkedSkillChild) {
    throw "skills/ai-bootstrap-converge must not contain symlinked children."
}
$destinationRelatives = New-Object System.Collections.Generic.List[string]
foreach ($relative in @('README.md', 'README.en.md', 'local/ai/bootstrap.ready', 'local/ai/chat_context.md')) {
    $destinationRelatives.Add($relative) | Out-Null
}
foreach ($assistant in @('gemini', 'qwen', 'codex', 'copilot', 'claude')) {
    $destinationRelatives.Add("local/ai/$assistant/sessions.log") | Out-Null
    $destinationRelatives.Add("local/ai/$assistant/requests.log") | Out-Null
}
foreach ($destinationRelative in $destinationRelatives) {
    $destinationPath = Join-Path $repoRoot $destinationRelative
    if (-not (Test-PathInsideRoot $destinationPath -AllowLeafLink)) {
        throw "${destinationRelative}: destination or ancestor escapes the repository or is a link."
    }
    $destinationItem = Get-Item -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $destinationItem -and $destinationItem.PSIsContainer) {
        throw "$destinationRelative must be a regular non-symlink file when present."
    }
    if ($null -ne $destinationItem) {
        $linkCount = Get-HardLinkCount $destinationPath
        if ((Get-ItemLinkType $destinationItem) -or $null -eq $linkCount -or $linkCount -ne 1) {
            throw "$destinationRelative is a symlink or hardlink; refusing to mutate shared file content."
        }
    }
}
$snippet = [System.IO.File]::ReadAllText((Resolve-Path "README_snippet.md"), [System.Text.Encoding]::UTF8)
$protocolTrigger = "AI AGENT PROTOCOL TRIGGER"

function Test-ProtocolCommentSignature {
    param([string]$Text)

    $commentEnd = $Text.IndexOf("-->", [System.StringComparison]::Ordinal)
    if ($commentEnd -lt 0) { return $false }
    $comment = $Text.Substring(0, $commentEnd + 3)
    $lines = @($comment -split "\r?\n")
    if ($lines.Count -eq 0 -or $lines[0] -cne "<!--") { return $false }

    foreach ($required in @(
        "AI AGENT PROTOCOL TRIGGER:",
        "SIGNAL: STARTUP_PROTOCOL_TRIGGER",
        "TARGET: AGENTS.md",
        "ACTION: Follow startup protocol immediately"
    )) {
        if (@($lines | Where-Object { $_ -ceq $required }).Count -ne 1) { return $false }
    }
    return $true
}

function Test-PreviousReadmeProtocol {
    param([string]$Text, [string]$Snippet)

    if ([regex]::Matches($Text, [regex]::Escape($protocolTrigger)).Count -ne 1) { return $false }
    return (Test-ProtocolCommentSignature $Snippet) -and (Test-ProtocolCommentSignature $Text)
}

foreach ($readmeRelative in @("README.md", "README.en.md")) {
    $readmePath = Join-Path $repoRoot $readmeRelative
    if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) { continue }
    $readme = [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8)
    if (-not $readme.StartsWith($snippet) -and $readme.Contains($protocolTrigger)) {
        $safePreviousSnippet = Test-PreviousReadmeProtocol $readme $snippet
        if (-not $safePreviousSnippet) {
            throw "$readmeRelative contains a conflicting, misplaced, or incomplete historical agent protocol snippet; preserve the body and reconcile the snippet before continuing."
        }
    }
}

# Preflight every instruction path before creating any link.
$links = @(
    @{ Path = ".github/copilot-instructions.md"; Target = "../AGENTS.md" },
    @{ Path = ".claude/CLAUDE.md"; Target = "../AGENTS.md" },
    @{ Path = "CLAUDE.md"; Target = "AGENTS.md" },
    @{ Path = ".gemini/GEMINI.md"; Target = "../AGENTS.md" },
    @{ Path = "GEMINI.md"; Target = "AGENTS.md" },
    @{ Path = "QWEN.md"; Target = "AGENTS.md" },
    @{ Path = ".qwen/QWEN.md"; Target = "../AGENTS.md" }
)
foreach ($link in $links) {
    Ensure-InstructionLink $link.Path $link.Target
}
foreach ($path in @(".agents/skills/ai-bootstrap-converge", ".claude/skills/ai-bootstrap-converge")) {
    Ensure-SkillLink $path
}
if ($linkFailures.Count -gt 0) {
    foreach ($failure in $linkFailures) { Write-Error $failure -ErrorAction Continue }
    throw "Bootstrap stopped before readiness changes because instruction conflicts remain."
}

foreach ($link in $links) {
    Ensure-InstructionLink $link.Path $link.Target -Apply
}
foreach ($path in @(".agents/skills/ai-bootstrap-converge", ".claude/skills/ai-bootstrap-converge")) {
    Ensure-SkillLink $path -Apply
}
if ($linkFailures.Count -gt 0) {
    foreach ($created in $createdLinks) {
        Remove-Item -LiteralPath $created -Force -ErrorAction SilentlyContinue
    }
    foreach ($failure in $linkFailures) { Write-Error $failure -ErrorAction Continue }
    throw "Bootstrap could not create every required link; newly created links were rolled back."
}

function Get-ExcludePatterns {
    return @(
        '.codex/',
        'AGENTS.override.md',
        'local/ai/bootstrap.ready',
        'local/ai/chat_context.md',
        'local/ai/project_addenda.md',
        'local/ai/session_history.md',
        'local/ai/context_packs/',
        'local/ai/session_summaries/*',
        '!local/ai/session_summaries/README.md',
        'local/ai/*/requests.log',
        'local/ai/*/sessions.log',
        'local/ai/*/*.session',
        'local/ai/ai-nest/',
        'tmp/ai/'
    )
}

$patterns = Get-ExcludePatterns
$legacyExcludeEntries = @(
    '.gemini/',
    '.claude/',
    '.github/copilot-instructions.md',
    '.qwen/',
    'AGENTS.md',
    'CLAUDE.md',
    'GEMINI.md',
    'local/ai/',
    'QWEN.md',
    'README_snippet.md'
)
$excludeLines = if (Test-Path -LiteralPath $ignoreFile -PathType Leaf) {
    @(Get-Content -LiteralPath $ignoreFile)
} else {
    @()
}
$excludeChanged = $false
foreach ($entry in $legacyExcludeEntries) {
    if ($excludeLines -ccontains $entry) {
        Write-Host "Removed obsolete scaffold-wide exclude entry '$entry' from $ignoreFile"
        $excludeChanged = $true
    }
}
if ($excludeChanged) {
    $excludeLines = @($excludeLines | Where-Object { -not ($legacyExcludeEntries -ccontains $_) })
}
foreach ($entry in $patterns) {
    if ($excludeLines -cnotcontains $entry) {
        $excludeLines += $entry
        $excludeChanged = $true
        Write-Host "Added '$entry' to $ignoreFile"
    }
}
if ($excludeChanged) {
    Write-LinesAtomic $ignoreFile ([string[]]$excludeLines)
}

function Set-ReadmeSnippet {
    param([string]$Relative, [switch]$Required)
    $path = Join-Path $repoRoot $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if ($Required) {
            Write-TextAtomic $path ($snippet.TrimEnd() + [Environment]::NewLine)
        }
        return
    }
    $readmePath = (Resolve-Path $path).Path
    $readme = [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8)
    if (-not $readme.StartsWith($snippet)) {
        if ($readme.Contains($protocolTrigger)) {
            $commentEnd = $readme.IndexOf("-->", [System.StringComparison]::Ordinal)
            $safePreviousSnippet = Test-PreviousReadmeProtocol $readme $snippet
            if (-not $safePreviousSnippet) {
                throw "$Relative contains a conflicting, misplaced, or incomplete historical agent protocol snippet; preserve the body and reconcile the snippet before continuing."
            }
            $body = $readme.Substring($commentEnd + 3).TrimStart([char[]]"`r`n")
            Write-TextAtomic $readmePath ($snippet.TrimEnd([char[]]"`r`n") + [Environment]::NewLine + [Environment]::NewLine + $body)
            return
        }
        Write-TextAtomic $readmePath ($snippet.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $readme)
    }
}

Set-ReadmeSnippet "README.md" -Required
Set-ReadmeSnippet "README.en.md"

foreach ($assistant in @('gemini', 'qwen', 'codex', 'copilot', 'claude')) {
    $directory = Join-Path $repoRoot "local/ai/$assistant"
    $sessions = Join-Path $directory 'sessions.log'
    $requests = Join-Path $directory 'requests.log'
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if (-not (Test-Path -LiteralPath $sessions -PathType Leaf)) {
        Write-TextAtomic $sessions ('{"session_id":"sample-' + $assistant + '-session","started_at":"YYYY-MM-DDTHH:MM:SSZ","assistant":"' + $assistant + '","language":"<lang>","gender":"<f/m/neutral>","logging_precision":"ISO8601Z"}' + [Environment]::NewLine)
    }
    if (-not (Test-Path -LiteralPath $requests -PathType Leaf)) {
        Write-TextAtomic $requests ('{"timestamp":"YYYY-MM-DDTHH:MM:SSZ","request_id":"sample-' + $assistant + '-req-001","assistant":"' + $assistant + '","summary":"placeholder summary","tools":[],"status":"success"}' + [Environment]::NewLine)
    }
}

# Readiness marker
New-Item -ItemType Directory -Force "local/ai" | Out-Null
$readyLines = @('true') + @($patterns)
Write-LinesAtomic (Join-Path $repoRoot "local/ai/bootstrap.ready") ([string[]]$readyLines)
Write-Host "local/ai/bootstrap.ready set"

# Ensure readiness block exists in chat_context.
$chatContext = "local/ai/chat_context.md"
if (Test-Path -LiteralPath $chatContext) {
    if (-not (Select-String -LiteralPath $chatContext -Pattern "## Статус готовности / Readiness status" -SimpleMatch -Quiet)) {
        $block = @"
## Статус готовности / Readiness status
- `status`: `pending`
- `last_verified_at`: `YYYY-MM-DDTHH:MM:SSZ`
- `agents_md_hash`: `sha256:<fill-after-bootstrap>`
- **RU:** После выполнения bootstrap-проверок обнови статус на `completed`, зафиксируй время (UTC) и актуальный хеш `AGENTS.md`; когда протокол пересматривается, перезапиши значения.
  **EN:** Once bootstrap checks pass, switch the status to `completed`, record the UTC timestamp, and store the current `AGENTS.md` hash; refresh the fields whenever the protocol is revisited.

"@
        $existing = [System.IO.File]::ReadAllText((Join-Path $repoRoot $chatContext), [System.Text.Encoding]::UTF8)
        Write-TextAtomic (Join-Path $repoRoot $chatContext) ($block + $existing)
        Write-Host "Readiness block injected into $chatContext"
    }
}

Write-Host "Agent scaffold bootstrap complete."
