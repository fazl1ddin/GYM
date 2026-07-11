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
**Android** — `android/app/build.gradle` → `minSdkVersion 24` (нужно для ML Kit и tflite).

**iOS** — плагины ML Kit требуют минимум **iOS 15.5**. В `ios/Podfile`:
```ruby
platform :ios, '15.5'                 # раскомментировать и поставить 15.5

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
    end
  end
end
```
Затем `cd ios && pod install` (при ошибке: `rm -rf Pods Podfile.lock && pod install`).
В Xcode: Runner → General → Minimum Deployments → iOS 15.5.
> Без этого сборка падает: `google_mlkit_commons requires a higher minimum iOS deployment version`.

### 3. Модель распознавания — не нужна
Распознавание считает **сервер** из загруженного фото (надёжнее). Приложению
модель на устройстве не требуется. Опциональный on-device вариант —
см. `assets/models/README.md`.

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

## Защита (реализовано на сервере, клиент шлёт данные)
- **Живость** проверяет сервер: приложение шлёт 2 кадра действия
  (`FaceScanView.snapshotDataUrl` → `cameraImageToDataUrl`), сервер сверяет с
  запрошенным действием. Ранняя отладка — `FACECLOCK_SERVER_LIVENESS=off`.
- **QR проходной**: если у рабочего места включён «требовать QR», перед отметкой
  открывается сканер (`qr_scan_screen.dart`). Админ показывает код на терминале
  (`qr_terminal_screen.dart`, экран рабочих мест → иконка QR).

## Функции
- **Табель** (админ → вкладка «Табель»): часы/опоздания/переработки, экспорт CSV
  кнопкой «CSV» (через share_plus).
- **Офлайн-отметки**: если сети нет, отметка снимается и сохраняется в очередь
  (`offline_queue.dart`), досылается автоматически при заходе на главную.
- **Push-напоминания**: сервер шлёт напоминания забывшим отметиться. Для приёма
  push настройте Firebase и вызовите `NotificationService.registerToken(fcmToken)`
  — точка интеграции в `services/notification_service.dart` (firebase_messaging
  добавляется в вашем проекте).

## На что обратить внимание на реальном устройстве
- Конвертация кадра камеры в формат ML Kit (`inputImageFromCamera`) и в JPEG
  для кадров живости (`cameraImageToDataUrl`, NV21/BGRA), а также ориентация
  фронтальной камеры могут потребовать подгонки под конкретный телефон.
- on-device `.tflite`-модель опциональна; если используете — сверьте формат
  входа/выхода с `face_service.dart`.
