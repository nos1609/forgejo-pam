BeforeAll {
    $SkillRoot = Split-Path -Parent $PSScriptRoot
$ConvergeScript = Join-Path $SkillRoot 'scripts/converge.ps1'
$ConvergeShellScript = Join-Path $SkillRoot 'scripts/converge.sh'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $SkillRoot)
$InitPowerShellScript = Join-Path $RepoRoot 'local/ai/scripts/init.ps1'
$InitShellScript = Join-Path $RepoRoot 'local/ai/scripts/init.sh'
$BootstrapCheckPowerShell = Join-Path $RepoRoot 'local/ai/scripts/bootstrap_check.ps1'
$BootstrapCheckShell = Join-Path $RepoRoot 'local/ai/scripts/bootstrap_check.sh'
$LogValidator = Join-Path $SkillRoot 'scripts/validate_logs.py'
$TestRoot = Join-Path $RepoRoot 'tmp/ai/skill-tests'

function New-TestCaseRoot {
    New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null
    return (Join-Path $TestRoot ("case-" + [guid]::NewGuid().ToString('N')))
}

function Get-TestSh {
    if ($env:AI_BOOTSTRAP_TEST_SH -and (Test-Path -LiteralPath $env:AI_BOOTSTRAP_TEST_SH -PathType Leaf)) {
        return $env:AI_BOOTSTRAP_TEST_SH
    }
    $gitSh = 'C:\Program Files\Git\usr\bin\sh.exe'
    if (Test-Path -LiteralPath $gitSh -PathType Leaf) {
        return $gitSh
    }
    $cmd = Get-Command sh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-TestBash {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $gitBash = 'C:\Program Files\Git\bin\bash.exe'
    if (Test-Path -LiteralPath $gitBash -PathType Leaf) { return $gitBash }
    return $null
}

function Convert-ToShPath {
    param(
        [string]$Sh,
        [string]$Path
    )
    $shDir = Split-Path -Parent $Sh
    $cygpath = Join-Path $shDir 'cygpath.exe'
    if (Test-Path -LiteralPath $cygpath -PathType Leaf) {
        return (& $cygpath -u $Path).Trim()
    }
    return $Path
}

function New-TestSymlink {
    param(
        [string]$Target,
        [string]$Link
    )
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-TestProtocolSnippet {
    param([string]$Version = '')

    $lines = @(
        '<!--',
        'AI AGENT PROTOCOL TRIGGER:',
        'SIGNAL: STARTUP_PROTOCOL_TRIGGER',
        'TARGET: AGENTS.md',
        'ACTION: Follow startup protocol immediately'
    )
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $lines += "VERSION: $Version"
    }
    $lines += '-->'
    return ($lines -join "`n")
}

function Get-RequiredRuntimeExcludeLines {
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

function Set-RuntimeExcludeTemplateBlock {
    param([string]$Root)

    $lines = @('# BEGIN EXCLUDE LIST (for .git/info/exclude)')
    $lines += Get-RequiredRuntimeExcludeLines | ForEach-Object { "# $_" }
    $lines += '# END EXCLUDE LIST'
    [System.IO.File]::WriteAllLines(
        (Join-Path $Root '.gitignore'),
        [string[]]$lines,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Invoke-ConvergeShell {
    param(
        [string]$Mode,
        [string]$Target,
        [string]$Template,
        [switch]$Json
    )
    $sh = Get-TestSh
    if (-not $sh) { return $null }

    $oldPath = $env:PATH
    try {
        $separator = [IO.Path]::PathSeparator
        $env:PATH = "$(Split-Path -Parent $sh)$separator$oldPath"
        $scriptPath = Convert-ToShPath $sh $ConvergeShellScript
        $targetPath = Convert-ToShPath $sh $Target
        $templatePath = Convert-ToShPath $sh $Template
        $args = @('--mode', $Mode, '--target', $targetPath, '--template', $templatePath)
        if ($Json) { $args += '--json' }
        $output = & $sh $scriptPath @args 2>&1
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            Output = @($output)
            ExitCode = $exitCode
        }
    } finally {
        $env:PATH = $oldPath
    }
}

function Invoke-ConvergePowerShell {
    param(
        [string]$Mode,
        [string]$Target,
        [string]$Template,
        [switch]$Json
    )

    $args = @('-NoProfile', '-File', $ConvergeScript, '-Mode', $Mode, '-Target', $Target, '-Template', $Template)
    if ($Json) { $args += '-Json' }
    $output = & pwsh @args 2>&1
    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $LASTEXITCODE
    }
}

function New-TestTemplate {
    param([string]$Root)
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'local/ai/agents') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'local/ai/scripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'local/ai/codex') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'skills/ai-bootstrap-converge') | Out-Null
    @'
<!-- AI AGENT INSTRUCTIONS BEGIN -->
template agents
<!-- AI AGENT INSTRUCTIONS END -->
'@ | Set-Content -LiteralPath (Join-Path $Root 'AGENTS.md') -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'README_snippet.md') -Value '<!-- ai-bootstrap -->' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/agents/01-bootstrap.md') -Value 'bootstrap module' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/scripts/init.ps1') -Value 'Write-Output init' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/chat_context.md') -Value 'template chat context' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/bootstrap.ready') -Value 'false' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/codex/requests.log') -Value '{"timestamp":"YYYY-MM-DDTHH:MM:SSZ"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'skills/ai-bootstrap-converge/SKILL.md') -Value 'canonical skill' -Encoding utf8NoBOM
    Set-RuntimeExcludeTemplateBlock $Root
}

function New-InitFixture {
    param([string]$Root, [switch]$SkipGitInit)
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'local/ai/scripts'), (Join-Path $Root 'skills/ai-bootstrap-converge') | Out-Null
    Copy-Item -LiteralPath $InitPowerShellScript -Destination (Join-Path $Root 'local/ai/scripts/init.ps1')
    Copy-Item -LiteralPath $InitShellScript -Destination (Join-Path $Root 'local/ai/scripts/init.sh')
    @'
<!-- AI AGENT INSTRUCTIONS BEGIN -->
canonical agents
<!-- AI AGENT INSTRUCTIONS END -->
'@ | Set-Content -LiteralPath (Join-Path $Root 'AGENTS.md') -Encoding utf8NoBOM
    $snippet = Get-TestProtocolSnippet
    Set-Content -LiteralPath (Join-Path $Root 'README_snippet.md') -Value $snippet -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'README.md') -Value $snippet -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'README.en.md') -Value $snippet -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/bootstrap.ready') -Value 'false' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/chat_context.md') -Value '## Статус готовности / Readiness status' -Encoding utf8NoBOM
    Set-RuntimeExcludeTemplateBlock $Root
    if (-not $SkipGitInit) {
        git -C $Root -c init.defaultBranch=main init | Out-Null
    }
}

function Invoke-InitPowerShell {
    param([string]$Root)
    $output = & pwsh -NoProfile -File (Join-Path $Root 'local/ai/scripts/init.ps1') 2>&1
    return [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
}

function Invoke-InitShell {
    param([string]$Root)
    $bash = Get-TestBash
    if (-not $bash) { return $null }
    $script = Convert-ToShPath $bash (Join-Path $Root 'local/ai/scripts/init.sh')
    $output = & $bash $script 2>&1
    return [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
}

function New-BootstrapCheckFixture {
    param([string]$Root)
    foreach ($directory in @('.github', '.claude', '.gemini', '.qwen', '.agents/skills', '.claude/skills', 'skills/ai-bootstrap-converge/scripts', 'local/ai/codex', 'local/ai/scripts')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Root $directory) | Out-Null
    }
    @'
<!-- AI AGENT INSTRUCTIONS BEGIN -->
canonical agents
<!-- AI AGENT INSTRUCTIONS END -->
'@ | Set-Content -LiteralPath (Join-Path $Root 'AGENTS.md') -Encoding utf8NoBOM
    $snippet = Get-TestProtocolSnippet
    Set-Content -LiteralPath (Join-Path $Root 'README_snippet.md') -Value $snippet -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'README.md') -Value $snippet -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'README.en.md') -Value $snippet -Encoding utf8NoBOM
    $reportedTopLevel = & git -C $Root rev-parse --show-toplevel 2>$null
    $fixtureRoot = [System.IO.Path]::GetFullPath($Root)
    $gitTopLevel = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$reportedTopLevel)) {
        [System.IO.Path]::GetFullPath(([string]$reportedTopLevel).Trim())
    } else {
        $null
    }
    $comparison = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    if (-not $gitTopLevel -or -not [string]::Equals($fixtureRoot, $gitTopLevel, $comparison)) {
        git -C $Root -c init.defaultBranch=main init | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/bootstrap.ready') -Value @('true', 'tmp/ai/') -Encoding utf8NoBOM
    $exclude = (& git -C $Root rev-parse --path-format=absolute --git-path info/exclude).Trim()
    Set-Content -LiteralPath $exclude -Value 'tmp/ai/' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/codex/sessions.log') -Value '{"session_id":"sample-codex-session","started_at":"YYYY-MM-DDTHH:MM:SSZ","assistant":"codex","language":"<lang>","gender":"<f/m/neutral>","logging_precision":"ISO8601Z"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Root 'local/ai/codex/requests.log') -Value '{"timestamp":"YYYY-MM-DDTHH:MM:SSZ","request_id":"sample-codex-req-001","assistant":"codex","summary":"placeholder summary","tools":[],"status":"success"}' -Encoding utf8NoBOM
    Copy-Item -LiteralPath $LogValidator -Destination (Join-Path $Root 'skills/ai-bootstrap-converge/scripts/validate_logs.py')
    Copy-Item -LiteralPath $BootstrapCheckPowerShell -Destination (Join-Path $Root 'local/ai/scripts/bootstrap_check.ps1')
    Copy-Item -LiteralPath $BootstrapCheckShell -Destination (Join-Path $Root 'local/ai/scripts/bootstrap_check.sh')

    foreach ($link in @(
        @{ Path = '.github/copilot-instructions.md'; Target = '../AGENTS.md' },
        @{ Path = '.claude/CLAUDE.md'; Target = '../AGENTS.md' },
        @{ Path = 'CLAUDE.md'; Target = 'AGENTS.md' },
        @{ Path = '.gemini/GEMINI.md'; Target = '../AGENTS.md' },
        @{ Path = 'GEMINI.md'; Target = 'AGENTS.md' },
        @{ Path = 'QWEN.md'; Target = 'AGENTS.md' },
        @{ Path = '.qwen/QWEN.md'; Target = '../AGENTS.md' },
        @{ Path = '.agents/skills/ai-bootstrap-converge'; Target = '../../skills/ai-bootstrap-converge' },
        @{ Path = '.claude/skills/ai-bootstrap-converge'; Target = '../../skills/ai-bootstrap-converge' }
    )) {
        (New-TestSymlink $link.Target (Join-Path $Root $link.Path)) | Should -Be $true
    }
}

