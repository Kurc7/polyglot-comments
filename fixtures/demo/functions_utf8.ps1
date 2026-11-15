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

