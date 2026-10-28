# EdtWorktree 3.0: переносимая установка и настройка из CLI — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Модуль ставится одной командой на любой ПК с Windows, настраивается
командами `edt setup` / `edt project ...` без правки JSON и не содержит багов,
найденных аудитом переносимости.

**Architecture:** Единый пользовательский конфиг v3 (`%APPDATA%\EdtWorktree\config.json`)
с реестром проектов и автоматической миграцией с 2.x; проекты — клоны в
`repos_root`, эталон собирается прямо из клона с валидацией. Публичные команды —
тонкие обёртки над приватными чистыми функциями, которые покрываются Pester.
Установщик `install.ps1` в корне репозитория самодостаточен (работает под `irm | iex`).

**Tech Stack:** PowerShell 7+, Pester 5, PSScriptAnalyzer, git, 1C:EDT (`1cedtcli`, `1cedt.exe`).

**Spec:** `docs/superpowers/specs/2026-10-28-portable-install-design.md`

## Global Constraints

- PowerShell 7+, Windows 10/11, без прав администратора; `#Requires -Version 7.0` в модуле-манифесте уже есть (`PowerShellVersion = '7.0'`).
- Все `.ps1`/`.psm1` с кириллицей — UTF-8 с BOM; после правки проверять BOM (AGENTS.md §3).
- Git вызывается только через `Invoke-EdtWtGit` (кроме `install.ps1`, где модуль ещё не загружен).
- Пути с пробелами в `Start-Process -ArgumentList` оборачиваются в кавычки (AGENTS.md §2).
- `config.json` пишется UTF-8 **без** BOM; сохранение пишет схему целиком, неизвестные ключи сохраняются.
- Тесты никогда не трогают реальный конфиг, PATH пользователя и `Documents\PowerShell\Modules`: `EDT_CONFIG_PATH` и все корни — во временном каталоге.
- Версия модуля `3.0.0`. Имена в конфиге — как в spec §5.1 (`repos_root`, `worktrees_root`, `workspaces_root`, `edt.cli_path`, `edt.vm_path`, `edt.prefs_source`, `edt.max_heap`, `edt.gui_max_heap`, `edt.extra_vmargs`, `edt.timeout_sec`, `git.remote`, `git.branch_prefix`, `projects.<имя>.ref_branch|cf_project|extensions`).
- Каталог эталона `_reference`; дефолты `git.remote = "origin"`, `git.branch_prefix = "feature/"`, `edt.timeout_sec = 7200`.
- Перед завершением каждой задачи: `pwsh -NoProfile -File Invoke-EdtWtChecks.ps1` — 0 провалов, 0 замечаний анализатора.
- Ключи CLI принимаются в стиле `-NoGui` и `--no-gui`; у изменяющих команд есть `-WhatIf` и `-Yes`.

## Review Focus