function Invoke-BootstrapCheckPowerShell {
    param([string]$Root)
    Push-Location $Root
    try {
        $output = & pwsh -NoProfile -File (Join-Path $Root 'local/ai/scripts/bootstrap_check.ps1') 2>&1
        return [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
    } finally {
        Pop-Location
    }
}

function Invoke-BootstrapCheckShell {
    param([string]$Root)
    $bash = Get-TestBash
    if (-not $bash) { return $null }
    $script = Convert-ToShPath $bash (Join-Path $Root 'local/ai/scripts/bootstrap_check.sh')
    Push-Location $Root
    try {
        $output = & $bash $script 2>&1
        return [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
    } finally {
        Pop-Location
    }
}
}

Describe 'ai-bootstrap-converge converge.ps1' {
    It 'plans missing framework files without writing in Plan mode' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project' -Encoding utf8NoBOM

            $json = & pwsh -NoProfile -File $ConvergeScript -Mode Plan -Target $target -Template $template -Json
            $LASTEXITCODE | Should -Be 0
            $ops = $json | ConvertFrom-Json
            @($ops | Where-Object Path -eq 'AGENTS.md' | Where-Object Status -eq 'MISSING').Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $target 'AGENTS.md') | Should -Be $false
            @($ops | Where-Object Path -eq 'skills/ai-bootstrap-converge/SKILL.md' | Where-Object Status -eq 'MISSING').Count | Should -Be 1
            @($ops | Where-Object Path -eq '.agents/skills/ai-bootstrap-converge' | Where-Object Type -eq 'EnsureSkillDiscoveryLink').Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not change parent Git metadata for a nested PowerShell target' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $parent = Join-Path $case 'parent'
        $target = Join-Path $parent 'nested-target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            git -C $parent -c init.defaultBranch=main init | Out-Null
            $exclude = (& git -C $parent rev-parse --path-format=absolute --git-path info/exclude).Trim()
            Set-Content -LiteralPath $exclude -Value 'parent-only-entry' -Encoding utf8NoBOM
            $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($exclude))

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json

            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($exclude)) | Should -Be $before
            ($result.Output -join "`n") | Should -Match 'parent Git metadata is not modified'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies safe framework operations while preserving existing local context' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            git -C $target -c init.defaultBranch=main init | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $target 'local/ai') | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'local/ai/chat_context.md') -Value 'project context' -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -Value @('true', 'project-entry') -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project' -Encoding utf8NoBOM

            $json = & pwsh -NoProfile -File $ConvergeScript -Mode Apply -Target $target -Template $template -Json
            $exitCode = $LASTEXITCODE
            ((0, 2) -contains $exitCode) | Should -Be $true
            $ops = $json | ConvertFrom-Json

            (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/chat_context.md')).Trim() | Should -Be 'project context'
            (@(Get-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')) -join '|') | Should -Be 'true|project-entry'
            Get-Content -Raw -LiteralPath (Join-Path $target 'README.md') | Should -Match '<!-- ai-bootstrap -->'
            (@(Get-Content -LiteralPath (Join-Path $target '.git/info/exclude')) -contains 'tmp/ai/') | Should -Be $true
            Test-Path -LiteralPath (Join-Path $target '.github/copilot-instructions.md') | Should -Be $true
            Test-Path -LiteralPath (Join-Path $target 'skills/ai-bootstrap-converge/SKILL.md') | Should -Be $true
            if ($exitCode -eq 0) {
                (Get-Item -LiteralPath (Join-Path $target '.agents/skills/ai-bootstrap-converge') -Force).LinkType | Should -Be 'SymbolicLink'
                (Get-Item -LiteralPath (Join-Path $target '.claude/skills/ai-bootstrap-converge') -Force).LinkType | Should -Be 'SymbolicLink'
            } else {
                (@($ops | Where-Object Type -eq 'EnsureSkillDiscoveryLink' | Where-Object Status -eq 'BLOCKED').Count -gt 0) | Should -Be $true
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'plans and applies authoritative updates to a drifting managed file' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'README_snippet.md') -Value 'custom snippet' -Encoding utf8NoBOM

            $planJson = & pwsh -NoProfile -File $ConvergeScript -Mode Plan -Target $target -Template $template -Json
            $LASTEXITCODE | Should -Be 0
            $plan = $planJson | ConvertFrom-Json
            $operation = @($plan | Where-Object Path -eq 'README_snippet.md' | Where-Object Status -eq 'DRIFT')
            $operation.Count | Should -Be 1
            $operation[0].Safe | Should -Be $true
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README_snippet.md')).Trim() | Should -Be 'custom snippet'

            $apply = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            ((0, 2) -contains $apply.ExitCode) | Should -Be $true
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README_snippet.md')).Trim() | Should -Be '<!-- ai-bootstrap -->'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'atomically updates the running PowerShell converge script' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $targetScript = Join-Path $target 'skills/ai-bootstrap-converge/scripts/converge.ps1'
        $sourceScript = Join-Path $template 'skills/ai-bootstrap-converge/scripts/converge.ps1'
        try {
            New-TestTemplate $template
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetScript), (Split-Path -Parent $sourceScript) | Out-Null
            Copy-Item -LiteralPath $ConvergeScript -Destination $targetScript
            Set-Content -LiteralPath $sourceScript -Value '# updated PowerShell converge payload' -Encoding utf8NoBOM

            $output = & pwsh -NoProfile -File $targetScript -Mode Apply -Target $target -Template $template -Json 2>&1
            ((0, 2) -contains $LASTEXITCODE) | Should -Be $true -Because ($output -join "`n")
            (Get-Content -Raw -LiteralPath $targetScript).Trim() | Should -Be '# updated PowerShell converge payload'
            @(Get-ChildItem -LiteralPath (Split-Path -Parent $targetScript) -Filter '.ai-bootstrap-*.tmp' -Force).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'updates a previous top README protocol snippet and preserves the body' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $template 'README_snippet.md') -Value (Get-TestProtocolSnippet -Version 'current') -Encoding utf8NoBOM
            $previousSnippet = Get-TestProtocolSnippet -Version 'previous'
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value ($previousSnippet + "`n`n# Project README`nKeep this body.") -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')
            $text | Should -Match 'VERSION: current'
            $text | Should -Not -Match 'VERSION: previous'
            $text | Should -Match '# Project README'
            $text | Should -Match 'Keep this body'
            ([regex]::Matches($text, 'AI AGENT PROTOCOL TRIGGER')).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'moves one exact README snippet without dropping text on either side' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            $snippet = Get-Content -Raw -LiteralPath (Join-Path $template 'README_snippet.md')
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value ("# Before`n`n" + $snippet + "`n# After`n") -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')
            $text.StartsWith($snippet.TrimEnd()) | Should -Be $true
            $text | Should -Match '# Before'
            $text | Should -Match '# After'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks a misplaced previous README protocol marker' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $template 'README_snippet.md') -Value (Get-TestProtocolSnippet -Version 'current') -Encoding utf8NoBOM
            $original = "# Project README`n`n<!-- AI AGENT PROTOCOL TRIGGER: previous -->`n"
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value $original -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            $operations = ($result.Output -join "`n") | ConvertFrom-Json
            @($operations | Where-Object Path -eq 'README.md' | Where-Object Status -eq 'CONFLICT').Count | Should -Be 1
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).Trim() | Should -Be $original.Trim()
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves a project-owned first README comment that only mentions the protocol trigger' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $template 'README_snippet.md') -Value (Get-TestProtocolSnippet -Version 'current') -Encoding utf8NoBOM
            $original = "<!--`nProject metadata: AI AGENT PROTOCOL TRIGGER:`n-->`n`n# Project README`nKeep this body.`n"
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value $original -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            $operations = ($result.Output -join "`n") | ConvertFrom-Json
            @($operations | Where-Object Path -eq 'README.md' | Where-Object Status -eq 'CONFLICT').Count | Should -Be 1
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).Trim() | Should -Be $original.Trim()
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'plans AGENTS.md convergence as a safe patch over project rules' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value @'
# Project agent rules

- Keep WARPinator-specific rules.
'@ -Encoding utf8NoBOM

            $json = & pwsh -NoProfile -File $ConvergeScript -Mode Plan -Target $target -Template $template -Json
            $LASTEXITCODE | Should -Be 0
            $ops = $json | ConvertFrom-Json
            $agentOp = @($ops | Where-Object Path -eq 'AGENTS.md' | Where-Object Type -eq 'EnsureAgentsInstructions')
            $agentOp.Count | Should -Be 1
            $agentOp[0].Status | Should -Be 'MISSING'
            $agentOp[0].Safe | Should -Be $true
            $agentOp[0].Detail | Should -Match 'preserving existing project rules'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies AGENTS.md convergence without dropping project rules' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value @'
# Project agent rules

- Keep WARPinator-specific rules.
'@ -Encoding utf8NoBOM

            $json = & pwsh -NoProfile -File $ConvergeScript -Mode Apply -Target $target -Template $template -Json
            ((0, 2) -contains $LASTEXITCODE) | Should -Be $true
            $ops = $json | ConvertFrom-Json
            @($ops | Where-Object Path -eq 'AGENTS.md' | Where-Object Type -eq 'EnsureAgentsInstructions' | Where-Object Safe -eq $true).Count | Should -Be 1
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md')
            $text | Should -Match 'template agents'
            $text | Should -Match 'Keep WARPinator-specific rules'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'updates a marked AGENTS.md block without dropping project rules' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            @'
# Rules before the managed block

<!-- AI AGENT INSTRUCTIONS BEGIN -->
old managed instructions
<!-- AI AGENT INSTRUCTIONS END -->

# Rules after the managed block
'@ | Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md')
            $text.IndexOf('<!-- AI AGENT INSTRUCTIONS BEGIN -->') | Should -Be 0
            ([regex]::Matches($text, '<!-- AI AGENT INSTRUCTIONS BEGIN -->')).Count | Should -Be 1
            ([regex]::Matches($text, '<!-- AI AGENT INSTRUCTIONS END -->')).Count | Should -Be 1
            $text | Should -Match 'template agents'
            $text | Should -Not -Match 'old managed instructions'
            $text | Should -Match 'Rules before the managed block'
            $text | Should -Match 'Rules after the managed block'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves instruction hardlinks while updating AGENTS.md in PowerShell convergence' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $agents = Join-Path $target 'AGENTS.md'
        $instruction = Join-Path $target '.github/copilot-instructions.md'
        New-Item -ItemType Directory -Force -Path $template, $target, (Split-Path -Parent $instruction) | Out-Null
        try {
            New-TestTemplate $template
            @'
<!-- AI AGENT INSTRUCTIONS BEGIN -->
old managed instructions
<!-- AI AGENT INSTRUCTIONS END -->

# Project rule
'@ | Set-Content -LiteralPath $agents -Encoding utf8NoBOM
            New-Item -ItemType HardLink -Path $instruction -Target $agents | Out-Null

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            $operations = ($result.Output -join "`n") | ConvertFrom-Json
            @($operations | Where-Object { $_.Path -eq '.github/copilot-instructions.md' -and $_.Status -eq 'OK' }).Count | Should -Be 1
            (Get-Content -Raw -LiteralPath $instruction) | Should -Be (Get-Content -Raw -LiteralPath $agents)
            (Get-Content -Raw -LiteralPath $instruction) | Should -Match 'template agents'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'upgrades a legacy unmarked AGENTS.md block without duplicating it' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            @'
# Инструкции ассистентам / Local agent instructions

legacy preamble
## P0 rules / P0 правила
legacy P0
## Modules / Разделы
legacy modules
## Reading order / Порядок чтения
1) legacy one
2) legacy two
3) legacy three
4) legacy four
5) legacy five

