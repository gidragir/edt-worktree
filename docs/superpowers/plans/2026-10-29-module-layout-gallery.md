# Структура src/scripts и выпуск через PowerShell Gallery — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Перенести модуль EdtWorktree в `src/EdtWorktree/` (файл = функция), служебные скрипты — в `scripts/`, добавить сборку, выпуск в PowerShell Gallery и GitHub Releases, установку одной командой из zip и не зависящий от версии shim для других оболочек.

**Architecture:** `src/EdtWorktree/` — рабочий модуль для разработки (подключение файлов по маске). `scripts/build.ps1` склеивает его в один `.psm1` в `out/`. CI прогоняет тесты над `src/` и над `out/`; тег `v*` публикует выпуск. Установка определяет свой вид (`Gallery`, `Zip`, `Dev`, `Legacy`), и от него зависят `self-update` и `uninstall`.

**Tech Stack:** PowerShell 7, Pester 5, PSScriptAnalyzer, Microsoft.PowerShell.PSResourceGet, GitHub Actions, `gh`.

**Spec:** `docs/superpowers/specs/2026-10-29-module-layout-gallery-design.md`

## Global Constraints

- PowerShell 7+, Windows 10/11; `install.ps1` парсится в Windows PowerShell 5.1 и сообщает о необходимости pwsh 7.
- `.ps1/.psm1` с не-ASCII — UTF-8 с BOM; после создания или правки проверять BOM, при потере перезаписывать `[IO.File]::WriteAllText($p, $t, [Text.UTF8Encoding]::new($true))` из файла-скрипта. Write/Edit BOM не гарантируют, поэтому массовые операции (перенос, разбиение) делать скриптом из scratchpad.
- Git в модуле — только через `Invoke-EdtWtGit`; `install.ps1` и `scripts/*` могут вызывать `git` напрямую.
- Тесты: `EDT_CONFIG_PATH`/`EDT_LEGACY_CONFIG_PATH` во временном каталоге (`Enter-EdtWtTestConfig`); PATH — `EDT_PATH_SCOPE=Process`; Modules — `EDT_MODULES_DIR`; новый shim — `EDT_SHIM_DIR`.
- Правила AGENTS.md о JVM, `Start-Process`, `.location`, конфиге не меняются.
- Перед каждым commit: `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1` (до Task 1 — из корня) → 0 провалов, 0 замечаний анализатора.
- Имя в Gallery: `EdtWorktree`. Версия выпуска: `4.0.0`. Адрес одной командой: `https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1`.
- Активы выпуска имеют **постоянные имена** `EdtWorktree.zip` и `install.ps1`: адрес `latest/download/<имя>` требует имени, не зависящего от версии. Это уточнение спецификации, где было `EdtWorktree-<версия>.zip`. Внутри zip лежит `EdtWorktree/<версия>/…`.
- Установка, обновление и удаление не трогают конфиг (кроме `-Purge`), клоны проектов, worktree, рабочие области и клон разработчика.
- Сообщения пользователю — по-русски, в стиле существующих (`==> …`, `    …`).
- Commit-сообщения в стиле репозитория (`feat(…)`, `refactor(…)`, `fix(…)`, `ci:`, `docs:`) с завершающей строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Путь к профилю с пробелом и кириллицей (`C:\Users\Иван Петров\AppData\Local`) — shim и установщик работают. Тест в Task 6 и Task 8.
2. Установлено несколько версий рядом (`Modules\EdtWorktree\4.0.0`, `4.1.0`) — shim и `edt` берут наибольшую. Тест в Task 6.
3. Аргументы с пробелами и `/` через `edt.cmd` → запускатель → `bin/edt.ps1` (`edt project add "my proj"`), код возврата сохраняется (2 — ошибка вызова, 1 — `doctor` с error). Тест в Task 6.
4. Склейка: файл без завершающего перевода строки, here-string, `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]` перед `param` — собранный модуль совпадает с `src/` по командам, и весь набор тестов проходит над `out/`. Тест в Task 5.
5. Старая установка 3.0, у которой в клоне есть незакоммиченные изменения: установщик снимает ссылку и PATH, а клон не трогает. Тест в Task 8.

---

### Task 1: Перенос в `src/EdtWorktree/` и `scripts/`

**Files:**
- Move (`git mv`): `EdtWorktree.psd1`, `EdtWorktree.psm1`, `Public/`, `Private/`, `Completers/`, `bin/` → `src/EdtWorktree/…`
- Move: `install.ps1`, `Invoke-EdtWtChecks.ps1` → `scripts/`; `COMMANDS.md` → `docs/COMMANDS.md`
- Modify: `Tests/TestHelpers.ps1`, все `Tests/*.Tests.ps1`, `scripts/Invoke-EdtWtChecks.ps1`, `scripts/install.ps1`, `src/EdtWorktree/Public/LifecycleCommands.ps1` (`Update-EdtSelf`: поиск манифеста), `.github/workflows/checks.yml`, `AGENTS.md`, `README.md`, `Tests/Docs.Tests.ps1`

