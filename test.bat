@echo off
:loop
start cmd
timeout /t 1 >nul
choice /c CE /n /m "Press C to continue or E to exit: "
if errorlevel 2 exit
goto loop
