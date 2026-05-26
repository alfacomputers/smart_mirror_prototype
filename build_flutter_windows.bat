@echo off
setlocal

if "%FLUTTER_ROOT%"=="" (
    if exist "C:\flutter\flutter\bin\flutter.bat" (
        set "FLUTTER_ROOT=C:\flutter\flutter"
    ) else if exist "C:\flutter\bin\flutter.bat" (
        set "FLUTTER_ROOT=C:\flutter"
    )
)

if "%FLUTTER_ROOT%"=="" (
    echo FLUTTER_ROOT is not set and no default Flutter SDK was found.
    echo Install Flutter at C:\flutter\flutter or set the FLUTTER_ROOT environment variable.
    exit /b 1
)

set "FLUTTER_CMD=%FLUTTER_ROOT%\bin\flutter.bat"
if not exist "%FLUTTER_CMD%" (
    echo Flutter executable not found at %FLUTTER_CMD%
    exit /b 1
)

pushd "%~dp0"
echo Using FLUTTER_ROOT=%FLUTTER_ROOT%
"%FLUTTER_CMD%" pub get || exit /b %ERRORLEVEL%
"%FLUTTER_CMD%" build windows || exit /b %ERRORLEVEL%
popd
