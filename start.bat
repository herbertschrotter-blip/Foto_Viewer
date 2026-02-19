@echo off
title Foto Viewer

echo Starting Foto Viewer...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0start.ps1'"

pause