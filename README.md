# EdtWorktree и команда `edt`

Карта модуля для быстрой ориентации. Шаблоны вызовов: [COMMANDS.md](COMMANDS.md).
Справка по операции: `Get-Help Invoke-EdtWorktreeOpen -Full`.

## Что это

Управление рабочими областями (workspace) 1C:EDT для git worktree: одна область
на задачу, клонируется из прогретого эталона, чтобы не строить индексы заново.
Плюс запуск `vrunner` с областью текущего worktree (`edt vr`).

## Точки входа

| Способ | Файл | Когда |
|---|---|---|
| `edt ...` в pwsh | алиас на `Invoke-EdtCommand`, профиль импортирует модуль через `powershell/conf.d/08-edt-worktree.ps1` | интерактивно |
| `pwsh -NoProfile -File ~/.config/bin/edt.ps1 ...` | [bin/edt.ps1](../../../bin/edt.ps1) | nushell, cmd, планировщик, CI. Коды возврата: 0 успех, 1 сбой, 2 ошибка вызова; для `vr` код vrunner отдаётся как есть |
| `wt-*`, `edt-wt-*` | `Invoke-EdtWtLegacyCommand` | устаревшие имена, печатают замену |

Алиас `edt` существует только в интерактивном `pwsh` с профилем. Агенты, nushell,
bash и cmd его не видят: для них нужен `~/.config/bin/edt.cmd` (шим над `edt.ps1`)
и каталог `~/.config/bin` в PATH. `.ps1` в PATHEXT нет, поэтому без шима `edt`
по имени не запускается. Проверка: `where.exe edt`.

## Подкоманды

| Команда | Операция (Public/) | Суть |
|---|---|---|
| `open [проект задача] [расширения]` | `Invoke-EdtWorktreeOpen` | создаёт worktree (если нет), клонирует область из эталона, перепривязывает проекты, доимпортирует недостающее, переносит настройки IDE, запускает IDE |
| `warmup [проект] [расширения]` | `Invoke-EdtWorktreeWarmup` | собирает эталон `_reference_preprod` |
| `add [проект задача] <расширения>` | `Invoke-EdtWorktreeAdd` | доимпорт расширений; IDE закрывается и поднимается обратно |
| `remove [проект] [задача]` | `Invoke-EdtWorktreeClean` | удаляет область и git worktree; эталон защищён |
| `status [проект]` | `Get-EdtWorktreeList` | области, пути, `LOCK`, занявшие процессы; возвращает объекты |
| `update [проекты]` | `Update-EdtWtReference` | fetch + ff-only pre-prod и пересборка эталонов; для расписания |
| `config [get/set/init]` | `Get-EdtConfig` / `Set-EdtConfig` / `Initialize-EdtConfig` | просмотр, установка параметров или запуск визарда с автопоиском EDT |
| `init [cf_project]` | `New-EdtProjectConfig` | создать файл проекта `.edt-worktree.json` в корне git-репозитория |
| `self-update` | `Update-EdtSelf` | обновить модуль из исходного Git-репозитория |
| `vr <аргументы vrunner>` | `Invoke-EdtWtVrunner` (Private) | vrunner с областью этого worktree, см. ниже |

Общие ключи: `-WhatIf`, `-Yes` (= `-Confirm:$false`), `-MaxHeap 12g` (куча headless
1cedtcli), у `open` ещё `-GuiMaxHeap`, `-NoGui`, `-Refresh`. Ключи пишутся как
`-Refresh` или `--refresh`. Режимы расширений: `all` (по умолчанию), `none`,
`changed` (затронутые веткой относительно pre-prod) или список имён.

## Конфигурация (2 уровня)

1. **Уровень машины (пользователя)**: `%APPDATA%\EdtWorktree\config.json` (управляется через `edt config` или `Initialize-EdtConfig`).
   Хранит пути (`projects_root`, `worktree_root`, `workspaces_root`), путь к `1cedtcli`, JVM-лимиты и донора настроек.
   *(Для обратной совместимости сохраняется fallback на `~/.config/1c/projects.json`).*
2. **Уровень проекта**: файл `.edt-worktree.json` в корне Git-репозитория проекта 1С (создаётся через `edt init`).
   Хранит метаданные проекта: `cf_project`, `reference_branch`, `v8version`, `active_extensions`, `ibconnection`.
   Когда файл есть в репозитории, проект не требует ручной регистрации на машине разработчика.

## Установка для разработчика

В каталоге модуля запустить:
```powershell
pwsh -NoProfile -File scripts/install.ps1
```
Скрипт создаст ссылку модуля в `Documents\PowerShell\Modules\EdtWorktree`, добавит CLI-шим `bin` в `PATH` пользователя и запустит мастер `Initialize-EdtConfig` с автопоиском EDT.

## Раскладка на диске

- Область worktree: `<worktree.root_dir>\<проект>\<ветка с дефисом>`, по умолчанию
  `D:\workspaces\worktree\my-project\feature-TASK-123` (`/` в имени ветки
  заменяется на `-`, `ConvertTo-EdtWtSafeName`).
