# Команды edt

Шаблоны вызовов для рабочих областей 1C:EDT. Плейсхолдеры: `$project` — имя
проекта (папка клона в `repos_root`), `$branch` — ветка задачи (`TASK-123`
превращается в `feature/TASK-123`, полное имя вроде `bugfix/x` берётся как есть),
`$extension` — имя папки расширения (`cfe_ad`) или путь относительно клона.

## Установить
Ставит модуль, добавляет edt в PATH и запускает мастер настройки
```snippet-template
irm https://raw.githubusercontent.com/gidragir/edt-worktree/main/scripts/install.ps1 | iex
```

## Первичная настройка
Каталоги клонов, worktree и рабочих областей, поиск EDT, регистрация клонов
```snippet-template
edt setup
```

## Настройка без диалога
Для скриптов и агентов: каталоги задаются ключами, проекты не предлагаются
```snippet-template
edt setup -ReposRoot D:\projects -WorktreesRoot D:\projects\worktree -WorkspacesRoot D:\workspaces -NoProjects
```

## Проверить окружение
Ищет проблемы окружения и проектов и печатает команды исправления
```snippet-template
edt doctor
```

## Список проектов
Эталонная ветка, ветка клона, рабочие расширения, наличие эталона
```snippet-template
edt project list
```

## Зарегистрировать проект
Находит конфигурацию и расширения в клоне, расширения выбираются номерами
```snippet-template
edt project add $project
```

## Зарегистрировать все клоны
Проходит по всем незарегистрированным клонам в repos_root
```snippet-template
edt project add
```

## Зарегистрировать без диалога
Для неинтерактивного запуска: расширения all, none или список имён
```snippet-template
edt project add $project -Extensions all -RefBranch develop
```

## Рабочие расширения
Список найденных расширений с отметками, ввод номеров заменяет набор
```snippet-template
edt project ext $project
```

## Добавить или убрать расширение
Без диалога: плюс включает расширение в эталон, минус выключает
```snippet-template
edt project ext $project +$extension
```

## Сменить эталонную ветку
Эталон будет собираться с другой ветки клона
```snippet-template
edt project set $project -RefBranch develop
```

## Убрать проект
Удаляет проект из конфига, клон и области остаются на диске
```snippet-template
edt project remove $project
```

## Прогреть эталон
Собирает эталон из клона на эталонной ветке, с валидацией
```snippet-template
edt warmup $project
```

## Открыть задачу
Создаёт worktree и область из эталона, запускает IDE
```snippet-template
edt open $project $branch
```

## Открыть текущую
Из каталога worktree, проект и ветка не нужны
```snippet-template
edt open
```

## Без IDE
Готовит область молча, без запуска графической оболочки
```snippet-template
edt open $project $branch -NoGui
```

## Пересобрать область
Удаляет область и клонирует заново из эталона
```snippet-template
edt open $project $branch -Refresh
```

## Проверить план
Печатает будущие действия, ничего не изменяя на диске
```snippet-template
edt open $project $branch -Refresh -WhatIf
```

## Подключить расширение
Доимпорт в область текущего worktree, IDE перезапускается автоматически
```snippet-template
edt add $extension
```

## Удалить область
Убирает рабочую область и git worktree завершённой задачи
```snippet-template
edt remove $project $branch
```

## Удалить молча
Без подтверждения, для скриптов и пакетной уборки
```snippet-template
edt remove $project $branch -Yes
```

## Показать области
Список областей, их путей и занявших процессов
```snippet-template
edt status
```

## Занятые области
Только те, что заблокированы работающей IDE
```snippet-template
edt status | Where-Object Locked -eq 'LOCK'
```

## Области проекта
Ограничивает сводку одним проектом
```snippet-template
edt status $project
```

## Обновить эталоны
Подтягивает эталонные ветки клонов и пересобирает эталоны всех проектов
```snippet-template
edt update
```

## Обновить выборочно
Только указанные проекты, остальные не трогаются
```snippet-template
edt update $project
```

## Пересобрать эталоны
Без git: пересборка из текущего состояния клонов
```snippet-template
edt update -SkipGit
```

## Проверить обновление
Показывает, какие проекты обновятся, какие пропустятся
```snippet-template
edt update -WhatIf
```

## vrunner в worktree
Настройки базы из autumn-properties.json, рабочая область EDT этого worktree
```snippet-template
edt vr validate edt
```

## Загрузка конфигурации
cf load и cfe load идут инкрементально, --increment добавляется сам
```snippet-template
edt vr cf load src/cf
```

## Полная загрузка
Отключает инкрементальную подстановку
```snippet-template
edt vr cf load src/cf -Full
```

## Показать настройки
Пути, найденный EDT и зарегистрированные проекты
```snippet-template
edt config show
```

## Путь к конфигу
Где лежит config.json
```snippet-template
edt config path
```

## Изменить настройку
Точечная правка ключа с проверкой формата; null возвращает автоопределение
```snippet-template
edt config set edt.max_heap 16g
```

## Указать EDT вручную
Если автопоиск не нашёл 1cedtcli
```snippet-template
edt config set edt.cli_path "C:\Program Files\1C\1CE\components\1c-edt-2024.2.10+1-x86_64\1cedtcli.exe"
```

## Указать JVM для IDE
JDK 17 с JavaFX, если автовыбор не подошёл
```snippet-template
edt config set edt.vm_path "C:\Program Files\Zulu\zulu-17\bin\server\jvm.dll"
```

## Обновление модуля
Обновляет модуль из Git-репозитория и перезагружает в сессии
```snippet-template
edt self-update
```

## Удалить модуль
Убирает ссылку модуля и bin из PATH; конфиг, клоны и области остаются
```snippet-template
edt uninstall
```

## Удалить полностью
Ещё и каталог установки с конфигом
```snippet-template
edt uninstall -Purge
```

## Справка команд
Список подкоманд, ключей и примеров вызова
```snippet-template
edt help
```

## Справка операции
Полное описание параметров конкретной операции модуля
```snippet-template
Get-Help Invoke-EdtWorktreeOpen -Full
```

## Запуск извне
Из cmd, bash, nushell или агента: bin\edt.cmd в PATH
```snippet-template
edt open $project $branch -NoGui
```

## Ночная подготовка
Команда для задания планировщика: обновляет все эталоны
```snippet-template
pwsh -NoProfile -File "$env:LOCALAPPDATA\EdtWorktree\bin\edt.ps1" update -Yes
```

## Создать задание
Регистрирует ежедневное обновление эталонов в три часа
```snippet-template
Register-ScheduledTask -TaskName "EDT update" -Action (New-ScheduledTaskAction -Execute pwsh.exe -Argument ('-NoProfile -File "' + "$env:LOCALAPPDATA\EdtWorktree\bin\edt.ps1" + '" update -Yes')) -Trigger (New-ScheduledTaskTrigger -Daily -At 03:00) -Settings (New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 4))
```

## Проверки модуля
Прогоняет тесты Pester и статический анализ кода
```snippet-template
pwsh -NoProfile -File scripts/Invoke-EdtWtChecks.ps1
```
