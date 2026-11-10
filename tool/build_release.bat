@echo off
REM 17c: release build wrapper. Reads version from pubspec.yaml, injects
REM --dart-define=APP_VERSION=<versionCode>, and copies the three per-ABI APKs
REM into dist/. Never hand-type the flutter command again.
REM
REM Usage:  tool\build_release.bat            (full build, three ABIs)
REM         tool\build_release.bat --dry-run  (print the plan only)
setlocal
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

for %%I in ("%~dp0..") do set "PROJECT_DIR=%%~fI"
if not defined FLUTTER_HOME set "FLUTTER_HOME=E:\AI\toolchains\flutter"
if not exist "%FLUTTER_HOME%\bin\dart.bat" (
  echo Flutter SDK not found. Set FLUTTER_HOME. 1>&2
  exit /b 2
)

pushd "%PROJECT_DIR%"
call "%FLUTTER_HOME%\bin\dart.bat" run tool\build_release.dart %*
set "EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %EXIT_CODE%
