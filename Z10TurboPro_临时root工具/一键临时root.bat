@echo off
chcp 65001 >nul
title vivo iQOO Temp Root Tool
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0root.ps1"
if errorlevel 1 pause
