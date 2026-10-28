# AGENTS.md — Правила для AI-ассистентов в репозитории edt-worktree

Модуль PowerShell `EdtWorktree` управляет рабочими областями (workspace) 1C:EDT для Git-worktree.

## 1. JVM и требования к окружению 1C:EDT

- **JavaFX обязателен**: 1C:EDT требует Java 17 с поддержкой JavaFX (модули `javafx.*`, библиотека `javafx-swt.jar`). Стандартные сборки OpenJDK (Temurin, headless-дистрибутивы) вызывают ошибку *"Поддержка JavaFX не установлена"*. Допустимы только полные сборки (Azul Zulu FX, Axiom JDK Full, Liberica Full).
- **Конфликт реестра Windows**: Eclipse Equinox Launcher опрашивает реестр Windows (`HKLM\SOFTWARE\JavaSoft\Java Runtime Environment`) раньше переменной `PATH`. Если на машине установлена Java 8, лончер падает с *"Incompatible JVM: Version 1.8.0"*.
- **Явный проброс `-vm`**: Функция `Start-EdtWtGui` обязана явно вычислять путь к `jvm.dll` (из `$env:JAVA_HOME` или стандартного `C:\Program Files\Zulu\zulu-17`) и передавать параметр `-vm` перед `-data`. Это делает запуск автономным и независимым от прав администратора на редактирование `1cedt.ini` или глобального реестра Windows.

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
- Перед завершением любых правок всегда выполнять проверку: `pwsh -NoProfile -File Invoke-EdtWtChecks.ps1`.

## 4. Eclipse Workspace `.location` и привязка проектов

- **Формат файла `.location`**: Eclipse Core Resources хранит привязки внешних проектов в файлах `.metadata\.plugins\org.eclipse.core.resources\.projects\<project>\.location`. Формат состоит из заголовка (16 байт), UTF-8 строки с префиксом `URI//` и неизменяемого хвоста. Повреждение заголовка или хвоста ломает проект.
- **Обязательное экранирование пробелов (`%20`)**: При парсинге `.location` класс Eclipse `LocalMetaArea.readPrivateDescription` вызывает `java.net.URI.create(storedValue.substring(5))`. Неэкранированные пробелы в путях вызывают `IllegalArgumentException`, из-за чего Eclipse сбрасывает `locationURI` на каталог по умолчанию внутри workspace (`<workspace>/<project>`), и проекты открываются как пустые желтые папки без метаданных 1С.
- **Преобразование URI**:
  - При записи: всегда экранировать пробелы как `%20` через `ConvertTo-EdtWtEclipseLocationUri` (`URI//file:/D:/projects/worktree/Интеграция%20с%20Каспи/...`), сохраняя символы Unicode/кириллицы.
  - При чтении: всегда разэкранировать строку перед сравнением с путями на диске через `ConvertFrom-EdtWtEclipseLocationUri` (`[System.Uri]::UnescapeDataString`).