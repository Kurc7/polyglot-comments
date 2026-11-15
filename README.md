# Сканер комментариев

Сканер комментариев в исходном коде с тремя независимыми реализациями:
**Python**, **PowerShell**, **Java**. Ключевое свойство проекта: отчёты всех версий
совпадают **побайтово** (`comments_report.txt`).

## Требования

- Python 3 — для основной версии;
- PowerShell 5.1+ (Windows) или pwsh (Linux/macOS);
- JDK с `javac` в PATH — только для `run_scan_java.bat`;
- JRE достаточно для запуска через JAR (`dist/scan-comments.jar`).

## Запуск

Сканер сканирует **текущую папку** (CWD) и пишет `comments_report.txt` в неё.
Откройте терминал в папке, которую нужно просканировать:

| Платформа | Команда |
|---|---|
| Windows (Python) | `..\check_comments\scripts\run_scan.bat` (или двойной клик) |
| Linux/macOS (Python) | `sh ../check_comments/scripts/run_scan.sh` |
| Windows (PowerShell) | `powershell -ExecutionPolicy Bypass -File ..\check_comments\src\powershell\scan_comments.ps1` |
| Windows (Java, нужен JDK) | `..\check_comments\scripts\run_scan_java.bat` |
| Любая (JAR, без JDK) | `java -jar ../check_comments/dist/scan-comments.jar` или `..\check_comments\scripts\run_scan_jar.bat` |

Все четыре способа дают одинаковый отчёт.

## Поддерживаемые языки

| Стиль | Расширения |
|---|---|
| C-стиль (`//`, `/* */`) | `.c .h .cpp .hpp .cc .cs .go .kt .kts .scala .php .swift .dart .rs .css .scss .less .groovy .gradle .proto .java .js .jsx .ts .tsx` |
| Hash (`#`) | `.py .rb .sh .bash .zsh .yaml .yml .properties .conf .toml .ini .r .pl .ps1 .dockerfile .gitignore .env .tf`, файл `Dockerfile` |
| XML (`<!-- -->`) | `.xml .html .htm .xhtml .svg .jsp .ftl .xsd .wsdl .pom .vue .svelte` |
| SQL | `.sql` |
| Lua | `.lua` |
| Batch | `.bat .cmd` (`REM` и `::`) |

## Структура проекта

```
├── README.md                 — это описание
├── AGENTS.md                 — контекст для AI-агентов: инвариант, нюансы, проверка
├── src/
│   ├── python/scan_comments.py      — реализация на Python (эталон)
│   ├── powershell/scan_comments.ps1 — реализация на PowerShell
│   └── java/ScanComments.java       — реализация на Java (один файл, без зависимостей)
├── scripts/                  — раннеры (bat/sh), все сканируют CWD
├── fixtures/demo/            — тестовое дерево: кодировки, CRLF, исключённые папки, все стили
└── dist/scan-comments.jar    — переносимый JAR (Main-Class: ScanComments)
```

## Пересборка JAR (после правок `src/java`)

```sh
javac -encoding UTF-8 -d /tmp/sc_classes src/java/ScanComments.java
jar --create --file dist/scan-comments.jar --main-class ScanComments -C /tmp/sc_classes .
```

## Проверка побайтового равенства

Полный рецепт — в [AGENTS.md](AGENTS.md#проверка-инварианта).
