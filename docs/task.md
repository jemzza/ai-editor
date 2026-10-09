# Задача

AI-редактор текста для iPhone в духе QuillBot. Тестовое задание: 4 часа подряд.
Основа — шаблон, собранный до старта из первого тестового (AI-чат), см. раздел
«Подготовлено до старта» в `docs/plan.md`.

## Задание (дословно)

ФИНАЛЬНОЕ ЗАДАНИЕ: AI-РЕДАКТОР ТЕКСТА ДЛЯ IPHONE
Сделайте небольшое приложение — AI-редактор текста в духе QuillBot. Как и в первом задании, пишите его с помощью любых AI-инструментов; свои наработки, в том числе с первого этапа, использовать можно. На задание — 4 часа подряд, когда начать, решаете сами.

ЧТО СДЕЛАТЬ
• Пользователь вставляет текст и выбирает действие: перефразировать, сократить, перевести на выбранный язык, исправить ошибки.
• Результат появляется по мере генерации, есть кнопка «Стоп».
• Режим «было — стало»: изменения подсвечены по словам, результат можно скопировать.
• История правок сохраняется после перезапуска, любую правку можно открыть из истории.
• Понятные состояния: загрузка, ошибка (нет сети, кончился лимит API) с кнопкой «Повторить», пустой экран.
• Аккуратный интерфейс в духе iOS, светлая и тёмная тема.
• По желанию: расширение «Поделиться» для других приложений, версия для Mac по гайдлайнам macOS, выбор тона для перефразирования.

ТРЕБОВАНИЯ К ПРОЕКТУ
• Минимальная версия iOS — 18: приложение должно работать и на iOS 18, и на последней iOS.
• Проект на XcodeGen (project.yml). В корне — файл Build.command: двойной клик в Finder запускает xcodegen generate и собирает проект под симулятор, без ручных команд в терминале.
• Зависимости — только через Swift Package Manager, без CocoaPods.

AI ВНУТРИ ПРИЛОЖЕНИЯ
Нужна только текстовая модель. Подойдут бесплатные: Groq, OpenRouter (бесплатные модели), Gemini API или Cloudflare Workers AI. Ключ положите прямо в проект в обфусцированном виде, не открытым текстом. Приложение должно запускаться сразу после сборки, без настроек. Проверьте, что у ключа останется бесплатный лимит на нашу проверку — около 40 запросов. Модель задайте одной константой: если к проверке бесплатная модель исчезнет, мы заменим её без штрафа.

СРОК
4 часа подряд. Время старта и финиша запишите в README. Что не успели — опишите в README, после финиша работу не продолжайте.

ЧТО ПРИСЛАТЬ
Архив (zip) всей папки проекта вместе с папкой .git — файлом или ссылкой на облако. В архиве:

1. Проект, который собирается двойным кликом по Build.command. Коммитьте по ходу работы, а не одним коммитом в конце.
2. Документацию, по которой вы вели AI: описание задачи, план, правила для агента (CLAUDE.md, AGENTS.md и т. п.) — в том виде, в каком реально её использовали. Описание и план — в папке docs/, файлы правил — там, где их читал агент.
3. Папку ai-logs/ с файлами сессий работы с AI. Claude Code и Codex сохраняют логи сами: Claude Code — папка вашего проекта в ~/.claude/projects/, Codex — файлы за день работы в ~/.codex/sessions/. Из Cursor и чатов в браузере — экспорт или ссылки на чаты. Пересказ логов не подходит. Уберите из логов ключи и личные данные.
4. README по шаблону:
— Время: старт и финиш.
— Инструменты: какими AI-инструментами и моделями пользовались.
— AI в приложении: какой сервис и какая модель.
— Сделано: что работает.
— Не сделано и известные баги.
— Как проверяли, что всё работает.

## Решения

