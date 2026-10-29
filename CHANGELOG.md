# Changelog

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версии — по [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

### Changed
- `edt warmup` сначала подтягивает эталонную ветку клона (fetch и перемотка вперёд с `git.remote`); грязный клон или расхождение с remote - отказ, эталон не трогается. Ключ `-SkipGit` собирает из текущего состояния клона.
- Батч прогрева: после импорта `build --yes true` для всех проектов, затем `validate`. Раньше 1cedtcli закрывался посреди фонового расчёта, а проекты с именем не по каталогу (`retail` в `src/cf_edt`) не проверялись вовсе, и проверку с индексацией доделывал GUI при первом открытии ветки.
- Эталон собирается в `_reference.building` и заменяет прежний только после сборки; прежний доступен для `edt open` до конца сборки. Проект без результатов проверки - ошибка «Эталон собран не полностью», прежний эталон остаётся.
- `edt update` не пересобирает эталон, уже собранный с текущего коммита (статус `current`); `-SkipGit` пересобирает все.
- При перепривязке проекта на worktree убирается устаревшая привязка EGit (`.gitdir` старого клона), из-за которой EGit при старте писал ошибку в журнал.

### Added
- `edt.prefs_source` принимает файл экспорта настроек EDT (`.epf`): ключи рабочей области применяются к эталону и к областям веток, один раз на версию файла; открытая в EDT область пропускается.
- Отметка сборки эталона `.edtwt-reference.json` (ветка, коммит, время); `edt open` предупреждает, если эталон отстал от `<remote>/<ref_branch>` или собран без отметки.

## [4.0.0] - 2026-10-29

Выпуск 4.0.0: модуль устанавливается из PowerShell Gallery или из zip выпуска GitHub. Установка 3.0 (клон репозитория) заменяется повторным запуском установки; `edt self-update` из 3.0 новый модуль не ставит.

### Changed
- Модуль перенесён в `src/EdtWorktree/`, одна функция — один файл (`Public/`, `Private/`, `Completers/`).
- Манифест: `CompatiblePSEditions`, `Copyright`, `ProjectUri`, `LicenseUri`, `ReleaseNotes`, теги `Windows` и `PSEdition_Core`.
- Установщик `scripts/install.ps1` ставит модуль из zip выпуска в `Modules\EdtWorktree\<версия>` (другие версии остаются), из локального zip (`-ZipPath`, `EDT_INSTALL_ZIP`), архива ветки (`-Branch`) или ссылкой на клон разработчика (`-Dev`, `EDT_INSTALL_DEV`) и ставит shim `edt`. Ссылка старой установки 3.0 и её `bin` в PATH снимаются, клон не трогается. git для установки больше не нужен; `-InstallDir`, `-RepoUrl` и `EDT_INSTALL_DIR` удалены.

### Added
- CI: проверки над `src/` и над собранным модулем, установка из zip; выпуск по тегу `v*` (`.github/workflows/release.yml`): публикация в PowerShell Gallery, затем GitHub Release с `EdtWorktree.zip` и `install.ps1`.
- Постоянный shim `edt` в `%LOCALAPPDATA%\Programs\EdtWorktree\bin` (`edt.cmd` и запускатель `edt.ps1`): не зависит от версии модуля, берёт наибольшую установленную; ставится командой `edt setup`, проверяется в `edt doctor`. Внутрь клона EdtWorktree (в том числе клона 3.0 в `%LOCALAPPDATA%\EdtWorktree`) shim не ставится; посторонние репозитории выше по пути (dotfiles в профиле) не мешают.
- Табличные виды (`EdtWorktree.format.ps1xml`) для строк `status`, `update`, `project`, `config`, `doctor`: типы `EdtWorktree.Worktree`, `.DoctorCheck`, `.Project`, `.ConfigSummary`, `.ReferenceUpdate`.
- Лицензия MIT (`LICENSE`).
- `self-update` и `uninstall` определяют вид установки (Dev, Legacy, Gallery, Zip) и действуют по-своему: Update-PSResource, установщик из релиза, `git pull` в клоне разработчика; удаление модуля, shim и (с `-Purge`) чистого клона.
- Настройки редактора для разработчиков (`.vscode/settings.json`, `.vscode/extensions.json`).
- Сборка выпуска `scripts/build.ps1`: однофайловый `EdtWorktree.psm1`, `out/EdtWorktree.zip`, `out/install.ps1`, заметки выпуска из `CHANGELOG.md` (`-Release`).