# Project-only rules
- Preserve this instruction.
'@ | Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md')
            $text | Should -Match 'template agents'
            $text | Should -Not -Match 'legacy P0'
            $text | Should -Match 'Preserve this instruction'
            ([regex]::Matches($text, '# Инструкции ассистентам / Local agent instructions')).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks a malformed marked AGENTS.md without changing it' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            $damaged = "<!-- AI AGENT INSTRUCTIONS BEGIN -->`nproject content without an end marker`n"
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value $damaged -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            $operations = ($result.Output -join "`n") | ConvertFrom-Json
            @($operations | Where-Object Path -eq 'AGENTS.md' | Where-Object Status -eq 'CONFLICT').Count | Should -Be 1
            (Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md')).Trim() | Should -Be $damaged.Trim()
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'uses a Windows PowerShell 5.1-compatible relative path calculation' {
        $source = Get-Content -Raw -LiteralPath $ConvergeScript
        $source | Should -Not -Match 'MakeRelativeUri'
        $source | Should -Not -Match '::GetRelativePath'
        $source | Should -Match 'function Get-RelativePath'
    }

    It 'reports tracked local-only files as explicit user decisions' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            git -C $target -c init.defaultBranch=main init | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.override.md') -Value 'local override' -Encoding utf8NoBOM
            New-Item -ItemType Directory -Force -Path (Join-Path $target 'local/ai'), (Join-Path $target 'local/ai/session_summaries') | Out-Null
            foreach ($relative in @(
                'local/ai/bootstrap.ready',
                'local/ai/chat_context.md',
                'local/ai/project_addenda.md',
                'local/ai/session_history.md'
            )) {
                Set-Content -LiteralPath (Join-Path $target $relative) -Value 'tracked runtime' -Encoding utf8NoBOM
            }
            Set-Content -LiteralPath (Join-Path $target 'local/ai/session_summaries/README.md') -Value 'tracked scaffold documentation' -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $target 'local/ai/session_summaries/private.md') -Value 'tracked runtime summary' -Encoding utf8NoBOM
            git -C $target add AGENTS.override.md local/ai/bootstrap.ready local/ai/chat_context.md local/ai/project_addenda.md local/ai/session_history.md local/ai/session_summaries/README.md local/ai/session_summaries/private.md | Out-Null

            $json = & pwsh -NoProfile -File $ConvergeScript -Mode Plan -Target $target -Template $template -Json
            $LASTEXITCODE | Should -Be 0
            $ops = $json | ConvertFrom-Json
            foreach ($relative in @(
                'AGENTS.override.md',
                'local/ai/bootstrap.ready',
                'local/ai/chat_context.md',
                'local/ai/project_addenda.md',
                'local/ai/session_history.md'
            )) {
                $tracked = @($ops | Where-Object Type -eq 'ReportLocalOnlyTracked' | Where-Object Path -eq $relative)
                $tracked.Count | Should -Be 1
                $tracked[0].Status | Should -Be 'NEEDS_DECISION'
                $tracked[0].Safe | Should -Be $false
                $tracked[0].Detail | Should -Match 'explicit user approval'
            }
            @($ops | Where-Object Type -eq 'ReportLocalOnlyTracked' | Where-Object Path -eq 'local/ai/session_summaries/README.md').Count | Should -Be 0
            @($ops | Where-Object Type -eq 'ReportLocalOnlyTracked' | Where-Object Path -eq 'local/ai/session_summaries/private.md').Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports deprecated credential residue without reading or removing it' {
        foreach ($runner in @('PowerShell', 'POSIX')) {
            if ($runner -eq 'POSIX' -and -not (Get-TestSh)) { continue }
            $case = New-TestCaseRoot
            $template = Join-Path $case 'template'
            $target = Join-Path $case 'target'
            $legacy = Join-Path $target 'tmp/ai/cli_tokens'
            $sentinel = Join-Path $legacy 'sentinel.txt'
            New-Item -ItemType Directory -Force -Path $template, $legacy | Out-Null
            try {
                New-TestTemplate $template
                Set-Content -LiteralPath $sentinel -Value 'do not inspect or remove' -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') {
                    Invoke-ConvergePowerShell -Mode Plan -Target $target -Template $template -Json
                } else {
                    Invoke-ConvergeShell -Mode plan -Target $target -Template $template -Json
                }

                $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
                $ops = $result.Output -join "`n" | ConvertFrom-Json
                $residue = @($ops | Where-Object Type -eq 'ReportLegacyCredentialResidue')
                $residue.Count | Should -Be 1
                $residue[0].Status | Should -Be 'NEEDS_DECISION'
                $residue[0].Path | Should -Be 'tmp/ai/cli_tokens'
                $residue[0].Safe | Should -Be $false
                $residue[0].Detail | Should -Match 'Do not inspect'
                (Get-Content -Raw -LiteralPath $sentinel).Trim() | Should -Be 'do not inspect or remove'
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'keeps Audit and Plan read-only when git exclude is absent' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            git -C $target -c init.defaultBranch=main init | Out-Null
            $exclude = Join-Path $target '.git/info/exclude'
            Remove-Item -LiteralPath $exclude -Force -ErrorAction SilentlyContinue

            foreach ($mode in @('Audit', 'Plan')) {
                $result = Invoke-ConvergePowerShell -Mode $mode -Target $target -Template $template -Json
                $result.ExitCode | Should -Be 0
                Test-Path -LiteralPath $exclude | Should -Be $false
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects option-shaped remote template and source ref values before invoking Git' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        $previousTemplate = $env:AI_BOOTSTRAP_TEMPLATE
        try {
            $env:AI_BOOTSTRAP_TEMPLATE = '--upload-pack=synthetic'
            $templateOutput = & pwsh -NoProfile -File $ConvergeScript -Mode Audit -Target $target 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($templateOutput -join "`n") | Should -Match 'Remote template value must not start'

            $env:AI_BOOTSTRAP_TEMPLATE = 'https://example.invalid/bootstrap.git'
            $refOutput = & pwsh -NoProfile -File $ConvergeScript -Mode Audit -Target $target -SourceRef '--upload-pack=synthetic' 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($refOutput -join "`n") | Should -Match 'Source ref must not start'
        } finally {
            $env:AI_BOOTSTRAP_TEMPLATE = $previousTemplate
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports file destination directories as conflicts without writing into them' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            foreach ($relative in @('AGENTS.md', 'README_snippet.md', 'README.md', 'local/ai/chat_context.md')) {
                New-Item -ItemType Directory -Force -Path (Join-Path $target $relative) | Out-Null
            }

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureAgentsInstructions' -and $_.Path -eq 'AGENTS.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureManagedFile' -and $_.Path -eq 'README_snippet.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureSnippetPresent' -and $_.Path -eq 'README.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureIfMissing' -and $_.Path -eq 'local/ai/chat_context.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Status -eq 'BLOCKED' }).Count | Should -BeGreaterThan 0
            foreach ($relative in @('AGENTS.md', 'README_snippet.md', 'README.md', 'local/ai/chat_context.md')) {
                @(Get-ChildItem -LiteralPath (Join-Path $target $relative) -Force).Count | Should -Be 0
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a symlinked template AGENTS.md before Apply can copy it' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $template, $target, $outside | Out-Null
        try {
            New-TestTemplate $template
            $outsideAgents = Join-Path $outside 'AGENTS.md'
            Set-Content -LiteralPath $outsideAgents -Value 'synthetic external template data' -Encoding utf8NoBOM
            Remove-Item -LiteralPath (Join-Path $template 'AGENTS.md') -Force
            (New-TestSymlink $outsideAgents (Join-Path $template 'AGENTS.md')) | Should -Be $true

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Not -Be 0
            Test-Path -LiteralPath (Join-Path $target 'AGENTS.md') | Should -Be $false
            ($result.Output -join "`n") | Should -Match 'regular non-symlink file'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a symlinked template README_snippet.md before Apply can dereference it' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $template, $target, $outside | Out-Null
        try {
            New-TestTemplate $template
            $outsideSnippet = Join-Path $outside 'README_snippet.md'
            Set-Content -LiteralPath $outsideSnippet -Value 'synthetic external snippet data' -Encoding utf8NoBOM
            Remove-Item -LiteralPath (Join-Path $template 'README_snippet.md') -Force
            (New-TestSymlink $outsideSnippet (Join-Path $template 'README_snippet.md')) | Should -Be $true
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project' -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Not -Be 0
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).Trim() | Should -Be '# Project'
            ($result.Output -join "`n") | Should -Match 'regular non-symlink file'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks Apply when a target descendant symlink would redirect a managed write' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $template, $target, $outside | Out-Null
        try {
            New-TestTemplate $template
            (New-TestSymlink $outside (Join-Path $target 'local')) | Should -Be $true

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            Test-Path -LiteralPath (Join-Path $outside 'ai/chat_context.md') | Should -Be $false
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureIfMissing' -and $_.Path -eq 'local/ai/chat_context.md' -and $_.Status -eq 'BLOCKED' }).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks exact instruction and skill links under symlinked ancestors' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outsideGitHub = Join-Path $case 'outside-github'
        $outsideAgents = Join-Path $case 'outside-agents'
        New-Item -ItemType Directory -Force -Path $template, $target, $outsideGitHub, (Join-Path $outsideAgents 'skills'), (Join-Path $case 'skills/ai-bootstrap-converge') | Out-Null
        Set-Content -LiteralPath (Join-Path $case 'AGENTS.md') -Value 'outside agents' -Encoding utf8NoBOM
        try {
            New-TestTemplate $template
            (New-TestSymlink $outsideGitHub (Join-Path $target '.github')) | Should -Be $true
            (New-TestSymlink $outsideAgents (Join-Path $target '.agents')) | Should -Be $true
            (New-TestSymlink '../AGENTS.md' (Join-Path $outsideGitHub 'copilot-instructions.md')) | Should -Be $true
            (New-TestSymlink '../../skills/ai-bootstrap-converge' (Join-Path $outsideAgents 'skills/ai-bootstrap-converge')) | Should -Be $true

            $result = Invoke-ConvergePowerShell -Mode Audit -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' -and $_.Status -eq 'BLOCKED' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureSkillDiscoveryLink' -and $_.Path -eq '.agents/skills/ai-bootstrap-converge' -and $_.Status -eq 'BLOCKED' }).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an instruction symlink with an arbitrary AGENTS.md suffix' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $template, $target, $outside, (Join-Path $target '.github') | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value 'canonical agents' -Encoding utf8NoBOM
            $outsideAgents = Join-Path $outside 'AGENTS.md'
            Set-Content -LiteralPath $outsideAgents -Value 'synthetic alternate instructions' -Encoding utf8NoBOM
            (New-TestSymlink $outsideAgents (Join-Path $target '.github/copilot-instructions.md')) | Should -Be $true

            $result = Invoke-ConvergePowerShell -Mode Audit -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            $op = @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' })
            $op.Count | Should -Be 1
            $op[0].Status | Should -Be 'CONFLICT'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a skill discovery symlink with an arbitrary skills suffix' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target '.agents/skills'), (Join-Path $target 'other/skills/ai-bootstrap-converge') | Out-Null
        try {
            New-TestTemplate $template
            (New-TestSymlink '../../other/skills/ai-bootstrap-converge' (Join-Path $target '.agents/skills/ai-bootstrap-converge')) | Should -Be $true

            $result = Invoke-ConvergePowerShell -Mode Audit -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            $op = @($ops | Where-Object { $_.Type -eq 'EnsureSkillDiscoveryLink' -and $_.Path -eq '.agents/skills/ai-bootstrap-converge' })
            $op.Count | Should -Be 1
            $op[0].Status | Should -Be 'CONFLICT'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not accept a same-content copy as an instruction hardlink' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target '.github') | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value 'canonical agents' -Encoding utf8NoBOM
            Copy-Item -LiteralPath (Join-Path $target 'AGENTS.md') -Destination (Join-Path $target '.github/copilot-instructions.md')

            $result = Invoke-ConvergePowerShell -Mode Audit -Target $target -Template $template -Json
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            $op = @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' })
            $op.Count | Should -Be 1
            $op[0].Status | Should -Be 'CONFLICT'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts an actual instruction hardlink' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target '.github') | Out-Null
        try {
            New-TestTemplate $template
            $agents = Join-Path $target 'AGENTS.md'
            $instruction = Join-Path $target '.github/copilot-instructions.md'
            Set-Content -LiteralPath $agents -Value 'canonical agents' -Encoding utf8NoBOM
            New-Item -ItemType HardLink -Path $instruction -Target $agents | Out-Null

            $result = Invoke-ConvergePowerShell -Mode Audit -Target $target -Template $template -Json
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            $op = @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' })
            $op.Count | Should -Be 1
            $op[0].Status | Should -Be 'OK'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not replace a broken instruction symlink in Apply mode' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target '.github') | Out-Null
        try {
            New-TestTemplate $template
            (New-TestSymlink '../missing/AGENTS.md' (Join-Path $target '.github/copilot-instructions.md')) | Should -Be $true

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            (Get-Item -LiteralPath (Join-Path $target '.github/copilot-instructions.md') -Force).Target | Should -Be '../missing/AGENTS.md'
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'ai-bootstrap-converge converge.sh' {
    It 'keeps audit and plan alive when safe operations are missing' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project' -Encoding utf8NoBOM
            $oldPath = $env:PATH
            $shDir = Split-Path -Parent $sh
            try {
                $env:PATH = "$shDir;$oldPath"
                $scriptPath = Convert-ToShPath $sh $ConvergeShellScript
                $targetPath = Convert-ToShPath $sh $target
                $templatePath = Convert-ToShPath $sh $template
                foreach ($mode in @('audit', 'plan')) {
                    $output = & $sh $scriptPath --mode $mode --target $targetPath --template $templatePath 2>&1
                    $LASTEXITCODE | Should -Be 0
                    ($output -join "`n") | Should -Match 'EnsureSnippetPresent'
                }
            } finally {
                $env:PATH = $oldPath
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not change parent Git metadata for a nested POSIX target' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $parent = Join-Path $case 'parent'
        $target = Join-Path $parent 'nested-target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            git -C $parent -c init.defaultBranch=main init | Out-Null
            $exclude = (& git -C $parent rev-parse --path-format=absolute --git-path info/exclude).Trim()
            Set-Content -LiteralPath $exclude -Value 'parent-only-entry' -Encoding utf8NoBOM
            $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($exclude))

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json

            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($exclude)) | Should -Be $before
            ($result.Output -join "`n") | Should -Match 'parent Git metadata is not modified'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps audit and plan read-only when git exclude is absent' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            git -C $target -c init.defaultBranch=main init | Out-Null
            $exclude = Join-Path $target '.git/info/exclude'
            Remove-Item -LiteralPath $exclude -Force -ErrorAction SilentlyContinue

            foreach ($mode in @('audit', 'plan')) {
                $result = Invoke-ConvergeShell -Mode $mode -Target $target -Template $template -Json
                $result.ExitCode | Should -Be 0
                Test-Path -LiteralPath $exclude | Should -Be $false
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects option-shaped remote template and source ref values before invoking Git' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        try {
            $scriptPath = Convert-ToShPath $sh $ConvergeShellScript
            $targetPath = Convert-ToShPath $sh $target

            $templateOutput = & $sh $scriptPath --mode audit --target $targetPath --template '--upload-pack=synthetic' 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($templateOutput -join "`n") | Should -Match 'remote template value must not start'

            $refOutput = & $sh $scriptPath --mode audit --target $targetPath --template 'https://example.invalid/bootstrap.git' --source-ref '--upload-pack=synthetic' 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($refOutput -join "`n") | Should -Match 'source ref must not start'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports file destination directories as conflicts without writing into them' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            foreach ($relative in @('AGENTS.md', 'README_snippet.md', 'README.md', 'local/ai/chat_context.md')) {
                New-Item -ItemType Directory -Force -Path (Join-Path $target $relative) | Out-Null
            }

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureAgentsInstructions' -and $_.Path -eq 'AGENTS.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureManagedFile' -and $_.Path -eq 'README_snippet.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureSnippetPresent' -and $_.Path -eq 'README.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureIfMissing' -and $_.Path -eq 'local/ai/chat_context.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Status -eq 'BLOCKED' }).Count | Should -BeGreaterThan 0
            foreach ($relative in @('AGENTS.md', 'README_snippet.md', 'README.md', 'local/ai/chat_context.md')) {
                @(Get-ChildItem -LiteralPath (Join-Path $target $relative) -Force).Count | Should -Be 0
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies AGENTS.md convergence without aborting on link fallback' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value @'
# Project agent rules

- Keep WARPinator-specific rules.
'@ -Encoding utf8NoBOM
            New-Item -ItemType Directory -Force -Path (Join-Path $target 'local/ai') | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -Value @('true', 'project-entry') -Encoding utf8NoBOM
            $oldPath = $env:PATH
            $shDir = Split-Path -Parent $sh
            try {
                $env:PATH = "$shDir;$oldPath"
                $scriptPath = Convert-ToShPath $sh $ConvergeShellScript
                $targetPath = Convert-ToShPath $sh $target
                $templatePath = Convert-ToShPath $sh $template
                $rootReadmeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $RepoRoot 'README.md')).Hash
                $null = & $sh $scriptPath --mode apply --target $targetPath --template $templatePath --json 2>&1
                ((0, 2) -contains $LASTEXITCODE) | Should -Be $true
                Test-Path -LiteralPath (Join-Path $target 'README.md') | Should -Be $true
                (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $RepoRoot 'README.md')).Hash | Should -Be $rootReadmeHash
                Test-Path -LiteralPath (Join-Path $SkillRoot 'ai-bootstrap-converge') | Should -Be $false
                $text = Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md')
                $text | Should -Match 'template agents'
                $text | Should -Match 'Keep WARPinator-specific rules'
                (@(Get-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')) -join '|') | Should -Be 'true|project-entry'
            } finally {
                $env:PATH = $oldPath
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies authoritative managed-file updates in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'README_snippet.md') -Value 'custom snippet' -Encoding utf8NoBOM

            $plan = Invoke-ConvergeShell -Mode plan -Target $target -Template $template -Json
            $plan.ExitCode | Should -Be 0
            $operations = ($plan.Output -join "`n") | ConvertFrom-Json
            $operation = @($operations | Where-Object Path -eq 'README_snippet.md' | Where-Object Status -eq 'DRIFT')
            $operation.Count | Should -Be 1
            $operation[0].Safe | Should -Be $true
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README_snippet.md')).Trim() | Should -Be 'custom snippet'

            $apply = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            ((0, 2) -contains $apply.ExitCode) | Should -Be $true
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README_snippet.md')).Trim() | Should -Be '<!-- ai-bootstrap -->'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'atomically updates the running POSIX converge script' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $targetScript = Join-Path $target 'skills/ai-bootstrap-converge/scripts/converge.sh'
        $sourceScript = Join-Path $template 'skills/ai-bootstrap-converge/scripts/converge.sh'
        try {
            New-TestTemplate $template
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetScript), (Split-Path -Parent $sourceScript) | Out-Null
            Copy-Item -LiteralPath $ConvergeShellScript -Destination $targetScript
            Set-Content -LiteralPath $sourceScript -Value '# updated POSIX converge payload' -Encoding utf8NoBOM

            $scriptPath = Convert-ToShPath $sh $targetScript
            $targetPath = Convert-ToShPath $sh $target
            $templatePath = Convert-ToShPath $sh $template
            $output = & $sh $scriptPath --mode apply --target $targetPath --template $templatePath --json 2>&1
            ((0, 2) -contains $LASTEXITCODE) | Should -Be $true -Because ($output -join "`n")
            (Get-Content -Raw -LiteralPath $targetScript).Trim() | Should -Be '# updated POSIX converge payload'
            @(Get-ChildItem -LiteralPath (Split-Path -Parent $targetScript) -Filter '.ai-bootstrap.*' -Force).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'updates a previous top README protocol snippet in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $template 'README_snippet.md') -Value (Get-TestProtocolSnippet -Version 'current') -Encoding utf8NoBOM
            $previousSnippet = Get-TestProtocolSnippet -Version 'previous'
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value ($previousSnippet + "`n`n# Project README`nKeep this body.") -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')
            $text | Should -Match 'VERSION: current'
            $text | Should -Not -Match 'VERSION: previous'
            $text | Should -Match '# Project README'
            $text | Should -Match 'Keep this body'
            ([regex]::Matches($text, 'AI AGENT PROTOCOL TRIGGER')).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'moves one exact README snippet in POSIX convergence without dropping surrounding text' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            $snippet = Get-Content -Raw -LiteralPath (Join-Path $template 'README_snippet.md')
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value ("# Before`n`n" + $snippet + "`n# After`n") -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')
            $text.StartsWith($snippet.TrimEnd()) | Should -Be $true
            $text | Should -Match '# Before'
            $text | Should -Match '# After'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks a misplaced previous README protocol marker in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $template 'README_snippet.md') -Value (Get-TestProtocolSnippet -Version 'current') -Encoding utf8NoBOM
            $original = "# Project README`n`n<!-- AI AGENT PROTOCOL TRIGGER: previous -->`n"
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value $original -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            $operations = ($result.Output -join "`n") | ConvertFrom-Json
            @($operations | Where-Object Path -eq 'README.md' | Where-Object Status -eq 'CONFLICT').Count | Should -Be 1
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).Trim() | Should -Be $original.Trim()
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves a project-owned first README comment that only mentions the protocol trigger in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $template 'README_snippet.md') -Value (Get-TestProtocolSnippet -Version 'current') -Encoding utf8NoBOM
            $original = "<!--`nProject metadata: AI AGENT PROTOCOL TRIGGER:`n-->`n`n# Project README`nKeep this body.`n"
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value $original -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            $operations = ($result.Output -join "`n") | ConvertFrom-Json
            @($operations | Where-Object Path -eq 'README.md' | Where-Object Status -eq 'CONFLICT').Count | Should -Be 1
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).Trim() | Should -Be $original.Trim()
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'updates a marked AGENTS.md block in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            @'
# Rules before the managed block