1. **Пути с пробелами и кириллицей** в `repos_root`/`worktrees_root` (`D:\projects\Интеграция с Каспи`): определение проекта, создание worktree и `.location` должны работать. Тест — Task 5 (`Resolve-EdtWtProjectFromPath` на таком пути) и Task 9.
2. **Неинтерактивный запуск** (`edt.cmd` из агента, планировщика): ни одна команда не должна зависнуть на `Read-Host`; вместо диалога — ошибка с нужным ключом. Тест — Task 4 (`Add-EdtProject` без `-Extensions`) и Task 10 (`Invoke-EdtSetup`).
3. **Конфиг, поправленный руками** (лишние ключи, битый JSON): лишние ключи переживают сохранение, битый JSON даёт понятную ошибку и файл не перезаписывается. Тест — Task 1.
4. **Регистр и хвостовые слеши в путях** (`d:\ws\p\x\` против `D:\ws\p\x`): сравнение путей проектов и процессов регистронезависимое и без учёта хвостового `\`. Тест — Task 5 и Task 8.
5. **Повторный запуск установщика** поверх существующей установки (junction или копия): обновляет, а не ломает и не дублирует PATH. Тест — Task 14.

## Перед началом

- В `main` есть незакоммиченные правки автора. Исполнитель не трогает их: работа идёт в отдельной ветке/worktree `feat/v3-portable`, созданной после того, как автор закоммитит или спрячет свои изменения (решает автор).
- Запуск одного тестового файла: `pwsh -NoProfile -Command "Invoke-Pester -Path Tests/<Файл>.Tests.ps1 -Output Detailed"`.

## Карта файлов

| Файл | Ответственность |
|---|---|
| `Private/Configuration.ps1` | v3: дефолты, путь, чтение, сохранение, доступ к проекту (переписать) |
| `Private/ConfigMigration.ps1` | новый: v2 → v3 |
| `Private/ProjectDiscovery.ps1` | новый: поиск EDT-проектов в клоне, разбор выбора номеров, определение проекта по пути |
| `Private/Interaction.ps1` | новый: `Test-EdtWtInteractive`, `Read-EdtWtAnswer` (точки для моков) |
| `Private/EdtProcess.ps1` | поиск EDT, выбор JVM, запуск GUI/CLI, процессы |
| `Private/EclipseLocation.ps1` | экранирование URI, сравнение путей |
| `Private/GitWorktree.ps1` | модель веток, создание worktree |
| `Private/Workspace.ps1` | эталон, настройки IDE, справка |
| `Public/ConfigCommands.ps1` | `Invoke-EdtSetup`, `Get-EdtConfig`, `Set-EdtConfig` |
| `Public/ProjectCommands.ps1` | новый: `Get-EdtProject`, `Add-EdtProject`, `Set-EdtProjectExtension`, `Set-EdtProject`, `Remove-EdtProject` |
| `Public/DoctorCommand.ps1` | новый: `Test-EdtEnvironment` |
| `Public/WorktreeCommands.ps1` | open/warmup/add/remove/status, контекст |
| `Public/LifecycleCommands.ps1` | update, self-update, `Uninstall-EdtWorktree` |
| `Public/Invoke-EdtCommand.ps1` | диспетчер подкоманд |
| `EdtWorktree.psm1`, `EdtWorktree.psd1`, `Completers/…`, `bin/edt.ps1` | загрузка, экспорт, автодополнение, CLI-вход |
| `install.ps1` | новый, корень: установщик |
| `Tests/TestHelpers.ps1` | новый: фикстуры конфига и git-репозиториев |
| `README.md`, `COMMANDS.md`, `AGENTS.md`, `.gitattributes`, `Invoke-EdtWtChecks.ps1`, `.github/workflows/checks.yml` | документация и обвязка |

Удаляются: `scripts/install.ps1`, `scripts/uninstall.ps1`, `New-EdtProjectConfig`, `Initialize-EdtConfig`, `Invoke-EdtWtLegacyCommand` и все `wt-*`/`edt-wt-*`, чтение `.edt-worktree.json` и `~/.config/1c/projects.json` (кроме миграции).

---

### Task 1: Конфиг v3 — дефолты, чтение, сохранение

**Files:**
- Modify: `Private/Configuration.ps1` (переписать целиком)
- Create: `Private/Interaction.ps1`, `Tests/TestHelpers.ps1`
- Test: `Tests/Config.Tests.ps1` (переписать)

**Interfaces:**
- Produces:
  - `Get-EdtWtUserConfigPath -> string` — `$env:EDT_CONFIG_PATH`, иначе `%APPDATA%\EdtWorktree\config.json`.
  - `New-EdtWtDefaultConfig -> PSCustomObject` — схема spec §5.1, `version = 3`, `projects = {}`; дефолтные корни: существующий `D:\projects\default` / `D:\projects\worktree` / `D:\workspaces\worktree`, иначе `%USERPROFILE%\projects`, `%USERPROFILE%\projects\worktree`, `%USERPROFILE%\edt-workspaces`.
  - `Get-EdtWtConfig -> PSCustomObject` — файл есть: JSON поверх дефолтов (глубокое слияние, неизвестные ключи сохраняются); файла нет: вызывает `Invoke-EdtWtConfigMigration` (Task 2; до Task 2 — заглушка, возвращающая `$null`), при `$null` — `New-EdtWtDefaultConfig` без записи на диск. Битый JSON — `throw "Конфиг повреждён: <путь>: <сообщение>. Исправьте файл или удалите его и выполните edt setup."`.
  - `Save-EdtWtConfig -Config <PSCustomObject> -> string` (путь) — UTF-8 без BOM, запись во временный файл и `Move-Item -Force`, `ConvertTo-Json -Depth 10`.
  - `Get-EdtWtProjectDef -Config <obj> -Name <string> -> PSCustomObject` — `throw "Проект '<имя>' не зарегистрирован. Зарегистрируйте: edt project add <имя>"`.
  - `Get-EdtWtProperty` — без изменений.
  - `Test-EdtWtInteractive -> bool` (`[Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and $Host.Name -eq 'ConsoleHost'`), `Read-EdtWtAnswer -Prompt <string> [-Default <string>] -> string` (пустой ответ → `Default`).
  - `Tests/TestHelpers.ps1`: `New-EdtWtTestRoot -> string` (временный каталог), `Use-EdtWtTestConfig -Root <string> -> string` (ставит `EDT_CONFIG_PATH` в `<Root>\config.json`, возвращает путь).

- [ ] **Step 1: Write the failing tests** (`Tests/Config.Tests.ps1`, через `& (Get-Module EdtWorktree) { ... }`)

```powershell
It 'без файла возвращает дефолты v3 и ничего не пишет' {
    $cfg = & $m { Get-EdtWtConfig }
    $cfg.version | Should -Be 3
    $cfg.git.remote | Should -Be 'origin'
    $cfg.git.branch_prefix | Should -Be 'feature/'
    $cfg.edt.timeout_sec | Should -Be 7200
    Test-Path $script:CfgPath | Should -BeFalse
}
It 'round-trip сохраняет проекты и неизвестные ключи' {
    '{"version":3,"custom":{"x":1},"projects":{"p":{"ref_branch":"main","cf_project":"src/cf","extensions":["src/cfe"]}}}' |
        Set-Content $script:CfgPath -Encoding utf8NoBOM
    & $m { Save-EdtWtConfig -Config (Get-EdtWtConfig) } | Out-Null
    $j = Get-Content $script:CfgPath -Raw | ConvertFrom-Json
    $j.custom.x | Should -Be 1
    $j.projects.p.extensions | Should -Be @('src/cfe')
    $j.git.remote | Should -Be 'origin'
}
It 'пишет UTF-8 без BOM' { ([IO.File]::ReadAllBytes($script:CfgPath))[0] | Should -Not -Be 0xEF }
It 'битый JSON: понятная ошибка, файл не перезаписан' {
    '{ broken' | Set-Content $script:CfgPath
    { & $m { Get-EdtWtConfig } } | Should -Throw '*Конфиг повреждён*'
    Get-Content $script:CfgPath -Raw | Should -Match '\{ broken'
}
It 'Get-EdtWtProjectDef для незарегистрированного проекта подсказывает edt project add' {
    { & $m { Get-EdtWtProjectDef -Config (New-EdtWtDefaultConfig) -Name 'zzz' } } | Should -Throw '*edt project add zzz*'
}
```

- [ ] **Step 2: Run, verify FAIL** — `Invoke-Pester -Path Tests/Config.Tests.ps1`: функции `New-EdtWtDefaultConfig`/`Get-EdtWtProjectDef` не найдены.
- [ ] **Step 3: Implement** функции из Interfaces. Добавить `Private\Interaction.ps1` в `$loadOrder` `EdtWorktree.psm1` перед `Configuration.ps1`. Остальной код модуля, читавший старые поля (`paths.projects_root`, `worktree.*`, `defaults.*`), временно переводится на новые имена минимальной правкой: `$script:EdtWtProjectsRoot`/`EdtWtWorktreeRoot`/`EdtWtDefaultRoot` убрать, читать `(Get-EdtWtConfig).paths.*`. `Get-EdtWtSettings` удалить; вызывающие получают конфиг из `Get-EdtWtConfig`.
- [ ] **Step 4: Run, verify PASS**; затем полный `Invoke-EdtWtChecks.ps1` — тесты, завязанные на удаляемое поведение (`New-EdtProjectConfig`, `Initialize-EdtConfig`, старые поля), удалить или переписать в этой же задаче.
- [ ] **Step 5: Commit** — `git commit -m "feat(config): v3 schema with lossless save"`

### Task 2: Миграция конфига v2 → v3

**Files:**
- Create: `Private/ConfigMigration.ps1`
- Test: `Tests/Migration.Tests.ps1`

**Interfaces:**
- Consumes: `New-EdtWtDefaultConfig`, `Save-EdtWtConfig` (Task 1).
- Produces:
  - `ConvertFrom-EdtWtV2Config -Primary <PSCustomObject|$null> -Legacy <PSCustomObject|$null> -ReposRootForCheck <string> -> [pscustomobject]@{ Config; Notes [string[]] }` — чистая функция по таблице соответствия spec §5.2; при конфликте побеждает `Primary`; `cli_path` переносится только если файл существует; `active_extensions` → `src/<имя>` только для существующих `<repos_root>\<проект>\src\<имя>\.project`; `ref_branch` = `projects.<p>.reference_branch` → общий `reference_branch` → текущая ветка клона; `jvm.extra_args` → `edt.extra_vmargs`; `jvm.max_heap`/`gui_max_heap` → `edt.*`; `min_heap`, `ignored_patterns`, `ibconnection`, `v8version`, `bases_dir`, `1cedtcli` проекта не переносятся (Note о каждом пропущенном ключе проекта не нужна — одна общая строка).
  - `Invoke-EdtWtConfigMigration -> PSCustomObject|$null` — ищет `%APPDATA%\EdtWorktree\config.json` без `version: 3` и `~/.config/1c/projects.json` (путь legacy берётся из `$env:EDT_LEGACY_CONFIG_PATH`, иначе `~\.config\1c\projects.json` — переменная нужна тестам); ничего нет → `$null`. Иначе: копия `config.json` → `config.json.v2.bak` (legacy не трогается), сохранение v3, печать Notes одним блоком, возврат конфига.
- Вызов: `Get-EdtWtConfig` (Task 1) вызывает миграцию и когда файла нет, и когда в файле нет `version: 3`.

- [ ] **Step 1: Write the failing tests** — фикстуры повторяют реальную форму (см. spec §5.2):

```powershell
It 'переносит пути, EDT, JVM и проекты' {
    $primary = '{"paths":{"projects_root":"R","worktree_root":"W","workspaces_root":"S"},"edt":{"cli_path":"<существующий temp-файл>","jvm":{"max_heap":"16g","gui_max_heap":"8g"}},"defaults":{"reference_branch":"pre-prod","edt_prefs_source":""}}' | ConvertFrom-Json
    $legacy = '{"defaults":{"jvm":{"extra_args":"-XX:+UseG1GC"}},"worktree":{"root_dir":"X","reference_branch":"pre-prod"},"projects":{"p":{"cf_project":"src/cf","active_extensions":["cfe_a","cfe_gone"]}}}' | ConvertFrom-Json
    $r = & $m { param($a,$b,$c) ConvertFrom-EdtWtV2Config -Primary $a -Legacy $b -ReposRootForCheck $c } $primary $legacy $script:Repos
    $r.Config.paths.repos_root | Should -Be 'R'
    $r.Config.paths.workspaces_root | Should -Be 'S'      # primary побеждает legacy
    $r.Config.edt.max_heap | Should -Be '16g'
    $r.Config.edt.extra_vmargs | Should -Be '-XX:+UseG1GC'
    $r.Config.projects.p.extensions | Should -Be @('src/cfe_a')   # cfe_gone отсутствует на диске
    $r.Config.projects.p.ref_branch | Should -Be 'pre-prod'
}
It 'несуществующий cli_path превращается в null (автопоиск)' { ... $r.Config.edt.cli_path | Should -BeNullOrEmpty }
It 'Get-EdtWtConfig мигрирует один раз, оставляет .v2.bak и не трогает legacy' {
    # config.json в формате v2 + EDT_LEGACY_CONFIG_PATH на temp-файл
    (& $m { Get-EdtWtConfig }).version | Should -Be 3
    Test-Path "$script:CfgPath.v2.bak" | Should -BeTrue
    (Get-Content $script:CfgPath -Raw | ConvertFrom-Json).version | Should -Be 3
    Get-FileHash $script:LegacyPath | Should -Be $script:LegacyHashBefore
}
```

- [ ] **Step 2: Run, verify FAIL** (`ConvertFrom-EdtWtV2Config` не найдена).
- [ ] **Step 3: Implement**; добавить файл в `$loadOrder` после `Configuration.ps1`.
- [ ] **Step 4: Run, verify PASS**; полный чек.
- [ ] **Step 5: Commit** — `feat(config): migrate 2.x user config to v3`

### Task 3: Поиск EDT-проектов в клоне и разбор выбора

**Files:**
- Create: `Private/ProjectDiscovery.ps1`
- Modify: `Tests/TestHelpers.ps1`
- Test: `Tests/Discovery.Tests.ps1`

**Interfaces:**
- Produces:
  - `Find-EdtWtEdtProjects -RepoPath <string> -> PSCustomObject[]` `{ RelPath ('src/cfe_a', прямые слеши); Name (projectDescription.name из .project); Kind ('Configuration'|'Extension') }` — `.project` на глубину до 3 уровней, каталог `.git` пропускается; nature `com._1c.g5.v8.dt.core.V8ConfigurationNature` / `com._1c.g5.v8.dt.core.V8ExtensionNature`; прочие `.project` игнорируются; сортировка по `RelPath`.
  - `ConvertFrom-EdtWtSelection -Text <string> -Count <int> -> int[]` (номера с 1, по возрастанию, без дублей): разделители пробел/запятая, диапазон `2-4`, `все`/`all`/`*` → 1..Count, `нет`/`none`/пусто → `@()`; номер вне 1..Count или мусор → `throw "Неверный выбор '<текст>': ожидаются номера 1-<Count>, диапазоны (2-4), 'все' или 'нет'."`.
  - `Tests/TestHelpers.ps1`: `New-EdtWtTestRepo -Root <string> -Name <string> [-Branch 'main'] [-Projects <hashtable relpath→'Configuration'|'Extension'>] [-WithRemote] -> [pscustomobject]@{ RepoPath; RemotePath }` — `git init`, `.project` с нужной nature, коммит; `-WithRemote` создаёт bare-репозиторий, `origin` на него и `push -u`.

- [ ] **Step 1: Write the failing tests**

```powershell
It 'находит конфигурацию и расширения, вложенную конфигурацию тоже' {
    $r = New-EdtWtTestRepo -Root $root -Name 'p' -Projects @{ 'src/cf/Main'='Configuration'; 'src/cfe_a'='Extension'; 'src/cfe_b'='Extension' }
    $found = & $m { param($p) Find-EdtWtEdtProjects -RepoPath $p } $r.RepoPath
    ($found | Where-Object Kind -eq 'Configuration').RelPath | Should -Be 'src/cf/Main'
    ($found | Where-Object Kind -eq 'Extension').RelPath | Should -Be @('src/cfe_a','src/cfe_b')
}
It 'разбирает выбор' -ForEach @(
    @{ T='1 3';  E=@(1,3) }, @{ T='2-4'; E=@(2,3,4) }, @{ T='1,1, 2'; E=@(1,2) },
    @{ T='все';  E=@(1,2,3,4,5) }, @{ T='нет'; E=@() }, @{ T=''; E=@() }
) { & $m { param($t) ConvertFrom-EdtWtSelection -Text $t -Count 5 } $T | Should -Be $E }
It 'отклоняет номер вне диапазона' { { & $m { ConvertFrom-EdtWtSelection -Text '9' -Count 5 } } | Should -Throw '*1-5*' }
```

- [ ] **Step 2–4:** FAIL → реализация (файл в `$loadOrder`) → PASS, полный чек.
- [ ] **Step 5: Commit** — `feat(projects): discover EDT projects in a clone`

### Task 4: Команды `edt project ...`

**Files:**
- Create: `Public/ProjectCommands.ps1`
- Test: `Tests/ProjectCommands.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 (`Get-EdtWtConfig`, `Save-EdtWtConfig`, `Get-EdtWtProjectDef`, `Test-EdtWtInteractive`, `Read-EdtWtAnswer`), Task 3.
- Produces (публичные, с comment-based help на русском):
  - `Get-EdtProject [-Name <string>] -> PSCustomObject[]` `{ Name; RefBranch; CloneBranch; Extensions ('3/7'); Reference ('есть'|'нет'); RepoPath }`.
  - `Add-EdtProject [-Name <string>] [-Extensions <string[]>] [-RefBranch <string>] [-CfProject <string>] [-WhatIf] [-Confirm]` — без `-Name`: все папки `repos_root` с `.git`, не зарегистрированные; для каждого: найти проекты, выбрать конфигурацию (одна — без вопроса; иначе вопрос номером или `-CfProject`), выбрать расширения (нумерованный список + `ConvertFrom-EdtWtSelection`; `-Extensions all|none|<имена>` без диалога), `ref_branch` = `-RefBranch` либо текущая ветка клона с вопросом «Эталонная ветка [<текущая>]». В неинтерактивном сеансе без `-Extensions` → `throw "...укажите -Extensions all|none|<имена>"`; без однозначной конфигурации и без `-CfProject` → `throw` с подсказкой `-CfProject`. Уже зарегистрированный проект → предупреждение и пропуск.
  - `Set-EdtProjectExtension -Name <string> [-Change <string[]>] [-WhatIf]` — без `-Change` (интерактивно): список найденных с отметками `[x]`, ввод номеров заменяет набор; `-Change '+cfe_new','-cfe_old'`: имя — папка (`cfe_new`) или относительный путь; неизвестное имя → `throw` со списком найденных.
  - `Set-EdtProject -Name <string> [-RefBranch <string>] [-CfProject <string>] [-WhatIf]`.
  - `Remove-EdtProject -Name <string> [-WhatIf] [-Confirm]` (`ConfirmImpact = 'Medium'`), файлы не трогает.
  - Приватная `Resolve-EdtWtExtensionRef -Found <obj[]> -Ref <string> -> string` (RelPath) — общая для `-Extensions` и `-Change`.

- [ ] **Step 1: Write the failing tests** (`Use-EdtWtTestConfig`, `repos_root` = temp, репозиторий с `src/cf`, `src/cfe_a`, `src/cfe_b`)

```powershell
It 'неинтерактивно регистрирует проект с выбранными расширениями' {
    Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $false }
    Add-EdtProject -Name 'p' -Extensions 'cfe_a' -Confirm:$false
    $p = (Get-Content $cfg -Raw | ConvertFrom-Json).projects.p
    $p.cf_project | Should -Be 'src/cf'; $p.extensions | Should -Be @('src/cfe_a'); $p.ref_branch | Should -Be 'main'
}
It 'неинтерактивно без -Extensions не зависает, а падает с подсказкой' {
    Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $false }
    { Add-EdtProject -Name 'p' -Confirm:$false } | Should -Throw '*-Extensions*'
}
It 'интерактивно принимает номера' {
    Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $true }
    Mock -ModuleName EdtWorktree Read-EdtWtAnswer { param($Prompt,$Default) if ($Prompt -match 'ветка') { $Default } else { '1 2' } }
    Add-EdtProject -Name 'p' -Confirm:$false
    (Get-Content $cfg -Raw | ConvertFrom-Json).projects.p.extensions | Should -Be @('src/cfe_a','src/cfe_b')
}
It '+/- меняет набор без диалога' {
    Set-EdtProjectExtension -Name 'p' -Change '+cfe_b','-cfe_a'
    (Get-Content $cfg -Raw | ConvertFrom-Json).projects.p.extensions | Should -Be @('src/cfe_b')
}
It 'неизвестное расширение — ошибка со списком' { { Set-EdtProjectExtension -Name 'p' -Change '+nope' } | Should -Throw '*cfe_a*' }
It 'Remove-EdtProject не трогает клон' { Remove-EdtProject -Name 'p' -Confirm:$false; Test-Path $repo | Should -BeTrue }
```

- [ ] **Step 2–4:** FAIL → реализация (файл в `$loadOrder`, функции в `FunctionsToExport`) → PASS, полный чек.
- [ ] **Step 5: Commit** — `feat(cli): manage projects from the command line`

### Task 5: Контекст, определение проекта и модель веток

Исправляет аудит #1, #2, #7 (ветки/remote).

**Files:**
- Modify: `Private/ProjectDiscovery.ps1`, `Private/GitWorktree.ps1`, `Public/WorktreeCommands.ps1` (`Get-EdtWtContext`)
- Test: `Tests/Context.Tests.ps1`, `Tests/Git.Tests.ps1`

**Interfaces:**
- Consumes: Task 1, Task 3 (`New-EdtWtTestRepo`).
- Produces:
  - `Test-EdtWtSamePath -A <string> -B <string> -> bool` (в `EclipseLocation.ps1`): `[IO.Path]::GetFullPath`, `TrimEnd('\','/')`, `OrdinalIgnoreCase`. Используется в Task 5, 7, 8, 12.
  - `Resolve-EdtWtProjectFromPath -Path <string> -Config <obj> -> [pscustomobject]@{ Name; RepoPath; Registered [bool] } | $null` — `git rev-parse --git-common-dir` → если лист `.git`, клон = родитель; иначе клон = сам каталог; `$null`, если родитель клона не равен `repos_root` (через `Test-EdtWtSamePath`).
  - `Resolve-EdtWtBranchName -Name <string> -Prefix <string> -> string` — есть `/` → как есть; иначе `Prefix + Name`.
  - `New-EdtWtWorktree -Project <string> -Branch <string> -> string` (путь) — полное имя ветки; каталог `<worktrees_root>\<проект>\<ConvertTo-EdtWtSafeName ветки>`; порядок spec §7.4: существующий worktree ветки → локальная ветка → `<remote>/<ветка>` (`worktree add --track -b`) → новая от `<remote>/<ref_branch>`. `fetch <remote>` и `worktree prune` перед этим.
  - `Get-EdtWtContext [-Path <string>] [-ProjectName <string>] -> PSCustomObject` — поля как сейчас плюс `RepoPath`, `Extensions` (относительные пути из конфига), `RefBranch` (из проекта); `ReferenceWsDir = <workspaces_root>\<проект>\_reference`; `ReferenceBranch` и `ActiveExtensions` удаляются (вызывающих перевести). Незарегистрированный клон → ошибка из `Get-EdtWtProjectDef`. `EdtCliPath`: `edt.cli_path`, иначе первый из `Find-EdtWtCli`.
  - `ConvertTo-EdtWtTaskFolder` удалить.

- [ ] **Step 1: Write the failing tests**

```powershell
It 'проект определяется и в клоне, и в его worktree (путь с пробелом и кириллицей)' {
    $repos = Join-Path $root 'Интеграция с Каспи'
    $r = New-EdtWtTestRepo -Root $repos -Name 'proj' -WithRemote
    git -C $r.RepoPath worktree add -q -b feature/T-1 (Join-Path $root 'wt\proj\feature-T-1')
    $cfg = & $m { $c = New-EdtWtDefaultConfig; $c.paths.repos_root = $args[0]; $c } $repos
    (& $m { param($p,$c) Resolve-EdtWtProjectFromPath -Path $p -Config $c } (Join-Path $root 'wt\proj\feature-T-1') $cfg).Name | Should -Be 'proj'
    (& $m { param($p,$c) Resolve-EdtWtProjectFromPath -Path $p -Config $c } $r.RepoPath $cfg).Name | Should -Be 'proj'
}
It 'сравнение путей без учёта регистра и хвостового слеша' {
    & $m { Test-EdtWtSamePath -A 'd:\ws\p\x\' -B 'D:\WS\p\x' } | Should -BeTrue
    & $m { Test-EdtWtSamePath -A 'D:\ws\p\x1' -B 'D:\ws\p\x10' } | Should -BeFalse
}
It 'эталонная ветка берётся из проекта' {   # регрессия аудита #1
    # проект зарегистрирован с ref_branch 'develop'
    (Get-EdtWtContext -Path $repo).RefBranch | Should -Be 'develop'
}
It 'короткое имя дополняется префиксом' { & $m { Resolve-EdtWtBranchName -Name 'T-1' -Prefix 'feature/' } | Should -Be 'feature/T-1' }
It 'ветка с remote подключается с отслеживанием, новая — от ref_branch' {
    # в bare-remote заранее запушена ветка bugfix/x; затем New-EdtWtWorktree для bugfix/x и для feature/new
    git -C $wtX rev-parse --abbrev-ref '@{u}' | Should -Be 'origin/bugfix/x'
    git -C $wtNew merge-base --is-ancestor origin/main HEAD; $LASTEXITCODE | Should -Be 0
}
```

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек (перевести вызовы `Get-EdtWtContext`/`ReferenceBranch`/`ActiveExtensions` в других файлах).
- [ ] **Step 5: Commit** — `fix(context): resolve project from clone and per-project ref branch`

### Task 6: Эталон без ключей: из клона, с валидацией; `update`

Исправляет аудит #6, #7 (`_reference`).

**Files:**
- Modify: `Public/WorktreeCommands.ps1` (`Invoke-EdtWorktreeWarmup`, `Invoke-EdtWorktreeOpen`), `Private/GitWorktree.ps1` (`Invoke-EdtWtSafeWarmup`), `Private/Workspace.ps1` (`Get-EdtWtPrefsSource`, `Get-EdtWtImportTargets`, `Initialize-EdtWtWorkspace`, удалить `Resolve-EdtWtExtensionList`/`Get-EdtWtChangedExtensions`), `Public/LifecycleCommands.ps1` (`Update-EdtWtReference`)
- Test: `Tests/Warmup.Tests.ps1`, `Tests/Update.Tests.ps1`, `Tests/Extensions.Tests.ps1` (удалить или свернуть в Warmup)

**Interfaces:**
- Consumes: Task 5 (`Get-EdtWtContext`), `Invoke-EdtWtCli`, `New-EdtWtBatch`, `Get-EdtWtWorkspaceProcesses`.
- Produces:
  - `Invoke-EdtWorktreeWarmup [-ProjectName <string>] [-WhatIf] [-Confirm]` — порядок: (1) `_reference_preprod` есть, `_reference` нет, не занят → `Rename-Item`; (2) клон на `RefBranch`, иначе `throw "Клон <путь> стоит на '<x>', эталон собирается с '<ref>'. Переключите: git -C <путь> switch <ref>"`; (3) эталон занят → `throw "Эталон занят: <имя:pid, ...>. Закройте EDT и повторите."` (процессы не закрываются); (4) батч: импорт `cf_project` + каждого рабочего расширения из `Extensions`, которое есть на диске (иначе строка `[skip]`); затем `validate` по всем импортированным (как сейчас при `-Validate`), из JVM-аргументов вырезать `-DisableProjectChecks=true`; (5) сборка через `Invoke-EdtWtSafeWarmup` (резерв `.previous`, возврат при ошибке); (6) `Copy-EdtWtPreferences`; (7) найденные, но не рабочие расширения — одна строка `Не в рабочих: cfe_x, cfe_y. Включить: edt project ext <проект>`. Куча — `edt.max_heap`, иначе авто.
  - `Get-EdtWtUnusedExtensions -Context <obj> -> string[]` (RelPath найденных, но не рабочих) — нужна и `doctor` (Task 12).
  - `Get-EdtWtPrefsSource -Context <obj> -> string|$null` — только `edt.prefs_source`; `D:\workspaces\full` удалить.
  - `Invoke-EdtWorktreeOpen [-NoGui] [-Refresh] [-WhatIf] [-Confirm]` — импортирует недостающие из `cf_project` + `Extensions` проекта (без режимов all/none/changed); `-MaxHeap`, `-GuiMaxHeap`, `-Extensions` удалить (куча — из конфига).
  - `Invoke-EdtWorktreeAdd -Extensions <string[]> [-NoGui] [-Force] [-WhatIf]` — имена (`cfe_x` или относительный путь) переводятся в пути через `Resolve-EdtWtExtensionRef` (Task 4) по `Find-EdtWtEdtProjects` текущего worktree; конфиг и эталон не меняются; `-MaxHeap` удалить.
  - `Update-EdtWtBranch -WorktreePath <string> -Branch <string> -Remote <string>` — добавить `-Remote` вместо зашитого `origin`.
  - `Update-EdtWtReference [-Project <string[]>] [-SkipGit] [-WhatIf] [-Confirm]` — клон берётся `<repos_root>\<проект>`, `Update-EdtWtBranch -WorktreePath <клон> -Branch <ref_branch> -Remote <git.remote>`, затем `Invoke-EdtWorktreeWarmup`; ошибки по проекту → строка отчёта `skipped` с причиной.

- [ ] **Step 1: Write the failing tests** (мок `Invoke-EdtWtCli` захватывает `$Commands`; `Get-EdtWtWorkspaceProcesses` мокается)

```powershell
It 'батч: cf + рабочие расширения + validate, без -DisableProjectChecks' {
    Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false
    $script:Captured.Commands | Should -Contain 'import --project "<repo>/src/cf"'.Replace('<repo>', $repoSlash)
    @($script:Captured.Commands -match 'cfe_b').Count | Should -Be 0          # не рабочее
    $script:Captured.Commands[-1] | Should -Match '^validate --project-name-list '
    $script:Captured.JvmArgs | Should -Not -Match 'DisableProjectChecks'
}
It 'клон не на эталонной ветке — отказ с командой switch' { ...; { Invoke-EdtWorktreeWarmup -ProjectName 'p' -Confirm:$false } | Should -Throw '*git -C*switch develop*' }
It 'занятый эталон — отказ, Stop-Process не вызывается' { ...; Should -Invoke Stop-Process -ModuleName EdtWorktree -Times 0 }
It 'старый _reference_preprod переименовывается' { ...; Test-Path (Join-Path $ws 'p\_reference') | Should -BeTrue }
It 'ошибка сборки возвращает прежний эталон' { Mock Invoke-EdtWtCli { throw 'boom' }; ...; Test-Path (Join-Path $ref 'marker.txt') | Should -BeTrue }
It 'Update пропускает грязный клон с причиной' { (Update-EdtWtReference -Project 'p' -Confirm:$false).Status | Should -Be 'skipped' }
```

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `feat(warmup): build validated reference from the clone without switches`

### Task 7: Поиск EDT, выбор JVM, единый запуск GUI

Исправляет аудит #4, #5, #8.

**Files:**
- Modify: `Private/EdtProcess.ps1`, `Public/WorktreeCommands.ps1` (`Invoke-EdtWorktreeAdd`)
- Test: `Tests/Jvm.Tests.ps1`, `Tests/EdtDiscovery.Tests.ps1`

**Interfaces:**
- Produces:
  - `Find-EdtWtCli [-SearchRoots <string[]>] [-SkipPath] -> PSCustomObject[]` — сортировка по `[version]` (версия вида `2024.2.10` из имени каталога; не разбирается → `[version]'0.0'`), по убыванию.
  - `Test-EdtWtJdkHasJavaFx -JdkHome <string> -> bool` — есть `jmods\javafx.base.jmod` или `lib\javafx-swt.jar`, и в `release` `JAVA_VERSION="<major>..."` с major ≥ 17.
  - `Resolve-EdtWtGuiJvm -EdtGuiPath <string> [-VmPath <string>] [-SearchRoots <string[]>] -> [pscustomobject]@{ Path (string|$null); Reason ('config'|'ini'|'JAVA_HOME'|'scan'|'none') }` — порядок spec §7.3; `Path` — путь к `bin\server\jvm.dll`; `Reason='ini'` → `Path=$null` (не передавать `-vm`); дефолт `SearchRoots`: `$env:ProgramFiles\Zulu\*`, `$env:ProgramFiles\BellSoft\*`, `$env:ProgramFiles\Axiom*\*`, `$env:ProgramFiles\Java\*`; кандидат принимается, только если `Test-EdtWtJdkHasJavaFx`.
  - `Start-EdtWtGui -Context <obj> [-WhatIf]` — `-vm` из `Resolve-EdtWtGuiJvm` (с кавычками), `-data`, `-vmargs` из `Resolve-EdtWtGuiVmArgs` с кучей из `edt.gui_max_heap` либо авто; при `Reason='none'` — предупреждение «JDK 17 с JavaFX не найдена, см. edt doctor». Параметр `-GuiMaxHeap` удалить.
  - `Invoke-EdtWorktreeAdd` перезапускает IDE через `Start-EdtWtGui` (никаких прямых `Start-Process`).

- [ ] **Step 1: Write the failing tests** (фейковые JDK во temp: каталоги с `release`, `jmods\javafx.base.jmod`, `bin\server\jvm.dll`; фейковый `1cedt.exe` + `1cedt.ini`)

```powershell
It 'версии EDT сортируются как версии' {
    # temp\1C\1CE\components\1c-edt-2024.2.9+1-x86_64\1cedtcli.exe и ...2024.2.10+1...
    (& $m { param($r) Find-EdtWtCli -SearchRoots $r -SkipPath } $root)[0].Path | Should -Match '2024\.2\.10'
}
It '-vm в 1cedt.ini побеждает JAVA_HOME' { $env:JAVA_HOME = $jdkFx; (Resolve…).Reason | Should -Be 'ini'; (Resolve…).Path | Should -BeNullOrEmpty }
It 'JAVA_HOME без JavaFX пропускается, берётся найденная JDK с JavaFX' { $env:JAVA_HOME = $jdkNoFx; (Resolve… -SearchRoots $fxRoot).Reason | Should -Be 'scan' }
It 'Java 11 с JavaFX не подходит' { & $m { param($j) Test-EdtWtJdkHasJavaFx -JdkHome $j } $jdk11Fx | Should -BeFalse }
It 'edt.vm_path из конфига имеет приоритет' { (Resolve… -VmPath $jdkFx).Reason | Should -Be 'config' }
It 'Invoke-EdtWorktreeAdd перезапускает IDE через Start-EdtWtGui' { ...; Should -Invoke Start-EdtWtGui -ModuleName EdtWorktree -Times 1 }
```
Тесты сохраняют и восстанавливают `$env:JAVA_HOME` в `BeforeEach`/`AfterEach`.

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `fix(jvm): pick a JavaFX JDK without overriding 1cedt.ini; sort EDT versions`

### Task 8: Точный поиск процессов и чтение вывода `1cedtcli`

Исправляет аудит #10, #11.

**Files:**
- Modify: `Private/EdtProcess.ps1` (`Get-EdtWtWorkspaceProcesses`, `Invoke-EdtWtCli`), `Public/WorktreeCommands.ps1` (`Get-EdtWorktreeList`)
- Test: `Tests/Process.Tests.ps1`

**Interfaces:**
- Consumes: `Test-EdtWtSamePath` (Task 5).
- Produces:
  - `Get-EdtWtDataArgument -CommandLine <string> -> string|$null` — значение после `-data` (в кавычках или до пробела).
  - `Get-EdtWtWorkspaceProcesses -WorkspaceDir <string> [-IncludeHeadless]` — процесс подходит, только если `Test-EdtWtSamePath (Get-EdtWtDataArgument ...) $WorkspaceDir`. `Get-EdtWorktreeList` использует ту же проверку.
  - `Invoke-EdtWtCli` — stderr читается `ReadToEndAsync()` до синхронного чтения stdout.

- [ ] **Step 1: Write the failing tests**

```powershell
It 'разбирает -data в кавычках и без' -ForEach @(
    @{ C='"C:\EDT\1cedt.exe" -data "D:\ws\p\feature-T-1" -vmargs -Xmx8g'; E='D:\ws\p\feature-T-1' },
    @{ C='1cedtcli.exe -data D:\ws\p\x -timeout 7200'; E='D:\ws\p\x' }
) { & $m { param($c) Get-EdtWtDataArgument -CommandLine $c } $C | Should -Be $E }
It 'feature-T-1 не захватывает процесс feature-T-10' {
    Mock -ModuleName EdtWorktree Get-CimInstance { [pscustomobject]@{ Name='1cedt.exe'; ProcessId=1; CommandLine='1cedt.exe -data "D:\ws\p\feature-T-10"' } }
    @(& $m { Get-EdtWtWorkspaceProcesses -WorkspaceDir 'D:\ws\p\feature-T-1' }).Count | Should -Be 0
    @(& $m { Get-EdtWtWorkspaceProcesses -WorkspaceDir 'd:\WS\p\feature-T-10\' }).Count | Should -Be 1
}
It 'большой stderr не вешает Invoke-EdtWtCli' {
    # фейковый cli.cmd: 5000 строк в stderr, 10 в stdout, exit 0; запуск в Start-ThreadJob с импортом модуля
    $job | Wait-Job -Timeout 60 | Should -Not -BeNullOrEmpty
}
```

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `fix(process): match workspaces exactly and read cli output without deadlock`

### Task 9: Экранирование `.location`

Исправляет аудит #12.

**Files:**
- Modify: `Private/EclipseLocation.ps1` (`ConvertTo-EdtWtEclipseLocationUri`, `Repair-EdtWtWorkspaceLocations`)
- Test: `Tests/Location.Tests.ps1`

**Interfaces:**
- Produces: `ConvertTo-EdtWtEclipseLocationUri -Path <string> -> string` — сначала `%` → `%25`, затем пробел `%20`, `#` `%23`, `[` `%5B`, `]` `%5D`, `{` `%7B`, `}` `%7D`, `^` `%5E`, `` ` `` `%60`, `"` `%22`, `<` `%3C`, `>` `%3E`, `|` `%7C`; кириллица без изменений. `Repair-EdtWtWorkspaceLocations` сравнивает префиксы через `StartsWith(..., OrdinalIgnoreCase)` вместо `-like`, а признак «невалидный URI» — «повторное кодирование декодированного пути даёт другую строку».

- [ ] **Step 1: Write the failing tests**

```powershell
It 'экранирует спецсимволы и оставляет кириллицу' {
    & $m { ConvertTo-EdtWtEclipseLocationUri -Path 'D:\Проекты\C# 50%\[x]' } | Should -Be 'URI//file:/D:/Проекты/C%23%2050%25/%5Bx%5D'
}
It 'round-trip' { & $m { ConvertFrom-EdtWtEclipseLocationUri (ConvertTo-EdtWtEclipseLocationUri 'D:\a b\#\%\{}') } | Should -Be 'D:\a b\#\%\{}' }
It 'перепривязка работает для worktree с [ ] в пути' { ... }
```

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `fix(location): escape all URI-reserved characters`

### Task 10: `edt setup` и `edt config show|path|set`

**Files:**
- Modify: `Public/ConfigCommands.ps1` (переписать)
- Test: `Tests/Setup.Tests.ps1`

**Interfaces:**
- Consumes: Task 1, Task 4 (`Add-EdtProject`), `Find-EdtWtCli`.
- Produces:
  - `Invoke-EdtSetup [-ReposRoot <string>] [-WorktreesRoot <string>] [-WorkspacesRoot <string>] [-NoProjects] [-WhatIf]` — для каждого не переданного пути: интерактивно `Read-EdtWtAnswer` с текущим значением по умолчанию, неинтерактивно — текущее значение; отсутствующий каталог: интерактивно вопрос «Создать? [Y/n]», неинтерактивно — создать; печать найденного EDT (или «не найден — укажите: edt config set edt.cli_path <путь>»); сохранение; затем (интерактивно и без `-NoProjects`) `Add-EdtProject` без имени.
  - `Get-EdtConfig [-Path] [-AsJson]` — по умолчанию сводка `{ ConfigFile; ReposRoot; WorktreesRoot; WorkspacesRoot; EdtCli (значение или 'авто: <найденный>'); Projects }`; `-Path` → только путь к файлу.
  - `Set-EdtConfig -Key <string> -Value <string> [-WhatIf]` — допустимые ключи и проверки: `paths.repos_root|worktrees_root|workspaces_root` (строка), `edt.cli_path|vm_path|prefs_source` (строка, предупреждение, если путь не существует), `edt.max_heap|gui_max_heap` (`^\d+[gGmM]$`), `edt.extra_vmargs` (строка), `edt.timeout_sec` (целое > 0), `git.remote|branch_prefix` (строка); значение `null` или пустое → `$null`; неизвестный ключ → `throw` со списком допустимых.

- [ ] **Step 1: Write the failing tests**

```powershell
It 'неинтерактивно пишет пути и не задаёт вопросов' {
    Mock -ModuleName EdtWorktree Test-EdtWtInteractive { $false }
    Mock -ModuleName EdtWorktree Read-EdtWtAnswer { throw 'не должен спрашивать' }
    Invoke-EdtSetup -ReposRoot "$root\r" -WorktreesRoot "$root\w" -WorkspacesRoot "$root\s"
    (Get-Content $cfg -Raw | ConvertFrom-Json).paths.worktrees_root | Should -Be "$root\w"
    Test-Path "$root\s" | Should -BeTrue
}
It 'повторный setup сохраняет проекты' { ...; (Get-Content $cfg -Raw | ConvertFrom-Json).projects.p | Should -Not -BeNullOrEmpty }
It 'config set валидирует ключ и формат' {
    Set-EdtConfig -Key 'edt.max_heap' -Value '16g'
    { Set-EdtConfig -Key 'edt.max_heap' -Value 'много' } | Should -Throw
    { Set-EdtConfig -Key 'nope' -Value 1 } | Should -Throw '*paths.repos_root*'
    Set-EdtConfig -Key 'edt.cli_path' -Value 'null'; (Get-Content $cfg -Raw | ConvertFrom-Json).edt.cli_path | Should -BeNullOrEmpty
}
```

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `feat(cli): edt setup and edt config set`

### Task 11: `edt doctor`

**Files:**
- Create: `Public/DoctorCommand.ps1`
- Test: `Tests/Doctor.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 (`Get-EdtWtConfig`), Task 3 (`Find-EdtWtEdtProjects`), Task 6 (`Get-EdtWtUnusedExtensions`), Task 7 (`Find-EdtWtCli`, `Resolve-EdtWtGuiJvm`).
- Produces: `Test-EdtEnvironment -> PSCustomObject[]` `{ Check; Status ('ok'|'warn'|'error'); Detail; Fix }`. Проверки и статусы: PowerShell ≥ 7 (error), git в PATH (error), EDT найден (error), JVM для GUI (`Reason='none'` → warn, иначе ok с причиной в `Detail`), каждый путь `paths.*` существует (error, `Fix = 'edt setup'`), нет ни одного проекта (warn, `Fix = 'edt project add'`); по проекту: клон существует (error), клон на `ref_branch` (error, `Fix = "git -C <клон> switch <ref>"`), рабочее расширение отсутствует на диске (warn, `Fix = "edt project ext <p> -<имя>"`), есть не рабочие расширения (warn, `Fix = "edt project ext <p>"`), эталон есть (warn, `Fix = "edt warmup <p>"`).

- [ ] **Step 1: Write the failing tests**

```powershell
It 'клон на чужой ветке — error с командой switch' {
    (Test-EdtEnvironment | Where-Object { $_.Check -match 'ветка' -and $_.Status -eq 'error' }).Fix | Should -Match 'switch develop'
}
It 'новое расширение — warn с edt project ext' { (Test-EdtEnvironment | Where-Object Fix -match '^edt project ext p$').Status | Should -Be 'warn' }
It 'всё в порядке — ни одного error' { @(Test-EdtEnvironment | Where-Object Status -eq 'error').Count | Should -Be 0 }
```
(Последний тест мокает `Find-EdtWtCli` на фейковый путь.)

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `feat(cli): edt doctor`

### Task 12: `self-update` и `edt uninstall`

Исправляет аудит #9, #17.

**Files:**
- Modify: `Public/LifecycleCommands.ps1`
- Delete: `scripts/uninstall.ps1`
- Test: `Tests/Uninstall.Tests.ps1`

**Interfaces:**
- Produces:
  - `Remove-EdtWtPathEntry -PathValue <string> -Entry <string> -> string` — убирает все совпадения `Entry` (через `Test-EdtWtSamePath`), пустые элементы выбрасываются.
  - `Get-EdtWtInstallInfo -> [pscustomobject]@{ ModuleLink; InstallDir; BinDir; ConfigDir }` — `ModuleLink = <MyDocuments>\PowerShell\Modules\EdtWorktree`; `InstallDir` — цель junction/symlink (или `ModuleBase`, если копия); `BinDir = <InstallDir>\bin`; `ConfigDir` — родитель `Get-EdtWtUserConfigPath`. Переопределение корней для тестов: `$env:EDT_MODULES_DIR`.
  - `Uninstall-EdtWorktree [-Purge] [-WhatIf] [-Confirm]` (`ConfirmImpact='High'`) — печатает список удаляемого, затем: ссылка модуля (для junction — удаление самой ссылки), `BinDir` из PATH пользователя; при `-Purge` ещё `InstallDir` и `ConfigDir`. Клоны, worktree, рабочие области не трогает. Тестовый режим PATH: при `$env:EDT_PATH_SCOPE = 'Process'` правится только `$env:Path` процесса.
  - `Update-EdtSelf` — без фолбэков поиска git; нет git → `throw "git не найден в PATH. Установите: winget install Git.Git"`.

- [ ] **Step 1: Write the failing tests**

```powershell
It 'убирает запись PATH без учёта регистра и слеша' {
    & $m { Remove-EdtWtPathEntry -PathValue 'C:\a;D:\Tools\edt\bin\;C:\b' -Entry 'd:\tools\EDT\bin' } | Should -Be 'C:\a;C:\b'
}
It 'uninstall удаляет только ссылку, исходники остаются' {
    # temp-клон + junction в $env:EDT_MODULES_DIR, EDT_PATH_SCOPE=Process
    Uninstall-EdtWorktree -Confirm:$false
    Test-Path $link | Should -BeFalse; Test-Path "$clone\EdtWorktree.psd1" | Should -BeTrue
    $env:Path | Should -Not -Match [regex]::Escape("$clone\bin")
}
It '-Purge удаляет каталог установки и конфиг, но не рабочие области' { ... }
```

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `feat(cli): edt uninstall; fix PATH cleanup`

### Task 13: Диспетчер, экспорт, автодополнение, CLI-вход

**Files:**
- Modify: `Public/Invoke-EdtCommand.ps1`, `EdtWorktree.psm1`, `EdtWorktree.psd1`, `Completers/Register-EdtWtCompleters.ps1`, `bin/edt.ps1`, `Private/Workspace.ps1` (`Show-EdtWtUsage`), `Private/EdtProcess.ps1` (`Resolve-EdtWtWrapperArgs`)
- Test: `Tests/Contract.Tests.ps1`, `Tests/Arguments.Tests.ps1`

**Interfaces:**
- Consumes: все публичные функции Tasks 4–12.
- Produces:
  - `Invoke-EdtCommand` `ValidateSet`: `open, warmup, add, remove, status, update, vr, setup, project, config, doctor, self-update, uninstall, help`. Подкоманды `project list|add|ext|set|remove` и `config show|path|set` разбираются из первого позиционного аргумента. Для `open <проект> <ветка>`: `Resolve-EdtWtBranchName`, затем существующий worktree или `New-EdtWtWorktree`, затем `Invoke-EdtWorktreeOpen` в нём. Для `open`/`warmup` по незарегистрированному клону из `repos_root`: интерактивно — `Add-EdtProject -Name`, иначе ошибка из `Get-EdtWtProjectDef`. `remove [проект] [ветка]` — та же нормализация ветки.
  - `Resolve-EdtWtWrapperArgs` знает только ключи 3.0: `-NoGui`, `-Refresh`, `-SkipGit`, `-Purge`, `-WhatIf`/`--dry-run`, `-Yes`, `-NoProjects`, `-Extensions <v>` (только для `project add`), `-RefBranch <v>`, `-CfProject <v>`, `-ReposRoot|-WorktreesRoot|-WorkspacesRoot <v>`; аргументы `+имя`/`-имя` после `project ext <p>` — не ключи, а изменения (разбор до общего парсера).
  - `bin/edt.ps1`: `$known` = тот же список; `doctor` → `Format-Table` и код 1 при любом `error`; `status`, `project list`, `config show`, `update`, `doctor` выводятся таблицей.
  - `EdtWorktree.psd1`: `ModuleVersion = '3.0.0'`; `FunctionsToExport` = `Invoke-EdtCommand, Invoke-EdtWorktreeOpen, Invoke-EdtWorktreeWarmup, Invoke-EdtWorktreeAdd, Invoke-EdtWorktreeClean, Get-EdtWorktreeList, Get-EdtWtContext, Update-EdtWtReference, Get-EdtConfig, Set-EdtConfig, Invoke-EdtSetup, Get-EdtProject, Add-EdtProject, Set-EdtProjectExtension, Set-EdtProject, Remove-EdtProject, Test-EdtEnvironment, Update-EdtSelf, Uninstall-EdtWorktree`; `wt-*`, `edt-wt-*`, `Invoke-EdtWtLegacyCommand`, `Initialize-EdtConfig`, `New-EdtProjectConfig` удалены (и в `psm1` — генерация legacy-функций).
  - Автодополнение: подкоманды; `project` → `list add ext set remove`; `config` → `show path set` и ключи для `set`; имена проектов после `open|warmup|update|remove|project <sub>`; после `project ext <p>` — `+<имя>`/`-<имя>` из найденных расширений клона.
  - `Show-EdtWtUsage` — справка 3.0 (без `-MaxHeap`, `-GuiMaxHeap`, `-Validate`, `-Force`, `wt-*`).

- [ ] **Step 1: Write the failing tests** — обновить `Contract.Tests.ps1`: `$script:Public` = список выше, `$script:Legacy` удалить; новые It:

```powershell
It 'подкоманды 3.0' { $set.ValidValues | Should -Be @('open','warmup','add','remove','status','update','vr','setup','project','config','doctor','self-update','uninstall','help') }
It 'старых имён нет' { Get-Command 'wt-open','edt-wt-open' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty }
It 'у warmup нет ключей кроме ProjectName и общих' { (Get-Command Invoke-EdtWorktreeWarmup).Parameters.Keys | Should -Not -Contain 'Validate' }
It 'edt project ext p +cfe_b -cfe_a доходит до Set-EdtProjectExtension' {
    Mock -ModuleName EdtWorktree Set-EdtProjectExtension {}
    edt project ext p +cfe_b -cfe_a
    Should -Invoke Set-EdtProjectExtension -ModuleName EdtWorktree -ParameterFilter { $Name -eq 'p' -and ($Change -join ',') -eq '+cfe_b,-cfe_a' }
}
It 'bin/edt.ps1 doctor возвращает 1 при ошибке' { Mock…; pwsh -NoProfile -File bin/edt.ps1 doctor; $LASTEXITCODE | Should -Be 1 }
```
`Arguments.Tests.ps1` — убрать кейсы удалённых ключей, добавить `--no-gui`, `-Yes`, `-RefBranch develop`.

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `feat(cli)!: edt 3.0 command set; drop legacy names`

### Task 14: Установщик в одну строку

Исправляет аудит #14, часть #15.

**Files:**
- Create: `install.ps1` (корень)
- Delete: `scripts/install.ps1` (каталог `scripts/` целиком)
- Test: `Tests/Install.Tests.ps1`

**Interfaces:**
- Produces (внутри `install.ps1`, самодостаточно, без импорта модуля):
  - `Install-EdtWorktree [-InstallDir <string>] [-Branch <string>] [-RepoUrl <string>] [-ModulesDir <string>] [-NoSetup] [-NoPath]` — дефолты: `InstallDir = $env:LOCALAPPDATA\EdtWorktree`, `Branch = 'main'`, `RepoUrl = 'https://github.com/gidragir/edt-worktree.git'`, `ModulesDir = <MyDocuments>\PowerShell\Modules`. Шаги spec §4.1 по порядку; источник: если файл запущен из клона модуля (`$PSScriptRoot` содержит `EdtWorktree.psd1`) — этот клон; иначе `git clone --branch <Branch>` или `git -C <InstallDir> pull --ff-only`. Существующая ссылка/копия модуля заменяется. PATH — без дублей (сравнение без регистра и хвостового `\`). Итог — таблица проверок (pwsh, git, EDT, JDK с JavaFX) и следующий шаг.
  - Нижняя часть файла (точка входа): если `$PSVersionTable.PSVersion.Major -lt 7` — сообщение `PowerShell 7 не найден. Установите: winget install Microsoft.PowerShell, затем выполните команду установки в pwsh.` и `return` (файл должен парситься в Windows PowerShell 5.1: без синтаксиса только для PS7 вне функций); если `$env:EDT_INSTALL_NO_AUTORUN` — только определить функции; иначе `Install-EdtWorktree` с параметрами из `$env:EDT_INSTALL_DIR`, `$env:EDT_INSTALL_BRANCH`, `$env:EDT_INSTALL_NOSETUP`.
  - `Add-EdtWtInstallPathEntry -PathValue <string> -Entry <string> -> string` — добавляет `Entry` в конец, если его ещё нет (без регистра и хвостового `\`); используется `Install-EdtWorktree` для PATH пользователя.
  - Под `iex` нет `$PSScriptRoot` — код обязан это переносить.

- [ ] **Step 1: Write the failing tests** (`EDT_INSTALL_NO_AUTORUN=1`, dot-source; `RepoUrl` — локальный bare-клон текущего репозитория, сделанный в `BeforeAll`; всё во temp; `-NoPath -NoSetup`)

```powershell
It 'ставит модуль из репозитория и он импортируется' {
    Install-EdtWorktree -InstallDir $inst -RepoUrl $bare -ModulesDir $mods -NoSetup -NoPath
    (Get-Item "$mods\EdtWorktree").LinkType | Should -Be 'Junction'
    pwsh -NoProfile -Command "Import-Module '$mods\EdtWorktree\EdtWorktree.psd1'; (Get-Module EdtWorktree).Version.ToString()" | Should -Be '3.0.0'
}
It 'повторный запуск обновляет, не ломая' {
    Install-EdtWorktree -InstallDir $inst -RepoUrl $bare -ModulesDir $mods -NoSetup -NoPath
    Test-Path "$mods\EdtWorktree\EdtWorktree.psd1" | Should -BeTrue
}
It 'добавляет bin в PATH без дублей' { & { Add-EdtWtInstallPathEntry -PathValue 'C:\a;D:\x\bin\' -Entry 'd:\x\bin' } | Should -Be 'C:\a;D:\x\bin\' }
It 'файл парсится в Windows PowerShell 5.1' {
    if (-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'нет powershell.exe'; return }
    powershell.exe -NoProfile -Command "`$e=`$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$PWD\install.ps1',[ref]`$null,[ref]`$e); `$e.Count" | Should -Be '0'
}
```

- [ ] **Step 2–4:** FAIL → реализация → PASS, полный чек.
- [ ] **Step 5: Commit** — `feat(install): one-line installer`

### Task 15: Документация и обвязка

Исправляет аудит #13, #15 (README), #16, #18.

**Files:**
- Modify: `README.md` (переписать), `COMMANDS.md` (переписать), `AGENTS.md` (§1: порядок выбора JVM из spec §7.3 вместо «обязана брать JAVA_HOME или Zulu»; §3 и раздел про `config.json`), `Invoke-EdtWtChecks.ps1`, `PSScriptAnalyzerSettings.psd1` (если правила потребуют)
- Create: `.gitattributes`, `.github/workflows/checks.yml`
- Test: `Tests/Docs.Tests.ps1`

**Interfaces:**
- README по сценарию spec §2: Требования (PowerShell 7, git, 1C:EDT, JDK 17 с JavaFX, для `edt vr` — OneScript и vrunner) → Установка (строка `irm … | iex`, вариант с параметрами `& ([scriptblock]::Create((irm …))) -NoSetup`, ручная установка из ZIP с `Get-ChildItem -Recurse | Unblock-File`) → Первые шаги (`edt setup`, `edt project add`, `edt warmup`, `edt open`) → Команды (таблица) → Конфиг (схема и `edt config set`) → Обновление и удаление → Решение проблем (`edt doctor`, JavaFX, занятый эталон) → Для разработчиков модуля (`Invoke-EdtWtChecks.ps1`, Pester 5). Без ссылок на dotfiles автора.
- `.gitattributes`: `* text=auto`, `*.cmd text eol=crlf`, `*.ps1 *.psm1 *.psd1 *.md *.json text eol=lf`.
- `Invoke-EdtWtChecks.ps1`: нет Pester ≥ 5 → `Write-Host 'Нужен Pester 5: Install-Module Pester -MinimumVersion 5 -Scope CurrentUser -Force -SkipPublisherCheck'` и `exit 1`; убрать проверку `~/.config/powershell/conf.d/08-edt-worktree.ps1`.
- `.github/workflows/checks.yml`: `windows-latest`, `shell: pwsh`; шаги: установка Pester 5 и PSScriptAnalyzer, `pwsh -NoProfile -File Invoke-EdtWtChecks.ps1`; затем установщик в чистом профиле: `$env:EDT_INSTALL_NOSETUP=1; ./install.ps1` и `edt help`.

- [ ] **Step 1: Write the failing tests** (`Tests/Docs.Tests.ps1`)

```powershell
It 'README не ссылается на dotfiles автора' { Get-Content README.md -Raw | Should -Not -Match '~/.config/bin|_Variables\.ps1|conf\.d|nushell/custom' }
It 'README содержит команду установки' { Get-Content README.md -Raw | Should -Match ([regex]::Escape('irm https://raw.githubusercontent.com/gidragir/edt-worktree/main/install.ps1 | iex')) }
It 'все подкоманды описаны в README и COMMANDS.md' {
    foreach ($c in 'setup','project','config','doctor','warmup','open','add','remove','status','update','vr','self-update','uninstall') {
        Get-Content README.md -Raw | Should -Match "edt $c"; Get-Content COMMANDS.md -Raw | Should -Match "edt $c"
    }
}
It '.gitattributes фиксирует CRLF для .cmd' { Get-Content .gitattributes -Raw | Should -Match '\*\.cmd\s+text\s+eol=crlf' }
```

- [ ] **Step 2–4:** FAIL → документы и файлы → PASS; `git add --renormalize .` и проверка BOM всех `.ps1`/`.psm1` (AGENTS.md §3); полный чек.
- [ ] **Step 5: Commit** — `docs: README and COMMANDS for 3.0; gitattributes; CI`

### Task 16: Сквозная проверка на реальной машине

Не автоматизируется: нужен установленный EDT.

- [ ] **Step 1:** На машине автора: `edt doctor` после миграции его конфига — проекты `ka-amadeo-4edt`, `ka-intertop-4edt`, `retail`, `employee-loyalty`, `it-department` (последний — через `edt project add`), без `error`, кроме реально не настроенного.
- [ ] **Step 2:** `edt warmup ka-intertop-4edt` — эталон в `_reference` (переименован из `_reference_preprod`), в журнале батча есть `validate`.
- [ ] **Step 3:** `edt open ka-intertop-4edt TASK-TEST -NoGui`, затем `edt open` в созданном worktree — IDE стартует с выбранной JVM (в выводе видно, почему выбрана).
- [ ] **Step 4:** `edt remove ka-intertop-4edt TASK-TEST -Yes` при открытой IDE соседней задачи — соседняя IDE не закрыта.
- [ ] **Step 5:** Чистый пользователь Windows (или Windows Sandbox): строка установки из README → `edt setup` → `edt doctor`.
- [ ] **Step 6:** Результаты — в описании PR.
