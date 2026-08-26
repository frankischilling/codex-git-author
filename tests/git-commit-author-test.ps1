$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$authorScript = Join-Path $repositoryRoot 'skills\git-commit-author\scripts\git-commit-author.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('git-commit-author-test-' + [guid]::NewGuid().ToString('N'))
$globalConfig = Join-Path $testRoot 'global.gitconfig'
$repo = Join-Path $testRoot 'repo'
$previousOutputEncoding = [Console]::OutputEncoding
$previousGitConfigGlobal = $env:GIT_CONFIG_GLOBAL

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Actual -ne $Expected) {
        throw "$Label`: expected '$Expected', got '$Actual'"
    }
}

function Invoke-AuthorHelper {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $authorScript @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git-commit-author.ps1 failed with exit code $LASTEXITCODE"
    }
    return $output
}

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    New-Item -ItemType File -Path $globalConfig -Force | Out-Null
    $env:GIT_CONFIG_GLOBAL = $globalConfig

    & git -C $repo init -q
    if ($LASTEXITCODE -ne 0) {
        throw 'git init failed'
    }
    & git -C $repo config user.name 'PowerShell User'
    & git -C $repo config user.email 'powershell@example.test'

    Push-Location $repo
    try {
        $resolved = (Invoke-AuthorHelper resolve) -join "`n"
        Assert-Equal "name=PowerShell User`nemail=powershell@example.test" $resolved 'resolved identity'

        $env:GIT_AUTHOR_NAME = 'Codex'
        $env:GIT_AUTHOR_EMAIL = 'codex@example.test'
        $env:GIT_COMMITTER_NAME = 'OpenAI'
        $env:GIT_COMMITTER_EMAIL = 'openai@example.test'
        $subject = "R$([char]0x00E9)sum$([char]0x00E9) $([char]0x2713)"
        Invoke-AuthorHelper commit --allow-empty -m $subject | Out-Null
    } finally {
        Pop-Location
    }

    $actual = (& git -C $repo log -1 --format='%an <%ae>|%cn <%ce>|%s') -join "`n"
    $expected = "PowerShell User <powershell@example.test>|PowerShell User <powershell@example.test>|$subject"
    Assert-Equal $expected $actual 'commit identity and subject'
    Write-Output 'ok - Windows PowerShell entry point preserves identity and Unicode arguments'
} finally {
    [Console]::OutputEncoding = $previousOutputEncoding
    $env:GIT_CONFIG_GLOBAL = $previousGitConfigGlobal

    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
