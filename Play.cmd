@echo off
setlocal
pushd "%~dp0" || exit /b 1
if exist "build\Godot.exe" (
    start "" "%CD%\build\Godot.exe" --path .
) else (
    where godot.exe >nul 2>&1
    if errorlevel 1 (
        echo Open project.godot in Godot 4.5 or later and press F6 in the arena scene or F5.
        pause
        popd
        exit /b 1
    )
    start "" godot.exe --path .
)
popd