- Эталон: `<root_dir>\<проект>\_reference_preprod` (клонируется robocopy).
- Git worktree: `D:\projects\worktree\<проект>\<задача>`, основной репозиторий
  `D:\projects\<проект>` (константа `EdtWtWorktreeRoot` в `_Variables.ps1`).
  Не путать с `root_dir` для областей: это разные каталоги.
- Эталонная ветка: `worktree.reference_branch` (pre-prod).
- Блокировка области: `.metadata\.lock`, её держит работающая IDE.

## `edt vr`: vrunner + область EDT

`autumn-properties.json` лежит в корне репозитория (локальный, в git не попадает,
содержит пароль базы) и даёт vrunner настройки базы. Файл не меняется.

Обёртка запускает `vrunner` в корне worktree и выставляет на время вызова:

| Переменная | Значение |
|---|---|
| `VRUNNER_EDT_WORKSPACE` | область текущего worktree |
| `VRUNNER_EDT_PATH` | `1cedtcli` из `projects.json` |
| `VRUNNER_EDT_VMARGS` | только `-Xmx<N>g` (как vrunner разбирает несколько аргументов в переменной, не проверено) |
| `VRUNNER_EDT_TIMEOUT` | `timeouts.export_batch_sec` |

Уже заданные пользователем `VRUNNER_EDT_*` не перезаписываются. Без
`autumn-properties.json` или без созданной области выдаётся ошибка (код 2),
область создаётся `edt open -NoGui`.

Для `cf load` и `cfe load` автоматически добавляется `--increment`; `-Full`
отключает (нужно для первой загрузки в пустую базу). Ключ `-Full` в vrunner не уходит.
Логика в `Resolve-EdtWtVrunnerPlan` (чистая, покрыта тестами), запуск в `Invoke-EdtWtVrunner`.

Не сделано: выбор файлов по `git diff` через `--list`, блокировка общей базы,
краткая сводка результата тестов.

## Карта файлов

- `EdtWorktree.psm1`: загрузка (сначала `Private/_Variables.ps1`, затем Private, Public, Completers), алиас `edt`, старые имена.
- `EdtWorktree.psd1`: список экспортируемых функций; новую публичную функцию нужно добавить и сюда, и в `Tests/Contract.Tests.ps1`.
- `Public/`: операции (по файлу на функцию). `Invoke-EdtCommand` только разбирает аргументы и диспетчеризует.
- `Private/`, самое нужное:
  - `Resolve-EdtWtTarget`: разбор `[проект задача]`, `Invoke-EdtWtInLocation`;
  - `Resolve-EdtWtWrapperArgs`: разбор ключей (для `vr` не используется);
  - `Initialize-EdtWtWorkspace`: клонирование эталона, `-Refresh`;
  - `Repair-EdtWtWorkspaceLocations`, `Set/Get-EdtWtLocationUri`: перепривязка проектов на текущий worktree;
  - `Get-EdtWtImportTargets`, `New-EdtWtBatch`, `Invoke-EdtWtCli`: пакет команд и запуск `1cedtcli` (headless);
  - `Resolve-EdtWtExtensionList`: режимы `all/none/changed`;
  - `Resolve-EdtWtJvmArgs` (headless), `Resolve-EdtWtGuiVmArgs`, `Start-EdtWtGui` (IDE);
  - `Stop-EdtWtProcesses`, `Get-EdtWtWorkspaceProcesses`: процессы, занявшие область;
  - `Update-EdtWtBranch`, `Test-EdtWtWorkspaceFreshness`: обновление эталона и проверка свежести клона;
  - `Copy-EdtWtPreferences`, `Get-EdtWtPrefsSource`: перенос настроек IDE.
- `Completers/`: автодополнение `edt`.
- `Tests/`: Pester 5; запуск и анализатор: `pwsh -NoProfile -File Invoke-EdtWtChecks.ps1`.

## Правила при доработке

- Логику в профиль оболочки не класть: она должна работать из `pwsh -NoProfile`.
- Новые `.ps1` с кириллицей сохранять в UTF-8 с BOM (иначе PSScriptAnalyzer падает).
- Изменяющие команды поддерживают `-WhatIf`; удаление необратимо, подтверждение по умолчанию.
- Подкоманда добавляется в: `ValidateSet` в `Invoke-EdtCommand`, `$known` в `bin/edt.ps1`,
  оба списка в `Completers`, `Show-EdtWtUsage`, `COMMANDS.md`, тест контракта.

## Смежное

- `1c/projects.json` читают также `nushell/custom/1c.nu` и `powershell/conf.d/07-1c.ps1` (`update-ib`: своя инкрементальная загрузка через `--ibcmd`).
- Справочники в `temp/`: `vrunner_usage_guide.md`, `1c_edt_cli_usage_guide.md`, `1c_standalone_server_ibsrv_ibcmd.md`.
- vrunner MCP подключён через `.mcp.json` (`vrunner-mcp`).
