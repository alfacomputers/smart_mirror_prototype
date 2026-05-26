param(
    [string]$FlutterRoot = $env:FLUTTER_ROOT
)

if (-not $FlutterRoot) {
    if (Test-Path "C:\flutter\flutter") {
        $FlutterRoot = "C:\flutter\flutter"
    }
    elseif (Test-Path "C:\flutter") {
        $FlutterRoot = "C:\flutter"
    }
}

if (-not $FlutterRoot) {
    Write-Error "FLUTTER_ROOT is not defined and no default Flutter SDK was found."
    Write-Error "Install Flutter at C:\flutter\flutter or set the FLUTTER_ROOT environment variable."
    exit 1
}

$flutterExe = Join-Path $FlutterRoot "bin\flutter.bat"
if (-not (Test-Path $flutterExe)) {
    Write-Error "Flutter executable not found at $flutterExe"
    exit 1
}

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir
Write-Host "Using FLUTTER_ROOT=$FlutterRoot"

& $flutterExe pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $flutterExe build windows
exit $LASTEXITCODE
