@echo off
setlocal

for %%I in ("%~dp0..") do set "PROJECT_DIR=%%~fI"
if defined FLUTTER_HOME (
  set "FLUTTER=%FLUTTER_HOME%\bin\flutter.bat"
  set "DART=%FLUTTER_HOME%\bin\dart.bat"
) else (
  set "FLUTTER=E:\AI\toolchains\flutter\bin\flutter.bat"
  set "DART=E:\AI\toolchains\flutter\bin\dart.bat"
)

if not exist "%FLUTTER%" (
  echo Flutter SDK not found. Set FLUTTER_HOME or install it at E:\AI\toolchains\flutter. 1>&2
  exit /b 2
)

pushd "%PROJECT_DIR%"
call "%FLUTTER%" pub get || goto :error
call "%DART%" format --output=none --set-exit-if-changed lib test || goto :error
call "%FLUTTER%" analyze || goto :error
call "%FLUTTER%" test || goto :error
popd
exit /b 0

:error
set "EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %EXIT_CODE%
