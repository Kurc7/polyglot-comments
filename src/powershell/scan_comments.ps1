#Requires -Version 3.0
<#
scan_comments.ps1 — утилита-сканер комментариев в исходном коде (PowerShell-версия scan_comments.py).

Запуск из корня проекта:
    powershell -ExecutionPolicy Bypass -File scan_comments.ps1
Результат: comments_report.txt в папке запуска (перезаписывается), UTF-8 без BOM, переводы строк LF.
Только стандартные возможности Windows PowerShell 5.1 / PowerShell 7+, внешних зависимостей нет.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---------------------------------------------------------------------------
# Исключения и карта расширений (та же, что в scan_comments.py)
# ---------------------------------------------------------------------------

# Папки, которые не сканируем (сравнение по basename, без учёта регистра)
$ExcludedDirs = @(
    'target', 'build', 'out', '.git', '.idea', 'node_modules',
    'test', 'tests', 'generated', 'gen',
    'generated-sources', 'generated-test-sources'
)

# Карта: расширение (в нижнем регистре) -> стиль комментариев.
#   c — //  /* ... */  /** ... */;  hash — #;  xml — <!-- ... -->
#   sql — -- и /* ... */;  lua — -- и --[[ ... ]];  bat — REM и ::
$CommentSyntax = @{
    '.java' = 'c'; '.js' = 'c'; '.jsx' = 'c'; '.ts' = 'c'; '.tsx' = 'c'
    '.c' = 'c'; '.h' = 'c'; '.cpp' = 'c'; '.hpp' = 'c'; '.cc' = 'c'
    '.cs' = 'c'; '.go' = 'c'; '.kt' = 'c'; '.kts' = 'c'; '.scala' = 'c'
    '.php' = 'c'; '.swift' = 'c'; '.dart' = 'c'; '.rs' = 'c'
    '.css' = 'c'; '.scss' = 'c'; '.less' = 'c'
    '.groovy' = 'c'; '.gradle' = 'c'; '.proto' = 'c'
    '.py' = 'hash'; '.rb' = 'hash'; '.sh' = 'hash'; '.bash' = 'hash'
    '.zsh' = 'hash'; '.yaml' = 'hash'; '.yml' = 'hash'
    '.properties' = 'hash'; '.conf' = 'hash'; '.toml' = 'hash'
    '.ini' = 'hash'; '.r' = 'hash'; '.pl' = 'hash'; '.ps1' = 'hash'
    '.dockerfile' = 'hash'; '.gitignore' = 'hash'; '.env' = 'hash'
    '.tf' = 'hash'
    '.xml' = 'xml'; '.html' = 'xml'; '.htm' = 'xml'; '.xhtml' = 'xml'
    '.svg' = 'xml'; '.jsp' = 'xml'; '.ftl' = 'xml'; '.xsd' = 'xml'
    '.wsdl' = 'xml'; '.pom' = 'xml'; '.vue' = 'xml'; '.svelte' = 'xml'
    '.sql' = 'sql'
    '.lua' = 'lua'
    '.bat' = 'bat'; '.cmd' = 'bat'
}

# Файлы без расширения, определяемые по имени (в нижнем регистре)
$FileNameSyntax = @{ 'dockerfile' = 'hash' }

$ReportName  = 'comments_report.txt'
$QuoteStyles = @('c', 'hash', 'xml', 'sql', 'lua')
$LineTypes   = @('line', 'hash', 'sql', 'lua', 'bat')

# Строгий UTF-8 (бросает исключение на невалидных байтах) и UTF-8 без BOM для отчёта
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
# Лексер
# ---------------------------------------------------------------------------

# Проверка префикса в заданной позиции: .NET String не имеет перегрузки
# StartsWith(string, int), поэтому сравниваем через Substring.
function Test-TextPrefix {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Prefix,
        [int]$Start
    )
    if (($Start + $Prefix.Length) -gt $Text.Length) { return $false }
    return ($Text.Substring($Start, $Prefix.Length) -eq $Prefix)
}