**Interfaces:**
- Produces (в `Tests/TestHelpers.ps1`):
  - `Get-EdtWtTestRepoRoot` → `[string]` — корень репозитория.
  - `Get-EdtWtTestModulePath` → `[string]` — `$env:EDT_TEST_MODULE`, если задан, иначе `<repo>\src\EdtWorktree\EdtWorktree.psd1`.
  - `Get-EdtWtTestModuleRoot` → `[string]` — каталог манифеста из `Get-EdtWtTestModulePath` (для `bin\edt.ps1` и т. п.).
- Produces: `scripts/Invoke-EdtWtChecks.ps1 [-SkipAnalyzer] [-ModulePath <psd1>]`. `-ModulePath` выставляет `EDT_TEST_MODULE` на время прогона; анализатор всегда идёт по `src/`, `scripts/` и `Tests/`, а не по `out/`.

- [ ] **Step 1:** Перенести файлы через `git mv` (так сохраняется история). Сделать `src/EdtWorktree/` загружаемым: `Import-Module ./src/EdtWorktree` работает без правок `.psm1`, потому что пути в нём относительны `$PSScriptRoot`.
- [ ] **Step 2:** Добавить три помощника в `TestHelpers.ps1` и заменить в тестах каждое `Join-Path $PSScriptRoot '..\EdtWorktree.psd1'` на `Get-EdtWtTestModulePath`, а `'..\bin\edt.ps1'` — на `Join-Path (Get-EdtWtTestModuleRoot) 'bin\edt.ps1'`. Пути к `install.ps1`, `README.md`, `.gitattributes` и workflow берутся от `Get-EdtWtTestRepoRoot` (`scripts\install.ps1`, `docs\COMMANDS.md`).
- [ ] **Step 3:** В `scripts/install.ps1` поменять поиск источника на `<клон>\src\EdtWorktree\EdtWorktree.psd1`: при запуске из клона это `$PSScriptRoot\..`. Junction ставится на `<клон>\src\EdtWorktree`, в PATH попадает `<клон>\src\EdtWorktree\bin`. Сейчас поведение установщика меняется только этим; полная переделка — в Task 8.
- [ ] **Step 4:** `Update-EdtSelf`: после `git pull` импортировать `<repoDir>\src\EdtWorktree\EdtWorktree.psd1`.
- [ ] **Step 5:** `scripts/Invoke-EdtWtChecks.ps1`: корень репозитория — `Split-Path $PSScriptRoot`; `Run.Path` — `<repo>\Tests`; `Invoke-ScriptAnalyzer` идёт по `src`, `scripts` и `Tests` с `<repo>\PSScriptAnalyzerSettings.psd1`; добавить `-ModulePath`.
- [ ] **Step 6:** `checks.yml`: `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1`, установщик — `./scripts/install.ps1`. В AGENTS.md и README заменить пути (`scripts/Invoke-EdtWtChecks.ps1`, `scripts/install.ps1`, `docs/COMMANDS.md`). Ссылку `irm …/main/install.ps1` в README пока заменить на `…/main/scripts/install.ps1`; адрес выпуска появится в Task 9.
- [ ] **Step 7:** Проверить BOM у всех перенесённых файлов, затем запустить `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1`. Ожидание: число пройденных тестов то же, что до переноса, 0 провалов, 0 замечаний.
- [ ] **Step 8:** Commit `refactor: move module to src/EdtWorktree, scripts to scripts/`.

### Task 2: Один файл — одна функция, загрузчик по маске

**Files:**
- Split: `src/EdtWorktree/Private/*.ps1` → `src/EdtWorktree/Private/<Подпапка>/<Функция>.ps1`; `src/EdtWorktree/Public/*.ps1` → `src/EdtWorktree/Public/<Функция>.ps1` (только 19 экспортируемых)
- Modify: `src/EdtWorktree/EdtWorktree.psm1`
- Create: `Tests/Layout.Tests.ps1`
- Modify: `AGENTS.md` (правило «файл = функция»)

**Interfaces:**
- Produces: раскладку `Private/` по подпапкам:

| Подпапка | Функции |
|---|---|
| `Config` | всё из `Configuration.ps1`, `ConfigMigration.ps1`; `Set-EdtWtProjectProperty`, `Resolve-EdtWtExtensionRef`, `Get-EdtWtCloneBranch`, `Assert-EdtWtProjectName`, `Confirm-EdtWtProjectKnown` |
| `Git` | всё из `GitWorktree.ps1` |
| `Eclipse` | всё из `EclipseLocation.ps1` |
| `Process` | всё из `EdtProcess.ps1` |
| `Workspace` | всё из `Workspace.ps1` |
| `Discovery` | всё из `ProjectDiscovery.ps1` |
| `Interaction` | всё из `Interaction.ps1`; `Write-EdtWtNumberedList`, `Read-EdtWtExtensionChoice` |
| `Install` | `Remove-EdtWtPathEntry`, `Get-EdtWtInstallInfo`, `Remove-EdtWtModuleLink`, `Test-EdtWtDirtyWorkTree` |