| Вопрос | Решение | Почему |
|---|---|---|
| Основа | Шаблон из AI-чата: всё, что в чате было и только переименовано Chat → Edit, перенесено **готовым, с тестами**; всё новое для редактора (промпты, diff, экран Editor) — только контракты и заглушки | На 4 часа остаётся только новая логика. Перенесённое уже проверено в первом задании |
| Архитектура | MVVM + offline-first: GRDB — единственный источник правды, UI читает через `ValueObservation` → `AsyncStream`, сеть только пишет в базу через `EditService` | Как в чате; история правок переживает перезапуск «бесплатно» |
| Живой стриминг | Исключение из offline-first: `EditService` отдаёт черновик результата в памяти (`draftUpdates`), ViewModel кладёт его поверх правки со статусом `streaming`. В БД — не чаще ~2 раз/с (`writeInterval` 500 мс) + финальная запись | Иначе при записи 2 раза/с текст появлялся бы кусками, а не по токенам |
| Владелец стрима | `EditService` (живёт в `AppContainer`), не ViewModel | Уход с экрана / открытие другой правки не отменяет генерацию |
| Правка = запись истории | Каждое нажатие главной кнопки — **новая** правка (`EditSession.start`). «Retry»/«Regenerate» — та же правка (`claimRetry`: результат очищается, статус `streaming`) | История показывает все попытки с разными режимами; повтор не плодит дубликаты |
| Outbox | **Не переносим.** Без сети запрос уходит и падает → правка `failed(offline)` с «Retry» | Задание прямо требует состояние «нет сети» с «Повторить». Очередь отправки для редактора не нужна |
| Статус сети | `NWPathMonitor` за `ConnectivityMonitoring` — **только подсказка** (баннер «No connection»), запрос не блокирует | Урок из чата: на симуляторе (и при VPN) монитор врёт; решает настоящий ответ сети |
| Хранилище | GRDB 7 (SPM, `exactVersion` в `project.yml`), одна миграция `v1` (`folder`, `edit`) | `ValueObservation` хорошо ложится на MVVM; `Sendable`-модели; контрактные тесты на фейке и GRDB уже есть. SwiftData тянет `@Query` во View и плохо дружит со строгой конкурентностью |
| AI-провайдер | Groq, OpenAI-совместимый `/chat/completions` со `stream: true`; свой SSE-парсер поверх `URLSession.bytes` | Бесплатный тариф, очень быстрый стриминг; парсер и маппинг ошибок перенесены с тестами |
| Модель | `openai/gpt-oss-120b` — **одна константа `LLMConfig.model`** (`AIEditor/Data/LLM/LLMConfig.swift`). Запасная — `openai/gpt-oss-20b` (лимиты те же, считаются отдельно). Параметры: `reasoning_effort: "low"`, `include_reasoning: false`, `max_completion_tokens: 2048` | Лучшая бесплатная production-модель Groq для многоязычного текста. gpt-oss — reasoning-модель: без `include_reasoning: false` в ответ попадут рассуждения |
| Лимит ключа | Groq Free для gpt-oss-120b (сверено 2026-10-09 по сторонним трекерам и нашей проверке 2026-10-08): **30 RPM, 1 000 RPD, 8 000 TPM, 200 000 TPD**. Проверка ≈ 40 запросов × 2–4K токенов = 80–160K < 200K TPD, RPD с запасом. Узкое место — 8K TPM ⇒ исходник ограничен `EditLimits.maxSourceCharacters = 5000` (≈1,5–2,5K токенов) | Чтобы проверяющему хватило лимита. Во время 4 часов гоняем UI на фейках (`-mockSlowStream`, `-mockError`), реальную модель — только для проверки промптов (≤ 20 запросов); лимиты суточные |
| Промпты | Контракт `PromptBuilding.messages(for:source:)` → `[system, user]`. Провайдер ничего не добавляет. Требования: в ответе только результат (без «Here is…», кавычек, Markdown), язык исходника (кроме translate). До реализации — `StubPromptBuilder` | Промпты — новая логика, на отрезок (ветка A) |
| Diff | Контракт `WordDiffing.diff(from:to:) -> [DiffSegment]` (`equal` / `inserted` / `removed`). Реализация — стандартный `CollectionDifference` по токенам «слово / пробелы / пунктуация» (без зависимостей), склейка соседних сегментов; подсветка — `AttributedString` (удалённое: `DiffRemoved` + зачёркивание, добавленное: `DiffInserted`). До реализации — `StubWordDiff` | Пробелы — тоже токены, поэтому текст собирается обратно без потерь (инвариант в `DiffSegment`). `difference(from:)` — алгоритм Майерса, O((n+m)·d): на 5 000 символов (~1 000 слов) мгновенно |
| UI | SwiftUI, `@Observable`. iPhone (compact) — свой выезжающий сайдбар поверх экрана; iPad/Mac (regular) — `NavigationSplitView`. Верхняя панель своя | Как в чате; одинаково на iOS 18 и 26 |
| Язык интерфейса | Только английский, все строки — через `Localizable.xcstrings` (`LocalizedStringKey`, `String(localized:)`, `LocalizedStringResource`). Русский перевод **не** ведём (в чате был) | Задание не требует; экономим время отрезка. Каталог позволяет добавить язык без правки кода. `xcodebuild` ключи сам не дописывает — `scripts/sync_strings.py` |
| Цвета | Монохром, как ChatGPT: системные + `Background` (белый/чёрный), `Surface` (светло-серый/тёмно-серый), `Accent` (чёрный/белый), `DiffInserted`, `DiffRemoved` — все с Light и Dark в `Assets.xcassets`. Тёплая палитра и serif из чата **не** переносятся | Решение заказчика, UI-референс ниже |
| Ключ | XOR с солью, `scripts/gen_secrets.py` из env (`GROQ_API_KEY`). **Запускает пользователь**, агент — никогда. `Secrets.generated.swift` закоммичен (не в `.gitignore`); пустой ключ → ошибка `unauthorized` без запроса | Ключ не попадает в чат с агентом и в git открытым текстом |
| DEBUG-хуки | Launch-аргументы: `-mockData` (история из `PreviewData`), `-mockOffline` (баннер + LLM падает `offline`), `-mockError 429\|401\|403\|500\|offline`, `-mockSlowStream`, `-mockDictation`. Разбирает `LaunchOptions`; по умолчанию — только реальные реализации; в Release аргументы игнорируются | Сценарии ошибок проверяемы без правки кода |
| Фейки | `AIEditor/Mocks/` под `#if DEBUG`: `InMemoryEditRepository`, `FakeLLMProvider`, `FakeConnectivityMonitor`, speech- и notification-фейки, `PreviewData`, `EditorDependencies.preview()` (настоящий `EditService` поверх фейков). Заглушки `StubPromptBuilder` / `StubWordDiff` — в `Domain/Services` (работают и в Release, пока не заменены) | Фейки не попадают в обычный запуск; заглушки — временный прод-код до слияния веток |
| Папки | Один уровень, правка — максимум в одной папке (`edit.folderId`), FK `ON DELETE SET NULL` (удаление папки возвращает правки в «Recents»); ручной порядок только у папок; перенос — drag-and-drop (`Transferable`, свой `UTType` в `project.yml`) и «Move to folder» в меню | Перенесено из чата как есть |
| Голос | Диктовка «зажми и говори» → текст дописывается в поле исходника (`VoiceRecording` + `SpeechTranscribing`: iOS 26 `SpeechAnalyzer`, iOS 18 `SFSpeechRecognizer`); «Read aloud» результата — `SpeechSynthesizing` (`AVSpeechSynthesizer`, голос по языку текста) | Перенесено из чата; без SPM-зависимостей |
| Настройки | `UserDefaults` за `SettingsStoring`: тема (System/Light/Dark через `overrideUserInterfaceStyle` окна), уведомление «Edit is ready» (только когда приложение не активно). Privacy: куда уходит текст + «Delete all history» | Перенесено из чата; тема нужна до открытия базы |
| Mac | Mac Catalyst «Optimize for Mac» (`SUPPORTS_MACCATALYST`, `TARGETED_DEVICE_FAMILY: 1,2,6`), код общий. Сборка: `xcodebuild … -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build`. `Build.command` собирает только под симулятор | Бонус без второго таргета |
| Тесты | Swift Testing; UI — XCUITest (`-mockData`). Контрактные тесты `EditRepository` — одни и те же для in-memory и GRDB | Как в чате |

