# Red Card Alert: Flutter + Laravel + MySQL

Repo sasa ina:

- `flutter_app/` — Android/iOS Flutter app.
- `laravel-api/` — Laravel REST API na MySQL database.
- `laravel-api/database/schema/red_card_alert.sql` — SQL schema kamili ya
  ku-import kwenye phpMyAdmin.
- `src/`, `backend/`, `android/`, `ios/` — toleo la zamani la
  React/Node/Capacitor, limeachwa kama reference ili kazi ya awali isipotee.

## 1. Install tools

Install:

1. VS Code.
2. VS Code extensions: **Flutter** na **Dart**.
3. Flutter SDK kisha hakikisha `flutter doctor` haina kosa muhimu.
4. Android Studio (kwa Android SDK, emulator na platform tools).
5. PHP 8.2+, Composer 2, na XAMPP/WAMP/MAMP yenye MySQL + phpMyAdmin.

Kwenye terminal:

```bash
flutter doctor
php -v
composer --version
```

## 2. Kutengeneza database kupitia phpMyAdmin

### Njia A: import SQL (rahisi)

1. Washa **Apache** na **MySQL** kwenye XAMPP.
2. Fungua `http://localhost/phpmyadmin`.
3. Chagua **Import**.
4. Chagua `laravel-api/database/schema/red_card_alert.sql`.
5. Bonyeza **Import/Go**. Script itatengeneza database `red_card_alert` pamoja
   na tables zote.

### Njia B: Laravel migrations

Kwenye phpMyAdmin, tengeneza database tupu iitwayo `red_card_alert`, collation
`utf8mb4_unicode_ci`. Usifanye SQL import ikiwa utatumia migrations.

```bash
cd laravel-api
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate
```

Tables muhimu:

- `users`, `personal_access_tokens`
- `leagues`, `teams`, `fixtures`, `match_events`
- `favorite_teams`, `favorite_leagues`, `favorite_fixtures`
- `alert_settings`, `device_tokens`, `alert_deliveries`
- `sync_runs`, `cache`, `jobs`, `job_batches`, `failed_jobs`

## 3. Laravel `.env`

Copy `laravel-api/.env.example` kwenda `laravel-api/.env`, halafu edit:

```dotenv
APP_URL=http://localhost:8000

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=red_card_alert
DB_USERNAME=root
DB_PASSWORD=

SPORTRADAR_API_KEY=WEKA_KEY_YAKO_HAPA
```

Kwa XAMPP default, username ni `root` na password ni tupu. Kama uliweka
password kwenye MySQL, iandike kwenye `DB_PASSWORD`.

Sportradar key ibaki Laravel `.env` pekee. Usiweke key kwenye Dart, Git, au APK.

Start API:

```bash
cd laravel-api
php artisan serve --host=0.0.0.0 --port=8000
```

Test:

```text
http://127.0.0.1:8000/api/health
http://127.0.0.1:8000/api/fixtures/live
```

## 4. Kufungua Flutter kwenye VS Code

```bash
cd flutter_app
flutter create . --platforms=android,ios --org com.redcardalert
flutter pub get
code .
```

`flutter create` ni ya mara moja tu; inatengeneza native runner files
zinazolingana na Flutter SDK uliyo-install. Web, iOS, na Android targets
zinapaswa kuwepo kwenye project.

Baada ya hapo fungua `android/app/build.gradle.kts` na hakikisha:

```kotlin
namespace = "com.redcardalert.app"
defaultConfig {
    applicationId = "com.redcardalert.app"
}
```

Kwa local HTTP development, ndani ya
`android/app/src/main/AndroidManifest.xml`, hakikisha `<application>` ina:

```xml
android:usesCleartextTraffic="true"
```

Production itumie HTTPS na cleartext izimwe.

## 5. Run kwenye Android Emulator

1. Android Studio → **Device Manager** → **Create device**.
2. Chagua Pixel na Android image, kisha start emulator.
3. VS Code: `Ctrl+Shift+P` → **Flutter: Select Device** → chagua emulator.
4. Hakikisha Laravel API inaendelea ku-run.
5. Bonyeza `F5`, au:

```bash
cd flutter_app
flutter run
```

Emulator hutumia API URL ya default `http://10.0.2.2:8000`. `10.0.2.2`
humaanisha computer yako kutoka ndani ya Android emulator.

## 6. Chrome na iOS Simulator

Chrome kwenye computer ileile hutumia `http://localhost:8000`:

```bash
cd flutter_app
flutter run -d chrome
```

iOS Simulator hutumia `http://127.0.0.1:8000` na inahitaji macOS pamoja na
Xcode:

```bash
cd flutter_app
flutter devices
flutter run -d <ios-simulator-id>
```

Kwa simu halisi, tumia IP ya LAN ya computer na endesha Laravel kwa
`--host=0.0.0.0`. Override inakubali server root au URL inayoishia `/api`:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

URL default hutofautiana kwa Web, Android Emulator, na iOS/Desktop. Android
cleartext na iOS ATS exceptions kwenye scaffold hii ni kwa local development;
production itumie HTTPS.

## 7. Run kwenye simu halisi kupitia VS Code

1. Simu na computer ziwe kwenye Wi-Fi moja.
2. Android: Settings → About phone → gonga **Build number** mara 7.
3. Developer options → washa **USB debugging**.
4. Unganisha USB na ukubali RSA prompt.
5. Thibitisha:

```bash
flutter devices
```

Tafuta local IPv4 ya computer:

- Windows: `ipconfig`
- macOS/Linux: `ifconfig` au `ip addr`

Run ukitumia IP hiyo, mfano:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

Usitumie `localhost` kwenye simu; `localhost` ya simu ni simu yenyewe. Ruhusu
PHP port 8000 kwenye firewall kama simu haiwezi ku-connect.

Njia mbadala ya USB bila kutafuta IP:

```bash
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## 8. Run services kwenye VS Code

Fungua terminals mbili:

**Terminal 1 — Laravel**

```bash
cd laravel-api
php artisan serve --host=0.0.0.0 --port=8000
```

**Terminal 2 — Flutter**

```bash
cd flutter_app
flutter run
```

## 9. Production

Deploy `laravel-api/` kwenye server yenye PHP/MySQL na HTTPS. Kisha:

```bash
cd flutter_app
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.example.com
```

File ya Play Store itakuwa:
`flutter_app/build/app/outputs/bundle/release/app-release.aab`.

Push notifications halisi zinahitaji kuongeza Firebase Cloud Messaging,
ku-register `device_tokens`, na queue job inayotengeneza `alert_deliveries`.
Schema ya database tayari imeandaliwa kwa hatua hiyo; client ya sasa
inaonyesha in-app alert inapogundua card mpya kwenye timeline.
