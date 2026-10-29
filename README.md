# EdtWorktree и команда `edt`

Рабочие области 1C:EDT для git worktree: у каждой задачи своя ветка, свой
каталог worktree и своя рабочая область EDT. Область клонируется из заранее
прогретого эталона, поэтому EDT не строит индексы заново при каждой задаче.

Шаблоны вызовов: [COMMANDS.md](docs/COMMANDS.md). Справка в консоли: `edt help`,
`Get-Help Invoke-EdtCommand -Full`.

## Требования

- Windows 10/11, права администратора не нужны.
- PowerShell 7+ (`winget install Microsoft.PowerShell`).
- git в PATH (`winget install Git.Git`).
- 1C:EDT (`1cedtcli.exe` и `1cedt.exe`).
- JDK 17+ с JavaFX для запуска IDE: полная сборка (Azul Zulu FX, Axiom JDK Full,
  Liberica Full). Обычный OpenJDK/Temurin не подходит: EDT пишет «Поддержка
  JavaFX не установлена».
- Для `edt vr`: OneScript и vrunner.

## Установка

Основной способ - PowerShell Gallery (PowerShell 7):

```powershell
Install-PSResource EdtWorktree
edt setup
```

Альтернатива - одна команда: скачивает zip выпуска GitHub, ставит модуль в
`Documents\PowerShell\Modules\EdtWorktree\<версия>` и shim `edt`:

```powershell
irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1 | iex
```

Установщик:

1. ставит модуль в `Documents\PowerShell\Modules\EdtWorktree\<версия>` (другие
   версии остаются рядом);
2. ставит постоянный shim `edt` (`edt.cmd` и `edt.ps1`) в
   `%LOCALAPPDATA%\Programs\EdtWorktree\bin` и добавляет этот каталог в PATH
   пользователя; shim берёт наибольшую установленную версию модуля, поэтому PATH
   не меняется при обновлении;
3. показывает проверки окружения: pwsh, git, 1C:EDT, JDK 17 с JavaFX;
4. в интерактивном сеансе без конфига запускает `edt setup`.

Повторный запуск обновляет установку и не дублирует запись в PATH. git для
установки не нужен (он нужен для работы `edt`).

С параметрами (без автозапуска `edt setup`, ветка, локальный zip):

```powershell
& ([scriptblock]::Create((irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1))) -NoSetup
```

Ключи: `-ZipPath` (локальный zip), `-Branch` (архив ветки GitHub, для проверки
правки до выпуска), `-Dev` (ссылка на клон разработчика, см. ниже), `-NoSetup`,
`-NoPath` (не менять PATH). Под `irm | iex` то же задаётся переменными
окружения `EDT_INSTALL_ZIP`, `EDT_INSTALL_BRANCH`, `EDT_INSTALL_DEV=1`,
`EDT_INSTALL_NOSETUP=1`.

Из ветки (для проверки до выпуска):

```powershell
& ([scriptblock]::Create((irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1))) -Branch feature/my-fix
```

