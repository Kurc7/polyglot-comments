@echo off
rem Запуск сканера комментариев (Python, Windows).
rem Корень сканирования = текущая папка (CWD), из которой запущен bat.
python "%~dp0..\src\python\scan_comments.py" %*
pause