- Produces: в `EdtWorktree.psm1` порядок такой: `Set-StrictMode -Version Latest`; `$script:EdtWtModuleRoot`; `$script:EdtWtPortablePrefs` (перенос из `Configuration.ps1` вместе с комментарием); подключение `Private\**\*.ps1`, `Public\*.ps1`, `Completers\*.ps1` (`Get-ChildItem -Recurse -File -Filter *.ps1 | Sort-Object FullName`); при ошибке подключения файла — `throw "Не удалось загрузить <относительный путь>: <сообщение>"`; `Set-Alias edt`; `Register-EdtWtCompleters`. Список файлов в `.psm1` больше не хранится.

- [ ] **Step 1: Написать `Tests/Layout.Tests.ps1`** (без импорта модуля; разбор через `[System.Management.Automation.Language.Parser]::ParseFile`):
  - `It 'в каждом файле Public/Private/Completers ровно одна функция верхнего уровня, имя = имя файла'` — для каждого `*.ps1` в `src/EdtWorktree/{Public,Private,Completers}` число `FunctionDefinitionAst` верхнего уровня `| Should -Be 1`, и `Name | Should -Be $file.BaseName`.
  - `It 'вне функции в этих файлах нет кода'` — все `EndBlock.Statements` верхнего уровня являются `FunctionDefinitionAst` (комментарии в AST не попадают).
  - `It 'FunctionsToExport совпадает с файлами Public/'` — `(Import-PowerShellDataFile psd1).FunctionsToExport | Sort-Object` `Should -Be` `(Get-ChildItem Public -Filter *.ps1).BaseName | Sort-Object`.
  - `It 'Set-StrictMode только в EdtWorktree.psm1'` — `Select-String -Pattern 'Set-StrictMode'` по `Public/Private/Completers` возвращает пусто.
- [ ] **Step 2:** Запустить `Invoke-Pester Tests/Layout.Tests.ps1`. Ожидание: FAIL (сейчас в файлах по несколько функций).
- [ ] **Step 3:** Разбить файлы скриптом из scratchpad: AST → `Extent.Text` каждой функции вместе с комментарием над ней (от конца предыдущей функции, без шапки файла `# ====`) → новый файл, UTF-8 с BOM, LF. Шапку-комментарий исходного файла перенести одной строкой в начало первой функции подсистемы или опустить. Старые файлы удалить через `git rm`. Обновить `.psm1`.
- [ ] **Step 4:** Запустить `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1`. Ожидание: все тесты, включая Layout, PASS; 0 замечаний.
- [ ] **Step 5:** В AGENTS.md добавить правило: «Одна функция — один файл `src/EdtWorktree/{Public|Private/<Подсистема>}/<Имя>.ps1`; в `Public/` только экспортируемые функции; переменные модуля — в `EdtWorktree.psm1`».
- [ ] **Step 6:** Commit `refactor: one function per file, glob loader`.

### Task 3: Манифест, LICENSE, CHANGELOG, окружение разработчика

**Files:**
- Modify: `src/EdtWorktree/EdtWorktree.psd1`, `.gitignore`
- Create: `LICENSE`, `CHANGELOG.md`, `.vscode/settings.json`, `.vscode/extensions.json`
- Modify: `Tests/Layout.Tests.ps1` (тест манифеста)

- [ ] **Step 1: Тест** `It 'манифест готов к публикации'`: `Test-ModuleManifest` без ошибок; `CompatiblePSEditions | Should -Be @('Core')`; `PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/gidragir/edt-worktree'`; `LicenseUri | Should -Be 'https://github.com/gidragir/edt-worktree/blob/main/LICENSE'`; `ReleaseNotes | Should -Match 'CHANGELOG.md'`; `Tags | Should -Contain 'Windows'` и `'PSEdition_Core'`; файл `LICENSE` в корне существует.
- [ ] **Step 2:** Запустить тест. Ожидание: FAIL.
- [ ] **Step 3: Лицензию выбирает пользователь.** Если выбора ещё нет, спросить и ждать ответа, не подставляя лицензию самостоятельно. Записать текст в `LICENSE` (правообладатель — `gidragir`, год 2026).
- [ ] **Step 4:** Манифест: `CompatiblePSEditions = @('Core')`, `Copyright = '(c) 2026 gidragir'`, `PSData`: `ProjectUri`, `LicenseUri`, `ReleaseNotes = 'https://github.com/gidragir/edt-worktree/blob/main/CHANGELOG.md'`, `Tags += 'Windows','PSEdition_Core'`. `ModuleVersion` пока не трогать (меняется в Task 9).
- [ ] **Step 5:** `CHANGELOG.md` в формате Keep a Changelog с разделом `## [Unreleased]`, куда записываются изменения этого плана. `.gitignore`: `out/`, `TestResults/`, `testResults.xml`, `coverage.xml`, `*.nupkg`; строку `.vscode/` заменить на `.vscode/*`, `!.vscode/settings.json`, `!.vscode/extensions.json`. `.vscode/settings.json`: `"powershell.scriptAnalysis.settingsPath": "PSScriptAnalyzerSettings.psd1"`, `"[powershell]": { "files.encoding": "utf8bom" }`, `"files.eol": "\n"`. `extensions.json`: `ms-vscode.powershell`.
- [ ] **Step 6:** Проверки → PASS. Commit `chore: manifest metadata, LICENSE, CHANGELOG, editor settings`.

