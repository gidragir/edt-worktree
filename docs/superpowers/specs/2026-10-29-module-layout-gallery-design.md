# Структура репозитория и выпуск через PowerShell Gallery — дизайн

Дата: 2026-10-29. Заменяет раздел 4 («Установка») и не-цель «Публикация в
PowerShell Gallery» из `2026-10-28-portable-install-design.md`. Остальные
решения той спецификации (конфиг, команды, поведение) в силе.

## 1. Зачем

Сейчас корень репозитория и есть каталог модуля: установщик клонирует репо и
ставит Junction из `Documents\PowerShell\Modules\EdtWorktree` на весь клон.
В модуль попадают тесты, документация, CI; обновление требует git; структура
не соответствует принятой для PowerShell-модулей. Пользователь хочет ставить
модуль штатно средствами PowerShell и иметь альтернативную установку одной
командой.

## 2. Цели, не-цели, анти-цели

**Цели**
- Основная установка: `Install-PSResource EdtWorktree` (или `Install-Module`)
  из публичной PowerShell Gallery. Имя `EdtWorktree` в Gallery свободно
  (проверено 2026-10-29).
- Альтернатива одной командой без Gallery и без git:
  `irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1 | iex`.
- Модуль в выпуске — только код модуля; тесты, документация, CI в него не входят.
- Стандартная раскладка репозитория: модуль в `src/EdtWorktree/`, служебные
  скрипты в `scripts/`.
- Одна функция — один файл, имя файла = имя функции (и `Public/`, и `Private/`).
- Выпуск по тегу автоматически: проверки → сборка → Gallery → GitHub Release.

**Не-цели**
- Объединение `Private/` в иные подсистемы, переименование функций или команд,
  изменение поведения подкоманд `edt` (кроме `self-update`, `uninstall`,
  `setup` в части установки и PATH).
- Публикация в winget/scoop/choco.
- Поддержка Windows PowerShell 5.1, Linux, macOS (как и раньше).

**Анти-цели (провал, даже если «работает»)**
- После `Update-PSResource` команда `edt` перестаёт работать в cmd/nushell
  (PATH указывает на каталог старой версии).
- Собранный модуль ведёт себя иначе, чем `src/` (функция потерялась при
  склейке, сломался BOM, лишний экспорт).
- Установка, обновление или удаление трогают конфиг, клоны, worktree или
  рабочие области.
- Публикация версии, не прошедшей тесты и анализатор.

## 3. Раскладка репозитория (утверждена)

```
edt-worktree/
├─ .github/workflows/
│  ├─ checks.yml            push/PR: проверки над src/, сборка, проверки над out/
│  └─ release.yml           тег v*: проверки, сборка, Publish-PSResource, GitHub Release
├─ .vscode/settings.json    в git: настройки PSScriptAnalyzer, кодировка utf8bom
├─ src/EdtWorktree/
│  ├─ EdtWorktree.psd1
│  ├─ EdtWorktree.psm1
│  ├─ EdtWorktree.format.ps1xml
│  ├─ Public/<Функция>.ps1            19 файлов, по экспортируемой функции
│  ├─ Private/<Подсистема>/<Функция>.ps1
│  ├─ Completers/Register-EdtWtCompleters.ps1
│  └─ bin/edt.ps1, edt.cmd
├─ scripts/
│  ├─ install.ps1
│  ├─ build.ps1
│  └─ Invoke-EdtWtChecks.ps1
├─ Tests/
├─ docs/
│  ├─ COMMANDS.md
│  └─ superpowers/specs, plans
├─ README.md, AGENTS.md, CHANGELOG.md, LICENSE
├─ PSScriptAnalyzerSettings.psd1, .gitattributes, .gitignore
└─ out/                     в .gitignore
```

В корне репозитория не остаётся ни манифеста, ни `install.ps1`.

### 3.1. `Private/`

Подпапки по подсистемам, файл на функцию. Ориентировочное соответствие нынешним
файлам (точные границы — на усмотрение исполнителя):

