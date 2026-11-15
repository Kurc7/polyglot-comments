import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.ByteBuffer;
import java.nio.charset.Charset;
import java.nio.charset.CharsetDecoder;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.charset.UnsupportedCharsetException;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.DirectoryStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Сканер комментариев в исходном коде.
 *
 * Запуск:  javac -encoding UTF-8 ScanComments.java
 *          java ScanComments
 * Флаг -encoding UTF-8 обязателен: в файле русские комментарии.
 * Консоль принудительно переводится в UTF-8 (на Windows иначе кириллица
 * съедается кодовой страницей cp866/cp1251); для окна cmd лучше chcp 65001.
 * Корень сканирования — текущая рабочая папка (CWD), а не папка класса.
 * Результат — comments_report.txt в папке запуска (UTF-8, переводы строк \n).
 * Только стандартная библиотека, внешних зависимостей нет.
 */
public class ScanComments {

    // Папки, которые не сканируются (сравнение по имени, без учёта регистра)
    static final Set<String> EXCLUDED_DIRS = new HashSet<>(Arrays.asList(
            "target", "build", "out", ".git", ".idea", "node_modules",
            "test", "tests", "generated", "gen",
            "generated-sources", "generated-test-sources"));

    // Семьи синтаксиса комментариев (по расширению, без учёта регистра)
    static final Set<String> C_FAMILY  = new HashSet<>(Arrays.asList(
            ".java", ".js", ".jsx", ".ts", ".tsx", ".c", ".h", ".cpp", ".hpp",
            ".cc", ".cs", ".go", ".kt", ".kts", ".scala", ".php", ".swift",
            ".dart", ".rs", ".css", ".scss", ".less", ".groovy", ".gradle", ".proto"));
    static final Set<String> HASH_FAMILY = new HashSet<>(Arrays.asList(
            ".py", ".rb", ".sh", ".bash", ".zsh", ".yaml", ".yml", ".properties",
            ".conf", ".toml", ".ini", ".r", ".pl", ".ps1", ".dockerfile",
            ".gitignore", ".env", ".tf"));
    static final Set<String> XML_FAMILY = new HashSet<>(Arrays.asList(
            ".xml", ".html", ".htm", ".xhtml", ".svg", ".jsp", ".ftl",
            ".xsd", ".wsdl", ".pom", ".vue", ".svelte"));
    static final Set<String> SQL_FAMILY  = new HashSet<>(Arrays.asList(".sql"));
    static final Set<String> LUA_FAMILY  = new HashSet<>(Arrays.asList(".lua"));
    static final Set<String> BATCH_FAMILY = new HashSet<>(Arrays.asList(".bat", ".cmd"));

    // Кодировки для фолбэка: UTF-8 -> cp1251 -> latin-1 (последняя не падает никогда)
    static final Charset[] FALLBACKS = { StandardCharsets.UTF_8, charset("cp1251"), charset("latin1") };

    static final Path REPORT_NAME = Paths.get("comments_report.txt");

    /** Один найденный комментарий: строка начала, тип, исходный текст с делимитерами. */
    static final class Comment {
        final int line; final String type; final String text;
        Comment(int line, String type, String text) { this.line = line; this.type = type; this.text = text; }
    }

    /** Результат чтения одного файла (текст + кодировка, по которой он прочитан). */
    static final class ReadFile {
        final String text; final Charset charset;
        ReadFile(String text, Charset charset) { this.text = text; this.charset = charset; }
    }