<!-- AI AGENT INSTRUCTIONS BEGIN -->
old managed instructions
<!-- AI AGENT INSTRUCTIONS END -->

# Rules after the managed block
'@ | Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md')
            $text.IndexOf('<!-- AI AGENT INSTRUCTIONS BEGIN -->') | Should -Be 0
            ([regex]::Matches($text, '<!-- AI AGENT INSTRUCTIONS BEGIN -->')).Count | Should -Be 1
            ([regex]::Matches($text, '<!-- AI AGENT INSTRUCTIONS END -->')).Count | Should -Be 1
            $text | Should -Match 'template agents'
            $text | Should -Not -Match 'old managed instructions'
            $text | Should -Match 'Rules before the managed block'
            $text | Should -Match 'Rules after the managed block'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves instruction hardlinks while updating AGENTS.md in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $agents = Join-Path $target 'AGENTS.md'
        $instruction = Join-Path $target '.github/copilot-instructions.md'
        New-Item -ItemType Directory -Force -Path $template, $target, (Split-Path -Parent $instruction) | Out-Null
        try {
            New-TestTemplate $template
            @'
<!-- AI AGENT INSTRUCTIONS BEGIN -->
old managed instructions
<!-- AI AGENT INSTRUCTIONS END -->

# Project rule
'@ | Set-Content -LiteralPath $agents -Encoding utf8NoBOM
            New-Item -ItemType HardLink -Path $instruction -Target $agents | Out-Null

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            $operations = ($result.Output -join "`n") | ConvertFrom-Json
            @($operations | Where-Object { $_.Path -eq '.github/copilot-instructions.md' -and $_.Status -eq 'OK' }).Count | Should -Be 1
            (Get-Content -Raw -LiteralPath $instruction) | Should -Be (Get-Content -Raw -LiteralPath $agents)
            (Get-Content -Raw -LiteralPath $instruction) | Should -Match 'template agents'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'upgrades a legacy unmarked AGENTS.md block in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            @'
# Инструкции ассистентам / Local agent instructions

legacy preamble
## P0 rules / P0 правила
legacy P0
## Modules / Разделы
legacy modules
## Reading order / Порядок чтения
1) legacy one
2) legacy two
3) legacy three
4) legacy four
5) legacy five

