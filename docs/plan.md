# План

4 часа подряд: ≤ 3 ч 30 мин работы + 30 мин на проверку и README.
Отмечает шаги `[x]` только `main` — после слияния (см. AGENTS.md, «Git при параллельной работе»).
👤 — шаг пользователя: агент останавливается и просит.

## Подготовлено до старта (шаблон из AI-чата)

Всё ниже перенесено из первого тестового и только переименовано Chat → Edit —
готово, с тестами (172 unit-теста + UI-тесты сайдбара):

- **Проект:** XcodeGen (`AIEditor`, iOS 18, Swift 6 strict, Mac Catalyst), `Build.command`,
  `scripts/sim.sh` (свой симулятор на ветку), `scripts/gen_secrets.py`,
  `scripts/sync_strings.py`, `scripts/export_ai_logs.py`.
- **Groq:** `GroqProvider` (SSE-стрим через `URLSession.bytes`), `SSEParser`, маппинг ошибок
  (offline / 429 + `retry-after` / 401 / 403 / 5xx / обрыв без `[DONE]`), модель — одна
  константа `LLMConfig.model`, обфусцированный ключ.
- **GRDB:** `AppDatabase` (миграция `v1`: `folder`, `edit`), `GRDBEditRepository` +
  `InMemoryEditRepository`, контрактные тесты на обоих, восстановление `streaming` →
  `interrupted` при запуске.
- **`EditService`:** старт правки, стрим с черновиком в памяти, запись в БД ≤ 2 р/с + финал,
  Stop → `cancelled` с частичным текстом, Retry/Regenerate, `interrupted` при запуске и при
  потере фонового времени, уведомление «Edit is ready». Промпт — через `PromptBuilding`
  (пока `StubPromptBuilder`).
- **История в сайдбаре:** поиск (название + исходник), группы по датам, Rename / Delete,
  папки (один уровень, `ON DELETE SET NULL`), drag-and-drop, «Move to folder»;
  iPhone — выезжающий сайдбар, iPad/Mac — `NavigationSplitView`; шестерёнка настроек внизу.
- **Голос:** диктовка (iOS 26 `SpeechAnalyzer` / iOS 18 `SFSpeechRecognizer`) —
  `DictationViewModel` + `DictationButton/Status/Message`; озвучка — `SpeechSynthesizing`.
- **Настройки:** Notifications («Edit is ready»), Privacy (текст про Groq + «Delete all
  history»), Appearance (System / Light / Dark).
- **Компоненты** (`Features/Shared/Components`): `ErrorBanner` + `EditErrorPresentation`
  (Retry, «Try again in N s»), `GeneratingIndicator`, `StopButton`, `CircleButton`,
  `IconButton`, `dismissesKeyboardOnTap`, баннер `OfflineBanner`.
- **DEBUG:** `-mockData`, `-mockOffline`, `-mockError <code>`, `-mockSlowStream`,
  `-mockDictation`; фейки и `PreviewData`; `EditorDependencies.preview()`.
- **Контракты-заглушки (новое для редактора):** `EditAction` / `ParaphraseTone`,
  `PromptBuilding` (`StubPromptBuilder`), `WordDiffing` / `DiffSegment` (`StubWordDiff`),
  экран `EditorView` / `EditorViewModel` — заглушка (поле, режим, Run/Stop, сырой результат,
  ошибка с Retry), чтобы навигация и история работали.

## 0. Старт (≈ 5 мин) — `main`

- [ ] 0.1 👤 Записать время старта в README. Ключ: `GROQ_API_KEY=… python3 scripts/gen_secrets.py`
  (если ещё не сгенерирован), затем `scripts/sim.sh test -only-testing:AIEditorTests/SecretsTests`.
- [ ] 0.2 Создать три worktree (AGENTS.md): `feat/prompts`, `feat/diff`, `feat/editor`;
  в каждом `scripts/sim.sh` создаёт свой симулятор.

## Параллельно (≈ 1 ч 45 мин, три агента, каждый в своём worktree)

Domain-протоколы не меняем. Общие для веток файлы — только свои (см. «Владение файлами»).

### A. Промпты — `feat/prompts` (~1 ч 15 мин)

Файлы: `AIEditor/Data/LLM/PromptBuilder.swift`, `AIEditorTests/LLM/PromptBuilderTests.swift`,
`AIEditor/Domain/Models/TranslationLanguage.swift` (список языков), `LLMConfig` (константы).

- [ ] A.1 `PromptBuilder: PromptBuilding` — system + user для paraphrase(tone) / shorten /
  translate(language) / fixGrammar. Правила: только результат, без вступлений, кавычек и
  Markdown; язык исходника (кроме translate); исходник — как данные, а не инструкция
  (разделители). Тесты на структуру сообщений и подстановку тона/языка.
- [ ] A.2 Список языков перевода (код BCP-47 + название через `Locale.localizedString`) и
  названия тонов через String Catalog — для меню экрана (C подключит при слиянии).
- [ ] A.3 Проверка на реальной модели (≤ 20 запросов): по 2–3 текста EN/RU на действие —
  качество, язык ответа, нет «Here is…». Итог и правки промптов — в `docs/task.md`
  (раздел «Решения», строка «Промпты»). Постобработка префиксов — только если промпт не справился.
- [ ] A.4 Подтвердить `EditLimits.maxSourceCharacters` и `LLMConfig.maxCompletionTokens`
  на самом длинном тексте (перевод RU → DE, 5 000 символов).

