# FaceClock — мобильное приложение (Flutter)

Мобильный клиент учёта рабочего времени по распознаванию лица.
Одно приложение, две роли: **сотрудник** (отметка прихода/ухода по лицу) и
**администратор** (управление сотрудниками, рабочими местами, разбор аномалий).
Дизайн — вариант A «Ясный день». Работает с backend из папки `../server`.

## Что нужно для сборки
- Flutter SDK (стабильный канал), Android Studio / Xcode.
- Реальное устройство (нужны камера и GPS; на эмуляторе камера/гео ограничены).

## Первый запуск
```bash
cd app
flutter create .            # сгенерирует папки android/ ios/ (lib/ и pubspec не трогает)
flutter pub get
```
Затем выполните три настройки ниже (права доступа, minSdk, модель) и:
```bash
flutter run
```

### 1. Разрешения

**Android** — в `android/app/src/main/AndroidManifest.xml`, внутри `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```
Если сервер на `http://` (не https), добавьте в тег `<application>`:
`android:usesCleartextTraffic="true"`.

**iOS** — в `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Съёмка лица для отметки прихода и ухода</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Проверка, что вы на рабочем месте</string>
```

### 2. Версии SDK
`android/app/build.gradle` → `minSdkVersion 24` (нужно для ML Kit и tflite).

### 3. Модель распознавания
Положите файл `assets/models/mobilefacenet.tflite` (см. `assets/models/README.md`).
Без него приложение запустится и покажет интерфейс, но отметка попросит добавить модель.

### 4. Адрес сервера
На экране входа → «Настройка сервера». По умолчанию `http://10.0.2.2:3000`
(так Android-эмулятор видит localhost хоста). Для реального телефона укажите
IP компьютера в общей сети, напр. `http://192.168.0.10:3000`.

## Тестовые входы (после `npm run seed` на сервере)
- Администратор: `admin` / `admin123`
- Сотрудник: `aziz` / `aziz123`

## Структура
```
lib/
  main.dart               маршрутизация по роли
  theme.dart              дизайн-система (вариант A)
  api/                    клиент REST + модели
  services/               лицо (ML Kit + TFLite), геолокация, устройство
  state/session.dart      текущий пользователь
  screens/
    login_screen.dart
    employee/             главная, регистрация лица, отметка, история
    admin/                обзор, сотрудники, аномалии, рабочие места
  widgets/face_scan.dart  камера + детекция лица + овал
```

## На что обратить внимание на реальном устройстве
- Конвертация кадра камеры в формат ML Kit (`face_service.dart`,
  `inputImageFromCamera`) и ориентация фронтальной камеры могут потребовать
  подгонки под конкретный телефон/версию плагина.
- Проверьте, что формат входа/выхода вашей `.tflite`-модели совпадает с
  параметрами в `face_service.dart`.
