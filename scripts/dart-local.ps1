param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $DartArguments
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sdkRoot = Join-Path $repoRoot 'tools\flutter'
$dartExe = Join-Path $sdkRoot 'bin\cache\dart-sdk\bin\dart.exe'

if (-not (Test-Path -LiteralPath $dartExe)) {
    throw "Project-local Dart SDK is missing: $dartExe"
}

$env:FLUTTER_ROOT = $sdkRoot
if (-not $env:PUB_CACHE) {
    $env:PUB_CACHE = Join-Path $env:LOCALAPPDATA 'Pub\Cache'
}

& $dartExe @DartArguments
exit $LASTEXITCODE
