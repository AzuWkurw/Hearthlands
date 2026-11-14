@echo off
rem Starts Hearthlands with the OpenGL renderer, whatever is chosen in Settings.
start "" "%~dp0Hearthlands.exe" --rendering-method gl_compatibility --rendering-driver opengl3 -- safe
