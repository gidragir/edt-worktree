# AGENTS.md — Правила для AI-ассистентов в репозитории edt-worktree

Модуль PowerShell `EdtWorktree` управляет рабочими областями (workspace) 1C:EDT для Git-worktree.

## 1. JVM и требования к окружению 1C:EDT

- **JavaFX обязателен**: 1C:EDT требует Java 17 с поддержкой JavaFX (модули `javafx.*`, библиотека `javafx-swt.jar`). Стандартные сборки OpenJDK (Temurin, headless-дистрибутивы) вызывают ошибку *"Поддержка JavaFX не установлена"*. Допустимы только полные сборки (Azul Zulu FX, Axiom JDK Full, Liberica Full).
- **Конфликт реестра Windows**: Eclipse Equinox Launcher опрашивает реестр Windows (`HKLM\SOFTWARE\JavaSoft\Java Runtime Environment`) раньше переменной `PATH`. Если на машине установлена Java 8, лончер падает с *"Incompatible JVM: Version 1.8.0"*.
- **Выбор JVM для GUI — только через `Resolve-EdtWtGuiJvm`**, порядок: (1) `edt.vm_path` из конфига; (2) если в `1cedt.ini` рядом с `1cedt.exe` уже есть `-vm` — `-vm` не передаётся (ini установщика EDT главнее); (3) `JAVA_HOME`, только если это JDK 17+ с JavaFX (`Test-EdtWtJdkHasJavaFx`); (4) JDK с JavaFX в `Program Files` (Zulu, BellSoft, Axiom, Java); (5) ничего — запуск без `-vm` и предупреждение со ссылкой на `edt doctor`. Если `-vm` передаётся, то перед `-data`. Все запуски GUI (включая перезапуск после `edt add`) идут через `Start-EdtWtGui`; прямой `Start-Process` IDE запрещён.
- **JVM для 1cedtcli**: `-vm` 1cedtcli не принимает (отдаёт его в java, *"Unrecognized option: -vm"*). `Invoke-EdtWtCli` берёт JDK из `Resolve-EdtWtGuiJvm` и ставит её `bin` первой в `PATH` и в `JAVA_HOME` дочернего процесса. Без этого лончер находит первый `javaw` из PATH (шим mise, Oracle `java8path`) или Java 8 из реестра и падает с ExitCode 14 за секунду.

## 2. Экранирование аргументов в PowerShell (Start-Process)