| Подпапка | Источник |
|---|---|
| `Config/` | `Configuration.ps1`, `ConfigMigration.ps1` |
| `Git/` | `GitWorktree.ps1` |
| `Eclipse/` | `EclipseLocation.ps1` |
| `Process/` | `EdtProcess.ps1` |
| `Workspace/` | `Workspace.ps1` |
| `Discovery/` | `ProjectDiscovery.ps1` |
| `Interaction/` | `Interaction.ps1` |
| `Install/` | помощники установки из `Public/LifecycleCommands.ps1` |

Все неэкспортируемые функции, лежащие сейчас в `Public/` (`Confirm-EdtWtProjectKnown`,
`Remove-EdtWtPathEntry`, `Get-EdtWtInstallInfo`, `Remove-EdtWtModuleLink`,
`Test-EdtWtDirtyWorkTree`, `Resolve-EdtWtExtensionRef`, `Set-EdtWtProjectProperty`,
`Get-EdtWtCloneBranch`, `Assert-EdtWtProjectName`, `Write-EdtWtNumberedList`,
`Read-EdtWtExtensionChoice`), переезжают в `Private/` в подходящую подпапку.

### 3.2. `EdtWorktree.psm1` (в `src/`)

- `Set-StrictMode -Version Latest` — один раз здесь; из файлов функций убрать.
- Переменные уровня модуля (`$script:EdtWtModuleRoot`, `$script:EdtWtPortablePrefs`
  и любые другие, объявленные сейчас вне функций) — здесь, до подключения функций.
  Файлы функций содержат только определение функции.
- Подключение: `Private/**/*.ps1`, затем `Public/*.ps1`, затем `Completers/*.ps1`,
  по маске, с сортировкой по пути. Ошибка подключения файла — исключение, а не
  пропуск.
- Затем `Set-Alias edt` и `Register-EdtWtCompleters`, как сейчас.

### 3.3. Манифест

- `FunctionsToExport` — явный список (не `*`); тест сверяет его с именами
  файлов `Public/*.ps1` в обе стороны.
- Добавить: `CompatiblePSEditions = @('Core')`, `Copyright`, `FormatsToProcess`,
  в `PSData`: `ProjectUri`, `LicenseUri`, `ReleaseNotes` (ссылка на CHANGELOG), теги
  `Windows`, `PSEdition_Core`.
- `ModuleVersion` в `src/EdtWorktree/EdtWorktree.psd1` — единственный источник
  версии. `release.yml` отказывает, если тег `vX.Y.Z` не равен `ModuleVersion`.

### 3.4. Форматирование

`EdtWorktree.format.ps1xml` с табличными видами для объектов, которые сейчас
выводятся таблицей в `bin/edt.ps1` (`status`, `update`, `setup`, `project`,
`config`, `doctor`). Объекты получают `PSTypeName` (`EdtWorktree.Worktree`,
`EdtWorktree.DoctorCheck` и т. п. — имена на усмотрение исполнителя). Набор и
порядок колонок — как в текущем выводе `edt`. Свойства объектов не меняются
(на них опираются тесты и `doctor` → код возврата).

## 4. Сборка (`scripts/build.ps1`)

- Вход: `src/EdtWorktree/`. Выход: `out/EdtWorktree/<ModuleVersion>/` и
  `out/EdtWorktree.zip` (имя постоянное, чтобы работал адрес
  `releases/latest/download/EdtWorktree.zip`; внутри — каталог
  `EdtWorktree/<версия>/`, готовый к распаковке в `Modules`).
- `EdtWorktree.psm1` в выпуске — один файл: шапка из `src/…psm1` (StrictMode,
  переменные) + содержимое всех файлов `Private`, `Public`, `Completers` в том
  же порядке, что при подключении, + алиас и регистрация автодополнения.
- Остальные файлы (`psd1`, `format.ps1xml`, `bin/`) копируются как есть.
- Все `.ps1/.psm1` выпуска — UTF-8 с BOM; сборка проверяет это и падает при
  нарушении.
- Проверки сборки: `Test-ModuleManifest`; импорт собранного модуля в чистом
  процессе; набор экспортированных команд совпадает с `src/`.
