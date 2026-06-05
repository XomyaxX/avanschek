# Авансовый отчёт — Мобильное приложение (Flutter)

Нативное Flutter-приложение для создания авансовых отчётов формы АО-1.

## Функции

- 📋 Заполнение общих данных (ФИО, дата, должность, подразделение, аванс)
- 🧾 Добавление нескольких чеков/документов
- 📷 **Сканирование QR-кода камерой телефона** (через `mobile_scanner`)
- 🖼️ **Загрузка фото чека из галереи** с распознаванием QR на сервере
- 🔗 **Получение полных данных из ФНС** через proverkacheka.com (список товаров, НДС, магазин)
- 📄 Генерация XLS + PDF через сервер Flask
- 📥 Скачивание и отправка готовых документов
- 🕘 **История отчётов** — сохранение всех сгенерированных отчётов в локальной базе данных
- 💾 **Автосохранение черновиков** — при закрытии приложения несохранённые данные восстанавливаются при следующем запуске

## Архитектура

Приложение работает в связке с Flask-сервером (`../app.py`), который должен быть запущен на ПК или VPS:

```
[Телефон]  ←→  [Flask сервер]  ←→  [Excel COM]
  Flutter         Python            Windows
```

**Важно:** Серверная часть (генерация XLS/PDF через Excel COM) работает **только на Windows** с установленным Microsoft Excel.

## Требования для сборки

1. **Flutter SDK** — https://docs.flutter.dev/get-started/install
2. **Android Studio** — устанавливает JDK + Android SDK + Gradle автоматически
3. **Developer Mode** в Windows — нужен Flutter для работы с плагинами:
   - Настройки → Конфиденциальность и безопасность → Для разработчиков → Режим разработчика → Вкл.

## Настройка IP сервера

Перед сборкой создайте/измените файл `assets/.env` (скопируйте из `assets/.env.example`):

```bash
cp assets/.env.example assets/.env
```

```env
API_BASE_URL=http://192.168.1.132:5000
```

Узнать IP компьютера: запустите `python app.py` в папке проекта — IP покажется в консоли.

> **Важно:** файл `assets/.env` добавлен в `.gitignore` и не попадёт в репозиторий.

## Скачать готовый APK (без сборки)

### 🔗 Прямая ссылка (самый простой способ)
**Страница скачивания:** https://xomyaxx.github.io/avanschek/

Или скачай напрямую с GitHub Releases:
- **APK (Android):** https://github.com/XomyaxX/avanschek/releases/tag/latest
- **Windows (ZIP):** https://github.com/XomyaxX/avanschek/releases/tag/latest

> ⚠️ APK собран без подписи (debug signing). При установке разрешите "Unknown sources" (Настройки → Безопасность).

### 📦 GitHub Actions (альтернатива)
1. Откройте https://github.com/XomyaxX/avanschek/actions
2. Выберите последний успешный workflow (зелёная галочка ✅)
3. Внизу — секция **Artifacts** → скачайте `avanschek-apk` (ZIP, распакуйте)

## Сборка APK (Android) — локально

```bash
cd C:\avanschek_mobile
flutter build apk --release
```

Готовый APK будет в:
```
build\app\outputs\flutter-apk\app-release.apk
```

### Скрипт для быстрой сборки (PowerShell)

```powershell
# build.ps1 — собрать APK и скопировать на рабочий стол
Set-Location "$PSScriptRoot\avanschek_mobile"
flutter pub get
flutter build apk --release
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$env:USERPROFILE\Desktop\avanschek.apk"
Write-Host "✅ APK скопирован на рабочий стол: $env:USERPROFILE\Desktop\avanschek.apk"
```

## Сборка для Windows (для теста на ПК)

```bash
flutter build windows --release
```

## Запуск в режиме разработки

```bash
flutter run
```

## Структура проекта

```
lib/
├── main.dart                    # Точка входа
├── models/
│   ├── check.dart               # Модель чека
│   └── report_data.dart         # Модель данных отчёта
├── services/
│   ├── api_service.dart         # HTTP-клиент для Flask API
│   ├── db_service.dart          # Локальная SQLite база данных
│   └── prefs_service.dart       # SharedPreferences wrapper
└── screens/
    ├── home_screen.dart         # Главный экран (форма + чеки)
    ├── qr_scan_screen.dart      # Экран сканирования QR камерой
    ├── history_screen.dart      # История сохранённых отчётов
    ├── settings_screen.dart     # Настройки профиля
    ├── onboarding_screen.dart   # Инструкция для новых пользователей
    └── profile_setup_screen.dart # Первоначальная настройка профиля
```

## Получение токена API ФНС

1. Зарегистрируйтесь на https://proverkacheka.com/
2. В профиле нажмите «Сгенерировать» рядом с полем токена
3. Вставьте токен в поле «Токен proverkacheka.com» в приложении

Бесплатный лимит: ~15 чеков в сутки.
