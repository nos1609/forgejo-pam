#!/usr/bin/env pwsh
# RU: Скрипт проверяет README-комментарий, симлинки, .git/info/exclude и гигиену логов ассистентов.
# EN: Script validates README comment, symlinks, .git/info/exclude, and assistant log hygiene.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = @()
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\..\..')).Path
Set-Location $repoRoot
$script:IsWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$script:IsMacOSPlatform = $false
if (-not $script:IsWindowsPlatform) {
    $uname = Get-Command uname -ErrorAction SilentlyContinue
    if ($uname) { $script:IsMacOSPlatform = ((& $uname.Source -s 2>$null) -eq "Darwin") }
}
function Get-ItemLinkType([System.IO.FileSystemInfo]$Item) {
    if ($Item.PSObject.Properties.Name -contains "LinkType") { return [string]$Item.LinkType }
    return ""
}

function Test-PathTreeSafe {
    param([string]$Path, [switch]$AllowLeafLink, [string]$Root = $repoRoot)
    $rootPath = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath($Path)
    $comparison = if ($script:IsWindowsPlatform) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($candidate.Equals($rootPath, $comparison)) { return $true }
    $prefix = $rootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, $comparison)) { return $false }
    $relative = $candidate.Substring($prefix.Length)
    $parts = @($relative -split '[\\/]+' | Where-Object { $_ -and $_ -ne "." })
    $current = $rootPath
    for ($index = 0; $index -lt $parts.Count; $index++) {
        if ($parts[$index] -eq "..") { return $false }
        $current = Join-Path $current $parts[$index]
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        $isLeaf = $index -eq ($parts.Count - 1)
        if ((Get-ItemLinkType $item) -and -not ($AllowLeafLink -and $isLeaf)) { return $false }
        if (-not $isLeaf -and -not $item.PSIsContainer) { return $false }
    }
    return $true
}

function Write-Ok([string]$ru, [string]$en) {
    Write-Host "[OK] $ru / $en"
}

function Write-Fail([string]$ru, [string]$en) {
    Write-Host "[FAIL] $ru / $en"
    $script:failures += $en
}