    public static void main(String[] args) throws IOException {
        // Консоль — всегда UTF-8, независимо от кодовой страницы Windows
        // (Charset-конструктор PrintStream появился в Java 10 — для совместимости с Java 8 используем строку)
        System.setOut(new PrintStream(new FileOutputStream(FileDescriptor.out), true, "UTF-8"));
        System.setErr(new PrintStream(new FileOutputStream(FileDescriptor.err), true, "UTF-8"));
        long t0 = System.currentTimeMillis();
        Path root = Paths.get("").toAbsolutePath().normalize(); // корень = CWD
        if (!Files.isDirectory(root)) {
            System.err.println("Корень сканирования не найден: " + root);
            System.exit(1);
        }

        List<Path> files = new ArrayList<>();
        walk(root, files); // рекурсивный обход без симлинков

        int scanned = 0;                  // файлов, прочитанных как текст
        int filesWithComments = 0;        // файлов, у которых нашлись комментарии (считаем структурно, не строкой по отчёту)
        int totalComments = 0;
        List<String> unknownExt = new ArrayList<>();   // неизвестное расширение
        List<String> unreadable = new ArrayList<>();   // не удалось прочитать
        List<String> binaryFiles = new ArrayList<>();  // эвристика бинарника (\x00 в первых 8 КБ)
        List<String> encFallbacks = new ArrayList<>(); // UTF-8 не подошёл

        StringBuilder body = new StringBuilder();

        for (Path f : files) {
            // Собственный отчёт при повторном запуске не сканируем (как в Python-версии)
            if (f.getParent().equals(root) && REPORT_NAME.getFileName().toString().equals(f.getFileName().toString())) continue;
            String name = f.getFileName().toString();
            String rel = root.relativize(f).toString().replace('\\', '/');
            String ext = extensionOf(name);

            String fam = family(ext);
            if (fam == null && "dockerfile".equals(name.toLowerCase(Locale.ROOT))) fam = "hash"; // имя без расширения
            // Неизвестное расширение — не сканируем, только фиксируем в summary
            if (fam == null) { unknownExt.add(rel); continue; }

            byte[] bytes;
            try {
                bytes = Files.readAllBytes(f);
            } catch (IOException e) {
                unreadable.add(rel); // нечитаемый файл — пишем в summary и идём дальше
                continue;
            }

            if (isBinary(bytes)) { binaryFiles.add(rel); continue; }

            ReadFile rf = decode(bytes);
            if (rf.charset != StandardCharsets.UTF_8) encFallbacks.add(rel);
            scanned++;

            List<Comment> comments = scan(rf.text, fam);
            if (comments.isEmpty()) continue; // файлы без комментариев в отчёт не попадают
            filesWithComments++;
            totalComments += comments.size();

            body.append("=== FILE: ").append(rel).append(" ===\n");
            for (Comment c : comments) {
                // перевод строки — всегда \n (не %n, чтобы не зависеть от ОС)
                body.append(formatComment(c.line, c.type, c.text)).append('\n');
            }
            body.append('\n'); // пустая строка между блоками файлов
        }

        String report = buildReport(body, scanned, filesWithComments, totalComments,
                unknownExt, unreadable, binaryFiles, encFallbacks);
        Files.write(REPORT_NAME, report.getBytes(StandardCharsets.UTF_8)); // переводы строк уже \n

        long ms = System.currentTimeMillis() - t0;
        System.out.printf("Обработано файлов: %d%n", scanned);
        System.out.printf("Найдено комментариев: %d%n", totalComments);
        System.out.printf("Отчёт: %s%n", REPORT_NAME.toAbsolutePath());
        // Locale.ROOT — точка как разделитель, как в Python/PowerShell-версиях
        System.out.printf(java.util.Locale.ROOT, "Время работы: %.2f c%n", ms / 1000.0);
    }

    // ---------- Обход дерева ----------

    /**
     * Рекурсивный обход: сначала файлы каталога (ordinal-сортировка имён),
     * потом подкаталоги в том же порядке — побайтово как sorted() в Python
     * и StringComparer.Ordinal в PowerShell. Симлинки не берём и не разворачиваем.
     */
    static void walk(Path dir, List<Path> out) throws IOException {
        try (DirectoryStream<Path> ds = Files.newDirectoryStream(dir)) {
            List<Path> dirs = new ArrayList<>();
            List<Path> files = new ArrayList<>();
            for (Path p : ds) {
                if (Files.isSymbolicLink(p)) continue; // symlink/djankshen — пропускаем
                if (Files.isDirectory(p)) dirs.add(p); else files.add(p);
            }
            Comparator<Path> byName = Comparator.comparing(p -> p.getFileName().toString());
            dirs.sort(byName);   files.sort(byName);
            for (Path f : files) out.add(f);
            for (Path d : dirs) {
                // исключаемая папка — целиком пропускаем
                if (!EXCLUDED_DIRS.contains(d.getFileName().toString().toLowerCase(Locale.ROOT))) walk(d, out);
            }
        } catch (IOException ignored) { /* нечитаемый каталог — молча пропускаем, как os.walk */ }
    }

