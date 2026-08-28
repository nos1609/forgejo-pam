[CmdletBinding()]
param(
    [ValidateSet("Audit", "Plan", "Apply", "Verify")]
    [string]$Mode = "Audit",

    [string]$Target = ".",

    [string]$Template = $env:AI_BOOTSTRAP_TEMPLATE,

    [string]$SourceRef = "",

    [switch]$IncludeClaude,

    [switch]$ForceManagedExact,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Operations = New-Object System.Collections.Generic.List[object]
$script:TemplateScratch = $null
$script:AgentsBeginMarker = "<!-- AI AGENT INSTRUCTIONS BEGIN -->"
$script:AgentsEndMarker = "<!-- AI AGENT INSTRUCTIONS END -->"
$script:IsWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$script:IsMacOSPlatform = $false
if (-not $script:IsWindowsPlatform) {
    $uname = Get-Command uname -ErrorAction SilentlyContinue
    if ($uname) { $script:IsMacOSPlatform = ((& $uname.Source -s 2>$null) -eq "Darwin") }
}

function Resolve-Directory([string]$Path, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Label path is required."
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label path does not exist or is not a directory: $Path"
    }
    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Add-Operation {
    param(
        [string]$Status,
        [string]$Type,
        [string]$Path,
        [string]$Detail,
        [bool]$Safe = $false
    )
    $script:Operations.Add([pscustomobject]@{
        Status = $Status
        Type = $Type
        Path = $Path
        Detail = $Detail
        Safe = $Safe
    }) | Out-Null
}

function Get-LinkType([System.IO.FileSystemInfo]$Item) {
    if ($Item.PSObject.Properties.Name -contains "LinkType") {
        return [string]$Item.LinkType
    }
    return ""
}

function Test-PathInsideRoot {
    param([string]$Root, [string]$Path)

    $rootPath = [System.IO.Path]::GetFullPath($Root)
    $candidatePath = [System.IO.Path]::GetFullPath($Path)
    $comparison = if ($script:IsWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ([string]::Equals($rootPath, $candidatePath, $comparison)) { return $true }
    $prefix = $rootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    return $candidatePath.StartsWith($prefix, $comparison)
}

function Test-PathTreeSafe {
    param(
        [string]$Root,
        [string]$Path,
        [switch]$AllowLeafLink,
        [switch]$AllowLeafHardLink
    )

    if (-not (Test-PathInsideRoot $Root $Path)) { return $false }
    $rootPath = [System.IO.Path]::GetFullPath($Root)
    $candidatePath = [System.IO.Path]::GetFullPath($Path)
    $comparison = if ($script:IsWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ([string]::Equals($rootPath, $candidatePath, $comparison)) { return $true }
    $prefix = $rootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    $relative = $candidatePath.Substring($prefix.Length)

    $parts = @($relative -split '[\\/]+' | Where-Object { $_ -and $_ -ne "." })
    $current = $rootPath
    for ($index = 0; $index -lt $parts.Count; $index++) {
        if ($parts[$index] -eq "..") { return $false }
        $current = Join-Path $current $parts[$index]
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }

        $isLeaf = $index -eq ($parts.Count - 1)
        $linkType = Get-LinkType $item
        $allowedLink = $isLeaf -and ($AllowLeafLink -or ($AllowLeafHardLink -and $linkType -eq "HardLink"))
        if ($linkType -and -not $allowedLink) { return $false }
        if (-not $isLeaf -and -not $item.PSIsContainer) { return $false }
    }
    return $true
}

function Test-AllowTargetPath {
    param(
        [string]$TargetRoot,
        [string]$Path,
        [string]$Type,
        [string]$Relative,
        [switch]$AllowLeafLink,
        [switch]$AllowLeafHardLink
    )

    if (Test-PathTreeSafe $TargetRoot $Path -AllowLeafLink:$AllowLeafLink -AllowLeafHardLink:$AllowLeafHardLink) { return $true }
    Add-Operation "BLOCKED" $Type $Relative "Target mutation blocked: destination or ancestor is a link or escapes the canonical target root." $false
    return $false
}

function Assert-TemplateSources {
    param([string]$TemplateRoot)

    foreach ($relative in @("AGENTS.md", "README_snippet.md", ".gitignore", "local/ai/bootstrap.ready")) {
        $path = Join-Path $TemplateRoot $relative
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        if ($item.PSIsContainer -or (Get-LinkType $item) -or -not (Test-PathTreeSafe $TemplateRoot $path)) {
            throw "Template source is not a regular non-symlink file inside the canonical template root: $relative"
        }
    }

    foreach ($relative in @("local/ai", "local/ai/agents", "local/ai/scripts", "skills/ai-bootstrap-converge")) {
        $path = Join-Path $TemplateRoot $relative
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        if (-not $item.PSIsContainer -or (Get-LinkType $item) -or -not (Test-PathTreeSafe $TemplateRoot $path)) {
            throw "Template source is not a non-symlink directory inside the canonical template root: $relative"
        }
        $linkedChild = Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction Stop |
            Where-Object { Get-LinkType $_ } |
            Select-Object -First 1
        if ($null -ne $linkedChild) {
            throw "Template source is not a non-symlink directory inside the canonical template root: $relative"
        }
    }

    $agentsPath = Join-Path $TemplateRoot "AGENTS.md"
    if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
        $agentsText = [System.IO.File]::ReadAllText($agentsPath, [System.Text.Encoding]::UTF8)
        $beginMatches = [regex]::Matches($agentsText, "(?m)^$([regex]::Escape($script:AgentsBeginMarker))\r?$")
        $endMatches = [regex]::Matches($agentsText, "(?m)^$([regex]::Escape($script:AgentsEndMarker))\r?$")
        $trimmed = $agentsText.TrimEnd([char[]]"`r`n")
        if ($beginMatches.Count -ne 1 -or $endMatches.Count -ne 1 -or
            $beginMatches[0].Index -ne 0 -or
            $endMatches[0].Index -le $beginMatches[0].Index -or
            -not $trimmed.EndsWith($script:AgentsEndMarker, [System.StringComparison]::Ordinal)) {
            throw "Template AGENTS.md must contain exactly one complete managed instruction block spanning the file."
        }
    }
}

function Test-GitTargetRoot {
    param([string]$TargetRoot)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    $reported = & git -C $TargetRoot rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$reported)) { return $false }

    $targetPath = [System.IO.Path]::GetFullPath($TargetRoot)
    $topLevelPath = [System.IO.Path]::GetFullPath(([string]$reported).Trim())
    $comparison = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    return [string]::Equals($targetPath, $topLevelPath, $comparison)
}

