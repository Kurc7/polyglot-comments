#!/bin/sh
# Запуск сканера комментариев (Python, Linux/macOS).
# Корень сканирования = текущая папка (CWD), из которой запущен скрипт.
python3 "$(dirname "$0")/../src/python/scan_comments.py" "$@"
