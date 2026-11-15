#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Утилита-сканер комментариев в исходном коде.

Запуск из корня проекта:  python scan_comments.py   (или python3)
Результат: comments_report.txt в папке запуска (перезаписывается).
Только стандартная библиотека, Python 3. Внешних зависимостей нет.
"""

import os
import time

# ---------------------------------------------------------------------------
# Исключения и карта расширений
# ---------------------------------------------------------------------------

# Папки, которые не сканируем (сравнение по basename, без учёта регистра)
EXCLUDED_DIRS = {
    'target', 'build', 'out', '.git', '.idea', 'node_modules',
    'test', 'tests', 'generated', 'gen',
    'generated-sources', 'generated-test-sources',
}

# Карта: расширение (в нижнем регистре) -> стиль комментариев.
#   c    — //  /* ... */  /** ... */ (javadoc)
#   hash — #
#   xml  — <!-- ... -->
#   sql  — -- и /* ... */
#   lua  — -- и --[[ ... ]] (в т.ч. --[=[ ... ]=])
#   bat  — REM и ::
COMMENT_SYNTAX = {
    # C-стиль
    '.java': 'c', '.js': 'c', '.jsx': 'c', '.ts': 'c', '.tsx': 'c',
    '.c': 'c', '.h': 'c', '.cpp': 'c', '.hpp': 'c', '.cc': 'c',
    '.cs': 'c', '.go': 'c', '.kt': 'c', '.kts': 'c', '.scala': 'c',
    '.php': 'c', '.swift': 'c', '.dart': 'c', '.rs': 'c',
    '.css': 'c', '.scss': 'c', '.less': 'c',
    '.groovy': 'c', '.gradle': 'c', '.proto': 'c',
    # Hash
    '.py': 'hash', '.rb': 'hash', '.sh': 'hash', '.bash': 'hash',
    '.zsh': 'hash', '.yaml': 'hash', '.yml': 'hash',
    '.properties': 'hash', '.conf': 'hash', '.toml': 'hash',
    '.ini': 'hash', '.r': 'hash', '.pl': 'hash', '.ps1': 'hash',
    '.dockerfile': 'hash', '.gitignore': 'hash', '.env': 'hash',
    '.tf': 'hash',
    # XML/HTML
    '.xml': 'xml', '.html': 'xml', '.htm': 'xml', '.xhtml': 'xml',
    '.svg': 'xml', '.jsp': 'xml', '.ftl': 'xml', '.xsd': 'xml',
    '.wsdl': 'xml', '.pom': 'xml', '.vue': 'xml', '.svelte': 'xml',
    # SQL
    '.sql': 'sql',
    # Lua
    '.lua': 'lua',
    # Batch
    '.bat': 'bat', '.cmd': 'bat',
}

# Файлы без расширения, определяемые по имени (в нижнем регистре)
FILENAME_SYNTAX = {
    'dockerfile': 'hash',
}

REPORT_NAME = 'comments_report.txt'

# ---------------------------------------------------------------------------
# Лексер
# ---------------------------------------------------------------------------

# Состояния лексера
CODE = 'CODE'
IN_LINE_COMMENT = 'IN_LINE_COMMENT'
IN_BLOCK_COMMENT = 'IN_BLOCK_COMMENT'
IN_STRING = 'IN_STRING'
IN_CHAR = 'IN_CHAR'

# Стили, где есть строковые/символьные литералы в кавычках
QUOTE_STYLES = ('c', 'hash', 'xml', 'sql', 'lua')

# Однострочные типы комментариев (для обрезки хвостового \r при CRLF)
LINE_TYPES = ('line', 'hash', 'sql', 'lua', 'bat')


class BinaryFileError(Exception):
    """Файл похож на бинарный (\x00 в первых 8 КБ)."""


def lex_comments(text, style):
    """Лёгкий посимвольный лексер с явными состояниями.

    Состояния: CODE / IN_LINE_COMMENT / IN_BLOCK_COMMENT / IN_STRING / IN_CHAR.
    В строках и символьных литералах делимитеры комментариев не считаются
    комментариями; учитывается экранирование \", \', \\, \\uXXXX (пара «\\ + символ»).
    Вложенные /* ... */ не поддерживаются: первый */ закрывает блок.

    Возвращает список кортежей (номер_строки, тип, исходный_текст_с_делимитерами).
    """
    comments = []
    i, n = 0, len(text)
    line = 1
    state = CODE
    quote = ''        # активная кавычка (IN_STRING / IN_CHAR)
    long_close = ''   # закрывающий delimiter длинных строк/комментариев Lua
    comment_type = '' # тип комментария, который сейчас набирается
    c_start = 0       # позиция начала текущего комментария
    c_line = 0        # строка начала текущего комментария
    at_line_start = True  # для bat: REM / :: считаются только в начале строки

    def push_comment(end_i):
        raw = text[c_start:end_i]
        if comment_type in LINE_TYPES:
            raw = raw.rstrip('\r')  # не тащим хвост CRLF в текст комментария
        comments.append((c_line, comment_type, raw))

    while i < n:
        ch = text[i]

        if state == CODE:
            # ---- строковые и символьные литералы (там делимитеры — не комментарии) ----
            if style in QUOTE_STYLES and ch in ('"', "'"):
                if style == 'c' and ch == "'":
                    state, quote = IN_CHAR, "'"
                else:
                    state, quote = IN_STRING, ch
                long_close = ''
                i += 1
                continue
            # длинные строки Lua: [[...]], [=[...]=]
            if style == 'lua' and ch == '[':
                j = i + 1
                while j < n and text[j] == '=':
                    j += 1
                if j < n and text[j] == '[':
                    long_close = ']' + text[i + 1:j] + ']'
                    state = IN_STRING
                    i = j + 1
                    continue

            # ---- комментарии (по стилю) ----
            if style in ('c', 'sql') and ch == '/' and i + 1 < n:
                if text[i + 1] == '/' and style == 'c':
                    c_start, c_line = i, line
                    comment_type = 'line'
                    state = IN_LINE_COMMENT
                    i += 2
                    continue
                if text[i + 1] == '*':
                    c_start, c_line = i, line
                    # javadoc: /** ..., но не /***
                    is_jd = (i + 2 < n and text[i + 2] == '*'
                             and not (i + 3 < n and text[i + 3] == '*'))
                    comment_type = 'javadoc' if is_jd else 'block'
                    state = IN_BLOCK_COMMENT
                    i += 2
                    continue
            elif style == 'hash' and ch == '#':
                c_start, c_line = i, line
                comment_type = 'hash'
                state = IN_LINE_COMMENT
                i += 1
                continue
            elif style == 'xml' and ch == '<' and text.startswith('<!--', i):
                c_start, c_line = i, line
                comment_type = 'xml'
                state = IN_BLOCK_COMMENT
                i += 4
                continue
            elif style == 'sql' and ch == '-' and i + 1 < n and text[i + 1] == '-':
                c_start, c_line = i, line
                comment_type = 'sql'
                state = IN_LINE_COMMENT
                i += 2
                continue
            elif style == 'lua' and ch == '-' and i + 1 < n and text[i + 1] == '-':
                c_start, c_line = i, line
                comment_type = 'lua'
                # длинный комментарий --[[...]] / --[=[...]=]
                j = i + 2
                if j < n and text[j] == '[':
                    k = j + 1
                    while k < n and text[k] == '=':
                        k += 1
                    if k < n and text[k] == '[':
                        long_close = ']' + text[j + 1:k] + ']'
                        state = IN_BLOCK_COMMENT
                        i = k + 1
                        continue
                state = IN_LINE_COMMENT
                i += 2
                continue
            elif style == 'bat' and at_line_start and ch not in ' \t':
                if ch == ':' and i + 1 < n and text[i + 1] == ':':
                    c_start, c_line = i, line
                    comment_type = 'bat'
                    state = IN_LINE_COMMENT
                    i += 2
                    continue
                # REM — только как отдельное слово в начале строки
                if (text[i:i + 3].upper() == 'REM'
                        and (i + 3 >= n or text[i + 3] in ' \t')):
                    c_start, c_line = i, line
                    comment_type = 'bat'
                    state = IN_LINE_COMMENT
                    i += 3
                    continue
                at_line_start = False

            # ---- обычный символ кода ----
            if ch == '\n':
                line += 1
                at_line_start = True
            elif style == 'bat' and ch not in ' \t':
                at_line_start = False
            i += 1

        elif state == IN_LINE_COMMENT:
            # однострочный комментарий: до конца строки (без самого \n)
            if ch == '\n':
                push_comment(i)
                state = CODE
                line += 1
                at_line_start = True
            i += 1

        elif state == IN_BLOCK_COMMENT:
            if comment_type == 'xml':
                # закрывается -->
                if text.startswith('-->', i):
                    i += 3
                    push_comment(i)
                    state = CODE
                else:
                    if ch == '\n':
                        line += 1
                    i += 1
            elif long_close:
                # длинный комментарий Lua --[[...]]
                if text.startswith(long_close, i):
                    i += len(long_close)
                    push_comment(i)
                    state = CODE
                else:
                    if ch == '\n':
                        line += 1
                    i += 1
            else:
                # /* ... */ (c и sql): первый */ закрывает блок, вложенность нет
                if ch == '*' and i + 1 < n and text[i + 1] == '/':
                    i += 2
                    push_comment(i)
                    state = CODE
                else:
                    if ch == '\n':
                        line += 1
                    i += 1

        elif state in (IN_STRING, IN_CHAR):
            if long_close:
                # длинная строка Lua: без экранирования, до закрывающего delimiter
                if text.startswith(long_close, i):
                    i += len(long_close)
                    state = CODE
                else:
                    if ch == '\n':
                        line += 1
                    i += 1
            elif ch == '\\' and style != 'xml' and i + 1 < n:
                # экранирование: \", \', \\, \\uXXXX — пропускаем пару «\\ + символ»
                i += 2
            elif ch == quote:
                i += 1
                state = CODE
            elif ch == '\n':
                # короткая строка не переносится (длинные — отдельный случай выше)
                line += 1
                state = CODE
                i += 1
            else:
                i += 1

    # незакрытый комментарий/строка в конце файла — берём до конца текста
    if state in (IN_LINE_COMMENT, IN_BLOCK_COMMENT):
        push_comment(n)
    return comments


# ---------------------------------------------------------------------------
# Чтение файлов и обход дерева
# ---------------------------------------------------------------------------

def read_source(path):
    """Читает файл как текст. Возвращает (text, encoding).

    Бинарные файлы (\x00 в первых 8 КБ) — BinaryFileError.
    Кодировки пробуются по порядку: UTF-8 -> cp1251 -> latin-1.
    """
    with open(path, 'rb') as f:
        data = f.read()
    if b'\x00' in data[:8192]:
        raise BinaryFileError()
    for enc in ('utf-8', 'cp1251', 'latin-1'):
        try:
            return data.decode(enc), enc
        except UnicodeDecodeError:
            continue
    # недостижимо: latin-1 декодирует любую последовательность байтов
    raise UnicodeDecodeError('utf-8', data, 0, 1, 'no encoding matched')


def syntax_for_filename(name):
    """Определяет стиль комментариев по имени файла; None — неизвестное расширение."""
    ext = os.path.splitext(name)[1].lower()
    if not ext and name.startswith('.'):
        # dot-файлы: .gitignore, .env — splitext даёт пустое расширение
        ext = name.lower()
    style = COMMENT_SYNTAX.get(ext)
    if style is None:
        style = FILENAME_SYNTAX.get(name.lower())  # например Dockerfile
    return style


def iter_source_files(root):
    """Рекурсивный обход дерева от корня. Симлинки не разыменовываются
    (followlinks=False + явный пропуск symlink-файлов) — защита от циклов."""
    for dirpath, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
        # вырезаем исключённые папки на месте, чтобы не заходить в них
        dirnames[:] = sorted(d for d in dirnames if d.lower() not in EXCLUDED_DIRS)
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                continue
            yield path


def rel_path(path, root):
    """Относительный путь от корня с разделителем /."""
    return os.path.relpath(path, root).replace(os.sep, '/')


# ---------------------------------------------------------------------------
# Отчёт
# ---------------------------------------------------------------------------

def format_comment(line_no, ctype, raw):
    """Форматирует один комментарий; многострочные — с выравниванием под текст."""
    lines = raw.split('\n')
    out = []
    for k, l in enumerate(lines):
        l = l.rstrip('\r')
        if k == 0:
            prefix = 'L{:<4d} [{}]'.format(line_no, ctype)
            out.append(prefix.ljust(15) + ' ' + l)
        else:
            out.append(' ' * 15 + l)
    return '\n'.join(out)


def write_report(path, files_with_comments, scanned, unknown, binary,
                 unreadable, fallbacks):
    """Собирает comments_report.txt: блоки файлов + SUMMARY в конце."""
    parts = []
    for rel, comments in files_with_comments.items():
        body = '\n'.join(format_comment(l, t, r) for l, t, r in comments)
        parts.append('=== FILE: {} ===\n{}'.format(rel, body))

    total = sum(len(c) for c in files_with_comments.values())
    summary = [
        '=== SUMMARY ===',
        'scanned_files: {}'.format(scanned),
        'files_with_comments: {}'.format(len(files_with_comments)),
        'total_comments: {}'.format(total),
    ]

    def add_list(label, items):
        summary.append('{}: {}'.format(label, len(items)))
        # список — в алфавитном (ordinal) порядке, как Sort-Ordinal в PowerShell
        summary.extend('  - ' + p for p in sorted(items))

    add_list('skipped_unknown_ext', unknown)
    add_list('skipped_binary', binary)
    add_list('skipped_unreadable', unreadable)
    add_list('encoding_fallbacks', fallbacks)
    parts.append('\n'.join(summary))

    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n\n'.join(parts) + '\n')
    return total


# ---------------------------------------------------------------------------
# Точка входа
# ---------------------------------------------------------------------------

def main():
    t0 = time.time()
    root = os.getcwd()  # корень сканирования — папка запуска (CWD), а не папка скрипта

    files_with_comments = {}  # relpath -> [(line, type, text), ...], порядок обхода
    scanned = 0
    unknown = []
    binary = []
    unreadable = []
    fallbacks = []

    for path in iter_source_files(root):
        name = os.path.basename(path)
        if os.path.dirname(path) == root and name == REPORT_NAME:
            continue  # не сканируем собственный отчёт при повторном запуске
        style = syntax_for_filename(name)
        if style is None:
            unknown.append(rel_path(path, root))
            continue
        try:
            text, enc = read_source(path)
        except BinaryFileError:
            binary.append(rel_path(path, root))
            continue
        except OSError:
            unreadable.append(rel_path(path, root))
            continue
        if enc != 'utf-8':
            fallbacks.append(rel_path(path, root))
        comments = lex_comments(text, style)
        scanned += 1
        if comments:
            files_with_comments[rel_path(path, root)] = comments

    report_path = os.path.join(root, REPORT_NAME)
    total = write_report(report_path, files_with_comments, scanned,
                         unknown, binary, unreadable, fallbacks)

    # итоговая сводка в консоль
    print('Обработано файлов: {}'.format(scanned))
    print('Найдено комментариев: {}'.format(total))
    print('Отчёт: {}'.format(os.path.abspath(report_path)))
    print('Время работы: {:.2f} c'.format(time.time() - t0))


if __name__ == '__main__':
    main()
