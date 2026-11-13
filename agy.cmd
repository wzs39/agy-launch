@echo off
rem ============================================================================
rem  agy -- thin entry point, defaults to DIRECT.
rem
rem  Replaces the old wrapper that unconditionally started mitmdump, installed a
rem  mitm CA and pointed HTTPS_PROXY at 127.0.0.1:18080. Typing "agy" used to
rem  mean "definitely proxied"; now it means "no proxy unless I ask for one".
rem
rem  The old wrapper is preserved as agy.cmd.old -- restore it with:
rem      ren agy.cmd.old agy.cmd
rem
rem  This file only forwards; the real logic is agy-run.py (see LAUNCH-MODES.md).
rem
rem  Usage
rem    agy                       -> direct, no proxy (this is the change)
rem    agy -p "hello"            -> direct, args forwarded to agy.exe
rem    agy launch                -> interactive menu (pick direct/socks/mitm)
rem    agy --mode socks -p "hi"  -> explicit mode, same flags as agy-run.py
rem ============================================================================
setlocal

set "HERE=%~dp0"
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY (
  where python >nul 2>nul && set "PY=python"
)
if not defined PY (
  rem No Python: fall back to the real binary directly. Never fall back to the
  rem old MITM wrapper -- silently proxying is exactly what this file removes.
  set "REAL_AGY=%LOCALAPPDATA%\agy\bin\agy.exe"
  if not exist "%REAL_AGY%" (
    echo [agy] Python not found and agy.exe missing at "%REAL_AGY%"
    exit /b 1
  )
  "%REAL_AGY%" %*
  exit /b %ERRORLEVEL%
)

rem "agy launch" opens the menu; everything else defaults to direct.
if /i "%~1"=="launch" (
  %PY% "%HERE%agy-run.py"
  exit /b %ERRORLEVEL%
)

rem If the caller passed an explicit --mode, let agy-run.py parse it as-is.
echo %* | findstr /i /c:"--mode" >nul
if not errorlevel 1 (
  %PY% "%HERE%agy-run.py" %*
  exit /b %ERRORLEVEL%
)

%PY% "%HERE%agy-run.py" --mode direct --target cli -- %*
exit /b %ERRORLEVEL%