### Task 4: Табличный вид через `EdtWorktree.format.ps1xml`

**Files:**
- Create: `src/EdtWorktree/EdtWorktree.format.ps1xml`
- Modify: `src/EdtWorktree/EdtWorktree.psd1` (`FormatsToProcess = @('EdtWorktree.format.ps1xml')`); публичные функции, которые возвращают строки таблиц для подкоманд `status`, `update`, `setup`, `project`, `config`, `doctor`
- Test: `Tests/Format.Tests.ps1`

**Interfaces:**
- Produces: имена типов `EdtWorktree.<Сущность>` (например, `EdtWorktree.Worktree` для `Get-EdtWorktreeList`, `EdtWorktree.DoctorCheck` для `Test-EdtEnvironment`; остальные исполнитель называет по сущности). Тип задаётся ключом `PSTypeName` в `[PSCustomObject]@{…}`. Набор и порядок свойств объектов не меняются.

- [ ] **Step 1: Тест** `Tests/Format.Tests.ps1`: для каждого имени типа из списка, который составляется в этом же файле, `Get-FormatData -TypeName <имя>` не `$null` после импорта модуля; `(Test-EdtEnvironment)[0].PSObject.TypeNames[0] | Should -Be 'EdtWorktree.DoctorCheck'` (с моками из `Doctor.Tests.ps1`); для `Get-EdtWorktreeList` на тестовом конфиге — `'EdtWorktree.Worktree'`; колонки вида `DoctorCheck` — `Check, Status, Detail, Fix`.
- [ ] **Step 2:** Запустить. Ожидание: FAIL.
- [ ] **Step 3:** Добавить `PSTypeName` в объекты и по `TableControl` на каждый тип с колонками в текущем порядке свойств. `bin/edt.ps1` по-прежнему вызывает `Format-Table -AutoSize`, и вид подхватывается автоматически.
- [ ] **Step 4:** Проверки → PASS; `Tests/Contract.Tests.ps1` (вывод `bin/edt.ps1`) без изменений. Commit `feat: format views for table output`.

### Task 5: Сборка `scripts/build.ps1`

**Files:**
- Create: `scripts/build.ps1`, `Tests/Build.Tests.ps1`
- Modify: `scripts/Invoke-EdtWtChecks.ps1` (не прогонять `Build.Tests.ps1` при `-ModulePath`, чтобы не было рекурсии), `AGENTS.md`, `CHANGELOG.md`

**Interfaces:**
- Produces: `scripts/build.ps1 [-OutputDir <path>] [-Release]` → `[PSCustomObject]@{ Version; ModuleDir; ZipPath; InstallerPath; ReleaseNotesPath }`.
  - `OutputDir` по умолчанию `<repo>\out`; каталог очищается перед сборкой.
  - `ModuleDir` = `<OutputDir>\EdtWorktree\<ModuleVersion>`: `EdtWorktree.psd1`, `EdtWorktree.format.ps1xml` и `bin\` копируются, `EdtWorktree.psm1` склеивается.
  - `ZipPath` = `<OutputDir>\EdtWorktree.zip`, корень архива — `EdtWorktree\<версия>\…`.
  - `InstallerPath` = `<OutputDir>\install.ps1` (копия `scripts/install.ps1`).
  - `-Release`: требует в `CHANGELOG.md` раздел `## [<ModuleVersion>]`, пишет его тело в `<OutputDir>\release-notes.md` (`ReleaseNotesPath`); без раздела — `throw "В CHANGELOG.md нет раздела [<версия>]"`. Без `-Release` `ReleaseNotesPath = $null`.
- Склейка: берётся `EdtWorktree.psm1` из `src`, блок подключения файлов заменяется содержимым файлов в том же порядке (`Private\**`, `Public`, `Completers`, сортировка по `FullName`). Перед каждым файлом — строка `# region <относительный путь>`, после — `# endregion`, между файлами — перевод строки. Блок подключения в `src/…psm1` обрамлён маркерами `# <build:files>` и `# </build:files>`, и сборка заменяет текст между ними. Маркеры добавляются в `src/EdtWorktree/EdtWorktree.psm1` в этой задаче.
- Проверки сборки (каждая — `throw` с понятным текстом): все `.ps1/.psm1` в `ModuleDir` начинаются с BOM; `Test-ModuleManifest`; в дочернем `pwsh -NoProfile` `Import-Module <ModuleDir>\EdtWorktree.psd1` экспортирует тот же набор функций и алиасов, что `src`.

