# ==============================================================================
# EdtWorktree - управление рабочими областями 1C:EDT для git worktree
# ==============================================================================
# Загрузчик модуля: переменные модуля и подключение функций по маске.
# Логика лежит в Private/<Подсистема>/ и Public/ по файлу на функцию.
# ==============================================================================

Set-StrictMode -Version Latest

$script:EdtWtModuleRoot = $PSScriptRoot
# Отметка сборки эталона в корне его рабочей области: ветка, коммит, время.
# В рабочие области веток не копируется.
$script:EdtWtReferenceStampName = '.edtwt-reference.json'
# Пользовательские настройки IDE: тема, шрифты, цвета, раскладка горячих клавиш,
# настройки редактора BSL. Всё это Eclipse хранит per-workspace в .prefs-файлах,
# поэтому каждая новая рабочая область стартует с настройками по умолчанию.
# Файлы, привязанные к конкретному проекту (инфобазы, публикации, серверы,
# порты MCP), сюда намеренно не входят.
$script:EdtWtPortablePrefs = @(
    'org.eclipse.ui.workbench.prefs'              # шрифты, цвета, горячие клавиши, декораторы
    'org.eclipse.ui.prefs'
    'org.eclipse.ui.ide.prefs'
    'org.eclipse.ui.editors.prefs'
    'org.eclipse.ui.navigator.prefs'
    'org.eclipse.ui.genericeditor.prefs'
    'org.eclipse.e4.ui.css.swt.theme.prefs'       # тема оформления
    'org.eclipse.e4.ui.workbench.renderers.swt.prefs'
    'org.eclipse.egit.ui.prefs'
    'com._1c.g5.v8.dt.theming.ui.prefs'
    'com._1c.g5.v8.dt.bsl.ui.prefs'               # редактор встроенного языка
    'com._1c.g5.v8.dt.compare.ui.prefs'
    'com._1c.g5.v8.dt.navigator.ui.navigator.prefs'
    'com._1c.g5.v8.dt.right.ql.ui.prefs'
    'com._1c.g5.v8.dt.ui.language.prefs'
    'com._1c.g5.v8.dt.ui.validation.prefs'
    'com.e1c.edt.ai.ui.prefs'
)

# Функции подключаются по маске: список файлов здесь не хранится.
# Порядок (Private, Public, Completers; внутри - по полному пути) детерминирован;
# функции вызываются только после загрузки модуля, так что порядок на работу не влияет.
# <build:files>
foreach ($dir in 'Private', 'Public', 'Completers') {
    $dirPath = Join-Path $PSScriptRoot $dir
    if (-not (Test-Path -LiteralPath $dirPath)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $dirPath -Recurse -File -Filter *.ps1 | Sort-Object FullName) {
        try {
            . $file.FullName
        } catch {
            $relative = $file.FullName.Substring($PSScriptRoot.Length).TrimStart('\', '/')
            throw "Не удалось загрузить ${relative}: $($_.Exception.Message)"
        }
    }
}
# </build:files>

# Единственное короткое имя: подкоманды вместо отдельных команд.
Set-Alias -Name edt -Value Invoke-EdtCommand

Register-EdtWtCompleters