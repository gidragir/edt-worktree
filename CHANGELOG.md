# Changelog

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версии — по [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

### Changed
- Модуль перенесён в `src/EdtWorktree/`, одна функция — один файл (`Public/`, `Private/`, `Completers/`).
- Манифест: `CompatiblePSEditions`, `Copyright`, `ProjectUri`, `LicenseUri`, `ReleaseNotes`, теги `Windows` и `PSEdition_Core`.
- Установщик `scripts/install.ps1` ставит модуль из zip выпуска в `Modules\EdtWorktree\<версия>` (другие версии остаются), из локального zip (`-ZipPath`, `EDT_INSTALL_ZIP`), архива ветки (`-Branch`) или ссылкой на клон разработчика (`-Dev`, `EDT_INSTALL_DEV`) и ставит shim `edt`. Ссылка старой установки 3.0 и её `bin` в PATH снимаются, клон не трогается. git для установки больше не нужен; `-InstallDir`, `-RepoUrl` и `EDT_INSTALL_DIR` удалены.

### Added
- Постоянный shim `edt` в `%LOCALAPPDATA%\Programs\EdtWorktree\bin` (`edt.cmd` и запускатель `edt.ps1`): не зависит от версии модуля, берёт наибольшую установленную; ставится командой `edt setup`, проверяется в `edt doctor`. Внутрь git-репозитория (в том числе клона 3.0 в `%LOCALAPPDATA%\EdtWorktree`) shim не ставится.
- Табличные виды (`EdtWorktree.format.ps1xml`) для строк `status`, `update`, `project`, `config`, `doctor`: типы `EdtWorktree.Worktree`, `.DoctorCheck`, `.Project`, `.ConfigSummary`, `.ReferenceUpdate`.
- Лицензия MIT (`LICENSE`).
- `self-update` и `uninstall` определяют вид установки (Dev, Legacy, Gallery, Zip) и действуют по-своему: Update-PSResource, установщик из релиза, `git pull` в клоне разработчика; удаление модуля, shim и (с `-Purge`) чистого клона.
- Настройки редактора для разработчиков (`.vscode/settings.json`, `.vscode/extensions.json`).
- Сборка выпуска `scripts/build.ps1`: однофайловый `EdtWorktree.psm1`, `out/EdtWorktree.zip`, `out/install.ps1`, заметки выпуска из `CHANGELOG.md` (`-Release`).