- [ ] **Step 1: Тест** `Tests/Build.Tests.ps1` (сборка в `New-EdtWtTestRoot`):
  - `It 'собирает модуль, zip и установщик'`: `ModuleDir`, `ZipPath`, `InstallerPath` существуют; `Get-ChildItem ModuleDir -Recurse -Filter *.ps1` содержит только `bin\edt.ps1`, а `Public/` и `Private/` в выпуске отсутствуют.
  - `It 'psm1 выпуска с BOM и содержит все функции src'`: первые 3 байта `EF BB BF`; число `FunctionDefinitionAst` верхнего уровня в склейке равно числу файлов в `src/{Public,Private,Completers}`.
  - `It 'файл без завершающего перевода строки не склеивается со следующим'`: копия `src` во временном каталоге, у одного файла срезан последний `\n`; сборка с `-SourceDir` (скрытый параметр для теста; добавить в сигнатуру `[string]$SourceDir = '<repo>\src\EdtWorktree'`) даёт модуль, который импортируется.
  - `It 'zip распаковывается в EdtWorktree/<версия>'`: `Expand-Archive` → `EdtWorktree\<версия>\EdtWorktree.psd1` существует.
  - `It '-Release без раздела CHANGELOG падает'` — `Should -Throw '*нет раздела*'` (CHANGELOG подменяется параметром `-ChangelogPath`, добавить в сигнатуру).
- [ ] **Step 2:** Запустить. Ожидание: FAIL (скрипта нет).
- [ ] **Step 3:** Реализовать `scripts/build.ps1` с итоговой сигнатурой `[-OutputDir] [-SourceDir] [-ChangelogPath] [-Release]`. Добавить маркеры в `src/…psm1`.
- [ ] **Step 4:** Запустить `Tests/Build.Tests.ps1` → PASS. Затем `pwsh -NoProfile -File scripts/build.ps1` и `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1 -ModulePath out/EdtWorktree/<версия>/EdtWorktree.psd1`. Ожидание: весь набор тестов PASS над собранным модулем. Тесты, которые обращаются к файлам `src/` напрямую (`Layout.Tests.ps1`), при заданном `EDT_TEST_MODULE` пропускаются через `-Skip:($env:EDT_TEST_MODULE)`.
- [ ] **Step 5:** AGENTS.md: «Сборка: `pwsh -NoProfile -File scripts/build.ps1`; перед выпуском — проверки над `out/` с `-ModulePath`». Commit `feat(build): single-file module build, zip and installer assets`.

### Task 6: Постоянный shim для других оболочек

**Files:**
- Create: `src/EdtWorktree/Private/Install/Get-EdtWtShimDir.ps1`, `Install-EdtWtShim.ps1`, `Remove-EdtWtShim.ps1`, `Test-EdtWtShim.ps1`
- Create: `src/EdtWorktree/bin/shim/edt.cmd`, `src/EdtWorktree/bin/shim/edt.ps1` (шаблоны)
- Modify: `src/EdtWorktree/Public/Invoke-EdtSetup.ps1` (ставит shim), `src/EdtWorktree/Public/Test-EdtEnvironment.ps1` (строка проверки shim), `scripts/build.ps1` (копирует `bin\shim`)
- Test: `Tests/Shim.Tests.ps1`

**Interfaces:**
- `Get-EdtWtShimDir` → `[string]`: `$env:EDT_SHIM_DIR`, иначе `Join-Path $env:LOCALAPPDATA 'EdtWorktree\bin'`.
- `Install-EdtWtShim [-NoPath]` → `[string]` (каталог shim): копирует `bin\shim\edt.cmd` и `edt.ps1` из `$script:EdtWtModuleRoot` в `Get-EdtWtShimDir` с перезаписью; без `-NoPath` добавляет каталог в PATH пользователя (при `EDT_PATH_SCOPE=Process` — только процесса) без дублей (`Test-EdtWtSamePath`); всегда добавляет его в `$env:Path`.
- `Remove-EdtWtShim` → `[void]`: удаляет файлы shim, затем каталог, если он пуст; убирает его из PATH (с учётом `EDT_PATH_SCOPE`) через `Remove-EdtWtPathEntry`.
- `Test-EdtWtShim` → `[bool]`: `edt.cmd` есть в `Get-EdtWtShimDir`, и каталог есть в `$env:Path`.
- Шаблон `edt.cmd`: `pwsh -NoProfile -File "%~dp0edt.ps1" %*` и `exit /b %ERRORLEVEL%` (CRLF, ASCII).
- Шаблон `edt.ps1` (запускатель, UTF-8 с BOM): `param([Parameter(ValueFromRemainingArguments)][string[]]$Rest)`; находит `Get-Module -ListAvailable -Name EdtWorktree | Sort-Object Version -Descending | Select-Object -First 1`; если модуля нет — сообщение «Модуль EdtWorktree не установлен: Install-PSResource EdtWorktree» и `exit 2`; иначе `& (Join-Path $m.ModuleBase 'bin\edt.ps1') @Rest; exit $LASTEXITCODE`.
- `Test-EdtEnvironment`: строка `Check = 'shim'`; `Status = 'ok'`, если `Test-EdtWtShim`, иначе `'warning'` с `Fix = 'edt setup'`.
- `Invoke-EdtSetup`: в конце вызывает `Install-EdtWtShim` и печатает каталог.

