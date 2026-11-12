@echo off
rem ============================================================================
rem  agy-launch.cmd -- one double-click / one command, everything else in Python.
rem
rem  Why so thin: a .cmd is parsed in the console code page (cp936 here), so a
rem  UTF-8 file with Chinese prompts gets split into stray commands, and
rem  "set /p" under a redirected stdin swallows the rest of the input. Both bugs
rem  showed up while testing this exact menu. Python's input() has neither
rem  problem, so the menu lives in agy-run.py and this file only forwards.
rem
rem  Usage
rem    agy-launch.cmd              interactive: pick mode, pick target, pass args
rem    agy-launch.cmd --mode ...   anything here goes straight to agy-run.py
rem
rem  Modes (agy-run.py --mode)
rem    direct  no proxy, no CA               (try first when something breaks)
rem    socks   socks5, TLS end-to-end        (no interception, native JA3)
rem    mitm    http MITM + body rewrite      (diagnostics only)
rem    status  listeners / binaries / CA / autostart
rem ============================================================================
setlocal

set "HERE=%~dp0"
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY (
  where python >nul 2>nul && set "PY=python"
)
if not defined PY (
  echo [!] Python not found. Install Python 3.9+ or add it to PATH.
  exit /b 1
)

%PY% "%HERE%agy-run.py" %*
exit /b %ERRORLEVEL%
