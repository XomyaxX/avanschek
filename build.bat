@echo off
chcp 65001 >nul
echo 🚀 Быстрая сборка avanschek
echo.

if not exist "%USERPROFILE%\Desktop" (
    echo ❌ Рабочий стол не найден
    exit /b 1
)

cd /d "%~dp0avanschek_mobile"

flutter pub get
if errorlevel 1 (
    echo ❌ Ошибка flutter pub get
    exit /b 1
)

flutter build apk --release
if errorlevel 1 (
    echo ❌ Ошибка сборки APK
    exit /b 1
)

copy /Y "build\app\outputs\flutter-apk\app-release.apk" "%USERPROFILE%\Desktop\avanschek.apk" >nul
if errorlevel 1 (
    echo ❌ Не удалось скопировать APK
    exit /b 1
)

echo ✅ APK скопирован на рабочий стол: %USERPROFILE%\Desktop\avanschek.apk
echo 📱 Скачать через GitHub CI: https://github.com/XomyaxX/avanschek/actions
pause