- [ ] **Step 1: Тест** `Tests/Shim.Tests.ps1`. `EDT_SHIM_DIR` указывает на временный каталог с пробелом и кириллицей (`…\Иван Петров\bin`), `EDT_PATH_SCOPE=Process`, `PSModulePath` дочернего процесса — временный `Modules` с поддельным модулем `EdtWorktree` версий `4.0.0` и `4.1.0`, где `bin\edt.ps1` печатает свою версию и аргументы и завершается кодом из первого аргумента:
  - `It 'Install-EdtWtShim кладёт edt.cmd и edt.ps1 и добавляет каталог в PATH процесса один раз'` (вызов дважды).
  - `It 'edt.cmd вызывает наибольшую версию'` — вывод содержит `4.1.0`.
  - `It 'аргументы с пробелами доходят без искажений'` — `cmd /c "<shim>\edt.cmd" 0 "my proj" feature/x` → вывод содержит `my proj|feature/x`.
  - `It 'код возврата передаётся'` — аргумент `2` → `$LASTEXITCODE | Should -Be 2`.
  - `It 'без модуля — код 2 и подсказка Install-PSResource'`.
  - `It 'Remove-EdtWtShim убирает файлы и запись PATH'`.
  - `It 'doctor: warning без shim, ok с shim'`.