    // ---------- Чтение и кодировки ----------

    /** Бинарник по эвристике: байт \x00 в первых 8 КБ. */
    static boolean isBinary(byte[] b) {
        int n = Math.min(b.length, 8192);
        for (int i = 0; i < n; i++) if (b[i] == 0) return true;
        return false;
    }

    /** UTF-8 строго; не подошло — cp1251; ещё не подошло — latin-1. */
    static ReadFile decode(byte[] bytes) {
        for (Charset cs : FALLBACKS) {
            try {
                // Строгий декодер: битая последовательность бросает исключение.
                // Иначе new String() молча заменил бы байты на U+FFFD, и cp1251-файлы
                // никогда не дошли бы до фолбэка.
                CharsetDecoder dec = cs.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT);
                return new ReadFile(dec.decode(ByteBuffer.wrap(bytes)).toString(), cs);
            } catch (Exception ignored) { /* пробуем следующую кодировку */ }
        }
        return new ReadFile(new String(bytes, StandardCharsets.ISO_8859_1), StandardCharsets.ISO_8859_1);
    }

    static Charset charset(String name) {
        try { return Charset.forName(name); } catch (UnsupportedCharsetException e) { return null; }
    }

    // ---------- Расширения ----------

    /** Маленькое расширение файла: ".java" для "A.java", "" если точки нет. */
    static String extensionOf(String name) {
        int dot = name.lastIndexOf('.');
        if (dot < 0 || dot == name.length() - 1) return "";
        return name.substring(dot).toLowerCase(Locale.ROOT);
    }

    /** Семья синтаксиса для расширения: c / hash / xml / sql / lua / bat / null. */
    static String family(String ext) {
        if (C_FAMILY.contains(ext)) return "c";
        if (HASH_FAMILY.contains(ext)) return "hash";
        if (XML_FAMILY.contains(ext)) return "xml";
        if (SQL_FAMILY.contains(ext)) return "sql";
        if (LUA_FAMILY.contains(ext)) return "lua";
        if (BATCH_FAMILY.contains(ext)) return "bat";
        return null;
    }

    static boolean isKnownExt(String ext) { return family(ext) != null; }

    // ---------- Лексеры ----------
    // Посимвольный разбор со слежением за состоянием: CODE / строка / комментарий.
    // Комментарии внутри строк и символов не считаются комментариями.

    /** Диспетчер по семье синтаксиса. */
    static List<Comment> scan(String src, String fam) {
        switch (fam) {
            case "c":    return scanC(src);
            case "hash": return scanHash(src);
            case "xml":  return scanXml(src);
            case "sql":  return scanSql(src);
            case "lua":  return scanLua(src);
            case "bat":  return scanBatch(src);
            default:     return Collections.emptyList();
        }
    }

    /** C-семейство: линейные //, блочные вида «/* ... * /», javadoc — блок, начинающийся с /**. В строках ".." и символах '..' делимитеры игнорируем. */
    static List<Comment> scanC(String s) {
        List<Comment> out = new ArrayList<>();
        int n = s.length(), i = 0, line = 1;
        while (i < n) {
            char c = s.charAt(i);
            if (c == '\n') { line++; i++; continue; }

            // Строка ".." — с экранированием \", \', \\ и т.д.
            if (c == '"') {
                i++;
                while (i < n) {
                    char d = s.charAt(i);
                    if (d == '\\') { i += 2; continue; } // экранированный символ — пропускаем пару
                    if (d == '\n' || d == '"') break;
                    i++;
                }
                if (i < n && s.charAt(i) == '"') i++; // закрывающая кавычка
                continue;
            }
            // Символ '..'
            if (c == '\'') {
                i++;
                while (i < n) {
                    char d = s.charAt(i);
                    if (d == '\\') { i += 2; continue; }
                    if (d == '\n' || d == '\'') break;
                    i++;
                }
                if (i < n && s.charAt(i) == '\'') i++; // закрывающая кавычка
                continue;
            }

            if (c == '/' && i + 1 < n && s.charAt(i + 1) == '/') {
                int st = i, lineSt = line;
                while (i < n && s.charAt(i) != '\n') i++;
                out.add(new Comment(lineSt, "line", s.substring(st, i)));
                continue;
            }
            if (c == '/' && i + 1 < n && s.charAt(i + 1) == '*') {
                boolean javadoc = i + 2 < n && s.charAt(i + 2) == '*';
                int st = i, lineSt = line;
                i += 2;
                while (i + 1 < n && !(s.charAt(i) == '*' && s.charAt(i + 1) == '/')) {
                    if (s.charAt(i) == '\n') line++;
                    i++; // вложенные /* не поддерживаются: первый */ закрывает блок
                }
                if (i + 1 < n) {
                    i += 2; // съедаем закрывающее */
                    out.add(new Comment(lineSt, javadoc ? "javadoc" : "block", s.substring(st, i)));
                } else {
                    out.add(new Comment(lineSt, javadoc ? "javadoc" : "block", s.substring(st))); // незакрытый до EOF
                }
                continue;
            }
            i++;
        }
        return out;
    }

    /** Hash-стиль: # с начала комментария строки. В кавычках '...' и "..." (с экранированием \\#) — не комментарий. */
    static List<Comment> scanHash(String s) {
        List<Comment> out = new ArrayList<>();
        int n = s.length(), i = 0, line = 1;
        while (i < n) {
            char c = s.charAt(i);
            if (c == '\n') { line++; i++; continue; }

            if (c == '"' || c == '\'') {
                char q = c;
                i++;
                while (i < n) {
                    char d = s.charAt(i);
                    if (d == '\\') { i += 2; continue; }
                    if (d == '\n' || d == q) break;
                    i++;
                }
                if (i < n && s.charAt(i) == q) i++; // закрывающая кавычка
                continue;
            }

            if (c == '#') {
                int st = i, lineSt = line;
                while (i < n && s.charAt(i) != '\n') i++;
                out.add(new Comment(lineSt, "hash", s.substring(st, i)));
                continue;
            }
            i++;
        }
        return out;
    }

    /** XML/HTML: <!-- ... -->. Внутри кавычек атрибутов ("..." или '...') — не комментарий. */
    static List<Comment> scanXml(String s) {
        List<Comment> out = new ArrayList<>();
        int n = s.length(), i = 0, line = 1;
        while (i < n) {
            char c = s.charAt(i);
            if (c == '\n') { line++; i++; continue; }

            if (c == '"' || c == '\'') {
                char q = c;
                i++;
                while (i < n && s.charAt(i) != q && s.charAt(i) != '\n') i++;
                if (i < n && s.charAt(i) == q) i++; // закрывающая кавычка атрибута
                continue;
            }

            if (c == '<' && s.startsWith("<!--", i)) {
                int st = i, lineSt = line;
                i += 4;
                while (i + 3 < n && !s.startsWith("-->", i)) {
                    if (s.charAt(i) == '\n') line++;
                    i++;
                }
                if (i + 3 < n) {
                    i += 3; // съедаем закрывающее -->
                    out.add(new Comment(lineSt, "xml", s.substring(st, i)));
                } else {
                    out.add(new Comment(lineSt, "xml", s.substring(st))); // незакрытый до EOF
                }
                continue;
            }
            i++;
        }
        return out;
    }

    /** SQL: линейные -- и блочные вида «/* ... * /». Строки '...' с экранированием — не комментарии. */
    static List<Comment> scanSql(String s) {
        List<Comment> out = new ArrayList<>();
        int n = s.length(), i = 0, line = 1;
        while (i < n) {
            char c = s.charAt(i);
            if (c == '\n') { line++; i++; continue; }

            if (c == '\'') {
                i++;
                while (i < n) {
                    char d = s.charAt(i);
                    if (d == '\\') { i += 2; continue; }
                    if (d == '\n' || d == '\'') break;
                    i++;
                }
                if (i < n && s.charAt(i) == '\'') i++; // закрывающая кавычка
                continue;
            }

            if (c == '-' && i + 1 < n && s.charAt(i + 1) == '-') {
                int st = i, lineSt = line;
                while (i < n && s.charAt(i) != '\n') i++;
                out.add(new Comment(lineSt, "sql", s.substring(st, i)));
                continue;
            }
            if (c == '/' && i + 1 < n && s.charAt(i + 1) == '*') {
                int st = i, lineSt = line;
                i += 2;
                while (i + 1 < n && !(s.charAt(i) == '*' && s.charAt(i + 1) == '/')) {
                    if (s.charAt(i) == '\n') line++;
                    i++;
                }
                if (i + 1 < n) {
                    i += 2; // съедаем закрывающее */
                    out.add(new Comment(lineSt, "block", s.substring(st, i)));
                } else {
                    out.add(new Comment(lineSt, "block", s.substring(st))); // незакрытый до EOF
                }
                continue;
            }
            i++;
        }
        return out;
    }

    /** Lua: -- ... и --[[ ... ]] (с уровнями скобок [==[ ]==]). Строки в '...' и "..." с экранированием. */
    static List<Comment> scanLua(String s) {
        List<Comment> out = new ArrayList<>();
        int n = s.length(), i = 0, line = 1;
        while (i < n) {
            char c = s.charAt(i);
            if (c == '\n') { line++; i++; continue; }

            if (c == '"' || c == '\'') {
                char q = c;
                i++;
                while (i < n) {
                    char d = s.charAt(i);
                    if (d == '\\') { i += 2; continue; }
                    if (d == '\n' || d == q) break;
                    i++;
                }
                if (i < n && s.charAt(i) == q) i++; // закрывающая кавычка
                continue;
            }

            // Длинная строка [[ ... ]] / [==[ ]==] — внутри неё -- не комментарий
            if (c == '[') {
                int j = i + 1, lv = 0;
                while (j < n && s.charAt(j) == '=') { lv++; j++; }
                if (j < n && s.charAt(j) == '[') {
                    StringBuilder eq2 = new StringBuilder();
                    for (int q = 0; q < lv; q++) eq2.append('=');
                    String close = "]" + eq2.toString() + "]";
                    int k = j + 1;
                    while (k + close.length() <= n && !s.startsWith(close, k)) {
                        if (s.charAt(k) == '\n') line++;
                        k++;
                    }
                    i = (k + close.length() <= n) ? k + close.length() : n; // закрылась или до EOF
                    continue;
                }
            }

            if (c == '-' && i + 1 < n && s.charAt(i + 1) == '-') {
                int st = i, lineSt = line;
                // Длинный комментарий --[[ ... ]] / --[==[ ]==]
                if (i + 2 < n && s.charAt(i + 2) == '[') {
                    int j = i + 3, level = 0;
                    while (j < n && s.charAt(j) == '=') { level++; j++; }
                    if (j < n && s.charAt(j) == '[') {
                        StringBuilder eq = new StringBuilder();
                        for (int q = 0; q < level; q++) eq.append('='); // уровень скобок [==[ ]==]
                        String close = "]" + eq.toString() + "]";
                        int k = j + 1;
                        while (k + close.length() <= n && !s.startsWith(close, k)) {
                            if (s.charAt(k) == '\n') line++;
                            k++;
                        }
                        if (k + close.length() <= n) {
                            i = k + close.length(); // закрылся
                            out.add(new Comment(lineSt, "lua", s.substring(st, i)));
                        } else {
                            out.add(new Comment(lineSt, "lua", s.substring(st))); // незакрытый до EOF
                            break;
                        }
                        continue;
                    }
                }
                // Обычный однострочный --
                while (i < n && s.charAt(i) != '\n') i++;
                out.add(new Comment(lineSt, "lua", s.substring(st, i)));
                continue;
            }
            i++;
        }
        return out;
    }

    /** Batch: :: и REM — только в начале строки; REM как отдельное слово (REMbad не комментарий). */
    static List<Comment> scanBatch(String s) {
        List<Comment> out = new ArrayList<>();
        int n = s.length(), i = 0, line = 1;
        while (i < n) {
            // Начало строки — место проверки bat-комментариев
            if (i == 0 || s.charAt(i - 1) == '\n') {
                int lineSt = line;
                int j = i;
                while (j < n && (s.charAt(j) == ' ' || s.charAt(j) == '\t')) j++; // отступ не в текст комментария (как c_start в Python)
                if (s.startsWith("::", j)) {
                    while (i < n && s.charAt(i) != '\n') i++;
                    out.add(new Comment(lineSt, "bat", s.substring(j, i)));
                    continue;
                }
                if (j + 3 <= n && s.substring(j, j + 3).equalsIgnoreCase("REM")) {
                    int k = j + 3;
                    // REM — только как отдельное слово: после него EOL, пробел или tab (без ';', как в Python/PS)
                    if (k == n || s.charAt(k) == ' ' || s.charAt(k) == '\t') {
                        while (i < n && s.charAt(i) != '\n') i++;
                        out.add(new Comment(lineSt, "bat", s.substring(j, i)));
                        continue;
                    }
                }
            }
            if (s.charAt(i) == '\n') line++;
            i++;
        }
        return out;
    }

    // ---------- Сборка отчёта ----------

    /**
     * Строка отчёта для одного комментария (как format_comment в Python):
     * префикс «L12   [line]» выравнивается до 15 символов, текст — после пробела;
     * продолжение многострочного комментария — с отступом 15 пробелов.
     */
    static String formatComment(int lineNo, String type, String raw) {
        String[] lines = raw.split("\n", -1);
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < lines.length; k++) {
            String l = stripTrailingCr(lines[k]);
            if (k == 0) {
                String prefix = "L" + padRight(String.valueOf(lineNo), 4) + " [" + type + "]";
                sb.append(padRight(prefix, 15)).append(' ').append(l);
            } else {
                sb.append("               ").append(l); // 15 пробелов
            }
            if (k + 1 < lines.length) sb.append('\n');
        }
        return sb.toString();
    }

    /** Срезает хвостовые \r (CRLF-файлы), как rstrip('\\r') в Python. */
    static String stripTrailingCr(String s) {
        int e = s.length();
        while (e > 0 && s.charAt(e - 1) == '\r') e--;
        return s.substring(0, e);
    }

    /** Добирает строку пробелами справа до ширины w. */
    static String padRight(String s, int w) {
        if (s.length() >= w) return s;
        StringBuilder sb = new StringBuilder(s);
        for (int i = s.length(); i < w; i++) sb.append(' ');
        return sb.toString();
    }

    /** Финальный текст: блоки файлов + === SUMMARY === со счётчиками и списками. */
    static String buildReport(StringBuilder body, int scanned, int filesWithComments, int total,
                              List<String> unknownExt, List<String> unreadable,
                              List<String> binaryFiles, List<String> encFallbacks) {
        StringBuilder sb = new StringBuilder(body);
        sb.append("=== SUMMARY ===\n");
        sb.append("scanned_files: ").append(scanned).append('\n');
        sb.append("files_with_comments: ").append(filesWithComments).append('\n');
        sb.append("total_comments: ").append(total).append('\n');
        // Порядок и имена ключей — как в Python-версии
        appendList(sb, "skipped_unknown_ext", unknownExt);
        appendList(sb, "skipped_binary", binaryFiles);
        appendList(sb, "skipped_unreadable", unreadable);
        appendList(sb, "encoding_fallbacks", encFallbacks);
        return sb.toString();
    }

    /** Строка «name: N» + список файлов с префиксом «- »; порядок — ordinal-алфавитный, как в PowerShell. */
    static void appendList(StringBuilder sb, String name, List<String> items) {
        sb.append(name).append(": ").append(items.size()).append('\n');
        List<String> sorted = new ArrayList<>(items);
        sorted.sort(null); // compareTo — сравнение по UTF-16, то же самое, что [StringComparer]::Ordinal
        for (String p : sorted) sb.append("  - ").append(p).append('\n');
    }
}
