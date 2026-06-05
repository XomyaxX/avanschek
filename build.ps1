# build.ps1 — Скрипт для локальной сборки APK и Windows-версии
# Запускайте из корня репозитория: .\build.ps1

param(
    [ValidateSet("apk","windows","all")]
    [string]$Target = "apk"
)

$ErrorActionPreference = "Stop"
$mobileDir = "$PSScriptRoot\avanschek_mobile"
$desktopDir = "$env:USERPROFILE\Desktop"

function Build-Apk {
    Write-Host "🚀 Сборка APK..." -ForegroundColor Cyan
    Set-Location $mobileDir
    flutter pub get
    flutter build apk --release
    $apkPath = "build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $apkPath) {
        Copy-Item $apkPath "$desktopDir\avanschek.apk"
        Write-Host "✅ APK скопирован на рабочий стол: $desktopDir\avanschek.apk" -ForegroundColor Green
    } else {
        Write-Host "❌ APK не найден после сборки" -ForegroundColor Red
    }
}

function Build-Windows {
    Write-Host "🚀 Сборка Windows-версии..." -ForegroundColor Cyan
    Set-Location $mobileDir
    flutter config --enable-windows-desktop
    flutter pub get
    flutter build windows --release
    $winPath = "build\windows\x64\runner\Release"
    if (Test-Path $winPath) {
        Compress-Archive -Path "$winPath\*" -DestinationPath "$desktopDir\avanschek-windows.zip" -Force
        Write-Host "✅ Windows-версия заархивирована: $desktopDir\avanschek-windows.zip" -ForegroundColor Green
    } else {
        Write-Host "❌ Windows-версия не найдена после сборки" -ForegroundColor Red
    }
}

# Проверка Flutter
if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Flutter не найден в PATH. Установите: https://docs.flutter.dev/get-started/install" -ForegroundColor Red
    exit 1
}

switch ($Target) {
    "apk"     { Build-Apk }
    "windows" { Build-Windows }
    "all"     { Build-Apk; Build-Windows }
}

Write-Host "`n📱 Скачать APK через GitHub CI: https://github.com/XomyaxX/avanschek/actions" -ForegroundColor Gray