## Маппинг ошибок

- `URLError` → `offline` только для `notConnectedToInternet`, `networkConnectionLost`,
  `dataNotAllowed`, `timedOut`, `cannotFindHost`, `cannotConnectToHost`; прочие → `unknown`.
- `CancellationError` и `URLError.cancelled` — не ошибка, а «Stop» → `cancelled`.
- HTTP ≠ 200: дочитать тело (до 4 KB), по коду: 401 → `unauthorized`, 403 → `forbidden`,
  429 → `rateLimited` + `retry-after` («Try again in N s»), 5xx → `server`; прочие — по
  `type`/`code` из тела, иначе `unknown`.
- Пустой ключ → `unauthorized` без запроса в сеть.
- Соединение закрылось без `data: [DONE]` → `unknown` (результат обрезан, а не готов).
- Ошибка внутри SSE при HTTP 200 (`data: {"error": …}`) → по `type`/`code`, иначе `server`.
- Тексты ошибок (`EditErrorPresentation`) не содержат ключ, URL и сырой ответ сервера.

| `ErrorKind` | Текст в UI | Иконка |
|---|---|---|
| `offline` | No internet connection. | `wifi.slash` |
| `rateLimited` | The AI service rate limit was reached. (+ «Try again in N s») | `hourglass` |
| `unauthorized` | The AI service rejected the API key. | `key` |
| `forbidden` | The AI service isn't available in your region. | `globe` |
| `server` | The AI service is having problems. Please try again. | `exclamationmark.icloud` |
| `unknown` | Something went wrong. | `exclamationmark.triangle` |
| статус `interrupted` | The result was interrupted. | `exclamationmark.bubble` |