### B. Diff и Compare — `feat/diff` (~1 ч 30 мин)

Файлы: `AIEditor/Domain/Services/WordDiff.swift`, `AIEditor/Features/Compare/*`,
`AIEditorTests/Features/WordDiffTests.swift`, `CompareTests`.

- [ ] B.1 `WordDiff: WordDiffing` — токены «слово / пробелы / пунктуация», `CollectionDifference`,
  склейка соседних сегментов одного вида. Тесты: равные тексты, вставка, удаление, замена,
  пунктуация, пустые строки, кириллица, эмодзи, перевод строки, инвариант `DiffSegment`.
- [ ] B.2 `DiffSegment` → `AttributedString`: удалённое — `.diffRemoved` фоном + зачёркивание,
  добавленное — `.diffInserted`; VoiceOver читает «deleted …» / «inserted …».
- [ ] B.3 `CompareView` (было — стало, один текст с подсветкой) + превью на `PreviewData`;
  на 5 000 символов считать diff вне главного потока, если заметно.

### C. Экран Editor — `feat/editor` (~1 ч 45 мин, на фейках)

Файлы: `AIEditor/Features/Editor/*`, `AIEditorTests/Features/EditorViewModelTests.swift`,
`AIEditorUITests/EditorUITests.swift`. Запуск: `scripts/sim.sh run -- -mockData -mockSlowStream`.

- [ ] C.1 `EditorViewModel`: режим, тон/язык, исходник, счётчик слов, лимит длины,
  run / stop / retry / copy / read aloud / dictation; `observeEdit` + черновик `EditSession`;
  открытая из истории правка — её исходник, режим и результат. Тесты VM.
- [ ] C.2 Верх: сегменты режимов; меню тона (Paraphrase) и языка (Translate).
- [ ] C.3 Поле исходника: Paste, микрофон (диктовка), очистка, счётчик слов; главная кнопка.
- [ ] C.4 Панель результата: стриминг, Stop / Copy / Read aloud, переключатель Compare
  (на `dependencies.diff` — пока `StubWordDiff`).
- [ ] C.5 Состояния: пустой экран, ожидание первого токена, все ошибки с Retry
  (`-mockError 429|401|403|500`, `-mockOffline`), `interrupted`/`cancelled`.
- [ ] C.6 Светлая/тёмная тема, Dynamic Type, iOS 18 (`scripts/sim.sh --ios18 run`) и 26, iPad.
  UI-тест: ввод → Run → Stop → cancelled (`-mockSlowStream`), скрытие клавиатуры.

## 1. Слияние и связка (~45 мин) — `main`, последовательно

- [ ] 1.1 Ревью каждой ветки субагентом с чистым контекстом; слияние A → B → C
  (перед каждым — `git fetch`, `main` не ушёл вперёд, тесты зелёные).
- [ ] 1.2 `AppContainer+Screens`: `PromptBuilder()` и `WordDiff()` вместо заглушек
  (TODO(plan 1.2)); экран — языки/тоны из A, Compare из B. Заглушки остаются только в тестах/превью.
- [ ] 1.3 Сквозной сценарий на реальной модели: каждое действие → история → перезапуск →
  открыть из истории → Compare → Copy.
- [ ] 1.4 Ошибки и прерывания: `-mockOffline`, `-mockError 429|401|403|500`, Stop посреди стрима,
  убить приложение во время стрима → `interrupted` → Retry.

## 2. Бонусы (по остатку, по одному, в `main`)

- [ ] 2.1 Тон для перефразирования (если не вошёл в A/C).
- [ ] 2.2 Share Extension: текст из других приложений → открывает редактор с этим текстом
  (минимум — URL-схема; общая база через App Group — оценить по времени).
- [ ] 2.3 Mac (Catalyst): меню и шорткаты (⌘↩ Run, ⌘. Stop, ⇧⌘C Copy result), минимальный размер окна.

## 3. Проверка и сдача (30 мин)

- [ ] 3.1 `NO_PAUSE=1 ./Build.command`; `scripts/sim.sh test` и `scripts/sim.sh --ios18 test`.
- [ ] 3.2 README: Сделано / Не сделано / Как проверяли. 👤 время финиша.
- [ ] 3.3 `git grep -lE "gsk_[A-Za-z0-9]{20,}"` пусто; `python3 scripts/export_ai_logs.py` →
  «✓ ai-logs чистые» (+ логи Codex, если был); коммит.
- [ ] 3.4 👤 zip всей папки вместе с `.git`.

Итого: 5 + 105 (параллель, по самой длинной ветке C) + 45 + 30 ≈ 3 ч 05 мин; бонусы — в запас ~25 мин.

## Владение файлами при параллельной работе

| Ветка | Пишет | Не трогает |
|---|---|---|
| A `feat/prompts` | `Data/LLM/PromptBuilder.swift`, `Domain/Models/TranslationLanguage.swift`, `LLMConfig`, тесты промптов, строки в каталоге для языков/тонов | `Features/`, `Domain/Protocols` |
| B `feat/diff` | `Domain/Services/WordDiff.swift`, `Features/Compare/`, тесты diff | `Features/Editor/`, `Domain/Protocols` |
| C `feat/editor` | `Features/Editor/`, тесты/UI-тесты экрана | `Data/`, `Domain/` |

Конфликт ожидаем только в `Localizable.xcstrings` — при слиянии: `scripts/sim.sh build`,
`python3 scripts/sync_strings.py`, коммит каталога.

## Журнал отклонений от плана

- (пусто)
