# Red Card Alert Laravel API

Laravel API inayotumia API-Football v3 kwa mechi za moja kwa moja, matukio na
takwimu za mechi; data husawazishwa kwenye MySQL.

## Mahitaji

- PHP 8.2+
- Composer 2
- MySQL 8 au MariaDB 10.6+

## Setup

```bash
cd laravel-api
composer install
cp .env.example .env
php artisan key:generate
```

Fungua `laravel-api/.env` na weka MySQL credentials pamoja na API keys:

```env
API_FOOTBALL_KEY=your_api_football_key
OPENAI_API_KEY=your_openai_api_key
```

Mkaria AI na AI Analyst hutumia modeli ya OpenAI `gpt-4o-mini`. Baada ya
kubadilisha `.env`, safisha config cache kisha endesha migrations:

```bash
php artisan config:clear
php artisan migrate
php artisan serve --host=0.0.0.0 --port=8000
```

Jaribu `http://127.0.0.1:8000/api/health` na
`http://127.0.0.1:8000/api/fixtures/live`.

## Match Insights na AI Analyst

`GET /api/fixtures/{fixture_id}/insights` hutoa pressure, card risk,
probabilities, na historia ya msimu kwa mechi zijazo. Takwimu mpya za cards,
shots na corners huhifadhiwa kwenye `fixtures`; `php artisan migrate` huongeza
columns hizo kwenye database iliyopo.

AI Analyst hutumia Laravel proxy, si SDK kwenye Flutter, ili API key
isifichuliwe ndani ya app. Weka `OPENAI_API_KEY` kwenye `.env` ya backend.
Modeli inayotumika ni `gpt-4o-mini`. Mipaka ya matumizi na
upatikanaji wa OpenAI hutegemea akaunti na modeli. Backend pia inaweka kikomo cha pamoja cha
maombi 8 kwa dakika na 100 kwa siku kwa API key, pamoja na kikomo cha IP cha
endpoint, ili kupunguza matumizi na kuepuka kufikia quota haraka. Endpoint ni
`POST /api/fixtures/{fixture_id}/ai-analysis`; matokeo huhifadhiwa kwa saa 6
kwa data inayolingana na insights, na endpoint ina kikomo cha maombi 10 kwa
dakika. Kwa deployment yenye server nyingi, tumia cache store inayoshirikiwa
kama Redis ili vikomo hivi vitumike kwa server zote. Usichapishe au kuweka API
key kwenye Flutter. Jibu la endpoint lina `data.reply` na `data.betslip`;
odds na combined odds hazipatikani bila odds provider, kwa hiyo hurudishwa
`null`.

Baada ya kubadilisha `.env` kwenye production, safisha config cache kwa
`php artisan config:clear` au tengeneza upya kwa `php artisan config:cache`.

## Admin na subscriptions

Usajili huanza trial ya siku 7. AI analysis inahitaji token ya `auth:sanctum`;
access inaruhusiwa kwa trial halali au subscription ya kulipia iliyo hai. Bei
ni TZS 5,000 kwa mwezi. Malipo hayathibitishwi na API ya app: admin aandike
payment reference iliyothibitishwa nje ya mfumo kabla ya kuwasha subscription.

Unda akaunti ya kwanza ya admin kwa kusajili akaunti ya kawaida, kisha endesha
amri hii kwenye server:

```bash
php artisan app:promote-admin admin@example.com
```

Admin API (Bearer token ya admin inahitajika):

- `GET /api/admin/stats` — `total_revenue` (idadi ya active paid users × TZS
  5,000), free trials, na active paid users.
- `GET /api/admin/dashboard` — stats za ziada za subscriptions na users.
- `GET /api/admin/users?search=&status=&per_page=` — orodha yenye pagination.
- `GET /api/admin/users/{id}` — maelezo, payment history na subscriptions.
- `PATCH /api/admin/users/{id}/subscription` — body ya kuwasha:
  `{"action":"activate","reference":"VERIFIED-PAYMENT-REFERENCE","payment_method":"mobile_money"}`.
  Hii hurekodi TZS 5,000 kama malipo yaliyothibitishwa na kuongeza mwezi mmoja.
  Kwa kusimamisha tumia `{"action":"disable"}`.
- `POST /api/admin/users/{id}/toggle-status` — `{"status":"active_paid","reference":"VERIFIED-PAYMENT-REFERENCE"}` au `{"status":"disabled"}`.
- `GET /api/subscription/status` na `GET /api/subscription/payments` — status na
  historia ya malipo ya mtumiaji aliyeingia.

Status za user ni `free_trial`, `active_paid`, `expired`, na `disabled`.
`GET /api/admin/stats` hukadiria mapato ya mwezi kwa kuzidisha active paid
users kwa TZS 5,000; payment ledger pia huhifadhi malipo yaliyothibitishwa.
Admin API ni JSON endpoints kwa Flutter au dashboard nyingine; haijaongezwa
Blade UI.