function Get-Comments {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Style
    )

    # Посимвольный лексер с явными состояниями:
    # 0 = CODE, 1 = IN_LINE_COMMENT, 2 = IN_BLOCK_COMMENT, 3 = IN_STRING/IN_CHAR.
    # В строках и символьных литералах делимитеры комментариев не считаются
    # комментариями; экранирование «\\ + символ» покрывает \", \', \\, \\uXXXX.
    # Вложенные /* ... */ не поддерживаются: первый */ закрывает блок.
    $chars = $Text.ToCharArray()
    $n = $chars.Length
    $result = New-Object 'System.Collections.Generic.List[object]'

    $isC = ($Style -eq 'c'); $isHash = ($Style -eq 'hash')
    $isXml = ($Style -eq 'xml'); $isSql = ($Style -eq 'sql')
    $isLua = ($Style -eq 'lua'); $isBat = ($Style -eq 'bat')
    $hasQuotes = ($QuoteStyles -contains $Style)

    # Параметры текущего комментария и литерала
    $cStart = 0; $cLine = 0; $commentType = ''
    $quote = [char]0       # активная кавычка (IN_STRING / IN_CHAR)
    $longClose = ''        # закрывающий delimiter длинных строк/комментариев Lua

    function Add-Cmt {
        param([int]$End)
        $raw = $Text.Substring($cStart, $End - $cStart)
        if ($LineTypes -contains $commentType) { $raw = $raw.TrimEnd([char]13) }
        $result.Add(@{ Line = $cLine; Type = $commentType; Text = $raw })
    }

    $i = 0; $line = 1; $state = 0; $atLineStart = $true

    while ($i -lt $n) {
        $ch = $chars[$i]

        if ($state -eq 0) {
            # ---- строковые и символьные литералы (делимитеры внутри — не комментарии) ----
            if ($hasQuotes -and (($ch -eq '"') -or ($ch -eq "'"))) {
                if ($isC -and $ch -eq "'") { $quote = [char]39 } else { $quote = $ch }
                $longClose = ''
                $state = 3
                $i++
                continue
            }
            # длинные строки Lua: [[...]], [=[...]=]
            if ($isLua -and $ch -eq '[') {
                $j = $i + 1
                while ($j -lt $n -and $chars[$j] -eq '=') { $j++ }
                if ($j -lt $n -and $chars[$j] -eq '[') {
                    # PS 5.1 не принимает арифметику в аргументах конструктора — берём срезы из $Text
                    $longClose = ']' + $Text.Substring($i + 1, $j - $i - 1) + ']'
                    $state = 3
                    $i = $j + 1
                    continue
                }
            }

            # ---- комментарии (по стилю) ----
            if (($isC -or $isSql) -and $ch -eq '/' -and ($i + 1) -lt $n) {
                if ($isC -and $chars[$i + 1] -eq '/') {
                    $cStart = $i; $cLine = $line; $commentType = 'line'
                    $state = 1; $i += 2; continue
                }
                if ($chars[$i + 1] -eq '*') {
                    $cStart = $i; $cLine = $line
                    # javadoc: /** ..., но не /***
                    $isJd = (($i + 2) -lt $n -and $chars[$i + 2] -eq '*') -and
                            (-not ((($i + 3) -lt $n) -and ($chars[$i + 3] -eq '*')))
                    $commentType = if ($isJd) { 'javadoc' } else { 'block' }
                    $state = 2; $i += 2; continue
                }
            }
            elseif ($isHash -and $ch -eq '#') {
                $cStart = $i; $cLine = $line; $commentType = 'hash'
                $state = 1; $i++; continue
            }
            elseif ($isXml -and $ch -eq '<' -and (Test-TextPrefix -Text $Text -Prefix '<!--' -Start $i)) {
                $cStart = $i; $cLine = $line; $commentType = 'xml'
                $state = 2; $i += 4; continue
            }
            elseif ($isSql -and $ch -eq '-' -and ($i + 1) -lt $n -and $chars[$i + 1] -eq '-') {
                $cStart = $i; $cLine = $line; $commentType = 'sql'
                $state = 1; $i += 2; continue
            }
            elseif ($isLua -and $ch -eq '-' -and ($i + 1) -lt $n -and $chars[$i + 1] -eq '-') {
                $cStart = $i; $cLine = $line; $commentType = 'lua'
                # длинный комментарий --[[...]] / --[=[...]=]
                $j = $i + 2
                if ($j -lt $n -and $chars[$j] -eq '[') {
                    $k = $j + 1
                    while ($k -lt $n -and $chars[$k] -eq '=') { $k++ }
                    if ($k -lt $n -and $chars[$k] -eq '[') {
                        $longClose = ']' + $Text.Substring($j + 1, $k - $j - 1) + ']'
                        $state = 2
                        $i = $k + 1
                        continue
                    }
                }
                $state = 1; $i += 2; continue
            }
            elseif ($isBat -and $atLineStart -and $ch -ne ' ' -and $ch -ne "`t") {
                # bat: :: и REM — только в начале строки; REM — как отдельное слово
                if ($ch -eq ':' -and ($i + 1) -lt $n -and $chars[$i + 1] -eq ':') {
                    $cStart = $i; $cLine = $line; $commentType = 'bat'
                    $state = 1; $i += 2; continue
                }
                $rem3 = $Text.Substring($i, [Math]::Min(3, $n - $i)).ToUpper()
                if (($rem3 -eq 'REM') -and ((($i + 3) -ge $n) -or ($chars[$i + 3] -in @(' ', "`t")))) {
                    $cStart = $i; $cLine = $line; $commentType = 'bat'
                    $state = 1; $i += 3; continue
                }
                $atLineStart = $false
            }

            # ---- обычный символ кода ----
            if ($ch -eq "`n") {
                $line++
                $atLineStart = $true
            }
            elseif ($isBat -and $ch -ne ' ' -and $ch -ne "`t") {
                $atLineStart = $false
            }
            $i++
        }
        elseif ($state -eq 1) {
            # однострочный комментарий: до конца строки (без самого \n)
            if ($ch -eq "`n") {
                Add-Cmt $i
                $state = 0
                $line++
                $atLineStart = $true
            }
            $i++
        }
        elseif ($state -eq 2) {
            if ($commentType -eq 'xml') {
                # закрывается -->
                if (Test-TextPrefix -Text $Text -Prefix '-->' -Start $i) {
                    $i += 3; Add-Cmt $i; $state = 0
                }
                else { if ($ch -eq "`n") { $line++ }; $i++ }
            }
            elseif ($longClose) {
                # длинный комментарий Lua --[[...]]
                if (Test-TextPrefix -Text $Text -Prefix $longClose -Start $i) {
                    $i += $longClose.Length; Add-Cmt $i; $state = 0
                }
                else { if ($ch -eq "`n") { $line++ }; $i++ }
            }
            else {
                # /* ... */ (c и sql): первый */ закрывает блок, вложенность нет
                if ($ch -eq '*' -and ($i + 1) -lt $n -and $chars[$i + 1] -eq '/') {
                    $i += 2; Add-Cmt $i; $state = 0
                }
                else { if ($ch -eq "`n") { $line++ }; $i++ }
            }
        }
        else {
            # IN_STRING / IN_CHAR
            if ($longClose) {
                # длинная строка Lua: без экранирования, до закрывающего delimiter
                if (Test-TextPrefix -Text $Text -Prefix $longClose -Start $i) {
                    $i += $longClose.Length; $state = 0
                }
                else { if ($ch -eq "`n") { $line++ }; $i++ }
            }
            elseif ($ch -eq '\' -and $Style -ne 'xml' -and ($i + 1) -lt $n) {
                # экранирование: \", \', \\, \\uXXXX — пропускаем пару «\\ + символ»
                $i += 2
            }
            elseif ($ch -eq $quote) {
                $i++; $state = 0
            }
            elseif ($ch -eq "`n") {
                # короткая строка не переносится (длинные — отдельный случай выше)
                $line++; $state = 0; $i++
            }
            else {
                $i++
            }
        }
    }

    # незакрытый комментарий в конце файла — берём до конца текста
    if ($state -eq 1 -or $state -eq 2) { Add-Cmt $n }
    return $result
}

