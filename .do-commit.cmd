@echo off
setlocal
cd /d "C:\Users\qwe\Documents\agy-launch"
git add -A
git commit -F "%TEMP%\agy-launch-commitmsg.txt"
git log --oneline
exit /b %ERRORLEVEL%
