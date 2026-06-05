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

Перед сборкой откройте `lib/services/api_service.dart` и измените `baseUrl` на IP-адрес компьютера, где запущен Flask:

```dart
ApiService({this.baseUrl = 'http://192.168.1.132:5000'});
```

Узнать IP компьютера: запустите `python app.py` в папке проекта — IP покажется в консоли.

## Сборка APK (Android)

```bash
cd C:\avanschek_mobile
flutter build apk --release
```

Готовый APK будет в:
```
build\app\outputs\flutter-apk\app-release.apk
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
├── main.dart                 # Точка входа
├── models/
│   ├── check.dart            # Модель чека
│   └── report_data.dart      # Модель данных отчёта
├── services/
│   └── api_service.dart      # HTTP-клиент для Flask API
└── screens/
    ├── home_screen.dart      # Главный экран (форма + чеки)
    └── qr_scan_screen.dart   # Экран сканирования QR камерой
```

## Получение токена API ФНС

1. Зарегистрируйтесь на https://proverkacheka.com/
2. В профиле нажмите «Сгенерировать» рядом с полем токена
3. Вставьте токен в поле «Токен proverkacheka.com» в приложении

Бесплатный лимит: ~15 чеков в сутки.
