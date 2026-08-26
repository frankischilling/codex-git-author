$ErrorActionPreference = 'Stop'

$bashCandidates = [System.Collections.Generic.List[string]]::new()
if ($env:GIT_COMMIT_AUTHOR_BASH) {
    $bashCandidates.Add($env:GIT_COMMIT_AUTHOR_BASH)
}

$programFiles = [Environment]::GetFolderPath('ProgramFiles')
$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
if ($programFiles) {
    $bashCandidates.Add((Join-Path $programFiles 'Git\bin\bash.exe'))
}
if ($programFilesX86) {
    $bashCandidates.Add((Join-Path $programFilesX86 'Git\bin\bash.exe'))
}
if ($env:LOCALAPPDATA) {
    $bashCandidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'))
}

$pathBash = Get-Command bash.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pathBash) {
    $bashCandidates.Add($pathBash.Source)
}

$bash = $bashCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $bash) {
    Write-Error 'git-commit-author: Git for Windows bash.exe was not found. Install Git for Windows or set GIT_COMMIT_AUTHOR_BASH.'
    exit 1
}

$authorScript = (Join-Path $PSScriptRoot 'git-commit-author.sh').Replace('\', '/')
$authorArguments = @($authorScript) + $args

if ($MyInvocation.ExpectingInput) {
    $previousOutputEncoding = $OutputEncoding
    try {
        $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $input | & $bash @authorArguments
        $authorExitCode = $LASTEXITCODE
    } finally {
        $OutputEncoding = $previousOutputEncoding
    }
} else {
    & $bash @authorArguments
    $authorExitCode = $LASTEXITCODE
}

exit $authorExitCode