Ручная установка из ZIP: скачайте `EdtWorktree.zip` и `install.ps1` из
[Releases](https://github.com/gidragir/edt-worktree/releases), снимите пометку
«скачано из интернета», иначе PowerShell откажется загружать скрипты, и
запустите установщик:

```powershell
Unblock-File D:\tools\install.ps1, D:\tools\EdtWorktree.zip
pwsh -NoProfile -File D:\tools\install.ps1 -ZipPath D:\tools\EdtWorktree.zip
```

### edt для cmd, nushell и агентов

Команда `edt` работает вне pwsh через shim: `edt setup` ставит или обновляет
его (установщик делает то же) и добавляет каталог shim в PATH. После этого
`edt open my-project TASK-123 -NoGui` вызывается из cmd, bash, nushell,
планировщика и агентов. `edt doctor` проверяет shim и PATH.

### Обновление с 3.0

В 3.0 модуль ставился клоном репозитория в `%LOCALAPPDATA%\EdtWorktree`.
`edt self-update` из 3.0 новый модуль не ставит (он делает `git pull` в клоне),
поэтому обновитесь одной командой установки:

```powershell
irm https://github.com/gidragir/edt-worktree/releases/latest/download/install.ps1 | iex
```

или `Install-PSResource EdtWorktree`, а затем `edt setup`. Установщик снимает
ссылку модуля 3.0 и старый `bin` в PATH, ставит shim. Клон, конфиг, проекты,
worktree и рабочие области не трогаются; клон можно удалить вручную.

## Первые шаги

```powershell
edt setup                       # каталоги клонов, worktree и рабочих областей; поиск EDT
edt project add my-project      # конфигурация и рабочие расширения - номерами из списка
edt warmup my-project           # эталон с индексами и валидацией
edt open my-project TASK-123    # worktree feature/TASK-123, рабочая область, IDE
```

- `edt setup` спрашивает три каталога: `repos_root` (клоны проектов, каждый на
  своей эталонной ветке), `worktrees_root` (git worktree задач) и
  `workspaces_root` (рабочие области EDT и эталоны). Без диалога:
  `edt setup -ReposRoot D:\projects -WorktreesRoot D:\projects\worktree -WorkspacesRoot D:\workspaces`.
- Имя проекта - имя папки клона в `repos_root`. `edt project add` без имени
  предлагает зарегистрировать все новые клоны.
- Эталонная ветка проекта (`ref_branch`) берётся из текущей ветки клона при
  регистрации. Клон должен стоять на ней, когда собирается эталон.
- Повторно `edt open` можно вызывать без аргументов из каталога worktree.

В репозиториях проектов модуль ничего не создаёт: вся настройка хранится на
машине пользователя.

## Команды

| Команда | Что делает |
|---|---|
| `edt setup` | Мастер: три каталога, найденный EDT, регистрация клонов. Ключи `-ReposRoot`, `-WorktreesRoot`, `-WorkspacesRoot`, `-NoProjects` |
| `edt project list` | Проекты: эталонная ветка, текущая ветка клона, рабочие/найденные расширения, есть ли эталон |
| `edt project add [имя]` | Зарегистрировать клон. Без диалога: `-Extensions all\|none\|<имена>`, `-RefBranch`, `-CfProject` |
| `edt project ext <проект> [+имя] [-имя]` | Рабочие расширения: без правок - список с отметками, с правками - без диалога |
| `edt project set <проект> -RefBranch <ветка> \| -CfProject <путь>` | Редкие правки проекта |
| `edt project remove <проект>` | Убрать проект из конфига; файлы не трогаются |
| `edt warmup [проект]` | Собрать эталон из клона: конфигурация + рабочие расширения, затем `validate` |
| `edt open [проект ветка]` | Worktree (создаётся при необходимости), рабочая область из эталона, IDE. Ключи `-NoGui`, `-Refresh` |
| `edt add <расширения>` | Подключить расширения к области текущего worktree; IDE перезапускается |
| `edt remove [проект] [ветка]` | Удалить рабочую область и git worktree (с подтверждением) |
| `edt status [проект]` | Области, блокировки и занявшие их процессы |
| `edt update [проекты]` | Подтянуть `ref_branch` в клонах и пересобрать эталоны; для расписания. Ключ `-SkipGit` |
| `edt vr <аргументы vrunner>` | vrunner с рабочей областью текущего worktree |
| `edt doctor` | Проверка окружения и проектов; у каждой проблемы - команда исправления |
| `edt config [show\|path\|set <ключ> <значение>]` | Показать настройки, путь к файлу, изменить ключ |
| `edt self-update` | Обновить модуль способом, подходящим виду установки (см. «Обновление и удаление») |
| `edt uninstall [-Purge]` | Удалить модуль и shim |

Ключи пишутся как `-NoGui` или `--no-gui`. Изменяющие команды понимают `-WhatIf`
(`--dry-run`) и `-Yes` (без вопросов). Коды возврата `src\EdtWorktree\bin\edt.ps1`: 0 успех,
1 сбой (у `doctor` - найдена ошибка), 2 ошибка вызова; для `vr` код vrunner
отдаётся как есть.

### Ветки и каталоги

- `edt open my-project TASK-123` работает с веткой `feature/TASK-123`: имя без `/`
  получает префикс `git.branch_prefix`. Полное имя (`bugfix/x`) берётся как есть.
- Если worktree ветки уже есть - используется он. Иначе: локальная ветка, затем
  ветка на `git.remote` (с отслеживанием), иначе новая ветка от
  `<remote>/<ref_branch>`.
- Worktree: `<worktrees_root>\<проект>\<ветка, / заменён на ->`.
- Рабочая область: `<workspaces_root>\<проект>\<ветка, / заменён на ->`.
- Эталон: `<workspaces_root>\<проект>\_reference`. Старый `_reference_preprod`
  переименовывается при первом `warmup`.

### `edt vr`

Вызывается из каталога worktree. Настройки базы vrunner берёт из
`autumn-properties.json` в корне worktree (файл не меняется). Обёртка на время
вызова выставляет `VRUNNER_EDT_WORKSPACE`, `VRUNNER_EDT_PATH`,
`VRUNNER_EDT_VMARGS`, `VRUNNER_EDT_TIMEOUT`; уже заданные вами `VRUNNER_EDT_*` не
перезаписываются. `cf load` и `cfe load` идут с `--increment`; ключ `-Full`
отключает это и в vrunner не передаётся. Нужна рабочая область: если её нет,
выполните `edt open -NoGui`.

## Конфиг

Один файл: `%APPDATA%\EdtWorktree\config.json` (путь: `edt config path`,
переопределяется переменной `EDT_CONFIG_PATH`). Править JSON руками не нужно:
пути задаёт `edt setup`, проекты - `edt project ...`, остальное -
`edt config set`.

```json
{
  "version": 3,
  "paths": {
    "repos_root": "D:\\projects\\default",
    "worktrees_root": "D:\\projects\\worktree",
    "workspaces_root": "D:\\workspaces\\worktree"
  },
  "edt": {
    "cli_path": null,
    "vm_path": null,
    "prefs_source": null,
    "max_heap": null,
    "gui_max_heap": null,
    "extra_vmargs": "",
    "timeout_sec": 7200
  },
  "git": { "remote": "origin", "branch_prefix": "feature/" },
  "projects": {
    "my-project": {
      "ref_branch": "develop",
      "cf_project": "src/cf",
      "extensions": ["src/cfe", "src/cfe_ad"]
    }
  }
}
```

- `null` - определять автоматически при каждом запуске: `cli_path` - самый новый
  найденный 1C:EDT, `max_heap`/`gui_max_heap` - по свободной памяти, `vm_path` -
  см. «Решение проблем».
- `extensions` - рабочие расширения: только они попадают в эталон.
- `edt.prefs_source` - рабочая область, из которой копируются настройки IDE.
- Примеры: `edt config set edt.max_heap 16g`, `edt config set git.remote upstream`,
  `edt config set edt.cli_path null` (вернуть автопоиск).
- Ключи, которых модуль не знает, при сохранении не теряются.

Конфиг 2.x (`%APPDATA%\EdtWorktree\config.json` без `version: 3` и
`~/.config/1c/projects.json`) переносится автоматически при первом запуске.
Прежний файл остаётся рядом как `config.json.v2.bak`, `projects.json` не
меняется.

## Обновление и удаление

`edt self-update` и `edt uninstall` определяют вид установки и действуют
по-своему:

| Вид | Как установлен | `edt self-update` | `edt uninstall` |
|---|---|---|---|
| Gallery | `Install-PSResource EdtWorktree` | `Update-PSResource` (или `Update-Module`), модуль перезагружается в сессии | `Uninstall-PSResource` всех версий, shim и запись PATH |
| Zip | установщик из выпуска GitHub | скачивает `install.ps1` последнего выпуска и запускает с `-NoSetup` | удаляет каталог модуля, shim и запись PATH |
| Dev | `scripts/install.ps1 -Dev` | `git pull --ff-only` в клоне разработчика | снимает ссылку модуля, shim и запись PATH |
| Legacy | клон 3.0 в `%LOCALAPPDATA%\EdtWorktree` | не обновляет, предлагает переустановку: команда установки из «Обновление с 3.0» | снимает ссылку модуля и `bin` клона из PATH |

- `edt uninstall -Purge` - ещё и конфиг (`%APPDATA%\EdtWorktree`) и для Dev и
  Legacy клон. Клон с незакоммиченными правками не удаляется (будет
  предупреждение).
- Клоны проектов, worktree и рабочие области не затрагиваются ни при обновлении,
  ни при удалении.
- Повторный запуск команды установки обновляет любую установку, кроме Dev.

## Решение проблем

Первым делом: `edt doctor`. Каждая найденная проблема выводится с командой
исправления.

- **«Поддержка JavaFX не установлена» / IDE не стартует.** JVM для IDE
  выбирается так: `edt.vm_path` из конфига; если в `1cedt.ini` уже есть `-vm` -
  он; `JAVA_HOME`, если это JDK 17+ с JavaFX; JDK с JavaFX в `Program Files`
  (Zulu, BellSoft, Axiom, Java); иначе запуск без `-vm` с предупреждением.
  `edt doctor` показывает выбранную JVM и причину. Явно:
  `edt config set edt.vm_path "C:\Program Files\Zulu\zulu-17\bin\server\jvm.dll"`.
- **«Эталон занят».** Эталон открыт в EDT. Закройте эту IDE и повторите
  `edt warmup`; модуль чужие процессы не закрывает.
- **«Клон стоит на '<x>', эталон собирается с '<ref>'».** Переключите клон
  командой из сообщения (`git -C <клон> switch <ref>`) или поменяйте эталонную
  ветку: `edt project set <проект> -RefBranch <ветка>`.
- **«Проект не зарегистрирован».** `edt project add <имя>`.
- **«Конфиг повреждён».** Исправьте JSON по сообщению или удалите файл и
  выполните `edt setup`.
- **EDT не найден.** `edt config set edt.cli_path <путь к 1cedtcli.exe>`.

## Для разработчиков модуля

- Режим разработчика: из клона `pwsh -NoProfile -File scripts/install.ps1 -Dev`.
  Ссылка модуля `Documents\PowerShell\Modules\EdtWorktree` будет указывать на
  `src\EdtWorktree` клона, shim ставится как обычно. Если модуль уже установлен
  из Gallery или zip, сначала `edt uninstall`.
- Проверки перед коммитом: `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1`
  (Pester 5 и PSScriptAnalyzer). Нужен Pester 5:
  `Install-Module Pester -MinimumVersion 5 -Scope CurrentUser -Force -SkipPublisherCheck`.
- Сборка: `pwsh -NoProfile -File scripts/build.ps1` собирает однофайловый модуль
  `out/EdtWorktree/<версия>/`, `out/EdtWorktree.zip` и `out/install.ps1`. Проверки
  над собранным модулем:
  `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1 -SkipAnalyzer -ModulePath out/EdtWorktree/<версия>/EdtWorktree.psd1`.
- Тесты не трогают реальный конфиг, PATH, shim и `Documents\PowerShell\Modules`:
  `EDT_CONFIG_PATH`, `EDT_MODULES_DIR`, `EDT_SHIM_DIR`, `EDT_PATH_SCOPE=Process`
  направляют их во временный каталог (см. `Tests/TestHelpers.ps1`). Установщик
  локально не запускайте: он пишет в настоящие Modules и PATH.
- Выпуск делает только CI. В `CHANGELOG.md` раздел `[Unreleased]` переименовывается
  в `## [<версия>] - <дата>`, `ModuleVersion` в манифесте поднимается, затем
  ставится тег `vX.Y.Z` (совпадающий с `ModuleVersion`) и пушится.
  `.github/workflows/release.yml` прогоняет проверки, собирает выпуск с
  `build.ps1 -Release`, публикует модуль в PowerShell Gallery
  (`Publish-PSResource`) и только потом создаёт GitHub Release с
  `EdtWorktree.zip` и `install.ps1`. Нужен секрет репозитория
  `PSGALLERY_API_KEY` (ключ PowerShell Gallery с правом публикации
  `EdtWorktree`). Публикация в Gallery необратима: версию нельзя ни заменить, ни
  вернуть, только выпустить следующую.
- Правила для кода (кодировка UTF-8 с BOM, git только через `Invoke-EdtWtGit`,
  кавычки в `Start-Process`, формат `.location`) - в [AGENTS.md](AGENTS.md).
- Новая подкоманда добавляется в: `ValidateSet` в `Invoke-EdtCommand`, `$known` в
  `src/EdtWorktree/bin/edt.ps1`, `Completers`, `Show-EdtWtUsage`, README, COMMANDS.md и
  `Tests/Contract.Tests.ps1`. Новая публичная функция - ещё и в
  `FunctionsToExport` в `src/EdtWorktree/EdtWorktree.psd1`.

### Карта файлов

- `scripts/install.ps1` - установщик (самодостаточный, работает под `irm | iex`; в выпуск попадает как `install.ps1`).
- `scripts/build.ps1` - сборка выпуска; `scripts/Invoke-EdtWtChecks.ps1` - тесты и анализатор.
- `.github/workflows/` - `checks.yml` (проверки) и `release.yml` (выпуск по тегу).
- `src/EdtWorktree/EdtWorktree.psd1` - манифест; `EdtWorktree.psm1` - загрузка
  файлов Private, Public, Completers (в выпуске склеиваются в один `psm1`); алиас `edt`;
  `EdtWorktree.format.ps1xml` - табличные виды.
- В `src/EdtWorktree/` одна функция - один файл, имя файла совпадает с именем функции.
- `src/EdtWorktree/Public/` - экспортируемые команды: `Invoke-EdtCommand` (диспетчер
  подкоманд), `Invoke-EdtWorktreeOpen`, `Invoke-EdtWorktreeWarmup`,
  `Invoke-EdtWorktreeAdd`, `Invoke-EdtWorktreeClean`, `Get-EdtWorktreeList`,
  `Update-EdtWtReference`, `Invoke-EdtSetup`, `Get-EdtConfig`/`Set-EdtConfig`,
  `Get-EdtProject`/`Add-EdtProject`/`Set-EdtProject`/`Remove-EdtProject`/`Set-EdtProjectExtension`,
  `Test-EdtEnvironment` (doctor), `Update-EdtSelf`, `Uninstall-EdtWorktree`, `Get-EdtWtContext`.
- `src/EdtWorktree/Private/` - внутренние функции по областям:
  - `src/EdtWorktree/Private/Config` - конфиг v3 и перенос с 2.x;
  - `src/EdtWorktree/Private/Discovery` - проекты в клоне, проект по пути;
  - `src/EdtWorktree/Private/Eclipse` - `.location` и имена проектов рабочей области;
  - `src/EdtWorktree/Private/Git` - git (`Invoke-EdtWtGit`), ветки, worktree;
  - `src/EdtWorktree/Private/Install` - вид установки, shim, ссылка модуля, PATH;
  - `src/EdtWorktree/Private/Interaction` - диалоги и разбор общих ключей;
  - `src/EdtWorktree/Private/Process` - поиск EDT, JVM, запуск GUI, `1cedtcli`, vrunner;
  - `src/EdtWorktree/Private/Workspace` - рабочие области, настройки IDE, справка.
- `src/EdtWorktree/Completers/` - автодополнение `edt`.
- `src/EdtWorktree/bin/edt.ps1`, `src/EdtWorktree/bin/edt.cmd` - вход для любых оболочек и планировщика.
- `src/EdtWorktree/bin/shim/` - шаблон постоянного shim (`edt.cmd` и запускатель `edt.ps1`),
  который `edt setup` и установщик копируют в `%LOCALAPPDATA%\Programs\EdtWorktree\bin`.
- `Tests/` - Pester 5 (`TestHelpers.ps1` - общие помощники).
- `docs/` - `COMMANDS.md` (справочник команд), `superpowers/` (спецификации и планы).