- `install.ps1` копируется в `out/` как отдельный актив выпуска.

## 5. Проверки и тесты

- `scripts/Invoke-EdtWtChecks.ps1` — тесты Pester и анализатор над `src/`.
  Ключ (например, `-ModulePath`) запускает тесты над собранным модулем.
- Все тесты получают путь к манифесту из одного помощника в `TestHelpers.ps1`
  (по умолчанию `src/EdtWorktree/EdtWorktree.psd1`, переопределяется
  переменной окружения, например `EDT_TEST_MODULE`). Прямых
  `Join-Path $PSScriptRoot '..\EdtWorktree.psd1'` в тестах не остаётся.
- Новые тесты: соответствие `FunctionsToExport` ↔ `Public/*.ps1`; «один файл —
  одна функция, имя совпадает» для `Public` и `Private`; сборка (склейка,
  BOM, экспорт); раскладка установки из zip; постоянный shim (раздел 6.3).
- `Tests/Docs.Tests.ps1` читает `docs/COMMANDS.md`; адрес установки в README —
  адрес из раздела 2.
- `checks.yml`: проверки над `src/` → сборка → проверки над `out/` → установка
  из собранного zip через `scripts/install.ps1` с локальным источником в чистом
  профиле → `edt help`.
- Правила AGENTS.md (BOM, `Invoke-EdtWtGit`, `EDT_CONFIG_PATH` в тестах и пр.)
  в силе; AGENTS.md обновляется под новые пути.

## 6. Установка, обновление, удаление

### 6.1. Способы установки

