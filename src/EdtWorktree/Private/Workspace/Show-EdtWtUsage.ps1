function Show-EdtWtUsage {
    <#
      Краткая справка команды edt.
    #>
    [CmdletBinding()]
    param()

    Write-Host @'
edt <подкоманда> [аргументы] [ключи]

Первые шаги:
  edt setup                             Задать каталоги, найти EDT, зарегистрировать клоны.
         Без диалога: -ReposRoot <путь> -WorktreesRoot <путь> -WorkspacesRoot <путь>
         Ключи: -NoProjects (не предлагать регистрацию), -WhatIf, -Yes
  edt doctor                            Проверить окружение и проекты; у каждой проблемы
         указана команда исправления. Код возврата 1 при ошибках.

Проекты:
  project list [проект]                 Таблица проектов: ветка, расширения, эталон.
  project add [имя]                     Зарегистрировать клон из repos_root (без имени - все
         новые). Без диалога: -Extensions all|none|<имена>, -RefBranch <ветка>, -CfProject <путь>
  project ext <проект> [+имя] [-имя]    Рабочие расширения: без правок - список с отметками,
         с правками (+cfe_new -cfe_old) - без диалога.
  project set <проект> -RefBranch <ветка> | -CfProject <путь>
  project remove <проект>               Убрать из конфига (файлы не удаляются).

Работа:
  open   [проект ветка]                 Открыть рабочую область и запустить IDE.
         Без аргументов берётся текущий каталог worktree. Ветка без слеша получает
         префикс git.branch_prefix (feature/), недостающий worktree создаётся.
         Ключи: -Refresh, -NoGui, -WhatIf, -Yes

  warmup [проект]                       Собрать эталон из клона (на ref_branch) с валидацией.
         Занятый эталон не трогается. Ключи: -WhatIf, -Yes

  add    <расширения>                   Подключить расширения к рабочей области текущего
         worktree. Имена: cfe_x или относительный путь. Ключи: -NoGui, -WhatIf, -Yes

  remove [проект] [ветка]               Удалить рабочую область и git worktree.
         Ключи: -WhatIf, -Yes

  status [проект]                       Что открыто и какими процессами занято.

  update [проекты]                      Подтянуть ref_branch клона и пересобрать эталоны.
         Для запуска по расписанию: занятые и конфликтные проекты пропускаются.
         Ключи: -SkipGit, -WhatIf, -Yes

  vr     <аргументы vrunner>            Запустить vrunner в текущем worktree.
         Вызывать из каталога worktree. Аргументы уходят в vrunner как есть,
         код возврата vrunner сохраняется.
         Настройки базы: autumn-properties.json в корне worktree (не меняется).
         Рабочая область EDT этого worktree передаётся через VRUNNER_EDT_WORKSPACE,
         VRUNNER_EDT_PATH, VRUNNER_EDT_VMARGS, VRUNNER_EDT_TIMEOUT; уже заданные
         вами VRUNNER_EDT_* не перезаписываются.
         cf load и cfe load идут с --increment (инкрементальная загрузка).
         Ключ: -Full - полная загрузка (первая загрузка в пустую базу, сомнения
         в рассинхроне); в vrunner не передаётся.
         Нужна область: если её нет, выполните edt open -NoGui.

Настройка и обслуживание:
  config [show | path | set <ключ> <значение>]
         Показать настройки, путь к config.json, изменить один ключ
         (например edt config set edt.max_heap 16g; null сбрасывает значение).
  self-update                           Обновить модуль из его Git-репозитория.
  uninstall [-Purge]                    Убрать модуль из Modules и bin из PATH; конфиг,
         клоны и рабочие области не трогаются. -Purge удаляет и каталог установки
         с конфигурацией. Ключи: -WhatIf, -Yes

Ключи пишутся как -NoGui или --no-gui. Изменяющие команды понимают -WhatIf
(--dry-run) и -Yes (без вопросов).

Примеры:
  edt project add ka-intertop-4edt
  edt project ext ka-intertop-4edt +cfe_ad -cfe_old
  edt open ka-intertop-4edt TASK-123
  edt open -NoGui                       открыть текущий worktree без IDE
  edt warmup ka-intertop-4edt
  edt add cfe_esf
  edt remove TASK-123 -WhatIf
  edt vr cf load src/cf                 инкрементально
  edt vr cf load src/cf -Full           полностью
  edt status | Where-Object Locked -eq 'LOCK'

Подробно: Get-Help Invoke-EdtCommand -Full
'@
}
