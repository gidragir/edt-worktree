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
- Перед завершением любых правок всегда выполнять проверку: `pwsh -NoProfile -File Invoke-EdtWtChecks.ps1`.