| Способ | Команда | Куда ставится |
|---|---|---|
| Gallery | `Install-PSResource EdtWorktree` (или `Install-Module`) | `Modules\EdtWorktree\<версия>\` |
| Одна команда | `irm …/releases/latest/download/install.ps1 \| iex` | то же, из zip последнего выпуска |
| Ветка | `install.ps1` с `-Branch <ветка>` (через `& ([scriptblock]::Create(...))`) | архив ветки с GitHub, без git; сборка не нужна, ставится `src/EdtWorktree` |
| Разработка | `pwsh -File scripts/install.ps1 -Dev` из клона | Junction `Modules\EdtWorktree` → `<клон>\src\EdtWorktree` |

`install.ps1` остаётся самодостаточным (не импортирует модуль, парсится в 5.1
и сообщает о необходимости pwsh 7), принимает параметры через переменные
окружения под `iex`, как сейчас. После установки он выполняет то же, что сейчас
шаги 5–7: PATH (раздел 6.3), проверки окружения, `edt setup` при отсутствии
конфига в интерактивном режиме. Для источника zip допускается `Unblock-File`.

### 6.2. После установки из Gallery

Gallery не выполняет действий после установки. В pwsh `edt` работает сразу
(автозагрузка модуля по экспортированному алиасу). Для cmd/nushell/агентов
пользователь один раз выполняет `edt setup`; README говорит об этом рядом с
командой установки. `edt doctor` показывает предупреждение, если shim не
установлен.

### 6.3. Постоянный shim для других оболочек

- Каталог `%LOCALAPPDATA%\EdtWorktree\bin` (переопределяемый для тестов) с
  `edt.cmd` и маленьким `edt.ps1`-запускателем. Они не привязаны к версии:
  запускатель находит установленный модуль `EdtWorktree` с наибольшей версией
  и передаёт аргументы в его `bin/edt.ps1` (коды возврата сохраняются).
- В PATH пользователя пишется только этот каталог. Его ставят `install.ps1` и
  `edt setup`; удаляет `edt uninstall`.
- Обновление модуля shim не трогает и не ломает.

### 6.4. Обновление (`edt self-update` / `Update-EdtSelf`)

Определяет способ установки и делает соответствующее:
- Gallery (модуль виден в `Get-InstalledPSResource`/`Get-InstalledModule`) —
  `Update-PSResource EdtWorktree` (если PSResourceGet нет — `Update-Module`);
- zip — скачивает и ставит последний выпуск тем же кодом, что `install.ps1`;
- Junction разработчика — `git pull --ff-only` в клоне (через `Invoke-EdtWtGit`);
- старая установка 3.0 (Junction на корень клона) — см. 6.6.

После обновления — перезагрузка модуля в сессии, как сейчас.

### 6.5. Удаление (`edt uninstall` / `Uninstall-EdtWorktree`)

- Gallery — `Uninstall-PSResource EdtWorktree` (все версии);
- zip — удаление `Modules\EdtWorktree\<версии>`;
- Junction — удаление только ссылки (как сейчас, без захода в цель);
- в любом случае — удаление shim и его записи в PATH; `-Purge` — как сейчас
  (конфиг; клон разработчика — только если чистый).

### 6.6. Переход со старой установки 3.0 (клон + Junction на корень)

`install.ps1` и `self-update` распознают Junction, цель которого — корень клона
(в цели есть `.git`, нет `src/`, либо есть `src/EdtWorktree` после `git pull`).
Действие: убрать ссылку, убрать из PATH `<клон>\bin`, поставить модуль новым
способом (zip последнего выпуска), поставить shim. Новый `self-update`,
встретив такую установку, не чинит её сам, а печатает команду установки.
Сам клон не удаляется; пользователю печатается, что его можно удалить.

Ограничение: `edt self-update` версии 3.0 — это старый код. Он делает
`git pull` в клоне, после чего в корне нет ни манифеста, ни `bin/`, и модуль
вместе с командой `edt` перестаёт загружаться. Новый код в этот момент ещё не
выполняется, поэтому починить это из нового выпуска нельзя. Переход для
пользователей 3.0 — повторный запуск команды установки одной командой. Это
указывается в CHANGELOG и в README (раздел «Обновление с 3.0»).

### 6.7. Версия

Выпуск с новой структурой — `4.0.0`: команды не меняются, но меняется способ
установки и обновления, а `self-update` из 3.0 к нему не ведёт.

## 7. Выпуск (`release.yml`)

Триггер — тег `v*`. Шаги: проверка тег = `ModuleVersion` и наличие раздела
версии в `CHANGELOG.md` → `Invoke-EdtWtChecks.ps1` над `src/` → `build.ps1` →
проверки над `out/` → `Publish-PSResource -Path out/EdtWorktree/<версия>
-ApiKey ${{ secrets.PSGALLERY_API_KEY }}` → GitHub Release с zip и `install.ps1`,
текст — раздел версии из CHANGELOG.

Ручная публикация с локальной машины не предусматривается. Секрет
`PSGALLERY_API_KEY` заводит владелец репозитория.

## 8. Документация

- README: установка из Gallery (основная), одна командой (альтернатива), `edt
  setup` для других оболочек, раздел для разработчика (клон, `scripts/install.ps1
  -Dev`, проверки, сборка, выпуск по тегу).
- `docs/COMMANDS.md` — перенос без изменения содержания (ссылки поправить).
- `CHANGELOG.md` — формат Keep a Changelog, начиная с выпуска этой структуры.
- AGENTS.md — новые пути (`scripts/Invoke-EdtWtChecks.ps1`, `src/EdtWorktree/…`),
  правило «файл = функция», правило про shim вместо `bin` в PATH.

## 9. Оставлено исполнителю

- Точные границы подпапок `Private/` и имена `PSTypeName`.
- Механика запускателя shim (поиск версии, передача аргументов).
- Порядок задач и сопоставление тестов.
- Мелкие правки `.gitignore` (`out/`, результаты Pester).

## 10. Решения, принятые без отдельного согласования

- Склейка в один `.psm1` только в выпуске; в `src/` файлы раздельные.
- `Invoke-EdtWtChecks.ps1` переносится в `scripts/` вместе с `install.ps1` и `build.ps1`.
- Адрес одной командой — актив последнего выпуска, а не `raw…/main/…`; старый
  адрес `raw…/main/install.ps1` не сохраняется.
- Публикация только из CI по тегу.
- Версия выпуска — 4.0.0 (раздел 6.7).