- [ ] **Step 2:** Запустить. Ожидание: FAIL.
- [ ] **Step 3:** Реализовать функции и шаблоны; в `build.ps1` убедиться, что `bin\shim` копируется (он лежит под `bin\`).
- [ ] **Step 4:** Проверки → PASS (над `src` и, после `build.ps1`, над `out`). Commit `feat(install): version-independent edt shim in LOCALAPPDATA`.

### Task 7: Вид установки, `self-update` и `uninstall`

**Files:**
- Modify: `src/EdtWorktree/Private/Install/Get-EdtWtInstallInfo.ps1`, `src/EdtWorktree/Public/Update-EdtSelf.ps1`, `src/EdtWorktree/Public/Uninstall-EdtWorktree.ps1`
- Create: `src/EdtWorktree/Private/Install/Get-EdtWtGalleryInstall.ps1`
- Modify: `Tests/Update.Tests.ps1`, `Tests/Uninstall.Tests.ps1`

**Interfaces:**
- `Get-EdtWtGalleryInstall -Version <version>` → `[bool]`: модуль этой версии установлен из Gallery. Проверяется `Get-InstalledPSResource -Name EdtWorktree -Version <v>`, при отсутствии PSResourceGet — `Get-InstalledModule`; ошибки дают `$false`. Это шов для моков.
- `Get-EdtWtInstallInfo` → `[PSCustomObject]@{ Kind; ModuleBase; ModulesDir; ModuleLink; CloneDir; ShimDir; ConfigDir }`:
  - `ModulesDir` — `$env:EDT_MODULES_DIR` или `Documents\PowerShell\Modules`; `ModuleLink` = `<ModulesDir>\EdtWorktree`.
  - `Kind = 'Dev'`, если `ModuleLink` — reparse point и его цель оканчивается на `src\EdtWorktree`, а в `<цель>\..\..` есть `.git`; `CloneDir` = `<цель>\..\..`.
  - `Kind = 'Legacy'`, если `ModuleLink` — reparse point, а в цели есть `.git` (корень клона 3.0); `CloneDir` = цель.
  - `Kind = 'Gallery'`, если `Get-EdtWtGalleryInstall -Version <версия загруженного модуля>`.
  - иначе `Kind = 'Zip'`. `CloneDir = $null` для `Gallery` и `Zip`. `ShimDir = Get-EdtWtShimDir`.
  - Свойства `InstallDir`, `ViaLink`, `BinDir` удаляются; их потребителей обновить.
- `Update-EdtSelf` по `Kind`:
  - `Gallery` — `Update-PSResource -Name EdtWorktree -Repository PSGallery` (при отсутствии — `Update-Module EdtWorktree`), затем `Import-Module EdtWorktree -Force`.
  - `Zip` — скачать `https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1` во временный файл (`$env:EDT_RELEASE_URL` переопределяет базовый адрес — шов для тестов) и выполнить `pwsh -NoProfile -File <файл> -NoSetup`, затем `Import-Module EdtWorktree -Force`.
  - `Dev` — текущее поведение (`git pull --ff-only` в `CloneDir` через `Invoke-EdtWtGit`), импорт `<CloneDir>\src\EdtWorktree\EdtWorktree.psd1`.
  - `Legacy` — `throw` «Установка 3.0 через клон. Переустановите: irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1 | iex».
  - `-WhatIf` действует для всех видов.
- `Uninstall-EdtWorktree [-Purge]` по `Kind`: `Gallery` — `Uninstall-PSResource -Name EdtWorktree -Version *` (или `Uninstall-Module -AllVersions`); `Zip` — удалить `<ModulesDir>\EdtWorktree` целиком (это не ссылка); `Dev`/`Legacy` — `Remove-EdtWtModuleLink`; для всех — `Remove-EdtWtShim`; при `Legacy` — ещё и удаление `<CloneDir>\bin` из PATH. `-Purge`: конфиг — как сейчас; `CloneDir` — только для `Dev`/`Legacy` и только если `Test-EdtWtDirtyWorkTree` = `clean`. Текст «Будет удалено» перечисляет фактические действия для своего вида.

- [ ] **Step 1: Тесты** (переписать затронутые `It` в `Update.Tests.ps1` и `Uninstall.Tests.ps1`; `Get-EdtWtGalleryInstall`, `Update-PSResource`, `Uninstall-PSResource` и скачивание — через `Mock -ModuleName EdtWorktree`):
  - `Get-EdtWtInstallInfo`: по одному `It` на каждый `Kind` (Junction на `<клон>\src\EdtWorktree` → `Dev`; Junction на корень клона с `.git` → `Legacy`; обычный каталог + мок `$true` → `Gallery`; + мок `$false` → `Zip`).
  - `Update-EdtSelf`: `Gallery` → `Should -Invoke Update-PSResource -Times 1`; `Zip` → скачивается `<EDT_RELEASE_URL>/install.ps1` и запускается с `-NoSetup`; `Dev` → `git pull` во временном клоне; `Legacy` → `Should -Throw '*releases/latest/download/install.ps1*'`.
  - `Uninstall-EdtWorktree -Confirm:$false`: `Gallery` → `Should -Invoke Uninstall-PSResource`; `Zip` → каталог удалён; `Dev` → ссылка удалена, цель цела; везде shim удалён; `Legacy -Purge` с грязным клоном → клон цел, предупреждение.
- [ ] **Step 2:** Запустить. Ожидание: FAIL.
- [ ] **Step 3:** Реализовать.
- [ ] **Step 4:** Проверки → PASS. Commit `feat(lifecycle): detect install kind for self-update and uninstall`.

### Task 8: Установщик `scripts/install.ps1` из zip выпуска

**Files:**
- Modify: `scripts/install.ps1`, `Tests/Install.Tests.ps1`

**Interfaces:**
- `Install-EdtWorktree [-ZipPath <path>] [-Branch <name>] [-Dev] [-ReleaseUrl <url>] [-ModulesDir <path>] [-NoSetup] [-NoPath]`:
  - `ReleaseUrl` по умолчанию `$env:EDT_RELEASE_URL` или `https://github.com/gidragir/edt-worktree/releases/latest/download`.
  - Источник (взаимоисключающие варианты, `throw` при сочетании):
    - по умолчанию — скачать `<ReleaseUrl>/EdtWorktree.zip`;
    - `-ZipPath` — локальный zip (CI, тесты);
    - `-Branch` — `https://github.com/gidragir/edt-worktree/archive/refs/heads/<Branch>.zip`, внутри искать `*/src/EdtWorktree/EdtWorktree.psd1`;
    - `-Dev` — Junction `<ModulesDir>\EdtWorktree` → `<$PSScriptRoot>\..\src\EdtWorktree` (только при запуске из клона, иначе `throw`).
  - Для zip и ветки: распаковать во временный каталог, `Unblock-File` по всем файлам, версия — из `EdtWorktree.psd1` (`Import-PowerShellDataFile`). Каталог `<ModulesDir>\EdtWorktree\<версия>` заменяется; другие версии остаются.
  - Перед установкой: если `<ModulesDir>\EdtWorktree` — reparse point (3.0 или Dev), снять ссылку (`[IO.Directory]::Delete`, без рекурсии). Если цель — корень клона 3.0, убрать `<цель>\bin` из PATH пользователя (с учётом `EDT_PATH_SCOPE`) и напечатать «Старая установка 3.0 снята. Клон <путь> больше не нужен модулю, его можно удалить». Клон не трогать.
  - После установки: без `-NoPath` — в дочернем `pwsh -NoProfile` импортировать установленный модуль (`<ModulesDir>\EdtWorktree\<версия>\EdtWorktree.psd1`, для `-Dev` — ссылку) и вызвать `& (Get-Module EdtWorktree) { Install-EdtWtShim }`. Это уточнение спецификации: установщик остаётся одним файлом и не требует модуль заранее, но для shim использует только что установленный модуль. Дальше — проверки окружения и `edt setup`, как сейчас.
  - Переменные окружения под `iex`: `EDT_INSTALL_BRANCH`, `EDT_INSTALL_NOSETUP`, `EDT_INSTALL_ZIP` (→ `-ZipPath`), `EDT_INSTALL_DEV` (→ `-Dev`); `EDT_INSTALL_DIR` и параметры `-InstallDir`/`-RepoUrl` удаляются вместе с git-клонированием.
  - Проверка git из установщика удаляется; проверки окружения (`Get-EdtWtInstallChecks`) показывают git как нужный для работы модуля, но не для установки.

- [ ] **Step 1: Тесты** (`Install.Tests.ps1` переписать под новые источники; zip собирается в `BeforeAll` через `scripts/build.ps1 -OutputDir <temp>`; `ModulesDir` и `EDT_SHIM_DIR` — во временном каталоге с пробелом и кириллицей; `EDT_PATH_SCOPE=Process`):
  - `It 'ставит из -ZipPath в Modules\EdtWorktree\<версия>'` — psd1 на месте, `Import-Module` из этого каталога работает.
  - `It 'повторная установка той же версии заменяет каталог, другие версии остаются'` (заранее положить `EdtWorktree\0.0.1\`).
  - `It 'снимает старую ссылку 3.0, не трогая грязный клон'` — Junction на временный клон 3.0 с `.git` и незакоммиченным файлом; после установки ссылки нет, клон и файл на месте, `<клон>\bin` убран из PATH процесса, вывод содержит «Старая установка 3.0 снята».
  - `It '-Dev ставит Junction на src\EdtWorktree'`.
  - `It 'ставит shim, если не задан -NoPath'` — `edt.cmd` в `EDT_SHIM_DIR`.
  - `It '-ZipPath вместе с -Branch — ошибка'`.
  - `It 'файл парсится в Windows PowerShell 5.1'` — сохранить существующий тест (`powershell.exe -NoProfile -Command` с парсером), путь `scripts\install.ps1`.
  - Тест скачивания по умолчанию: `EDT_RELEASE_URL` = `file:///` путь к каталогу со сборкой. Если `Invoke-WebRequest` не поддерживает `file://`, ввести в установщике функцию `Get-EdtWtInstallDownload -Url -OutFile` и мокать её.
- [ ] **Step 2:** Запустить. Ожидание: FAIL.
- [ ] **Step 3:** Реализовать.
- [ ] **Step 4:** Проверки → PASS. Commit `feat(install): install from release zip, branch archive or dev junction`.

### Task 9: CI, выпуск, документация, версия 4.0.0

**Files:**
- Modify: `.github/workflows/checks.yml`, `README.md`, `docs/COMMANDS.md`, `AGENTS.md`, `CHANGELOG.md`, `src/EdtWorktree/EdtWorktree.psd1` (`ModuleVersion = '4.0.0'`), `Tests/Docs.Tests.ps1`
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Тесты** в `Docs.Tests.ps1`:
  - README содержит `Install-PSResource EdtWorktree`, `irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1 | iex`, `edt setup` и раздел `Обновление с 3.0`; не содержит `raw.githubusercontent.com/gidragir/edt-worktree/main/install.ps1`.
  - `release.yml` содержит `Publish-PSResource`, `secrets.PSGALLERY_API_KEY`, `build.ps1 -Release` и проверку тега против `ModuleVersion`.
  - `checks.yml` запускает проверки над `src`, `build.ps1`, проверки с `-ModulePath`, установку `scripts/install.ps1 -ZipPath out/EdtWorktree.zip`.
  - `CHANGELOG.md` содержит `## [4.0.0]`.
- [ ] **Step 2:** Запустить. Ожидание: FAIL.
- [ ] **Step 3: `checks.yml`** (windows-latest, pwsh): установить Pester 5 и PSScriptAnalyzer → `scripts/Invoke-EdtWtChecks.ps1` → `scripts/build.ps1` → `scripts/Invoke-EdtWtChecks.ps1 -SkipAnalyzer -ModulePath out/EdtWorktree/<версия>/EdtWorktree.psd1` (версия — из `Import-PowerShellDataFile src/EdtWorktree/EdtWorktree.psd1`) → `$env:EDT_INSTALL_NOSETUP='1'; ./scripts/install.ps1 -ZipPath out/EdtWorktree.zip` → `edt help` в новом `pwsh` и `cmd /c edt help` (проверка shim).
- [ ] **Step 4: `release.yml`** (on `push: tags: ['v*']`, `permissions: contents: write`): те же проверки и сборка с `-Release`; шаг `if ("v$version" -ne $env:GITHUB_REF_NAME) { throw … }`; `Publish-PSResource -Path out/EdtWorktree/$version -Repository PSGallery -ApiKey ${{ secrets.PSGALLERY_API_KEY }}`; `gh release create $env:GITHUB_REF_NAME out/EdtWorktree.zip out/install.ps1 --title $env:GITHUB_REF_NAME --notes-file out/release-notes.md` (`GH_TOKEN: ${{ github.token }}`). Публикация в Gallery идёт перед созданием Release: если Gallery отказала, Release не создаётся.
- [ ] **Step 5: Документация.** README: установка (Gallery — основная, одна команда — альтернатива, ветка — для проверки), `edt setup` для cmd/nushell/агентов, «Обновление с 3.0» (повторить команду установки одной командой; `edt self-update` из 3.0 модуль ломает), раздел для разработчика (`scripts/install.ps1 -Dev`, проверки, сборка, выпуск по тегу, секрет `PSGALLERY_API_KEY`). `docs/COMMANDS.md`: описать `self-update`/`uninstall` по видам установки. AGENTS.md: раскладка `src/`/`scripts/`, shim вместо `bin` в PATH, выпуск только из CI. `CHANGELOG.md`: `[Unreleased]` → `## [4.0.0] - <дата выпуска>`.
- [ ] **Step 6:** `ModuleVersion = '4.0.0'`. Проверки над `src` и над `out` → PASS.
- [ ] **Step 7:** Commit `ci: release to PowerShell Gallery and GitHub Releases; docs for 4.0.0`. Тег `v4.0.0` и push не делать без отдельного разрешения пользователя: нужен секрет `PSGALLERY_API_KEY`, а публикация в Gallery необратима.