$legacyCredentialPath = Join-Path $repoRoot 'tmp/ai/cli_tokens'
if ($null -ne (Get-Item -LiteralPath $legacyCredentialPath -Force -ErrorAction SilentlyContinue)) {
    Write-Fail 'Обнаружен устаревший путь с учётными данными tmp/ai/cli_tokens; не читайте и не удаляйте его без явного подтверждения пользователя' 'Deprecated credential residue exists at tmp/ai/cli_tokens; do not inspect or remove it without explicit user approval'
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

function Test-IsoUtc([object]$value) {
    return $value -is [string] -and [regex]::IsMatch(
        $value,
        '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
}

function Test-OrdinalEqual([object]$first, [object]$second) {
    return $first -is [string] -and
        $second -is [string] -and
        [string]::Equals($first, $second, [System.StringComparison]::Ordinal)
}

function Test-ContainsOrdinal([string[]]$values, [string]$expected) {
    foreach ($value in $values) {
        if ([string]::Equals($value, $expected, [System.StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Assert-UniqueJsonObjectKeys([string]$json, [string]$source) {
    # ConvertFrom-Json keeps the last duplicate, so inspect object keys before normal parsing.
    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    for ($index = 0; $index -lt $json.Length; $index++) {
        $character = $json[$index]
        if ($character -eq '{') {
            $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            $stack.Push([pscustomobject]@{ Kind = 'object'; Keys = $keys })
            continue
        }
        if ($character -eq '[') {
            $stack.Push([pscustomobject]@{ Kind = 'array'; Keys = $null })
            continue
        }
        if ($character -eq '}' -or $character -eq ']') {
            if ($stack.Count -gt 0) { [void]$stack.Pop() }
            continue
        }
        if ($character -ne '"') { continue }

        $start = $index
        $escaped = $false
        $closed = $false
        for ($cursor = $index + 1; $cursor -lt $json.Length; $cursor++) {
            $current = $json[$cursor]
            if ($escaped) {
                $escaped = $false
                continue
            }
            if ($current -eq '\') {
                $escaped = $true
                continue
            }
            if ($current -eq '"') {
                $closed = $true
                break
            }
        }
        if (-not $closed) { return }

        $index = $cursor
        $next = $cursor + 1
        while ($next -lt $json.Length -and [char]::IsWhiteSpace($json[$next])) { $next++ }
        if ($stack.Count -eq 0 -or $stack.Peek().Kind -ne 'object' -or
            $next -ge $json.Length -or $json[$next] -ne ':') {
            continue
        }

        try {
            $keyLiteral = $json.Substring($start, $cursor - $start + 1)
            $key = ('{"key":' + $keyLiteral + '}') | ConvertFrom-Json -ErrorAction Stop |
                Select-Object -ExpandProperty key
        } catch {
            return
        }
        if ($key -is [string] -and -not $stack.Peek().Keys.Add($key)) {
            throw "$source duplicate JSON key: $key"
        }
    }
}

function Assert-Fields([pscustomobject]$entry, [string[]]$required, [string]$source) {
    $properties = [string[]]@($entry.PSObject.Properties.Name)
    $missing = @()
    foreach ($field in $required) {
        if (-not (Test-ContainsOrdinal $properties $field)) { $missing += $field }
    }
    if ($missing.Count -gt 0) {
        throw "$source missing fields: $($missing -join ', ')"
    }
}

function Assert-ExactPlaceholder([pscustomobject]$entry, [hashtable]$expected, [string]$source) {
    $actualNames = [string[]]@($entry.PSObject.Properties.Name)
    $expectedNames = [string[]]@($expected.Keys)
    if ($actualNames.Count -ne $expectedNames.Count) {
        throw "$source placeholder fields differ from the canonical sample"
    }
    Assert-Fields $entry $expectedNames $source
    foreach ($name in $expected.Keys) {
        $actual = $entry.$name
        $wanted = $expected[$name]
        if ($wanted -is [array]) {
            if ($actual -isnot [array] -or @($actual).Count -ne 0) {
                throw "$source placeholder field '$name' differs from the canonical sample"
            }
        } elseif ($wanted -is [string] -and -not (Test-OrdinalEqual $actual $wanted)) {
            throw "$source placeholder field '$name' differs from the canonical sample"
        } elseif ($wanted -isnot [string] -and -not [object]::Equals($actual, $wanted)) {
            throw "$source placeholder field '$name' differs from the canonical sample"
        }
    }
}

function Assert-LogEntry([pscustomobject]$entry, [string]$kind, [string]$assistant, [string]$source) {
    if ($kind -eq "sessions.log") {
        $fields = @("session_id", "started_at", "assistant", "language", "gender", "logging_precision")
        Assert-Fields $entry $fields $source
        if (-not (Test-OrdinalEqual $entry.assistant $assistant)) { throw "$source assistant must equal directory name '$assistant'" }
        if ($entry.session_id -isnot [string] -or -not $entry.session_id) { throw "$source session_id must be a non-empty string" }
        foreach ($field in @("language", "gender", "logging_precision")) {
            if ($entry.$field -isnot [string] -or -not $entry.$field) { throw "$source $field must be a non-empty string" }
        }
        if (Test-OrdinalEqual $entry.started_at "YYYY-MM-DDTHH:MM:SSZ") {
            Assert-ExactPlaceholder $entry @{
                session_id = "sample-$assistant-session"
                started_at = "YYYY-MM-DDTHH:MM:SSZ"
                assistant = $assistant
                language = "<lang>"
                gender = "<f/m/neutral>"
                logging_precision = "ISO8601Z"
            } $source
        } elseif (-not (Test-IsoUtc $entry.started_at)) {
            throw "$source started_at must use ISO 8601 UTC"
        }
        return
    }

    $fields = @("timestamp", "request_id", "assistant", "summary", "tools", "status")
    Assert-Fields $entry $fields $source
    if (-not (Test-OrdinalEqual $entry.assistant $assistant)) { throw "$source assistant must equal directory name '$assistant'" }
    if ($entry.request_id -isnot [string] -or -not $entry.request_id) { throw "$source request_id must be a non-empty string" }
    if ($entry.summary -isnot [string] -or -not $entry.summary) { throw "$source summary must be a non-empty string" }
    if ($entry.tools -isnot [array]) { throw "$source tools must be an array" }
    if ($entry.status -isnot [string] -or -not $entry.status) { throw "$source status must be a non-empty string" }
    if (Test-OrdinalEqual $entry.timestamp "YYYY-MM-DDTHH:MM:SSZ") {
        Assert-ExactPlaceholder $entry @{
            timestamp = "YYYY-MM-DDTHH:MM:SSZ"
            request_id = "sample-$assistant-req-001"
            assistant = $assistant
            summary = "placeholder summary"
            tools = @()
            status = "success"
        } $source
    } elseif (-not (Test-IsoUtc $entry.timestamp)) {
        throw "$source timestamp must use ISO 8601 UTC"
    }
}

if (-not (Test-Path README_snippet.md -PathType Leaf) -or -not (Test-PathTreeSafe (Join-Path $repoRoot "README_snippet.md"))) {
    Write-Fail "README_snippet.md не найден или небезопасен" "README_snippet.md missing or unsafe"
} else {
    $snippet = [System.IO.File]::ReadAllText((Resolve-Path README_snippet.md), [System.Text.Encoding]::UTF8)
    foreach ($relative in @("README.md", "README.en.md")) {
        $path = Join-Path $repoRoot $relative
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($relative -eq "README.en.md" -and $null -eq $item) { continue }
        if ($null -eq $item -or $item.PSIsContainer -or (Get-ItemLinkType $item) -or -not (Test-PathTreeSafe $path)) {
            Write-Fail "$relative не найден или небезопасен" "$relative missing or unsafe"
            continue
        }
        $readme = [System.IO.File]::ReadAllText($item.FullName, [System.Text.Encoding]::UTF8)
        if ($readme.StartsWith($snippet)) {
            Write-Ok "$relative начинается с точного скрытого фрагмента" "$relative starts with the exact hidden snippet"
        } else {
            Write-Fail "$relative не начинается с точного скрытого фрагмента" "$relative does not start with the exact hidden snippet"
        }
    }
}

$agentsSource = Get-Item -LiteralPath (Join-Path $repoRoot "AGENTS.md") -Force -ErrorAction SilentlyContinue
$agentsSourceLinkType = if ($null -ne $agentsSource) { Get-ItemLinkType $agentsSource } else { "" }
$agentsSourceSafe = $null -ne $agentsSource -and -not $agentsSource.PSIsContainer -and
    (-not $agentsSourceLinkType -or $agentsSourceLinkType -eq "HardLink") -and
    (Test-PathTreeSafe $agentsSource.FullName -AllowLeafLink)
if (-not $agentsSourceSafe) {
    Write-Fail "AGENTS.md отсутствует или небезопасен" "AGENTS.md missing or unsafe"
} else {
    $agentsText = [System.IO.File]::ReadAllText($agentsSource.FullName, [System.Text.Encoding]::UTF8)
    $beginMarker = "<!-- AI AGENT INSTRUCTIONS BEGIN -->"
    $endMarker = "<!-- AI AGENT INSTRUCTIONS END -->"
    $beginMatches = [regex]::Matches($agentsText, "(?m)^$([regex]::Escape($beginMarker))\r?$")
    $endMatches = [regex]::Matches($agentsText, "(?m)^$([regex]::Escape($endMarker))\r?$")
    if ($beginMatches.Count -eq 1 -and $endMatches.Count -eq 1 -and
        $beginMatches[0].Index -eq 0 -and $endMatches[0].Index -gt $beginMatches[0].Index) {
        Write-Ok "AGENTS.md содержит один управляемый блок в начале" "AGENTS.md has one managed block at the top"
    } else {
        Write-Fail "AGENTS.md не содержит один полный управляемый блок в начале" "AGENTS.md does not have one complete managed block at the top"
    }
}

$skillSourcePath = Join-Path $repoRoot "skills/ai-bootstrap-converge"
$skillSource = Get-Item -LiteralPath $skillSourcePath -Force -ErrorAction SilentlyContinue
$skillSourceSafe = $null -ne $skillSource -and $skillSource.PSIsContainer -and
    -not (Get-ItemLinkType $skillSource) -and (Test-PathTreeSafe $skillSource.FullName)
if ($skillSourceSafe) {
    $linkedSkillChild = Get-ChildItem -LiteralPath $skillSourcePath -Recurse -Force |
        Where-Object { Get-ItemLinkType $_ } |
        Select-Object -First 1
    $skillSourceSafe = $null -eq $linkedSkillChild
}
if (-not $skillSourceSafe) {
    Write-Fail "Канонический каталог skill отсутствует или небезопасен" "Canonical skill directory missing or unsafe"
}

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
    $fullPath = Join-Path $repoRoot $link.Path
    if (-not (Test-PathTreeSafe $fullPath -AllowLeafLink)) {
        Write-Fail "$($link.Path) имеет небезопасный путь" "$($link.Path) has an unsafe path or ancestor"
        continue
    }
    if (-not (Test-Path -LiteralPath $link.Path)) {
        Write-Fail "$($link.Path) отсутствует" "$($link.Path) missing"
        continue
    }
    $item = Get-Item -LiteralPath $link.Path -Force -ErrorAction SilentlyContinue
    $isSymlink = $null -ne $item -and (Get-ItemLinkType $item) -eq "SymbolicLink" -and
        ([string]$item.Target).Replace("\", "/") -eq $link.Target.Replace("\", "/")
    $isHardlink = $null -ne $item -and (Get-ItemLinkType $item) -eq "HardLink" -and
        (Test-SameFileIdentity $item.FullName (Join-Path (Get-Location) "AGENTS.md"))
    if (-not $isSymlink -and -not $isHardlink) {
        Write-Fail "$($link.Path) не использует точную ссылку на AGENTS.md" "$($link.Path) does not use the required AGENTS.md link"
    } else {
        Write-Ok "$($link.Path) связан с AGENTS.md" "$($link.Path) uses the required AGENTS.md link"
    }
}

$skillLinks = @(
    @{ Path = ".agents/skills/ai-bootstrap-converge"; Target = "../../skills/ai-bootstrap-converge" },
    @{ Path = ".claude/skills/ai-bootstrap-converge"; Target = "../../skills/ai-bootstrap-converge" }
)
foreach ($link in $skillLinks) {
    $fullPath = Join-Path $repoRoot $link.Path
    $item = Get-Item -LiteralPath $link.Path -Force -ErrorAction SilentlyContinue
    $valid = $skillSourceSafe -and (Test-PathTreeSafe $fullPath -AllowLeafLink) -and $null -ne $item -and (Get-ItemLinkType $item) -eq "SymbolicLink" -and
        ([string]$item.Target).Replace("\", "/") -eq $link.Target.Replace("\", "/")
    if ($valid) {
        Write-Ok "$($link.Path) указывает на канонический skill" "$($link.Path) uses the canonical skill link"
    } else {
        Write-Fail "$($link.Path) не использует точную ссылку на канонический skill" "$($link.Path) does not use the required canonical skill link"
    }
}

$patterns = @()
$readyFile = "local/ai/bootstrap.ready"
$readyMarker = $null
if (-not (Test-Path -LiteralPath $readyFile -PathType Leaf) -or -not (Test-PathTreeSafe (Join-Path $repoRoot $readyFile))) {
    Write-Fail "local/ai/bootstrap.ready отсутствует или небезопасен" "local/ai/bootstrap.ready missing or unsafe"
} else {
    $firstEntry = $true
    $readyInvalid = $false
    foreach ($line in Get-Content -LiteralPath $readyFile) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }
        if ($firstEntry) {
            $firstEntry = $false
            if ($trimmed -notin @("true", "false")) {
                Write-Fail "local/ai/bootstrap.ready должен начинаться с true или false" "local/ai/bootstrap.ready must start with true or false"
                $readyInvalid = $true
                break
            }
            $readyMarker = $trimmed
            continue
        }
        if ($trimmed -in @("true", "false")) {
            Write-Fail "local/ai/bootstrap.ready содержит повторный маркер" "local/ai/bootstrap.ready contains a duplicate marker"
            $readyInvalid = $true
            break
        }
        $patterns += $trimmed
    }
    if (-not $readyInvalid -and $readyMarker -eq "false") {
        Write-Fail "Bootstrap ещё не завершён" "Bootstrap is not completed yet"
    } elseif (-not $readyInvalid -and -not $patterns) {
        Write-Fail "local/ai/bootstrap.ready не содержит списка exclude" "local/ai/bootstrap.ready missing exclude list"
    }
}

$ignoreFile = $null
$gitCommon = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    $inside = & git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $inside -eq "true") {
        $reported = & git rev-parse --path-format=absolute --git-path info/exclude 2>$null
        if ($LASTEXITCODE -eq 0) { $ignoreFile = ([string]$reported).Trim() }
        $reportedCommon = & git rev-parse --path-format=absolute --git-common-dir 2>$null
        if ($LASTEXITCODE -eq 0) { $gitCommon = ([string]$reportedCommon).Trim() }
    }
}
if ($ignoreFile -and (Test-Path -LiteralPath $ignoreFile -PathType Leaf)) {
    $ignoreFile = [System.IO.Path]::GetFullPath($ignoreFile)
    if (-not $gitCommon -or -not (Test-Path -LiteralPath $gitCommon -PathType Container) -or -not (Test-PathTreeSafe $ignoreFile -Root (Resolve-Path -LiteralPath $gitCommon).Path)) {
        Write-Fail "Путь Git exclude небезопасен" "Git exclude path or ancestor is unsafe"
        $ignoreFile = $null
    }
} elseif ($ignoreFile) {
    Write-Fail ".git/info/exclude отсутствует" ".git/info/exclude missing"
    $ignoreFile = $null
} else {
    Write-Fail "Git не инициализирован" "Git worktree is required"
}

if ($ignoreFile -and $patterns.Count -gt 0) {
    $ignoreLines = @(Get-Content -LiteralPath $ignoreFile)
    $missingPattern = $false
    foreach ($pat in $patterns) {
        if ($ignoreLines -cnotcontains $pat) {
            Write-Fail "$ignoreFile не содержит $pat" "$ignoreFile missing $pat"
            $missingPattern = $true
        }
    }
    foreach ($obsolete in @(
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
    )) {
        if ($ignoreLines -ccontains $obsolete) {
            Write-Fail "$ignoreFile содержит устаревшее широкое исключение $obsolete" "$ignoreFile contains obsolete scaffold-wide entry $obsolete"
            $missingPattern = $true
        }
    }
    if (-not $missingPattern) {
        Write-Ok "$ignoreFile скрывает только изменяемое локальное состояние" "$ignoreFile covers mutable local state only"
    }
}

$logs = @(
    Get-ChildItem -Path "local/ai/*/sessions.log" -File -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "local/ai/*/requests.log" -File -Force -ErrorAction SilentlyContinue
)
if (-not $logs) {
    Write-Fail "Логи ассистентов не найдены в local/" "No assistant logs found under local/"
} else {
    foreach ($log in $logs) {
        try {
            if (-not (Test-PathTreeSafe $log.FullName)) { throw "$($log.FullName) has an unsafe path or ancestor" }
            $lines = @(Get-Content -LiteralPath $log.FullName)
            if ($lines.Count -eq 0) { throw "$($log.FullName) is empty" }
            for ($index = 0; $index -lt $lines.Count; $index++) {
                $source = "$($log.FullName):$($index + 1)"
                if ([string]::IsNullOrWhiteSpace($lines[$index])) { throw "$source contains a blank JSONL line" }
                Assert-UniqueJsonObjectKeys $lines[$index] $source
                $entry = $lines[$index] | ConvertFrom-Json -ErrorAction Stop
                if ($entry -isnot [pscustomobject]) { throw "$source must contain a JSON object" }
                Assert-LogEntry $entry $log.Name $log.Directory.Name $source
            }
            Write-Ok "$($log.FullName) содержит корректный JSONL" "$($log.FullName) JSONL schema valid"
        } catch {
            Write-Fail "$($log.FullName) не прошёл JSONL-проверку" $_.Exception.Message
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Bootstrap проверка провалена / Bootstrap check failed: " + ($failures -join ", "))
    exit 1
}

Write-Host "Bootstrap проверка пройдена / Bootstrap check passed"
