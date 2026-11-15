# AGENTS.md — контекст для AI-агентов

## Что это
Сканер комментариев в исходном коде с тремя независимыми реализациями
(Python, PowerShell, Java + JAR). Сканирует дерево папок от **CWD** и пишет
`comments_report.txt` в эту же папку (UTF-8 без BOM, переводы строк `\n`).

## Ключевой инвариант (не ломать)
Все четыре входные точки — `src/python/scan_comments.py`, `src/powershell/scan_comments.ps1`,
Java-классы и `dist/scan-comments.jar` — обязаны давать **побайтово идентичный** отчёт
на одном и том же дереве. Любое изменение одной реализации зеркалится во все остальные,
JAR пересобирается, затем обязательна проверка (см. ниже).

## Структура
| Путь | Назначение |
|---|---|
| `src/python/scan_comments.py` | Реализация на Python (эталон) |
| `src/powershell/scan_comments.ps1` | Реализация на PowerShell 5.1+ |
| `src/java/ScanComments.java` | Реализация на Java (один файл, без зависимостей) |
| `scripts/run_scan*.bat`, `run_scan.sh` | Раннеры; все сканируют CWD, а не свою папку |
| `fixtures/demo/` | Тестовое дерево: кодировки (UTF-8/cp1251/BOM), CRLF, исключённые папки (`build/`, `node_modules/`), все стили комментариев |
| `dist/scan-comments.jar` | Переносимый JAR (Main-Class: ScanComments) |

## Формат отчёта (жёсткий; менять только зеркально во всех реализациях)
- Блок файла: `=== FILE: <относительный путь> ===`, затем строки вида
  `L<номер>` + тип комментария, дополненный пробелами до фиксированной ширины префикса (15), + сырой текст комментария.
- Порядок: **файлы перед папками**, ordinal-сортировка (байтовый порядок, не локальный).
- В конце `=== SUMMARY ===`: `scanned_files`, `files_with_comments`, `total_comments`
  и списки (`unknown_ext`, `unreadable`, `binary`, `enc_fallbacks`) — порядок ключей жёсткий.
- Сам файл отчёта исключается из сканирования только в корне дерева.

## Языковая поддержка
Карта «расширение → стиль» продублирована **в трёх местах**: `COMMENT_SYNTAX` в py
(~строка 33), аналогичные карты в ps1 и java. Стили: `c` (`//`, `/* */`), `hash` (`#`),
`xml` (`<!-- -->`), `sql`, `lua`, `bat` (`REM`, `::`). Добавление языка = правка всех трёх
карт + пересборка JAR + проверка инварианта.

## Нюансы (выученные на практике)
1. **javac**: без `-d` пишет `.class` рядом с исходником и **молча пропускает** компиляцию,
   если существующий `.class` новее `.java`. Всегда собирать с `-d <dir>`;
   `run_scan_java.bat` чистит `%TEMP%\scan_comments_classes` перед сборкой.
   Файлы `.class` в проекте не оставлять.
2. **Комментарии bat**: `::` и `REM` распознаются только в начале строки (после пробелов/tab);
   `REM` — отдельное слово: после него EOL, пробел или tab, но **не** `;`
   (`REM;x=1` — не комментарий). Текст комментария начинается с первого непустого символа.
3. **`files_with_comments` считать структурно** (счётчик в main), а не строковым поиском
   «=== FILE: » по телу отчёта — javadoc с таким литералом раздувал счётчик
   (регрессия исправлена 2026-11-15).
4. **Кодировки**: цепочка BOM → UTF-8 → cp1251 fallback; бинарный файл = NUL-байт в первых
   8 КБ. Цепочка должна совпадать во всех реализациях (в отчёте — `enc_fallbacks`).
5. **Шаблонные литералы JS/TS** (backticks): `//` внутри `` `...` `` считается комментарием —
   равное ограничение всех трёх лексеров, а не баг. Не «чинить» в одной реализации отдельно.
6. **Исключаемые папки** (`EXCLUDED_DIRS`, одинаковы везде): target, build, out, .git, .idea,
   node_modules, test, tests, generated, gen, generated-sources, generated-test-sources.

## Проверка инварианта (обязательна после любого изменения)
```sh
P=C:/PROJECTS/check_comments
S=$LOCALAPPDATA/Temp/sc_check        # любая scratch-папка
rm -rf "$S"/v1 "$S"/v2 "$S"/v3 "$S"/v4 "$S/jc"
mkdir -p "$S/v1" "$S/v2" "$S/v3" "$S/v4" "$S/jc"
for v in 1 2 3 4; do cp -r "$P/fixtures/demo/." "$S/v$v/"; done
(cd "$S/v1" && python "$P/src/python/scan_comments.py")
(cd "$S/v2" && powershell -NoProfile -ExecutionPolicy Bypass -File "$P/src/powershell/scan_comments.ps1")
javac -encoding UTF-8 -d "$S/jc" "$P/src/java/ScanComments.java"
(cd "$S/v3" && java -cp "$S/jc" ScanComments)
(cd "$S/v4" && java -jar "$P/dist/scan-comments.jar")
sha256sum "$S"/v1/comments_report.txt "$S"/v2/comments_report.txt \
          "$S"/v3/comments_report.txt "$S"/v4/comments_report.txt   # все 4 хэша должны совпасть
```

## Пересборка JAR (после любой правки `src/java`)
```sh
javac -encoding UTF-8 -d /tmp/sc_classes src/java/ScanComments.java
jar --create --file dist/scan-comments.jar --main-class ScanComments -C /tmp/sc_classes .
```

## Исправленные баги (не регрессить)
- bat: в Java текст комментария включал начальные пробелы строки → теперь режется от первого
  непустого символа (py/ps были корректны).
- bat: `REM;` распознавался как комментарий только в Java → граница слова REM = EOL/пробел/tab.
- `files_with_comments` раздувался javadoc, содержащим литерал «=== FILE: » → структурный счётчик.
- `run_scan_java.bat`: старые классы в `%TEMP%` молча исполнялись вместо свежих → очистка перед `javac`.

## История (кратко)
- 2026-11-15: исправлены три бага Java (см. выше); подтверждена поддержка C/C++/JS/React;
  проект реструктурирован: `src/<язык>/`, `scripts/`, `fixtures/demo/`, `dist/`;
  удалены артефакты (`build/`, `ab_tree/`, старый zip, устаревшие копии кода в demo).
