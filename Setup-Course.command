#!/bin/bash
cd "$(dirname "$0")"
bash ./install-macos.sh "$@"
code=$?
if [[ -t 0 && $# -eq 0 ]]; then
  printf '\nНажмите Enter, чтобы закрыть окно.\n'
  read -r _
fi
exit $code