## Поведение правки

1. Главная кнопка: правка сразу пишется в БД (`streaming`, заголовок — первые слова
   исходника), генерацией владеет `EditService`.
2. Стриминг: текст копится в памяти и идёт в UI через черновик; в БД — не чаще ~2 раз/с и в конце.
3. «Stop» → `cancelled`, частичный текст остаётся (и виден в истории).
4. Ошибка → `failed` + `EditFailure` (вид, `retryAt` при 429) — плашка с «Retry».
5. «Retry» / «Regenerate» → та же правка, `claimRetry` атомарно; повторное нажатие
   во время генерации ничего не делает.
6. Запуск приложения: `streaming` → `interrupted` (с «Retry»).
7. Удаление правки во время стрима отменяет его `Task`; запоздавшая запись получает
   `EditNotFound`, сервис её глотает.
8. «Загрузка» в UI = ожидание первого токена (`GeneratingIndicator`).
9. Готовая правка при свёрнутом приложении → локальное уведомление «Edit is ready»
   (если включено в настройках); нажатие открывает правку.

## UI-референс

Без логотипа, названия и фирменного цвета Claude/QuillBot; иконки — SF Symbols.

### Структура (как у QuillBot)

- **Сверху** — переключатель режимов: Paraphrase / Shorten / Translate / Fix grammar
  (сегменты). Для Paraphrase — выбор тона (Standard / Formal / Casual / Simple), для
  Translate — выбор языка (меню).
- **Поле исходного текста** — карточка `Surface` со скруглением; внутри внизу:
  кнопки **Paste** и **микрофон** (диктовка), справа — **счётчик слов**
  (и предупреждение при приближении к лимиту 5 000 символов). Пустое поле — плейсхолдер.
- **Главная кнопка действия** — на всю ширину, `Accent` (чёрная в светлой теме, белая
  в тёмной), подпись по режиму («Paraphrase», «Translate to German»…); во время генерации
  на её месте — «Stop».
- **Панель результата** ниже: текст появляется по токенам; до первого токена — три точки;
  внизу — **Stop** (во время генерации), **Copy**, **Read aloud** и переключатель
  **Compare** (было — стало: удалённое — приглушённо-красное с зачёркиванием,
  добавленное — приглушённо-зелёное, по словам).
- **Ошибки** — спокойная плашка под панелью результата: иконка, текст по таблице выше,
  «Retry» (неактивна во время обратного отсчёта 429).
- **Пустой экран** (новая правка): короткая подсказка в панели результата
  («Paste or type text, choose a mode…»), без иллюстраций.