function Get-GitPath {
    param([string]$TargetRoot, [string]$GitPath)

    if (-not (Test-GitTargetRoot $TargetRoot)) { return $null }

    $reported = & git -C $TargetRoot rev-parse --path-format=absolute --git-path $GitPath 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($reported)) { return $null }
    return [System.IO.Path]::GetFullPath(([string]$reported).Trim())
}

function Get-GitCommonDirectory {
    param([string]$TargetRoot)

    if (-not (Test-GitTargetRoot $TargetRoot)) { return $null }
    $reported = & git -C $TargetRoot rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($reported)) { return $null }
    return [System.IO.Path]::GetFullPath(([string]$reported).Trim())
}

function Test-SameFileIdentity {
    param([string]$First, [string]$Second)

    if (-not (Test-Path -LiteralPath $First -PathType Leaf) -or -not (Test-Path -LiteralPath $Second -PathType Leaf)) {
        return $false
    }

    if ($script:IsWindowsPlatform) {
        if ([System.IO.Path]::GetPathRoot($First) -ne [System.IO.Path]::GetPathRoot($Second)) { return $false }
        $firstId = & fsutil file queryfileid $First 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $secondId = & fsutil file queryfileid $Second 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $firstMatch = [regex]::Match(($firstId -join " "), '0x[0-9a-fA-F]+')
        $secondMatch = [regex]::Match(($secondId -join " "), '0x[0-9a-fA-F]+')
        return $firstMatch.Success -and $secondMatch.Success -and $firstMatch.Value -eq $secondMatch.Value
    }

    $stat = Get-Command stat -ErrorAction SilentlyContinue
    if (-not $stat) { return $false }
    if ($script:IsMacOSPlatform) {
        $firstId = & $stat.Source -f '%d:%i' $First 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $secondId = & $stat.Source -f '%d:%i' $Second 2>$null
    } else {
        $firstId = & $stat.Source -Lc '%d:%i' -- $First 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $secondId = & $stat.Source -Lc '%d:%i' -- $Second 2>$null
    }
    return $LASTEXITCODE -eq 0 -and ([string]$firstId).Trim() -eq ([string]$secondId).Trim()
}

function Get-HardLinkCount {
    param([string]$Path)

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
    param([string]$TargetRoot)

    return @(
        '.github/copilot-instructions.md',
        '.claude/CLAUDE.md',
        'CLAUDE.md',
        '.gemini/GEMINI.md',
        'GEMINI.md',
        '.qwen/QWEN.md',
        'QWEN.md'
    ) | ForEach-Object { Join-Path $TargetRoot $_ }
}

function Get-KnownAgentsHardlinks {
    param([string]$TargetRoot, [string]$AgentsPath)

    $known = New-Object System.Collections.Generic.List[string]
    foreach ($path in Get-KnownInstructionPaths $TargetRoot) {
        if ((Test-PathTreeSafe $TargetRoot $path -AllowLeafHardLink) -and
            (Test-SameFileIdentity $path $AgentsPath)) {
            $known.Add($path) | Out-Null
        }
    }
    return $known
}

function Test-AgentsHardlinksKnown {
    param([string]$TargetRoot, [string]$AgentsPath)

    $count = Get-HardLinkCount $AgentsPath
    if ($null -eq $count) { return $false }
    $known = @(Get-KnownAgentsHardlinks $TargetRoot $AgentsPath)
    return $count -eq ($known.Count + 1)
}