# ---------------------------------------------------------------------------
# Чтение файлов и обход дерева
# ---------------------------------------------------------------------------

function Read-SourceText {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)   # IOException -> «не читается»
    if ($bytes.Length -gt 0) {
        # бинарная эвристика: \x00 в первых 8 КБ
        $headLen = [Math]::Min(8192, $bytes.Length)
        $head = New-Object 'byte[]' $headLen
        [Array]::Copy($bytes, $head, $headLen)
        foreach ($b in $head) { if ($b -eq 0) { throw 'BINARY' } }
    }
    # кодировки: UTF-8 -> cp1251 -> latin-1
    try {
        return @{ Text = $Utf8Strict.GetString($bytes); Enc = 'utf-8' }
    }
    catch {
        try {
            return @{ Text = [System.Text.Encoding]::GetEncoding(1251).GetString($bytes); Enc = 'cp1251' }
        }
        catch {
            return @{ Text = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes); Enc = 'latin-1' }
        }
    }
}

function Get-SyntaxForFile {
    param([string]$Name)
    $dot = $Name.LastIndexOf('.')
    if ($dot -ge 0) { $ext = $Name.Substring($dot).ToLower() } else { $ext = '' }
    if (($ext -eq '') -and $Name.StartsWith('.')) { $ext = $Name.ToLower() }  # dot-файлы: .gitignore, .env
    if ($ext -ne '') {
        $s = $CommentSyntax[$ext]
        if ($null -ne $s) { return $s }
    }
    $fn = $FileNameSyntax[$Name.ToLower()]          # например Dockerfile
    if ($null -ne $fn) { return $fn }
    return $null
}

