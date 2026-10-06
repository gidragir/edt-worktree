# Команды edt

Шаблоны вызовов для рабочих областей 1C:EDT. Плейсхолдеры: `$project` — имя из
`projects.json`, `$task` — задача без префикса `feature-`, `$extension` — имя
расширения, `$heap` — размер кучи вида `12g`.

## Открыть задачу
Создаёт область из эталона и запускает IDE
```snippet-template
edt open $project $task
```

## Открыть текущую
Из каталога worktree, проект и задача не нужны
```snippet-template
edt open
```

## Больше памяти
IDE стартует с увеличенной кучей вместо штатных 4g
```snippet-template
edt open $project $task -GuiMaxHeap $heap
```

## Только конфигурация
Расширения не подключаются, IDE грузится быстрее
```snippet-template
edt open $project $task none
```

## Изменённые расширения
Подключает только затронутые веткой относительно pre-prod
```snippet-template
edt open $project $task changed
```

## Выбранные расширения
Подключает перечисленные расширения вместо всех активных
```snippet-template
edt open $project $task $extension
```

## Без IDE
Готовит область молча, без запуска графической оболочки
```snippet-template
edt open $project $task -NoGui
```

## Пересобрать область
Удаляет область и клонирует заново из эталона
```snippet-template
edt open $project $task -Refresh
```

## Проверить план
Печатает будущие действия, ничего не изменяя на диске
```snippet-template
edt open $project $task -Refresh -WhatIf
```

## Прогреть эталон
Собирает эталон, из которого клонируются все области
```snippet-template
edt warmup $project -Force
```

## Прогреть проверки
Дополнительно строит derived-данные, ускоряя первый запуск IDE
```snippet-template
edt warmup $project -Force -Validate
```

## Эталон конфигурации
Прогрев без расширений, для проектов без них
```snippet-template
edt warmup $project none
```

## Подключить расширение
Доимпорт в готовую область, IDE перезапускается автоматически
```snippet-template
edt add $extension
```

## Подключить принудительно
Закрывает работающую IDE без вопроса о несохранённом
```snippet-template
edt add $extension -Force
```

## Подключить извне
Доимпорт в область другой задачи, из любого каталога
```snippet-template
edt add $project $task $extension
```

## Удалить область
Убирает рабочую область и git worktree завершённой задачи
```snippet-template
edt remove $project $task
```

## Удалить молча
Без подтверждения, для скриптов и пакетной уборки
```snippet-template
edt remove $project $task -Yes
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
Ограничивает сводку одним проектом из реестра
```snippet-template
edt status $project
```

## Обновить эталоны
Подтягивает pre-prod и пересобирает эталоны всех проектов
```snippet-template
edt update
```

## Обновить выборочно
Только указанные проекты, остальные не трогаются
```snippet-template
edt update $project
```

## Обновить полностью
С прогревом проверок и без вопросов, для расписания
```snippet-template
edt update -Validate -Yes
```

## Пересобрать эталоны
Без git: пересборка из текущего состояния веток
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
Точка входа без профиля: cmd, планировщик, CI
```snippet-template
pwsh -NoProfile -File "$HOME\.config\bin\edt.ps1" open $project $task -NoGui
```

## Ночная подготовка
Команда для задания планировщика: обновляет все эталоны
```snippet-template
pwsh -NoProfile -File "$HOME\.config\bin\edt.ps1" update -Validate -Yes
```

## Создать задание
Регистрирует ежедневное обновление эталонов в три часа
```snippet-template
Register-ScheduledTask -TaskName "EDT update" -Action (New-ScheduledTaskAction -Execute pwsh.exe -Argument ('-NoProfile -File ' + "$HOME\.config\bin\edt.ps1" + ' update -Validate -Yes')) -Trigger (New-ScheduledTaskTrigger -Daily -At 03:00) -Settings (New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 4))
```

## Настройка окружения (мастер)
Запуск интерактивного мастера первичной настройки и автопоиска EDT
```snippet-template
edt config init
```

## Просмотр текущей конфигурации
Показывает пути машины и настройки активного проекта
```snippet-template
edt config
```

## Инициализация проекта 1C
Создаёт `.edt-worktree.json` в корне текущего Git-репозитория
```snippet-template
edt init
```

## Обновление модуля
Обновляет модуль из Git-репозитория и перезагружает в сессии
```snippet-template
edt self-update
```

## Проверки модуля
Прогоняет тесты Pester и статический анализ кода
```snippet-template
pwsh -NoProfile -File Invoke-EdtWtChecks.ps1
```