function Get-RelativePath([string]$Base, [string]$Path) {
    $basePath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Base).Path)
    $targetPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
    $comparison = if ($script:IsWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $baseRoot = [System.IO.Path]::GetPathRoot($basePath)
    $targetRoot = [System.IO.Path]::GetPathRoot($targetPath)
    if (-not [string]::Equals($baseRoot, $targetRoot, $comparison)) {
        throw "Cannot calculate a relative path across filesystem roots."
    }

    $baseTail = $basePath.Substring($baseRoot.Length).Trim([char[]]@('\', '/'))
    $targetTail = $targetPath.Substring($targetRoot.Length).Trim([char[]]@('\', '/'))
    $baseParts = if ($baseTail) { @($baseTail -split '[\\/]+') } else { @() }
    $targetParts = if ($targetTail) { @($targetTail -split '[\\/]+') } else { @() }
    $common = 0
    while ($common -lt $baseParts.Count -and $common -lt $targetParts.Count -and
        [string]::Equals($baseParts[$common], $targetParts[$common], $comparison)) {
        $common++
    }

    $segments = New-Object System.Collections.Generic.List[string]
    for ($index = $common; $index -lt $baseParts.Count; $index++) { $segments.Add('..') | Out-Null }
    for ($index = $common; $index -lt $targetParts.Count; $index++) { $segments.Add($targetParts[$index]) | Out-Null }
    if ($segments.Count -eq 0) { return '.' }
    return ($segments -join '/')
}

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Text([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $temporary = Join-Path $dir ('.ai-bootstrap-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporary, $Text, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Write-AgentsText {
    param([string]$TargetRoot, [string]$Path, [string]$Text)

    if (-not (Test-AgentsHardlinksKnown $TargetRoot $Path)) {
        throw 'AGENTS.md has a hardlink outside the known instruction-link set.'
    }
    $known = @(Get-KnownAgentsHardlinks $TargetRoot $Path)
    Write-Text $Path $Text

    foreach ($link in $known) {
        $parent = Split-Path -Parent $link
        $temporary = Join-Path $parent ('.ai-bootstrap-link-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            New-Item -ItemType HardLink -Path $temporary -Target $Path -ErrorAction Stop | Out-Null
            Move-Item -LiteralPath $temporary -Destination $link -Force -ErrorAction Stop
        } finally {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-LinesAtomic {
    param([string]$Path, [string[]]$Lines)

    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $temporary = Join-Path $dir ('.ai-bootstrap-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllLines($temporary, $Lines, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Copy-FileExact([string]$Source, [string]$Destination) {
    $dir = Split-Path -Parent $Destination
    if ($dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $temporary = Join-Path $dir (".ai-bootstrap-" + [guid]::NewGuid().ToString("N") + ".tmp")
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary -ErrorAction Stop
        Move-Item -LiteralPath $temporary -Destination $Destination -Force -ErrorAction Stop
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-TemplateRoot {
    param([string]$TemplateValue, [string]$Ref)

    if ([string]::IsNullOrWhiteSpace($TemplateValue)) {
        throw "Template is required. Pass -Template or set AI_BOOTSTRAP_TEMPLATE."
    }

    if (Test-Path -LiteralPath $TemplateValue -PathType Container) {
        return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $TemplateValue).Path)
    }

    if ($TemplateValue.StartsWith("-", [System.StringComparison]::Ordinal)) {
        throw "Remote template value must not start with '-': $TemplateValue"
    }
    if (-not [string]::IsNullOrWhiteSpace($Ref) -and $Ref.StartsWith("-", [System.StringComparison]::Ordinal)) {
        throw "Source ref must not start with '-': $Ref"
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        throw "Template '$TemplateValue' is not a local directory and git is unavailable."
    }

    $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-bootstrap-template-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null
    $script:TemplateScratch = $scratchRoot

    if ([string]::IsNullOrWhiteSpace($Ref)) {
        & git clone --depth 1 -- $TemplateValue $scratchRoot | Out-Null
    } else {
        & git clone --depth 1 --branch $Ref -- $TemplateValue $scratchRoot | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
            $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-bootstrap-template-" + [guid]::NewGuid().ToString("N"))
            $script:TemplateScratch = $scratchRoot
            & git clone -- $TemplateValue $scratchRoot | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git clone failed for template: $TemplateValue" }
            & git -C $scratchRoot checkout $Ref | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git checkout failed for template ref: $Ref" }
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed for template: $TemplateValue"
    }
    return $scratchRoot
}

function Get-TemplateFilesByRoots {
    param([string]$TemplateRoot, [string[]]$Roots)
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($root in $Roots) {
        $path = Join-Path $TemplateRoot $root
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $files.Add($path) | Out-Null
        } elseif (Test-Path -LiteralPath $path -PathType Container) {
            Get-ChildItem -LiteralPath $path -Recurse -File -Force | ForEach-Object {
                $files.Add($_.FullName) | Out-Null
            }
        }
    }
    return $files
}

function Test-FileSame([string]$A, [string]$B) {
    if (-not (Test-Path -LiteralPath $A -PathType Leaf) -or -not (Test-Path -LiteralPath $B -PathType Leaf)) {
        return $false
    }
    $hashA = Get-FileHash -LiteralPath $A -Algorithm SHA256
    $hashB = Get-FileHash -LiteralPath $B -Algorithm SHA256
    return $hashA.Hash -eq $hashB.Hash
}

function Ensure-ManagedExact {
    param([string]$TemplateRoot, [string]$TargetRoot, [string]$Relative)
    $src = Join-Path $TemplateRoot $Relative
    $dst = Join-Path $TargetRoot $Relative
    if (-not (Test-AllowTargetPath $TargetRoot $dst "EnsureManagedFile" $Relative)) { return }
    $destinationItem = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    if ($null -ne $destinationItem -and $destinationItem.PSIsContainer) {
        Add-Operation "CONFLICT" "EnsureManagedFile" $Relative "A directory exists where the managed file is required; preserve it for manual recovery." $false
        return
    }
    if ($null -eq $destinationItem) {
        Add-Operation "MISSING" "EnsureManagedFile" $Relative "Create from template." $true
        if ($Mode -eq "Apply") { Copy-FileExact $src $dst }
        return
    }
    if (Test-FileSame $src $dst) {
        Add-Operation "OK" "EnsureManagedFile" $Relative "Matches template." $false
        return
    }
    Add-Operation "DRIFT" "EnsureManagedFile" $Relative "Replace the framework-owned file with the required version." $true
    if ($Mode -eq "Apply") { Copy-FileExact $src $dst }
}

function Get-AgentsMarkerRange {
    param([string]$Text)

    $beginMatches = [regex]::Matches($Text, "(?m)^$([regex]::Escape($script:AgentsBeginMarker))\r?$")
    $endMatches = [regex]::Matches($Text, "(?m)^$([regex]::Escape($script:AgentsEndMarker))\r?$")
    $present = $beginMatches.Count -gt 0 -or $endMatches.Count -gt 0
    $valid = $beginMatches.Count -eq 1 -and $endMatches.Count -eq 1 -and $endMatches[0].Index -gt $beginMatches[0].Index
    if (-not $valid) {
        return [pscustomobject]@{ Present = $present; Valid = $false }
    }

    $endIndex = $endMatches[0].Index + $endMatches[0].Length
    return [pscustomobject]@{
        Present = $true
        Valid = $true
        BeginIndex = $beginMatches[0].Index
        EndIndex = $endIndex
        Block = $Text.Substring($beginMatches[0].Index, $endIndex - $beginMatches[0].Index)
    }
}

function Get-LegacyAgentsBody {
    param([string]$Text)

    $lines = [regex]::Split($Text, "\r?\n")
    $titles = @(
        "# Инструкции ассистентам / Local agent instructions",
        "# Инструкции ассистентам (шаблон) / Local agent instructions (template)"
    )
    if ($lines.Count -eq 0 -or $titles -notcontains $lines[0]) {
        return [pscustomobject]@{ IsLegacy = $false; Body = "" }
    }

    $cursor = 1
    foreach ($heading in @("## P0 rules / P0 правила", "## Modules / Разделы", "## Reading order / Порядок чтения")) {
        $found = -1
        for ($index = $cursor; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -ceq $heading) {
                $found = $index
                break
            }
        }
        if ($found -lt 0) {
            return [pscustomobject]@{ IsLegacy = $false; Body = "" }
        }
        $cursor = $found + 1
    }

    foreach ($number in 1..5) {
        if ($cursor -ge $lines.Count -or $lines[$cursor] -notmatch "^$number\)\s") {
            return [pscustomobject]@{ IsLegacy = $false; Body = "" }
        }
        $cursor++
    }

    $body = ""
    if ($cursor -lt $lines.Count) {
        $body = [string]::Join("`n", $lines[$cursor..($lines.Count - 1)])
    }
    return [pscustomobject]@{ IsLegacy = $true; Body = $body }
}

function Join-ManagedContent {
    param([string]$ManagedBlock, [string[]]$ProjectSections)

    $canonical = $ManagedBlock.TrimEnd([char[]]"`r`n")
    $preserved = New-Object System.Collections.Generic.List[string]
    foreach ($section in $ProjectSections) {
        if (-not [string]::IsNullOrWhiteSpace($section)) {
            $preserved.Add($section.Trim([char[]]"`r`n")) | Out-Null
        }
    }
    if ($preserved.Count -eq 0) { return $canonical + "`n" }
    return $canonical + "`n`n" + ($preserved -join "`n`n") + "`n"
}

function Ensure-AgentsInstructions {
    param([string]$TemplateRoot, [string]$TargetRoot)
    $relative = "AGENTS.md"
    $src = Join-Path $TemplateRoot $relative
    $dst = Join-Path $TargetRoot $relative
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return }
    if (-not (Test-AllowTargetPath $TargetRoot $dst "EnsureAgentsInstructions" $relative -AllowLeafHardLink)) { return }

    $destinationItem = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    if ($null -ne $destinationItem -and $destinationItem.PSIsContainer) {
        Add-Operation "CONFLICT" "EnsureAgentsInstructions" $relative "A directory exists where AGENTS.md is required; preserve it for manual recovery." $false
        return
    }
    if ($null -eq $destinationItem) {
        Add-Operation "MISSING" "EnsureAgentsInstructions" $relative "Create from template." $true
        if ($Mode -eq "Apply") { Copy-FileExact $src $dst }
        return
    }
    if (-not (Test-AgentsHardlinksKnown $TargetRoot $dst)) {
        Add-Operation "BLOCKED" "EnsureAgentsInstructions" $relative "AGENTS.md has a hardlink outside the known instruction-link set; refusing to read-modify-write it." $false
        return
    }

    $templateText = Read-Text $src
    $canonicalBlock = $templateText.TrimEnd([char[]]"`r`n")
    $targetText = Read-Text $dst
    $range = Get-AgentsMarkerRange $targetText

    if ($range.Valid -and $range.BeginIndex -eq 0 -and $range.Block -ceq $canonicalBlock) {
        Add-Operation "OK" "EnsureAgentsInstructions" $relative "Required instruction block is current and at the top." $false
        return
    }

    if ($ForceManagedExact) {
        Add-Operation "DRIFT" "EnsureAgentsInstructions" $relative "Replace the complete file because -ForceManagedExact was set." $true
        if ($Mode -eq "Apply") { Write-AgentsText $TargetRoot $dst $templateText }
        return
    }

    if ($range.Present) {
        if (-not $range.Valid) {
            Add-Operation "CONFLICT" "EnsureAgentsInstructions" $relative "Managed instruction markers are incomplete, duplicated, or out of order; preserve the file for manual recovery." $false
            return
        }
        Add-Operation "DRIFT" "EnsureAgentsInstructions" $relative "Update and move the managed instruction block to the top while preserving project rules outside it." $true
        if ($Mode -eq "Apply") {
            $before = $targetText.Substring(0, $range.BeginIndex)
            $after = $targetText.Substring($range.EndIndex)
            Write-AgentsText $TargetRoot $dst (Join-ManagedContent $templateText @($before, $after))
        }
        return
    }

    $legacy = Get-LegacyAgentsBody $targetText
    if ($legacy.IsLegacy) {
        Add-Operation "DRIFT" "EnsureAgentsInstructions" $relative "Upgrade the legacy instruction block while preserving project rules after it." $true
        if ($Mode -eq "Apply") {
            Write-AgentsText $TargetRoot $dst (Join-ManagedContent $templateText @($legacy.Body))
        }
        return
    }

    Add-Operation "MISSING" "EnsureAgentsInstructions" $relative "Insert the required instruction block at the top while preserving existing project rules." $true
    if ($Mode -eq "Apply") {
        Write-AgentsText $TargetRoot $dst (Join-ManagedContent $templateText @($targetText))
    }
}

function Ensure-IfMissing {
    param([string]$TemplateRoot, [string]$TargetRoot, [string]$Relative)
    $src = Join-Path $TemplateRoot $Relative
    $dst = Join-Path $TargetRoot $Relative
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return }
    if (-not (Test-AllowTargetPath $TargetRoot $dst "EnsureIfMissing" $Relative)) { return }
    $destinationItem = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    if ($null -ne $destinationItem -and $destinationItem.PSIsContainer) {
        Add-Operation "CONFLICT" "EnsureIfMissing" $Relative "A directory exists where a file is required; preserve it for manual recovery." $false
    } elseif ($null -ne $destinationItem) {
        Add-Operation "OK" "EnsureIfMissing" $Relative "Existing project/local file preserved." $false
    } else {
        Add-Operation "MISSING" "EnsureIfMissing" $Relative "Create placeholder/sample from template." $true
        if ($Mode -eq "Apply") { Copy-FileExact $src $dst }
    }
}

function Get-ReadmeSnippet([string]$TemplateRoot) {
    $snippet = Join-Path $TemplateRoot "README_snippet.md"
    if (-not (Test-Path -LiteralPath $snippet -PathType Leaf)) {
        return ""
    }
    return Read-Text $snippet
}

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

    $trigger = "AI AGENT PROTOCOL TRIGGER"
    if ([regex]::Matches($Text, [regex]::Escape($trigger)).Count -ne 1) { return $false }
    return (Test-ProtocolCommentSignature $Snippet) -and (Test-ProtocolCommentSignature $Text)
}

function Ensure-ReadmeSnippet {
    param([string]$TargetRoot, [string]$Relative, [string]$Snippet)
    if ([string]::IsNullOrWhiteSpace($Snippet)) { return }
    $path = Join-Path $TargetRoot $Relative
    if (-not (Test-AllowTargetPath $TargetRoot $path "EnsureSnippetPresent" $Relative)) { return }
    $destinationItem = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -ne $destinationItem -and $destinationItem.PSIsContainer) {
        Add-Operation "CONFLICT" "EnsureSnippetPresent" $Relative "A directory exists where README is required; preserve it for manual recovery." $false
        return
    }
    if ($null -eq $destinationItem) {
        Add-Operation "MISSING" "EnsureSnippetPresent" $Relative "Create README containing the required hidden snippet." $true
        if ($Mode -eq "Apply") { Write-Text $path ($Snippet.TrimEnd() + [Environment]::NewLine) }
        return
    }
    $text = Read-Text $path
    $canonicalSnippet = $Snippet.TrimEnd([char[]]"`r`n")
    $exactMatches = [regex]::Matches($text, [regex]::Escape($canonicalSnippet))
    if ($text.StartsWith($canonicalSnippet, [System.StringComparison]::Ordinal) -and $exactMatches.Count -eq 1) {
        Add-Operation "OK" "EnsureSnippetPresent" $Relative "Snippet is already at the top." $false
        return
    }
    if ($exactMatches.Count -gt 1) {
        Add-Operation "CONFLICT" "EnsureSnippetPresent" $Relative "The exact protocol snippet appears more than once; preserve the README for manual recovery." $false
        return
    }
    if ($exactMatches.Count -eq 1) {
        Add-Operation "DRIFT" "EnsureSnippetPresent" $Relative "Move existing snippet to the top without changing README body." $true
        if ($Mode -eq "Apply") {
            $match = $exactMatches[0]
            $before = $text.Substring(0, $match.Index)
            $after = $text.Substring($match.Index + $match.Length)
            Write-Text $path (Join-ManagedContent $Snippet @($before, $after))
        }
        return
    }

    $trigger = "AI AGENT PROTOCOL TRIGGER"
    $triggerMatches = [regex]::Matches($text, [regex]::Escape($trigger))
    if ($triggerMatches.Count -gt 0) {
        $commentEnd = $text.IndexOf("-->", [System.StringComparison]::Ordinal)
        $safeOldSnippet = Test-PreviousReadmeProtocol $text $Snippet
        if (-not $safeOldSnippet) {
            Add-Operation "CONFLICT" "EnsureSnippetPresent" $Relative "The protocol marker is misplaced, duplicated, or lacks the complete historical signature; preserve the README for manual recovery." $false
            return
        }
        Add-Operation "DRIFT" "EnsureSnippetPresent" $Relative "Replace the previous top protocol snippet without changing the README body." $true
        if ($Mode -eq "Apply") {
            $body = $text.Substring($commentEnd + 3)
            Write-Text $path (Join-ManagedContent $Snippet @($body))
        }
        return
    }

    Add-Operation "MISSING" "EnsureSnippetPresent" $Relative "Insert required hidden snippet at the top." $true
    if ($Mode -eq "Apply") {
        Write-Text $path (Join-ManagedContent $Snippet @($text))
    }
}

function Get-TemplateExcludeLines([string]$TemplateRoot) {
    $gitignore = Join-Path $TemplateRoot ".gitignore"
    $required = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $gitignore -PathType Leaf) {
        $inside = $false
        foreach ($line in Get-Content -LiteralPath $gitignore) {
            if ($line -match "BEGIN EXCLUDE LIST") { $inside = $true; continue }
            if ($line -match "END EXCLUDE LIST") { $inside = $false; continue }
            if ($inside) {
                $clean = $line -replace "^\s*#\s?", ""
                if (-not [string]::IsNullOrWhiteSpace($clean)) {
                    $required.Add($clean.Trim()) | Out-Null
                }
            }
        }
    }
    foreach ($extra in @(".codex/", "AGENTS.override.md")) {
        if (-not $required.Contains($extra)) { $required.Add($extra) | Out-Null }
    }
    return $required
}

function Ensure-ExcludeLines {
    param([string]$TargetRoot, [string[]]$Lines)
    $exclude = Get-GitPath $TargetRoot "info/exclude"
    $gitCommon = Get-GitCommonDirectory $TargetRoot
    if (-not $exclude -or -not $gitCommon) {
        Add-Operation "SKIP" "EnsureExcludeLines" ".git/info/exclude" "Target is not the root of a Git worktree; parent Git metadata is not modified." $false
        return
    }
    if (-not (Test-PathTreeSafe $gitCommon $exclude)) {
        Add-Operation "BLOCKED" "EnsureExcludeLines" ".git/info/exclude" "Git exclude path or ancestor is a link or escapes the canonical git common directory." $false
        return
    }
    $existing = @()
    if (Test-Path -LiteralPath $exclude -PathType Leaf) {
        $existing = @(Get-Content -LiteralPath $exclude)
    }
    $legacy = @(
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
    $changed = $false
    foreach ($line in $legacy) {
        if ($existing -ccontains $line) {
            Add-Operation "DRIFT" "EnsureExcludeLines" ".git/info/exclude" "Remove obsolete scaffold-wide line: $line" $true
            $changed = $true
        }
    }
    if ($changed) {
        $existing = @($existing | Where-Object { -not ($legacy -ccontains $_) })
    }
    foreach ($line in $Lines) {
        if ($existing -ccontains $line) {
            Add-Operation "OK" "EnsureExcludeLines" ".git/info/exclude" "Line present: $line" $false
        } else {
            Add-Operation "MISSING" "EnsureExcludeLines" ".git/info/exclude" "Append line: $line" $true
            $existing += $line
            $changed = $true
        }
    }
    if ($Mode -eq 'Apply' -and $changed) {
        Write-LinesAtomic $exclude ([string[]]$existing)
    }
}

function Test-LinkOrHardlink {
    param([string]$Path, [string]$AgentPath, [string]$RelativeTarget)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }
    $linkType = Get-LinkType $item
    if ($linkType -eq "SymbolicLink") {
        $target = ([string]$item.Target).Replace("\", "/")
        $expected = $RelativeTarget.Replace("\", "/")
        return $target -eq $expected
    }
    if ($linkType -eq "HardLink") {
        return Test-SameFileIdentity $Path $AgentPath
    }
    return $false
}

function New-AgentLink {
    param([string]$Path, [string]$RelativeTarget, [string]$HardlinkSource)
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $RelativeTarget -ErrorAction Stop | Out-Null
    } catch {
        New-Item -ItemType HardLink -Path $Path -Target $HardlinkSource -ErrorAction Stop | Out-Null
    }
}

function Test-DirectorySymlinkTarget {
    param([string]$Path, [string]$RelativeTarget)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }
    $linkType = Get-LinkType $item
    if ($linkType -ne "SymbolicLink") { return $false }
    $target = [string]$item.Target
    $normalizedTarget = $target.Replace("/", "\")
    $normalizedExpected = $RelativeTarget.Replace("/", "\")
    return $normalizedTarget -eq $normalizedExpected
}

function Ensure-SkillDiscoveryLink {
    param([string]$TargetRoot, [string]$Relative, [string]$RelativeTarget)
    $path = Join-Path $TargetRoot $Relative
    if (-not (Test-AllowTargetPath $TargetRoot $path "EnsureSkillDiscoveryLink" $Relative -AllowLeafLink)) { return }
    if (Test-DirectorySymlinkTarget $path $RelativeTarget) {
        Add-Operation "OK" "EnsureSkillDiscoveryLink" $Relative "Symlink points to canonical skills/ai-bootstrap-converge." $false
        return
    }
    if ($null -ne (Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)) {
        Add-Operation "CONFLICT" "EnsureSkillDiscoveryLink" $Relative "Path exists but is not the required symlink. Do not duplicate skill files here." $false
        return
    }
    Add-Operation "MISSING" "EnsureSkillDiscoveryLink" $Relative "Create symlink to ../../skills/ai-bootstrap-converge." $true
    if ($Mode -eq "Apply") {
        $dir = Split-Path -Parent $path
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        try {
            New-Item -ItemType SymbolicLink -Path $path -Target $RelativeTarget -ErrorAction Stop | Out-Null
        } catch {
            Add-Operation "BLOCKED" "EnsureSkillDiscoveryLink" $Relative "Could not create directory symlink: $($_.Exception.Message)" $false
        }
    }
}

function Ensure-InstructionLink {
    param([string]$TargetRoot, [string]$Relative, [string]$RelativeTarget)
    $path = Join-Path $TargetRoot $Relative
    $agent = Join-Path $TargetRoot "AGENTS.md"
    if (-not (Test-AllowTargetPath $TargetRoot $path "EnsureInstructionLink" $Relative -AllowLeafLink)) { return }
    $agentItem = Get-Item -LiteralPath $agent -Force -ErrorAction SilentlyContinue
    if ($null -ne $agentItem -and ($agentItem.PSIsContainer -or (Get-LinkType $agentItem) -eq "SymbolicLink")) {
        Add-Operation "BLOCKED" "EnsureInstructionLink" $Relative "Canonical AGENTS.md is not a regular file; do not create or accept an instruction link." $false
        return
    }
    if (Test-LinkOrHardlink $path $agent $RelativeTarget) {
        Add-Operation "OK" "EnsureInstructionLink" $Relative "Points to or matches AGENTS.md." $false
        return
    }
    if ($null -ne (Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)) {
        Add-Operation "CONFLICT" "EnsureInstructionLink" $Relative "Existing instruction file differs. Preserve it and merge project-specific content before replacing." $false
        return
    }
    Add-Operation "MISSING" "EnsureInstructionLink" $Relative "Create symlink or hardlink to AGENTS.md." $true
    if ($Mode -eq "Apply") {
        New-AgentLink $path $RelativeTarget $agent
    }
}

function Get-InstructionLinks {
    param([string]$TemplateRoot, [switch]$WithClaude)
    $links = @(
        @{ Path = ".github/copilot-instructions.md"; Target = "../AGENTS.md" },
        @{ Path = ".gemini/GEMINI.md"; Target = "../AGENTS.md" },
        @{ Path = ".qwen/QWEN.md"; Target = "../AGENTS.md" },
        @{ Path = "GEMINI.md"; Target = "AGENTS.md" },
        @{ Path = "QWEN.md"; Target = "AGENTS.md" }
    )
    $templateHasClaude = (Test-Path -LiteralPath (Join-Path $TemplateRoot ".claude/CLAUDE.md")) -or (Test-Path -LiteralPath (Join-Path $TemplateRoot "CLAUDE.md"))
    if ($WithClaude -or $templateHasClaude) {
        $links += @{ Path = ".claude/CLAUDE.md"; Target = "../AGENTS.md" }
        $links += @{ Path = "CLAUDE.md"; Target = "AGENTS.md" }
    }
    return $links
}

function Get-EnsureIfMissingFiles {
    param([string]$TemplateRoot)
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($relative in @(
        "local/ai/bootstrap.ready",
        "local/ai/chat_context.md",
        "local/ai/project_addenda.md",
        "local/ai/session_history.md"
    )) {
        if (Test-Path -LiteralPath (Join-Path $TemplateRoot $relative) -PathType Leaf) {
            $candidates.Add($relative) | Out-Null
        }
    }
    $localAi = Join-Path $TemplateRoot "local/ai"
    if (Test-Path -LiteralPath $localAi -PathType Container) {
        Get-ChildItem -LiteralPath $localAi -Directory -Force | Where-Object {
            $_.Name -notin @("agents", "scripts", "context_packs", "session_summaries")
        } | ForEach-Object {
            foreach ($name in @("README.md", "requests.log", "sessions.log")) {
                $file = Join-Path $_.FullName $name
                if (Test-Path -LiteralPath $file -PathType Leaf) {
                    $candidates.Add((Get-RelativePath $TemplateRoot $file)) | Out-Null
                }
            }
        }
    }
    return $candidates
}

function Report-LocalOnlyTracked {
    param([string]$TargetRoot)
    if (-not (Get-GitCommonDirectory $TargetRoot)) { return }
    $patterns = @(
        "AGENTS.override.md",
        ".codex/",
        "tmp/ai/",
        "local/ai/bootstrap.ready",
        "local/ai/chat_context.md",
        "local/ai/project_addenda.md",
        "local/ai/session_history.md",
        "local/ai/session_summaries/",
        ":!local/ai/session_summaries/README.md",
        "local/ai/context_packs/",
        "local/ai/ai-nest/",
        "local/ai/*/requests.log",
        "local/ai/*/sessions.log",
        "local/ai/*/*.session"
    )
    $tracked = @(& git -C $TargetRoot ls-files -- $patterns 2>$null)
    foreach ($path in $tracked) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            Add-Operation "NEEDS_DECISION" "ReportLocalOnlyTracked" $path "Local-only/runtime path is tracked by git. Remove from index only after explicit user approval." $false
        }
    }
}

function Report-LegacyCredentialResidue {
    param([string]$TargetRoot)
    $relative = 'tmp/ai/cli_tokens'
    $path = Join-Path $TargetRoot $relative
    if ($null -ne (Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)) {
        Add-Operation 'NEEDS_DECISION' 'ReportLegacyCredentialResidue' $relative 'Deprecated credential residue exists. Do not inspect or remove it without explicit user approval.' $false
    }
}

function Build-Plan {
    param([string]$TargetRoot, [string]$TemplateRoot)

    $managedRoots = @(
        "README_snippet.md",
        "local/ai/agents",
        "local/ai/scripts",
        "skills/ai-bootstrap-converge"
    )
    Ensure-AgentsInstructions $TemplateRoot $TargetRoot
    foreach ($src in Get-TemplateFilesByRoots $TemplateRoot $managedRoots) {
        Ensure-ManagedExact $TemplateRoot $TargetRoot (Get-RelativePath $TemplateRoot $src)
    }

    foreach ($relative in Get-EnsureIfMissingFiles $TemplateRoot) {
        Ensure-IfMissing $TemplateRoot $TargetRoot $relative
    }

    $snippet = Get-ReadmeSnippet $TemplateRoot
    foreach ($readme in @("README.md", "README.en.md")) {
        Ensure-ReadmeSnippet $TargetRoot $readme $snippet
    }

    Ensure-ExcludeLines $TargetRoot (Get-TemplateExcludeLines $TemplateRoot)

    foreach ($link in Get-InstructionLinks $TemplateRoot $IncludeClaude) {
        Ensure-InstructionLink $TargetRoot $link.Path $link.Target
    }

    Ensure-SkillDiscoveryLink $TargetRoot ".agents/skills/ai-bootstrap-converge" "../../skills/ai-bootstrap-converge"
    Ensure-SkillDiscoveryLink $TargetRoot ".claude/skills/ai-bootstrap-converge" "../../skills/ai-bootstrap-converge"

    Report-LocalOnlyTracked $TargetRoot
    Report-LegacyCredentialResidue $TargetRoot
}

try {
    $targetRoot = Resolve-Directory $Target "Target"
    $templateRoot = Resolve-TemplateRoot $Template $SourceRef
    Assert-TemplateSources $templateRoot
    Build-Plan $targetRoot $templateRoot

    if ($Json) {
        $script:Operations | ConvertTo-Json -Depth 4
    } else {
        $script:Operations |
            Sort-Object Status, Type, Path |
            Format-Table Status, Type, Path, Detail -AutoSize -Wrap
    }

    $bad = @($script:Operations | Where-Object {
        $_.Status -in @("MISSING", "DRIFT", "CONFLICT", "BLOCKED", "NEEDS_DECISION") -and
        -not ($Mode -eq "Apply" -and $_.Safe)
    })
    if ($Mode -eq "Verify" -and $bad.Count -gt 0) {
        exit 1
    }
    if ($Mode -eq "Apply") {
        $remaining = @($script:Operations | Where-Object { $_.Status -in @("CONFLICT", "BLOCKED") })
        if ($remaining.Count -gt 0) { exit 2 }
    }
} finally {
    if ($script:TemplateScratch -and (Test-Path -LiteralPath $script:TemplateScratch)) {
        Remove-Item -LiteralPath $script:TemplateScratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}
