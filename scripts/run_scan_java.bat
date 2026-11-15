@echo off
rem Запуск Java-сканера комментариев (Windows, двойной клик).
rem Корень сканирования = папка, из которой запущен bat (CWD).
chcp 65001 >nul
where javac >nul 2>nul || (
    echo [ОШИБКА] JDK не найден: установите JDK и добавьте javac в PATH.
    pause
    exit /b 1
)
rem Убираем старые классы: javac молча пропускает сборку, если .class новее .java
if exist "%TEMP%\scan_comments_classes" rmdir /s /q "%TEMP%\scan_comments_classes"
javac -encoding UTF-8 -d "%TEMP%\scan_comments_classes" "%~dp0..\src\java\ScanComments.java" || (
    echo [ОШИБКА] Не удалось скомпилировать ScanComments.java
    pause
    exit /b 1
)
java -cp "%TEMP%\scan_comments_classes" ScanComments %*
pause
