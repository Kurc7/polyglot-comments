@echo off
rem Запуск Java-сканера комментариев через JAR.
rem Корень сканирования = папка, из которой запущен bat (CWD).
setlocal
java -jar "%~dp0..\dist\scan-comments.jar" %*
pause