# Ordinal-сортировка имён — как sorted() в Python (отчёты совпадают побайтово)
function Sort-Ordinal {
    param([string[]]$Items)
    $a = @($Items).Clone()
    [Array]::Sort($a, [System.StringComparer]::Ordinal)
    return , $a
}

function Get-SourceFiles {
    param([string]$Dir)
    # симлинки/джанкшены не разыменовываем (защита от циклов)
    $allDirs  = @(Get-ChildItem -LiteralPath $Dir -Directory -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.LinkType -eq $null })
    $dirMap   = @{}; foreach ($d in $allDirs)  { $dirMap[$d.Name]  = $d }
    # .Name по пустому массиву вернёт $null — перечисляем явно
    $dirNames = @($allDirs | ForEach-Object { $_.Name })
    $subdirs  = @((Sort-Ordinal $dirNames) | ForEach-Object { $dirMap[$_] })

    $allFiles = @(Get-ChildItem -LiteralPath $Dir -File -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.LinkType -eq $null })
    $fileMap  = @{}; foreach ($f in $allFiles) { $fileMap[$f.Name] = $f }
    $fileNames = @($allFiles | ForEach-Object { $_.Name })
    $files     = @((Sort-Ordinal $fileNames) | ForEach-Object { $fileMap[$_] })
    foreach ($f in $files) { $f.FullName }
    foreach ($d in $subdirs) {
        if ($ExcludedDirs -notcontains $d.Name.ToLower()) { Get-SourceFiles -Dir $d.FullName }
    }
}

# ---------------------------------------------------------------------------
# Форматирование отчёта
# ---------------------------------------------------------------------------

function Format-Comment {
    param([int]$LineNo, [string]$Type, [string]$Raw)
    # "L12   [line]" — номер слева в ширине 4, префикс выравнивается до 15 символов;
    # продолжение многострочных комментариев — с отступом 15 пробелов
    $lines = @($Raw -split "`n")
    $out = New-Object 'System.Collections.Generic.List[string]'
    for ($k = 0; $k -lt $lines.Count; $k++) {
        $l = $lines[$k].TrimEnd([char]13)
        if ($k -eq 0) {
            $prefix = ('L{0,-4} [{1}]' -f $LineNo, $Type).PadRight(15)
            $out.Add($prefix + ' ' + $l)
        }
        else {
            $out.Add((' ' * 15) + $l)
        }
    }
    return ($out -join "`n")
}