- **Верхняя панель** своя: слева — сайдбар, по центру — название правки (тап —
  переименовать) и подпись «Groq · gpt-oss-120b», справа — «New edit».
- **История** — в сайдбаре, как чаты в первом проекте: поиск (по названию и исходнику),
  папки, «Recents» по датам (Today / Yesterday / Previous 7 days / Older), долгое
  нажатие — Rename / Move to folder / Delete. Тап открывает правку целиком (исходник,
  режим, результат, Compare). Внизу слева — шестерёнка настроек.
- Клавиатура скрывается тапом по пустому месту и свайпом прокрутки.

### Цвета и типографика

- Монохром: светлая — белый фон, светло-серые поверхности, чёрная главная кнопка;
  тёмная — наоборот. Системные цвета (`.primary`, `.secondary`) + `Background`,
  `Surface`, `Accent`, `DiffInserted`, `DiffRemoved` из `Assets.xcassets`.
- Шрифт — SF Pro, только Dynamic Type; текст исходника и результата — `.body`.
- Светлая и тёмная тема без отдельного кода; проверка на iOS 18 и iOS 26.

## Модель данных

```swift
enum EditAction { paraphrase(tone: ParaphraseTone?), shorten, translate(language: String /* BCP-47 */), fixGrammar }
enum ParaphraseTone: String { standard, formal, casual, simple }
enum EditStatus: String { streaming, done, cancelled, failed, interrupted }   // isRetryable: всё, кроме streaming
struct EditFailure { kind: ErrorKind; retryAt: Date? }
struct Edit { id, title, folderId?, action, sourceText, resultText, status, failure?, createdAt, updatedAt }
struct Folder { id, name, position, createdAt }
struct DiffSegment { kind: equal | inserted | removed; text }
```

Таблицы (миграция `v1`):

- `folder(id BLOB PK, name, position INTEGER indexed, createdAt REAL)`
- `edit(id BLOB PK, title, folderId BLOB → folder ON DELETE SET NULL (indexed), action TEXT,
  actionOption TEXT /* тон или код языка */, sourceText, resultText, status TEXT indexed,
  failureKind TEXT, failureRetryAt REAL, createdAt REAL, updatedAt REAL indexed)`

Даты хранятся числом (`timeIntervalSinceReferenceDate`) — без потери точности.

## Протоколы (`Domain/Protocols/`)

- `EditRepository` — история, сайдбар, одна правка (наблюдение), запись, повтор, папки. ✅ GRDB + in-memory.
- `EditSession` — старт, черновик стрима, Stop, Retry, удаление. ✅ `EditService`.
- `LLMProvider` — дельты текста (`AsyncThrowingStream`). ✅ `GroqProvider`, `FakeLLMProvider`.
- `PromptBuilding` — сообщения для действия. ⏳ заглушка `StubPromptBuilder` (ветка A).
- `WordDiffing` — сравнение по словам. ⏳ заглушка `StubWordDiff` (ветка B).
- `ConnectivityMonitoring`, `SettingsStoring`, `EditEventHandling`, `BackgroundTaskScheduling`,
  `LocalNotificationScheduling`, `PermissionStatusProviding`, `VoiceRecording`,
  `SpeechTranscribing`, `SpeechSynthesizing` — ✅ перенесены из чата.

## Известные риски

- Бесплатная модель могут убрать к проверке — меняется одной строкой `LLMConfig.model`.
- 8K TPM: два длинных запроса подряд могут упереться в 429 — это штатная ошибка с «Retry».
- gpt-oss иногда добавляет вступление («Here is the paraphrased text:») — чистим промптом
  (ветка A), постобработкой — только если промпт не справился.
- UI-тесты с контекстным меню на симуляторе iOS 26.5 медленные: после меню XCUITest ждёт
  «animations complete» до 60 с (поведение симулятора, тесты проходят).
- Из симулятора через VPN не резолвился DNS Groq (опыт чата) — живую модель проверять
  без VPN или на Mac Catalyst.

## Вне рамок

Аккаунты и синхронизация, свой прокси для ключа, вложенные папки, история версий одной
правки, автоопределение языка исходника в UI.
