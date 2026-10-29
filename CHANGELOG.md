# Changelog

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версии — по [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

### Changed
- Модуль перенесён в `src/EdtWorktree/`, одна функция — один файл (`Public/`, `Private/`, `Completers/`).
- Манифест: `CompatiblePSEditions`, `Copyright`, `ProjectUri`, `LicenseUri`, `ReleaseNotes`, теги `Windows` и `PSEdition_Core`.

### Added
- Табличные виды (`EdtWorktree.format.ps1xml`) для строк `status`, `update`, `project`, `config`, `doctor`: типы `EdtWorktree.Worktree`, `.DoctorCheck`, `.Project`, `.ConfigSummary`, `.ReferenceUpdate`.
- Лицензия MIT (`LICENSE`).
- Настройки редактора для разработчиков (`.vscode/settings.json`, `.vscode/extensions.json`).