# ---------------------------------------------------------------------------
# Основная часть: корень сканирования — папка запуска (CWD)
# ---------------------------------------------------------------------------

$sw = [System.Diagnostics.Stopwatch]::StartNew()

$root = (Get-Location).Path
if (-not $root.EndsWith('\')) { $root += '\' }

$filesWithComments = [ordered]@{}
$scanned = 0
$unknownFiles    = New-Object 'System.Collections.Generic.List[string]'
$binaryFiles     = New-Object 'System.Collections.Generic.List[string]'
$unreadableFiles = New-Object 'System.Collections.Generic.List[string]'
$fallbackFiles   = New-Object 'System.Collections.Generic.List[string]'

foreach ($full in (Get-SourceFiles -Dir $root.TrimEnd('\'))) {
    $name = [System.IO.Path]::GetFileName($full)
    $rel  = $full.Substring($root.Length).Replace('\', '/')

    # при повторном запуске не сканируем собственный отчёт
    if (([System.IO.Path]::GetDirectoryName($full) -ieq $root.TrimEnd('\')) -and ($name -ieq $ReportName)) { continue }

    $style = Get-SyntaxForFile -Name $name
    if ($null -eq $style) { $unknownFiles.Add($rel); continue }

    try {
        $src = Read-SourceText -Path $full
    }
    catch {
        if ($_.Exception.Message -eq 'BINARY') { $binaryFiles.Add($rel) }
        else { $unreadableFiles.Add($rel) }
        continue
    }

    if ($src.Enc -ne 'utf-8') { $fallbackFiles.Add($rel) }

    # @(...) — защита от «разворачивания» одноэлементного списка: иначе
    # .Count у хэш-таблицы считает ключи, а не число комментариев
    $comments = @(Get-Comments -Text $src.Text -Style $style)
    $scanned++
    if ($comments.Count -gt 0) { $filesWithComments[$rel] = $comments }
}

# ---- сборка отчёта: блоки файлов + SUMMARY в конце ----
$parts = New-Object 'System.Collections.Generic.List[string]'
foreach ($rel in $filesWithComments.Keys) {
    $body = New-Object 'System.Collections.Generic.List[string]'
    foreach ($c in $filesWithComments[$rel]) {
        $body.Add((Format-Comment -LineNo $c.Line -Type $c.Type -Raw $c.Text))
    }
    $parts.Add(('=== FILE: {0} ===' -f $rel) + "`n" + ($body -join "`n"))
}

$total = 0
foreach ($k in $filesWithComments.Keys) { $total += $filesWithComments[$k].Count }

$summary = New-Object 'System.Collections.Generic.List[string]'
$summary.Add('=== SUMMARY ===')
$summary.Add(('scanned_files: {0}' -f $scanned))
$summary.Add(('files_with_comments: {0}' -f $filesWithComments.Count))
$summary.Add(('total_comments: {0}' -f $total))

foreach ($pair in @(
        @('skipped_unknown_ext',  $unknownFiles),
        @('skipped_binary',       $binaryFiles),
        @('skipped_unreadable',   $unreadableFiles),
        @('encoding_fallbacks',   $fallbackFiles))) {
    $summary.Add(('{0}: {1}' -f $pair[0], $pair[1].Count))
    foreach ($p in (Sort-Ordinal (@($pair[1])))) { $summary.Add('  - ' + $p) }
}
$parts.Add(($summary -join "`n"))

$reportPath = Join-Path (Get-Location).Path $ReportName
[System.IO.File]::WriteAllText($reportPath, (($parts -join "`n`n") + "`n"), $Utf8NoBom)

# ---- сводка в консоль ----
$sw.Stop()
Write-Output ('Обработано файлов: {0}' -f $scanned)
Write-Output ('Найдено комментариев: {0}' -f $total)
Write-Output ('Отчёт: {0}' -f $reportPath)
Write-Output ('Время работы: {0:F2} c' -f $sw.Elapsed.TotalSeconds)