- **Строгое правило для путей с пробелами**: Командлет `Start-Process -FilePath ... -ArgumentList $args` не оборачивает элементы массива в кавычки автоматически при передаче в Win32 CreateProcess.
- Любые пути с пробелами (особенно `C:\Program Files\...`), передаваемые как значение ключа, ОБЯЗАНЫ экранироваться кавычками:
  ```powershell
  $guiArgs += @("-vm", "`"$jvmDll`"")
  $guiArgs += @("-data", "`"$($Context.WorkspaceDir)`"")
  ```
  Иначе лончер обрезает путь по первому пробелу (`C:\Program`), завершаясь ошибкой *"No Java virtual machine was found after searching: C:\Program"*.

## 3. Кодировки и статический анализ

- Все `.ps1` и `.psm1` файлы, содержащие кириллицу или не-ASCII символы, сохраняются строго в **UTF-8 с BOM** (правило PSScriptAnalyzer `PSUseBOMForUnicodeEncodedFile`).
- После любой правки таких файлов проверять, что BOM сохранился. При потере — перезаписать через `[IO.File]::WriteAllText($p, $t, [Text.UTF8Encoding]::new($true))`, запуская из файла-скрипта, а не через `pwsh -Command "..."` (там теряются `$переменные`).
- **Вызовы Git строго через `Invoke-EdtWtGit`**: Прямой вызов `git` в модуле запрещён. Все взаимодействия с Git обязаны выполняться через внутреннюю функцию `Invoke-EdtWtGit`. Она изолированно устанавливает `[Console]::OutputEncoding = UTF-8`, передаёт флаг `-c core.quotepath=false` и восстанавливает прежнюю кодировку в `finally`. Иначе кириллические пути и ветки декодируются как cp866 (`╨Ш╨╜╤В...`) и ломают поиск каталогов на диске.
- Перед завершением любых правок всегда выполнять проверку: `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1`.
- Сборка выпуска: `pwsh -NoProfile -File scripts/build.ps1` (склейка в один `psm1`, `out/EdtWorktree.zip`, `out/install.ps1`); перед выпуском — проверки над `out/` с `-ModulePath`: `pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1 -ModulePath out/EdtWorktree/<версия>/EdtWorktree.psd1`.

## 4. Eclipse Workspace `.location` и привязка проектов

- **Формат файла `.location`**: Eclipse Core Resources хранит привязки внешних проектов в файлах `.metadata\.plugins\org.eclipse.core.resources\.projects\<project>\.location`. Формат состоит из заголовка (16 байт), UTF-8 строки с префиксом `URI//` и неизменяемого хвоста. Повреждение заголовка или хвоста ломает проект.
- **Обязательное экранирование пробелов (`%20`)**: При парсинге `.location` класс Eclipse `LocalMetaArea.readPrivateDescription` вызывает `java.net.URI.create(storedValue.substring(5))`. Неэкранированные пробелы в путях вызывают `IllegalArgumentException`, из-за чего Eclipse сбрасывает `locationURI` на каталог по умолчанию внутри workspace (`<workspace>/<project>`), и проекты открываются как пустые желтые папки без метаданных 1С.
- **Преобразование URI**:
  - При записи: всегда экранировать пробелы как `%20` через `ConvertTo-EdtWtEclipseLocationUri` (`URI//file:/D:/projects/worktree/Интеграция%20с%20Каспи/...`), сохраняя символы Unicode/кириллицы.
  - При чтении: всегда разэкранировать строку перед сравнением с путями на диске через `ConvertFrom-EdtWtEclipseLocationUri` (`[System.Uri]::UnescapeDataString`).

## 5. Конфиг пользователя `config.json`

- Один файл: `%APPDATA%\EdtWorktree\config.json` (схема v3, `version: 3`), путь — `Get-EdtWtUserConfigPath`, переопределяется `EDT_CONFIG_PATH`. Конфига в репозиториях проектов нет.
- Пишется только через `Save-EdtWtConfig`: UTF-8 **без** BOM, временный файл + `Move-Item`, схема целиком; ключи, которых модуль не знает, сохраняются.
- Битый JSON — ошибка «Конфиг повреждён», файл не перезаписывается.
- Конфиг 2.x мигрирует при первом чтении (`Invoke-EdtWtConfigMigration`), оригинал — `config.json.v2.bak`, `~/.config/1c/projects.json` не трогается. Автодополнение читает конфиг только без миграции и записи.
- Тесты и любой запуск модуля вне Pester при разработке — только с `EDT_CONFIG_PATH` во временном каталоге; PATH и `Modules` в тестах — через `EDT_PATH_SCOPE=Process` и `EDT_MODULES_DIR`.

## 6. Раскладка модуля

- Одна функция - один файл `src/EdtWorktree/{Public|Private/<Подсистема>}/<Имя>.ps1`; имя файла = имя функции. В `Public/` только экспортируемые функции (совпадают с `FunctionsToExport`); приватные - в `Private/<Подсистема>/` (Config, Git, Eclipse, Process, Workspace, Discovery, Interaction, Install). Код вне функций и `Set-StrictMode` в этих файлах запрещены; переменные модуля - только в `EdtWorktree.psm1`. Файлы подключаются по маске, список в `.psm1` не хранится. Проверяет `Tests/Layout.Tests.ps1`.

## 7. Раскладка репозитория, shim и выпуск

- Репозиторий: `src/EdtWorktree/` - модуль (манифест, `Public/`, `Private/`, `Completers/`, `bin/`, `bin/shim/`); `scripts/` - `install.ps1` (установщик, самодостаточный), `build.ps1` (сборка выпуска в `out/`), `Invoke-EdtWtChecks.ps1`; `Tests/` - Pester 5; `.github/workflows/` - `checks.yml` и `release.yml`.
- В PATH пользователя попадает только каталог постоянного shim `%LOCALAPPDATA%\Programs\EdtWorktree\bin` (`edt.cmd`, `edt.ps1`), а не `bin` клона или каталог версии модуля: shim берёт наибольшую установленную версию. Каталог 3.0 `%LOCALAPPDATA%\EdtWorktree` (клон) занят старой установкой, shim туда и внутрь любого клона EdtWorktree (`.git` и `EdtWorktree.psd1` в корне или в `src\EdtWorktree`) не ставится. Статус shim в `edt doctor` - `ok`/`warn`.
- Виды установки: Gallery, Zip, Dev, Legacy (3.0). `self-update` и `uninstall` действуют по виду; конфиг, клоны проектов, worktree и рабочие области не трогаются (конфиг - только `uninstall -Purge`).
- Выпуск делает только CI по тегу `vX.Y.Z`, совпадающему с `ModuleVersion` (`release.yml`: проверки, `build.ps1 -Release`, `Publish-PSResource`, затем GitHub Release). Не ставить теги, не пушить и не публиковать в Gallery вручную без прямого указания пользователя: публикация необратима, нужен секрет `PSGALLERY_API_KEY`.
- Локально установщик не запускать (он пишет в настоящие `Documents\PowerShell\Modules` и PATH); его тесты используют `EDT_MODULES_DIR`, `EDT_SHIM_DIR`, `EDT_PATH_SCOPE=Process`.