# Project-only rules
- Preserve this instruction.
'@ | Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            ((0, 2) -contains $result.ExitCode) | Should -Be $true
            $text = Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md')
            $text | Should -Match 'template agents'
            $text | Should -Not -Match 'legacy P0'
            $text | Should -Match 'Preserve this instruction'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks malformed AGENTS.md markers in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            $damaged = "<!-- AI AGENT INSTRUCTIONS BEGIN -->`nproject content without an end marker`n"
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value $damaged -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            $operations = ($result.Output -join "`n") | ConvertFrom-Json
            @($operations | Where-Object Path -eq 'AGENTS.md' | Where-Object Status -eq 'CONFLICT').Count | Should -Be 1
            (Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md')).Trim() | Should -Be $damaged.Trim()
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a symlinked template AGENTS.md before Apply can copy it' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $template, $target, $outside | Out-Null
        try {
            New-TestTemplate $template
            $outsideAgents = Join-Path $outside 'AGENTS.md'
            Set-Content -LiteralPath $outsideAgents -Value 'synthetic external template data' -Encoding utf8NoBOM
            Remove-Item -LiteralPath (Join-Path $template 'AGENTS.md') -Force
            (New-TestSymlink $outsideAgents (Join-Path $template 'AGENTS.md')) | Should -Be $true
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project' -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Not -Be 0
            Test-Path -LiteralPath (Join-Path $target 'AGENTS.md') | Should -Be $false
            ($result.Output -join "`n") | Should -Match 'regular non-symlink file'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a symlinked template README_snippet.md before Apply can dereference it' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $template, $target, $outside | Out-Null
        try {
            New-TestTemplate $template
            $outsideSnippet = Join-Path $outside 'README_snippet.md'
            Set-Content -LiteralPath $outsideSnippet -Value 'synthetic external snippet data' -Encoding utf8NoBOM
            Remove-Item -LiteralPath (Join-Path $template 'README_snippet.md') -Force
            (New-TestSymlink $outsideSnippet (Join-Path $template 'README_snippet.md')) | Should -Be $true
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project' -Encoding utf8NoBOM

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Not -Be 0
            (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).Trim() | Should -Be '# Project'
            ($result.Output -join "`n") | Should -Match 'regular non-symlink file'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks Apply when a target descendant symlink would redirect a managed write' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $template, $target, $outside | Out-Null
        try {
            New-TestTemplate $template
            (New-TestSymlink $outside (Join-Path $target 'local')) | Should -Be $true

            $result = Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 2
            Test-Path -LiteralPath (Join-Path $outside 'ai/chat_context.md') | Should -Be $false
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureIfMissing' -and $_.Path -eq 'local/ai/chat_context.md' -and $_.Status -eq 'BLOCKED' }).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks exact instruction and skill links under symlinked ancestors in POSIX convergence' {
        if (-not (Get-TestSh)) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        $outsideGitHub = Join-Path $case 'outside-github'
        $outsideAgents = Join-Path $case 'outside-agents'
        New-Item -ItemType Directory -Force -Path $template, $target, $outsideGitHub, (Join-Path $outsideAgents 'skills'), (Join-Path $case 'skills/ai-bootstrap-converge') | Out-Null
        Set-Content -LiteralPath (Join-Path $case 'AGENTS.md') -Value 'outside agents' -Encoding utf8NoBOM
        try {
            New-TestTemplate $template
            (New-TestSymlink $outsideGitHub (Join-Path $target '.github')) | Should -Be $true
            (New-TestSymlink $outsideAgents (Join-Path $target '.agents')) | Should -Be $true
            (New-TestSymlink '../AGENTS.md' (Join-Path $outsideGitHub 'copilot-instructions.md')) | Should -Be $true
            (New-TestSymlink '../../skills/ai-bootstrap-converge' (Join-Path $outsideAgents 'skills/ai-bootstrap-converge')) | Should -Be $true

            $result = Invoke-ConvergeShell -Mode audit -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' -and $_.Status -eq 'BLOCKED' }).Count | Should -Be 1
            @($ops | Where-Object { $_.Type -eq 'EnsureSkillDiscoveryLink' -and $_.Path -eq '.agents/skills/ai-bootstrap-converge' -and $_.Status -eq 'BLOCKED' }).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an instruction symlink with an arbitrary AGENTS.md suffix' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target '.github'), (Join-Path $target 'nested') | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value 'canonical agents' -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $target 'nested/AGENTS.md') -Value 'synthetic alternate instructions' -Encoding utf8NoBOM
            (New-TestSymlink '../nested/AGENTS.md' (Join-Path $target '.github/copilot-instructions.md')) | Should -Be $true

            $result = Invoke-ConvergeShell -Mode audit -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            $op = @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' })
            $op.Count | Should -Be 1
            $op[0].Status | Should -Be 'CONFLICT'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a skill discovery symlink with an arbitrary skills suffix' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target '.agents/skills'), (Join-Path $target 'other/skills/ai-bootstrap-converge') | Out-Null
        try {
            New-TestTemplate $template
            (New-TestSymlink '../../other/skills/ai-bootstrap-converge' (Join-Path $target '.agents/skills/ai-bootstrap-converge')) | Should -Be $true

            $result = Invoke-ConvergeShell -Mode audit -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            $op = @($ops | Where-Object { $_.Type -eq 'EnsureSkillDiscoveryLink' -and $_.Path -eq '.agents/skills/ai-bootstrap-converge' })
            $op.Count | Should -Be 1
            $op[0].Status | Should -Be 'CONFLICT'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not accept a same-content copy as an instruction hardlink' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target '.github') | Out-Null
        try {
            New-TestTemplate $template
            Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value 'canonical agents' -Encoding utf8NoBOM
            Copy-Item -LiteralPath (Join-Path $target 'AGENTS.md') -Destination (Join-Path $target '.github/copilot-instructions.md')

            $result = Invoke-ConvergeShell -Mode audit -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' -and $_.Status -eq 'CONFLICT' }).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts an actual instruction hardlink' {
        $sh = Get-TestSh
        if (-not $sh) {
            Set-ItResult -Skipped -Because 'No POSIX sh is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target '.github') | Out-Null
        try {
            New-TestTemplate $template
            $agents = Join-Path $target 'AGENTS.md'
            $instruction = Join-Path $target '.github/copilot-instructions.md'
            Set-Content -LiteralPath $agents -Value 'canonical agents' -Encoding utf8NoBOM
            New-Item -ItemType HardLink -Path $instruction -Target $agents | Out-Null

            $result = Invoke-ConvergeShell -Mode audit -Target $target -Template $template -Json
            $result.ExitCode | Should -Be 0
            $ops = $result.Output -join "`n" | ConvertFrom-Json
            @($ops | Where-Object { $_.Type -eq 'EnsureInstructionLink' -and $_.Path -eq '.github/copilot-instructions.md' -and $_.Status -eq 'OK' }).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'mandatory init safety' {
    It 'resolves a Bash init root reached through a repository symlink' {
        if (-not (Get-TestBash)) {
            Set-ItResult -Skipped -Because 'No Bash executable is available in this environment.'
            return
        }

        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $link = Join-Path $case 'target-link'
        try {
            New-InitFixture $target
            (New-TestSymlink $target $link) | Should -Be $true

            $result = Invoke-InitShell $link

            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            (Get-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -First 1).Trim() | Should -Be 'true'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a hardlinked readiness file before PowerShell and Bash init mutations' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            $outside = Join-Path $case 'outside-ready.txt'
            try {
                New-InitFixture $target
                Remove-Item -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -Force
                Set-Content -LiteralPath $outside -Value 'outside unchanged' -Encoding utf8NoBOM
                New-Item -ItemType HardLink -Path (Join-Path $target 'local/ai/bootstrap.ready') -Target $outside | Out-Null

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }

                $result.ExitCode | Should -Not -Be 0
                ($result.Output -join "`n") | Should -Match 'hardlink|hard link'
                (Get-Content -Raw -LiteralPath $outside).Trim() | Should -Be 'outside unchanged'
                Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects tracked mutable runtime before PowerShell and Bash init mutations' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            try {
                New-InitFixture $target
                git -C $target add local/ai/bootstrap.ready | Out-Null

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }

                $result.ExitCode | Should -Not -Be 0
                ($result.Output -join "`n") | Should -Match 'tracked.*runtime|runtime.*tracked'
                (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
                Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'allows the tracked session summaries README in PowerShell and Bash init' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            try {
                New-InitFixture $target
                New-Item -ItemType Directory -Force -Path (Join-Path $target 'local/ai/session_summaries') | Out-Null
                Set-Content -LiteralPath (Join-Path $target 'local/ai/session_summaries/README.md') -Value 'tracked scaffold documentation' -Encoding utf8NoBOM
                git -C $target add local/ai/session_summaries/README.md | Out-Null

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }

                $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects deprecated credential residue before PowerShell and Bash init mutations' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            $legacy = Join-Path $target 'tmp/ai/cli_tokens'
            $sentinel = Join-Path $legacy 'sentinel.txt'
            try {
                New-InitFixture $target
                New-Item -ItemType Directory -Force -Path $legacy | Out-Null
                Set-Content -LiteralPath $sentinel -Value 'preserve for user decision' -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }

                $result.ExitCode | Should -Not -Be 0
                ($result.Output -join "`n") | Should -Match 'tmp/ai/cli_tokens'
                (Get-Content -Raw -LiteralPath $sentinel).Trim() | Should -Be 'preserve for user decision'
                (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
                Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'applies canonical runtime excludes without a project gitignore block' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            try {
                New-InitFixture $target
                Set-Content -LiteralPath (Join-Path $target '.gitignore') -Value '# project-owned ignore rules only' -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }

                $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
                $exclude = (& git -C $target rev-parse --path-format=absolute --git-path info/exclude).Trim()
                $excludeLines = @(Get-Content -LiteralPath $exclude)
                $readyLines = @(Get-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready'))
                $readyLines[0] | Should -Be 'true'
                foreach ($required in Get-RequiredRuntimeExcludeLines) {
                    @($excludeLines | Where-Object { $_ -ceq $required }).Count | Should -Be 1
                    @($readyLines | Where-Object { $_ -ceq $required }).Count | Should -Be 1
                }
                foreach ($assistant in @('gemini', 'qwen', 'codex', 'copilot', 'claude')) {
                    $session = Get-Content -Raw -LiteralPath (Join-Path $target "local/ai/$assistant/sessions.log") | ConvertFrom-Json
                    $request = Get-Content -Raw -LiteralPath (Join-Path $target "local/ai/$assistant/requests.log") | ConvertFrom-Json
                    $session.session_id | Should -Be "sample-$assistant-session"
                    $session.assistant | Should -Be $assistant
                    $request.request_id | Should -Be "sample-$assistant-req-001"
                    $request.assistant | Should -Be $assistant
                }
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not change parent Git metadata from a nested init root' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $parent = Join-Path $case 'parent'
            $target = Join-Path $parent 'nested-target'
            try {
                New-InitFixture $target -SkipGitInit
                git -C $parent -c init.defaultBranch=main init | Out-Null
                $exclude = (& git -C $parent rev-parse --path-format=absolute --git-path info/exclude).Trim()
                Set-Content -LiteralPath $exclude -Value 'parent-only-entry' -Encoding utf8NoBOM
                $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($exclude))

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }

                $result.ExitCode | Should -Not -Be 0
                $errorText = $result.Output -join "`n"
                $errorText | Should -Match 'Bootstrap root must be the Git worktree root'
                $errorText | Should -Match 'not modified'
                [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($exclude)) | Should -Be $before
                (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
                Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
                Test-Path -LiteralPath (Join-Path $target '.agents/skills/ai-bootstrap-converge') | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects incomplete managed AGENTS.md markers before init mutations' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            try {
                New-InitFixture $target
                Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value @'
<!-- AI AGENT INSTRUCTIONS BEGIN -->
damaged managed instructions
'@ -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }
                $result.ExitCode | Should -Not -Be 0
                ($result.Output -join "`n") | Should -Match 'managed instruction block'
                (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
                Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'updates a previous top README protocol snippet during init' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            try {
                New-InitFixture $target
                $previousSnippet = Get-TestProtocolSnippet -Version 'previous'
                Set-Content -LiteralPath (Join-Path $target 'README.md') -Value ($previousSnippet + "`n`n# Project README`nKeep this body.") -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }
                $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
                $snippet = Get-Content -Raw -LiteralPath (Join-Path $target 'README_snippet.md')
                $text = Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')
                $text.StartsWith($snippet.TrimEnd()) | Should -Be $true
                $text | Should -Not -Match 'previous'
                $text | Should -Match '# Project README'
                $text | Should -Match 'Keep this body'
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'accepts an existing AGENTS.md instruction hardlink during repeated init' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            try {
                New-InitFixture $target
                New-Item -ItemType Directory -Force -Path (Join-Path $target '.github') | Out-Null
                New-Item -ItemType HardLink -Path (Join-Path $target '.github/copilot-instructions.md') -Target (Join-Path $target 'AGENTS.md') | Out-Null

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }
                $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
                (Get-Content -Raw -LiteralPath (Join-Path $target '.github/copilot-instructions.md')) | Should -Be (Get-Content -Raw -LiteralPath (Join-Path $target 'AGENTS.md'))
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'applies the mandatory links in PowerShell init' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-InitFixture $target
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project' -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $target 'README.en.md') -Value '# Project EN' -Encoding utf8NoBOM
            $result = Invoke-InitPowerShell $target
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            (Get-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -First 1).Trim() | Should -Be 'true'
            (Get-Item -LiteralPath (Join-Path $target '.github/copilot-instructions.md') -Force).LinkType | Should -BeIn @('SymbolicLink', 'HardLink')
            (Get-Item -LiteralPath (Join-Path $target '.agents/skills/ai-bootstrap-converge') -Force).LinkType | Should -Be 'SymbolicLink'
            $snippet = Get-Content -Raw -LiteralPath (Join-Path $target 'README_snippet.md')
            foreach ($readme in @('README.md', 'README.en.md')) {
                $text = Get-Content -Raw -LiteralPath (Join-Path $target $readme)
                $text.StartsWith($snippet) | Should -Be $true
                $text | Should -Match '# Project'
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves a project-owned instruction file in PowerShell init' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path (Join-Path $target '.github') | Out-Null
        try {
            New-InitFixture $target
            $instruction = Join-Path $target '.github/copilot-instructions.md'
            Set-Content -LiteralPath $instruction -Value 'project-owned rules' -Encoding utf8NoBOM

            $result = Invoke-InitPowerShell $target
            $result.ExitCode | Should -Not -Be 0
            (Get-Content -Raw -LiteralPath $instruction).Trim() | Should -Be 'project-owned rules'
            (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
            Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
            Test-Path -LiteralPath (Join-Path $target '.agents/skills/ai-bootstrap-converge') | Should -Be $false
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks a symlinked instruction ancestor in PowerShell init' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $target, $outside | Out-Null
        try {
            New-InitFixture $target
            (New-TestSymlink $outside (Join-Path $target '.github')) | Should -Be $true

            $result = Invoke-InitPowerShell $target
            $result.ExitCode | Should -Not -Be 0
            Test-Path -LiteralPath (Join-Path $outside 'copilot-instructions.md') | Should -Be $false
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a symlinked skill child before PowerShell init mutations' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside.txt'
        try {
            New-InitFixture $target
            Set-Content -LiteralPath $outside -Value 'external skill content' -Encoding utf8NoBOM
            (New-TestSymlink $outside (Join-Path $target 'skills/ai-bootstrap-converge/external.txt')) | Should -Be $true

            $result = Invoke-InitPowerShell $target
            $result.ExitCode | Should -Not -Be 0
            Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
            (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves a project-owned instruction file in Bash init' {
        $bash = Get-TestBash
        if (-not $bash) {
            Set-ItResult -Skipped -Because 'No Bash executable is available in this environment.'
            return
        }
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path (Join-Path $target '.github') | Out-Null
        try {
            New-InitFixture $target
            $instruction = Join-Path $target '.github/copilot-instructions.md'
            Set-Content -LiteralPath $instruction -Value 'project-owned rules' -Encoding utf8NoBOM

            $result = Invoke-InitShell $target
            $result.ExitCode | Should -Not -Be 0
            (Get-Content -Raw -LiteralPath $instruction).Trim() | Should -Be 'project-owned rules'
            (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
            Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
            Test-Path -LiteralPath (Join-Path $target '.agents/skills/ai-bootstrap-converge') | Should -Be $false
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies the mandatory links in Bash init' {
        $bash = Get-TestBash
        if (-not $bash) {
            Set-ItResult -Skipped -Because 'No Bash executable is available in this environment.'
            return
        }
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-InitFixture $target
            Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project' -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $target 'README.en.md') -Value '# Project EN' -Encoding utf8NoBOM
            $result = Invoke-InitShell $target
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            (Get-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -First 1).Trim() | Should -Be 'true'
            (Get-Item -LiteralPath (Join-Path $target '.github/copilot-instructions.md') -Force).LinkType | Should -BeIn @('SymbolicLink', 'HardLink')
            (Get-Item -LiteralPath (Join-Path $target '.agents/skills/ai-bootstrap-converge') -Force).LinkType | Should -Be 'SymbolicLink'
            $snippet = Get-Content -Raw -LiteralPath (Join-Path $target 'README_snippet.md')
            foreach ($readme in @('README.md', 'README.en.md')) {
                $text = Get-Content -Raw -LiteralPath (Join-Path $target $readme)
                $text.StartsWith($snippet) | Should -Be $true
                $text | Should -Match '# Project'
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks a symlinked instruction ancestor in Bash init' {
        $bash = Get-TestBash
        if (-not $bash) {
            Set-ItResult -Skipped -Because 'No Bash executable is available in this environment.'
            return
        }
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        New-Item -ItemType Directory -Force -Path $target, $outside | Out-Null
        try {
            New-InitFixture $target
            (New-TestSymlink $outside (Join-Path $target '.github')) | Should -Be $true

            $result = Invoke-InitShell $target
            $result.ExitCode | Should -Not -Be 0
            Test-Path -LiteralPath (Join-Path $outside 'copilot-instructions.md') | Should -Be $false
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a symlinked skill child before Bash init mutations' {
        $bash = Get-TestBash
        if (-not $bash) {
            Set-ItResult -Skipped -Because 'No Bash executable is available in this environment.'
            return
        }
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside.txt'
        try {
            New-InitFixture $target
            Set-Content -LiteralPath $outside -Value 'external skill content' -Encoding utf8NoBOM
            (New-TestSymlink $outside (Join-Path $target 'skills/ai-bootstrap-converge/external.txt')) | Should -Be $true

            $result = Invoke-InitShell $target
            $result.ExitCode | Should -Not -Be 0
            Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
            (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a conflicting README before PowerShell and Bash init mutations' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            try {
                New-InitFixture $target
                $conflicting = "# Project`n<!-- AI AGENT PROTOCOL TRIGGER -->`n"
                Set-Content -LiteralPath (Join-Path $target 'README.md') -Value $conflicting -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }
                $result.ExitCode | Should -Not -Be 0
                Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
                Test-Path -LiteralPath (Join-Path $target '.agents/skills/ai-bootstrap-converge') | Should -Be $false
                (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
                (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).Trim() | Should -Be $conflicting.Trim()
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects an incomplete first README protocol comment before PowerShell and Bash init mutations' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            try {
                New-InitFixture $target
                $original = "<!--`nProject metadata: AI AGENT PROTOCOL TRIGGER:`n-->`n`n# Project README`n"
                Set-Content -LiteralPath (Join-Path $target 'README.md') -Value $original -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }
                $result.ExitCode | Should -Not -Be 0
                (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).Trim() | Should -Be $original.Trim()
                (Get-Content -Raw -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready')).Trim() | Should -Be 'false'
                Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md') | Should -Be $false
                Test-Path -LiteralPath (Join-Path $target '.agents/skills/ai-bootstrap-converge') | Should -Be $false
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'does not use a repository tmp symlink for PowerShell or Bash init temporary files' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            $target = Join-Path $case 'target'
            $outside = Join-Path $case 'outside-tmp'
            try {
                New-InitFixture $target
                New-Item -ItemType Directory -Force -Path $outside | Out-Null
                (New-TestSymlink $outside (Join-Path $target 'tmp')) | Should -Be $true
                Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# Project README' -Encoding utf8NoBOM
                Set-Content -LiteralPath (Join-Path $target 'README.en.md') -Value '# Project README EN' -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') { Invoke-InitPowerShell $target } else { Invoke-InitShell $target }
                $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
                @(Get-ChildItem -LiteralPath $outside -Force).Count | Should -Be 0
                (Get-Content -Raw -LiteralPath (Join-Path $target 'README.md')).StartsWith((Get-Content -Raw -LiteralPath (Join-Path $target 'README_snippet.md')).TrimEnd()) | Should -Be $true
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'review regressions' {
    It 'blocks an unknown external AGENTS.md hardlink in PowerShell and POSIX convergence' {
        foreach ($runner in @('PowerShell', 'POSIX')) {
            if ($runner -eq 'POSIX' -and -not (Get-TestSh)) { continue }
            $case = New-TestCaseRoot
            $template = Join-Path $case 'template'
            $target = Join-Path $case 'target'
            $outside = Join-Path $case 'outside-agents.md'
            New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
            try {
                New-TestTemplate $template
                @'
<!-- AI AGENT INSTRUCTIONS BEGIN -->
old managed instructions
<!-- AI AGENT INSTRUCTIONS END -->

# External file
'@ | Set-Content -LiteralPath $outside -Encoding utf8NoBOM
                New-Item -ItemType HardLink -Path (Join-Path $target 'AGENTS.md') -Target $outside | Out-Null
                $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($outside))

                $result = if ($runner -eq 'PowerShell') {
                    Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
                } else {
                    Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
                }

                $result.ExitCode | Should -Be 2 -Because ($result.Output -join "`n")
                ($result.Output -join "`n") | Should -Match 'BLOCKED|hardlink|hard link'
                [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($outside)) | Should -Be $before
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'blocks an unknown managed-file hardlink in PowerShell and POSIX convergence' {
        foreach ($runner in @('PowerShell', 'POSIX')) {
            if ($runner -eq 'POSIX' -and -not (Get-TestSh)) { continue }
            $case = New-TestCaseRoot
            $template = Join-Path $case 'template'
            $target = Join-Path $case 'target'
            $outside = Join-Path $case 'outside-module.md'
            $relative = 'local/ai/agents/01-bootstrap.md'
            New-Item -ItemType Directory -Force -Path $template, $target, (Join-Path $target 'local/ai/agents') | Out-Null
            try {
                New-TestTemplate $template
                Copy-Item -LiteralPath (Join-Path $template $relative) -Destination $outside
                New-Item -ItemType HardLink -Path (Join-Path $target $relative) -Target $outside | Out-Null
                $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($outside))

                $result = if ($runner -eq 'PowerShell') {
                    Invoke-ConvergePowerShell -Mode Verify -Target $target -Template $template -Json
                } else {
                    Invoke-ConvergeShell -Mode verify -Target $target -Template $template -Json
                }

                $result.ExitCode | Should -Be 1 -Because ($result.Output -join "`n")
                $operations = ($result.Output -join "`n") | ConvertFrom-Json
                @($operations | Where-Object { $_.Path -eq $relative -and $_.Status -eq 'BLOCKED' }).Count | Should -Be 1
                [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($outside)) | Should -Be $before
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'uses case-sensitive exclude matching in PowerShell convergence' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $target = Join-Path $case 'target'
        New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
        try {
            New-TestTemplate $template
            git -C $target -c init.defaultBranch=main init | Out-Null
            $exclude = (& git -C $target rev-parse --path-format=absolute --git-path info/exclude).Trim()
            Set-Content -LiteralPath $exclude -Value 'TMP/AI/' -Encoding utf8NoBOM

            $result = Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json

            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            @(Get-Content -LiteralPath $exclude | Where-Object { $_ -ceq 'tmp/ai/' }).Count | Should -Be 1
            @(Get-Content -LiteralPath $exclude | Where-Object { $_ -ceq 'TMP/AI/' }).Count | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'migrates only legacy scaffold-wide exclude entries in both convergence scripts' {
        foreach ($runner in @('PowerShell', 'POSIX')) {
            if ($runner -eq 'POSIX' -and -not (Get-TestSh)) { continue }
            $case = New-TestCaseRoot
            $template = Join-Path $case 'template'
            $target = Join-Path $case 'target'
            New-Item -ItemType Directory -Force -Path $template, $target | Out-Null
            try {
                New-TestTemplate $template
                Set-RuntimeExcludeTemplateBlock $template
                git -C $target -c init.defaultBranch=main init | Out-Null
                $exclude = (& git -C $target rev-parse --path-format=absolute --git-path info/exclude).Trim()
                @('project-cache/', 'AGENTS.md', 'local/ai/', '.claude/', 'tmp/ai/') |
                    Set-Content -LiteralPath $exclude -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') {
                    Invoke-ConvergePowerShell -Mode Apply -Target $target -Template $template -Json
                } else {
                    Invoke-ConvergeShell -Mode apply -Target $target -Template $template -Json
                }

                $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
                $actual = @(Get-Content -LiteralPath $exclude)
                $actual | Should -Contain 'project-cache/'
                foreach ($obsolete in @('AGENTS.md', 'local/ai/', '.claude/')) {
                    @($actual | Where-Object { $_ -ceq $obsolete }).Count | Should -Be 0
                }
                foreach ($required in Get-RequiredRuntimeExcludeLines) {
                    @($actual | Where-Object { $_ -ceq $required }).Count | Should -Be 1
                }
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'keeps mandatory scaffold visible and defines the strict logging fallback' {
        $gitignore = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.gitignore')
        foreach ($obsolete in @('# AGENTS.md', '# local/ai/', '# .claude/', '# README_snippet.md')) {
            $gitignore | Should -Not -Match ([regex]::Escape($obsolete) + '(?:\r?\n|$)')
        }
        foreach ($required in Get-RequiredRuntimeExcludeLines) {
            $gitignore | Should -Match ([regex]::Escape("# $required") + '(?:\r?\n|$)')
        }

        $logging = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'local/ai/agents/02-logging.md')
        $bootstrap = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'local/ai/agents/01-bootstrap.md')
        foreach ($text in @($logging, $bootstrap)) {
            $text | Should -Match ([regex]::Escape('tmp/ai/<assistant>/requests.log'))
        }
        $logging | Should -Match 'одно минимальное техническое сообщение|one minimal technical message'

        $snippet = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'README_snippet.md')
        $snippet | Should -Match ([regex]::Escape('tmp/ai/cli_tokens'))
        $snippet | Should -Match 'устаревш|deprecated'

        $sandboxPosition = $bootstrap.IndexOf('sandbox_mode', [System.StringComparison]::Ordinal)
        $applyPosition = $bootstrap.IndexOf('Step 1a (mandatory apply)', [System.StringComparison]::Ordinal)
        $sandboxPosition | Should -BeGreaterThan -1
        $applyPosition | Should -BeGreaterThan $sandboxPosition

        foreach ($readme in @('README.md', 'README.en.md')) {
            $readmeText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $readme)
            $readmeText | Should -Not -Match 'populates `\.git/info/exclude` based on the list in `\.gitignore`|заполнения `\.git/info/exclude` по списку из `\.gitignore`'
        }

        foreach ($script in @(
            'local/ai/scripts/init.ps1',
            'local/ai/scripts/init.sh',
            'skills/ai-bootstrap-converge/scripts/converge.ps1',
            'skills/ai-bootstrap-converge/scripts/converge.sh'
        )) {
            (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $script)) |
                Should -Match ([regex]::Escape(':!local/ai/session_summaries/README.md'))
        }
        $convergeShell = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'skills/ai-bootstrap-converge/scripts/converge.sh')
        $convergeShell | Should -Not -Match 'rm -f "\$path"'
        $convergeShell | Should -Match 'ln -P "\$agent" "\$path"'
    }
}

Describe 'bootstrap check validation' {
    It 'uses the script repository when invoked from another working directory' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            Push-Location $case
            try {
                $powerShellOutput = & pwsh -NoProfile -File (Join-Path $target 'local/ai/scripts/bootstrap_check.ps1') 2>&1
                $powerShellExit = $LASTEXITCODE
                $powerShellExit | Should -Be 0 -Because ($powerShellOutput -join "`n")

                $bash = Get-TestBash
                if ($bash) {
                    $script = Convert-ToShPath $bash (Join-Path $target 'local/ai/scripts/bootstrap_check.sh')
                    $shellOutput = & $bash $script 2>&1
                    $LASTEXITCODE | Should -Be 0 -Because ($shellOutput -join "`n")
                }
            } finally {
                Pop-Location
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not modify parent repository Git metadata from a nested fixture' {
        $sourceExclude = (& git -C $RepoRoot rev-parse --path-format=absolute --git-path info/exclude).Trim()
        $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($sourceExclude))
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            $actualTopLevel = (& git -C $target rev-parse --show-toplevel).Trim()
            [System.IO.Path]::GetFullPath($actualTopLevel) | Should -Be ([System.IO.Path]::GetFullPath($target))
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($sourceExclude)) | Should -Be $before
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects deprecated credential residue without reading or removing it' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $legacy = Join-Path $target 'tmp/ai/cli_tokens'
        $sentinel = Join-Path $legacy 'sentinel.txt'
        try {
            New-BootstrapCheckFixture $target
            New-Item -ItemType Directory -Force -Path $legacy | Out-Null
            Set-Content -LiteralPath $sentinel -Value 'preserve for user decision' -Encoding utf8NoBOM

            $powerShellOutput = & pwsh -NoProfile -File (Join-Path $target 'local/ai/scripts/bootstrap_check.ps1') 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($powerShellOutput -join "`n") | Should -Match 'tmp/ai/cli_tokens'

            $bash = Get-TestBash
            if ($bash) {
                $script = Convert-ToShPath $bash (Join-Path $target 'local/ai/scripts/bootstrap_check.sh')
                $shellOutput = & $bash $script 2>&1
                $LASTEXITCODE | Should -Not -Be 0
                ($shellOutput -join "`n") | Should -Match 'tmp/ai/cli_tokens'
            }

            (Get-Content -Raw -LiteralPath $sentinel).Trim() | Should -Be 'preserve for user decision'
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts canonical JSONL samples in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts AGENTS.md with an instruction hardlink in PowerShell and Bash checks' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            try {
                New-BootstrapCheckFixture $case
                $instruction = Join-Path $case '.github/copilot-instructions.md'
                Remove-Item -LiteralPath $instruction -Force
                New-Item -ItemType HardLink -Path $instruction -Target (Join-Path $case 'AGENTS.md') | Out-Null

                $result = if ($runner -eq 'PowerShell') { Invoke-BootstrapCheckPowerShell $case } else { Invoke-BootstrapCheckShell $case }
                $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects incomplete readiness in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            Set-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -Value 'false' -Encoding utf8NoBOM
            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects false readiness even when exclude patterns follow' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            Set-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -Value @('false', 'tmp/ai/') -Encoding utf8NoBOM
            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects missing assistant logs in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            Remove-Item -LiteralPath (Join-Path $target 'local/ai/codex/sessions.log'), (Join-Path $target 'local/ai/codex/requests.log') -Force
            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects timestamp-shaped non-JSON text in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            Set-Content -LiteralPath (Join-Path $target 'local/ai/codex/requests.log') -Value 'not-json 1970-01-01T00:00:00Z' -Encoding utf8NoBOM
            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects duplicate and case-variant JSON keys in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            $log = Join-Path $target 'local/ai/codex/requests.log'
            $invalidEntries = @(
                '{"timestamp":"1970-01-01T00:00:00Z","timestamp":"YYYY-MM-DDTHH:MM:SSZ","request_id":"sample-codex-req-001","assistant":"codex","summary":"placeholder summary","tools":[],"status":"success"}',
                '{"Timestamp":"YYYY-MM-DDTHH:MM:SSZ","request_id":"sample-codex-req-001","assistant":"codex","summary":"placeholder summary","tools":[],"status":"success"}'
            )
            foreach ($entry in $invalidEntries) {
                Set-Content -LiteralPath $log -Value $entry -Encoding utf8NoBOM
                (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
                $shell = Invoke-BootstrapCheckShell $target
                if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a modified placeholder entry in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            Set-Content -LiteralPath (Join-Path $target 'local/ai/codex/requests.log') -Value '{"timestamp":"YYYY-MM-DDTHH:MM:SSZ","request_id":"sample-codex-req-001","assistant":"codex","summary":"runtime data","tools":[],"status":"success","extra":"not allowed"}' -Encoding utf8NoBOM
            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an external AGENTS.md instruction symlink in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        try {
            New-BootstrapCheckFixture $target
            New-Item -ItemType Directory -Force -Path $outside | Out-Null
            $outsideAgents = Join-Path $outside 'AGENTS.md'
            Set-Content -LiteralPath $outsideAgents -Value 'external rules' -Encoding utf8NoBOM
            Remove-Item -LiteralPath (Join-Path $target '.github/copilot-instructions.md') -Force
            (New-TestSymlink $outsideAgents (Join-Path $target '.github/copilot-instructions.md')) | Should -Be $true

            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an external AGENTS.md source symlink in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside-AGENTS.md'
        try {
            New-BootstrapCheckFixture $target
            Set-Content -LiteralPath $outside -Value 'external rules' -Encoding utf8NoBOM
            Remove-Item -LiteralPath (Join-Path $target 'AGENTS.md') -Force
            (New-TestSymlink $outside (Join-Path $target 'AGENTS.md')) | Should -Be $true

            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects incomplete managed AGENTS.md markers in PowerShell and Bash checks' {
        foreach ($runner in @('PowerShell', 'Bash')) {
            if ($runner -eq 'Bash' -and -not (Get-TestBash)) { continue }
            $case = New-TestCaseRoot
            try {
                New-BootstrapCheckFixture $case
                Set-Content -LiteralPath (Join-Path $case 'AGENTS.md') -Value @'
<!-- AI AGENT INSTRUCTIONS BEGIN -->
damaged managed instructions
'@ -Encoding utf8NoBOM

                $result = if ($runner -eq 'PowerShell') { Invoke-BootstrapCheckPowerShell $case } else { Invoke-BootstrapCheckShell $case }
                $result.ExitCode | Should -Not -Be 0
                ($result.Output -join "`n") | Should -Match 'managed block'
            } finally {
                Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'rejects a symlinked child in the canonical skill directory' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside-skill.md'
        try {
            New-BootstrapCheckFixture $target
            Set-Content -LiteralPath $outside -Value 'external skill content' -Encoding utf8NoBOM
            (New-TestSymlink $outside (Join-Path $target 'skills/ai-bootstrap-converge/external.md')) | Should -Be $true

            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an external README symlink in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        try {
            New-BootstrapCheckFixture $target
            New-Item -ItemType Directory -Force -Path $outside | Out-Null
            $outsideReadme = Join-Path $outside 'README.md'
            Set-Content -LiteralPath $outsideReadme -Value '<!-- AI AGENT PROTOCOL TRIGGER -->' -Encoding utf8NoBOM
            Remove-Item -LiteralPath (Join-Path $target 'README.md') -Force
            (New-TestSymlink $outsideReadme (Join-Path $target 'README.md')) | Should -Be $true

            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an external assistant log symlink in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside'
        try {
            New-BootstrapCheckFixture $target
            New-Item -ItemType Directory -Force -Path $outside | Out-Null
            $outsideLog = Join-Path $outside 'requests.log'
            Set-Content -LiteralPath $outsideLog -Value '{"timestamp":"YYYY-MM-DDTHH:MM:SSZ","request_id":"sample-codex-req-001","assistant":"codex","summary":"placeholder summary","tools":[],"status":"success"}' -Encoding utf8NoBOM
            Remove-Item -LiteralPath (Join-Path $target 'local/ai/codex/requests.log') -Force
            (New-TestSymlink $outsideLog (Join-Path $target 'local/ai/codex/requests.log')) | Should -Be $true

            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an external assistant log hardlink in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        $outside = Join-Path $case 'outside-requests.log'
        try {
            New-BootstrapCheckFixture $target
            Remove-Item -LiteralPath (Join-Path $target 'local/ai/codex/requests.log') -Force
            Set-Content -LiteralPath $outside -Value '{"timestamp":"YYYY-MM-DDTHH:MM:SSZ","request_id":"sample-codex-req-001","assistant":"codex","summary":"placeholder summary","tools":[],"status":"success"}' -Encoding utf8NoBOM
            New-Item -ItemType HardLink -Path (Join-Path $target 'local/ai/codex/requests.log') -Target $outside | Out-Null

            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'requires exact git exclude lines in PowerShell and Bash' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            git -C $target -c init.defaultBranch=main init | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'local/ai/bootstrap.ready') -Value @('true', 'AGENTS.md') -Encoding utf8NoBOM
            $exclude = (& git -C $target rev-parse --path-format=absolute --git-path info/exclude).Trim()
            Set-Content -LiteralPath $exclude -Value 'AGENTS.md.backup' -Encoding utf8NoBOM

            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Not -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Not -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ignores unrelated diagnostic logs outside assistant log names' {
        $case = New-TestCaseRoot
        $target = Join-Path $case 'target'
        try {
            New-BootstrapCheckFixture $target
            New-Item -ItemType Directory -Force -Path (Join-Path $target 'local/ai/context_packs') | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'local/ai/context_packs/debug.log') -Value 'not assistant JSONL' -Encoding utf8NoBOM

            (Invoke-BootstrapCheckPowerShell $target).ExitCode | Should -Be 0
            $shell = Invoke-BootstrapCheckShell $target
            if ($null -ne $shell) { $shell.ExitCode | Should -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'linked worktree support' {
    It 'uses the git common exclude path in PowerShell and POSIX convergence' {
        $case = New-TestCaseRoot
        $template = Join-Path $case 'template'
        $base = Join-Path $case 'base'
        $targetPowerShell = Join-Path $case 'target-powershell'
        $targetShell = Join-Path $case 'target-shell'
        New-Item -ItemType Directory -Force -Path $template, $base | Out-Null
        try {
            New-TestTemplate $template
            git -C $base -c init.defaultBranch=main init | Out-Null
            Set-Content -LiteralPath (Join-Path $base 'seed.txt') -Value 'seed' -Encoding utf8NoBOM
            git -C $base add seed.txt | Out-Null
            git -C $base -c user.name='Bootstrap Tests' -c user.email='bootstrap@example.invalid' commit -m seed | Out-Null
            git -C $base worktree add -b test-powershell $targetPowerShell | Out-Null
            git -C $base worktree add -b test-shell $targetShell | Out-Null
            $exclude = Join-Path $base '.git/info/exclude'
            Remove-Item -LiteralPath $exclude -Force -ErrorAction SilentlyContinue

            $powerShellResult = Invoke-ConvergePowerShell -Mode Apply -Target $targetPowerShell -Template $template -Json
            ((0, 2) -contains $powerShellResult.ExitCode) | Should -Be $true
            (Get-Content -LiteralPath $exclude) | Should -Contain 'tmp/ai/'

            $shell = Get-TestSh
            if ($shell) {
                Remove-Item -LiteralPath $exclude -Force
                $shellResult = Invoke-ConvergeShell -Mode apply -Target $targetShell -Template $template -Json
                ((0, 2) -contains $shellResult.ExitCode) | Should -Be $true
                (Get-Content -LiteralPath $exclude) | Should -Contain 'tmp/ai/'
            }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'uses the git common exclude path in init and bootstrap checks' {
        $case = New-TestCaseRoot
        $base = Join-Path $case 'base'
        $targetPowerShell = Join-Path $case 'init-powershell'
        $targetShell = Join-Path $case 'init-shell'
        $targetCheck = Join-Path $case 'bootstrap-check'
        New-Item -ItemType Directory -Force -Path $base | Out-Null
        try {
            git -C $base -c init.defaultBranch=main init | Out-Null
            Set-Content -LiteralPath (Join-Path $base 'seed.txt') -Value 'seed' -Encoding utf8NoBOM
            git -C $base add seed.txt | Out-Null
            git -C $base -c user.name='Bootstrap Tests' -c user.email='bootstrap@example.invalid' commit -m seed | Out-Null
            git -C $base worktree add -b init-powershell $targetPowerShell | Out-Null
            git -C $base worktree add -b init-shell $targetShell | Out-Null
            git -C $base worktree add -b bootstrap-check $targetCheck | Out-Null
            $exclude = Join-Path $base '.git/info/exclude'

            New-InitFixture $targetPowerShell -SkipGitInit
            (Invoke-InitPowerShell $targetPowerShell).ExitCode | Should -Be 0
            (Get-Content -LiteralPath $exclude) | Should -Contain 'tmp/ai/'

            New-InitFixture $targetShell -SkipGitInit
            Remove-Item -LiteralPath $exclude -Force
            $shellInit = Invoke-InitShell $targetShell
            if ($null -ne $shellInit) {
                $shellInit.ExitCode | Should -Be 0
                (Get-Content -LiteralPath $exclude) | Should -Contain 'tmp/ai/'
            }

            New-BootstrapCheckFixture $targetCheck
            Set-Content -LiteralPath (Join-Path $targetCheck 'local/ai/bootstrap.ready') -Value @('true', 'tmp/ai/') -Encoding utf8NoBOM
            Set-Content -LiteralPath $exclude -Value 'tmp/ai/' -Encoding utf8NoBOM
            (Invoke-BootstrapCheckPowerShell $targetCheck).ExitCode | Should -Be 0
            $shellCheck = Invoke-BootstrapCheckShell $targetCheck
            if ($null -ne $shellCheck) { $shellCheck.ExitCode | Should -Be 0 }
        } finally {
            Remove-Item -LiteralPath $case -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
