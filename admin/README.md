# OddFlip Admin Flutter App

Flutter admin dashboard ya kusimamia subscriptions za OddFlip. Code ya app hii
ipo ndani ya folda hii, tofauti na app ya watumiaji iliyo `flutter_app/`.

## Inachofanya

- Admin anaingia kwa email na password ya Laravel.
- Inakataa akaunti isiyo na role ya `admin`.
- Inaonyesha mapato yanayokadiriwa, free trials na active paid subscriptions.
- Inaorodhesha, kutafuta na kuchuja watumiaji; orodha ina pagination.
- Inawezesha admin kuzima subscription au kuwasha paid plan baada ya kuweka
  payment reference iliyothibitishwa.
- Access token huhifadhiwa kupitia `flutter_secure_storage`.

## Kuendesha

Anzisha Laravel API kwanza. Kutoka `laravel-api/`:

```powershell
php artisan serve --host=0.0.0.0 --port=8000
```

Kisha, kutoka `admin/`, weka dependencies na endesha:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Kwa Android emulator tumia:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

Kwa simu halisi, tumia IP ya kompyuta kwenye mtandao wa ndani badala ya
`127.0.0.1`, na hakikisha server/firewall inaruhusu muunganisho.

## Admin ya kwanza

Sajili akaunti kupitia app/API, kisha ipeleke role ya akaunti hiyo kuwa admin
kwenye Laravel server:

```powershell
php artisan app:promote-admin admin@example.com
```

Admin API inahitaji Sanctum auth na middleware ya admin. Kuongeza paid plan
kunatengeneza ledger entry ya TZS 5,000; paneli haitoi uthibitisho wa payment
provider. Hakikisha reference ni ya malipo yaliyopokelewa kabla ya kuthibitisha.