Unaweza pia ku-import `database/schema/red_card_alert.sql` kupitia phpMyAdmin
badala ya `php artisan migrate`. Usitumie zote mbili kwenye database ileile.

Kwa production, run scheduler na queue worker:

```bash
php artisan schedule:work
php artisan queue:work --tries=3
```

Scheduler husawazisha fixtures za live, matukio na takwimu za mechi kila
dakika tano. API-Football ina vikomo vinavyotegemea mpango wa API; maombi ya
fixtures pamoja na kila mechi hai yanaweza kutumia quota haraka. API key
hubaki kwenye backend na kamwe isiwekwe kwenye Flutter.

## Mkaria AI Chat

Flutter app ina screen ya Mkaria AI inayotumia `POST /api/mkaria-chat` kwa
Bearer token ya Sanctum. Endpoint inahitaji trial/subscription hai na ina
kikomo cha maombi 6 kwa dakika kwa mtumiaji. Body ina `message`, na inaweza
kuwa na `fixture_id`, `history` ya ujumbe hadi 10 iliyopita (`role` ni `user`
au `assistant`), na `filters` za `date`, `time_from`, `time_to`, `league` na
`country`. Filters za tarehe na saa hutumia timezone ya Laravel app. History
iliyotumwa hutumika tu kuanzisha mazungumzo mapya na huhifadhiwa pamoja na
mazungumzo hayo; kwa `conversation_id`, backend hutumia historia iliyohifadhiwa
ya mtumiaji aliyeingia na hupuuza history inayotumwa na client. Backend huingiza
live fixtures na upcoming fixtures zinazoanza ndani ya saa sita zijazo kutoka
API-Football cache na, inapopewa `fixture_id`, match insights ya mechi hiyo.
Ikiwa dirisha la saa sita linavuka usiku wa manane, backend pia hutafuta ratiba
ya siku inayofuata. Tarehe, muda, ligi na nchi zilizochaguliwa bado huchujwa
kama ilivyoombwa.

Ujumbe unaoomba uchambuzi wa upcoming games au betslip hujumuisha historia ya
mechi. Ujumbe wa betslip hutumia mechi ambazo bado hazijaanza pekee. Backend
huchambua hadi mechi 5 za karibu ndani ya dirisha hilo, ikijumuisha form ya
mechi 5 za karibuni za kila timu, head-to-head ya hadi mechi 5, na takwimu za
msimu zinazopatikana. Historia huhifadhiwa kwenye cache ili kupunguza maombi ya
API-Football. Mkaria hutumia chaguo 72 za msingi pamoja na mistari mingine
sanifu ya Over/Under, team totals, corners, Asian Handicap na European
Handicap; anaweza kurudisha hadi picks 8 zinazoungwa mkono na data kutoka
kwenye masoko ya matokeo, magoli, BTTS, kona, kadi na mchanganyiko. Kila chaguo
hufafanuliwa kwenye reply. Kwa betslip yenye mechi nyingi, Mkaria hulinganisha
ushahidi wa kila mechi kando na hupendelea kutofautisha market ikiwa ushahidi
unaunga mkono. Backend huhifadhi historia ya mazungumzo na huepuka kupendekeza
tena mechi zilizochaguliwa awali ndani ya mazungumzo hayo. Muktadha wa AI
hupunguzwa kwa mechi zisizozidi 5 zenye uchambuzi unaolingana ili kuboresha
muda wa maandalizi. Masoko ya handicap, kona na kadi ni ya kabla ya
mechi; kona na kadi haziruhusiwi kwa mechi inayoendelea bila data ya sasa ya
matukio/takwimu inayothibitisha hali yake. Chaguo la mchezaji kupewa kadi
halitumiki kwa sasa kwa sababu schema ya betslip na match context havitoi
uthibitisho wa mchezaji husika. Betslip hurudishwa hata kama hakuna chaguo
linalothibitishwa, lakini picks zake hubaki tupu badala ya kubuni mapendekezo.

Mkaria AI Chat hutumia OpenAI Chat Completions na `gpt-4o-mini`. Weka
`OPENAI_API_KEY` kwenye `.env` ya backend; API key hutumika backend pekee.
OpenAI huombwa kurudisha JSON kupitia `response_format: json_object`
na backend huthibitisha muundo wake kabla ya kutuma jibu. Jibu
hurudisha `data.reply` na `data.betslip` yenye picks, market, risk na
confidence. Hakuna odds provider iliyounganishwa kwenye chat, kwa hiyo
`odds` na `combinedOdds` hurudishwa `null` badala ya kubuni bei. Prompt ya
backend inaelekeza Mkaria AI isitoe uhakika wa matokeo na itaje kutokuwa na
uhakika. Filters za mechi na sheria za kuondoa mapendekezo ambayo tayari
yameamuliwa huhifadhiwa kwenye backend bila kujali majibu ya modeli.
