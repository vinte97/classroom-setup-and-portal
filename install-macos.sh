#!/bin/bash
# Установка курса «ИИ для руководителей v2» на macOS 12+.
# Не отключает Gatekeeper и не ставит Homebrew удалённым скриптом.

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/course_sync.sh
. "$ROOT/lib/course_sync.sh"

MODE=""
ASSUME_YES=0
DRY_RUN=0
SELF_CHECK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
      shift 2
      ;;
    --yes) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --self-check) SELF_CHECK=1; shift ;;
    -h|--help)
      printf '%s\n' "Использование: ./install-macos.sh [--mode basic|advanced] [--yes] [--dry-run]"
      exit 0
      ;;
    *)
      printf 'Неизвестный аргумент: %s\n' "$1"
      exit 1
      ;;
  esac
done

if [[ "$SELF_CHECK" -eq 1 ]]; then
  run_self_check
  exit $?
fi

LOG_FILE="${TMPDIR:-/tmp}/ai-managers-v2-setup.log"
: > "$LOG_FILE"

log() {
  local line
  line="$(redact_line "$*")"
  printf '%s\n' "$line" | tee -a "$LOG_FILE"
}

cfg() {
  sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$ROOT/config/sources.json" | head -1
}

open_url() {
  log "Страница: $1"
  if [[ "$DRY_RUN" -eq 1 || "${COURSE_SETUP_TEST:-}" == "1" ]]; then
    return 0
  fi
  open "$1" || log "Не удалось открыть браузер. Скопируйте адрес выше."
}

finish() {
  local status="$1"
  log "================================"
  log "ИТОГ: $status"
  log "Журнал: $LOG_FILE"
  log "================================"
  case "$status" in
    ГОТОВО) exit 0 ;;
    ЧАСТИЧНО) exit 2 ;;
    *) exit 3 ;;
  esac
}

shopt -s nullglob

if [[ "${COURSE_SETUP_TEST:-}" == "1" ]]; then
  if [[ -z "${COURSE_HOME:-}" || "$COURSE_HOME" == "/" || "$COURSE_HOME" == "$HOME" ]]; then
    printf '%s\n' "COURSE_HOME для теста задан небезопасно"
    exit 1
  fi
  DEST="$COURSE_HOME"
else
  DEST="$HOME/Documents/$(cfg course_dir_name)"
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  log "Этот файл только для macOS. На Windows запустите Setup-Course.cmd."
  finish "ТРЕБУЕТСЯ ПОМОЩЬ"
fi

os_ok=1
ver="$(sw_vers -productVersion)"
major="${ver%%.*}"
if [[ "$major" -lt 12 ]]; then
  os_ok=0
  log "Нужна macOS 12 или новее. Сейчас: $ver"
else
  log "macOS $ver, архитектура $(uname -m)"
fi

if [[ "$(id -u)" -eq 0 ]]; then
  log "Скрипт запущен от имени root. Запустите его от своего пользователя."
  finish "ТРЕБУЕТСЯ ПОМОЩЬ"
fi

space_target="$HOME"
[[ -d "$HOME/Documents" ]] && space_target="$HOME/Documents"
free_kb="$(df -k "$space_target" | awk 'NR==2 {print $4}')"
free_mb=$((free_kb / 1024))
min_mb="$(cfg min_free_mb)"
space_ok=1
if [[ "$free_mb" -lt "$min_mb" ]]; then
  space_ok=0
  log "Свободно ${free_mb} МБ, нужно не меньше ${min_mb} МБ."
else
  log "Свободно около ${free_mb} МБ."
fi

writable=1
parent="$HOME/Documents"
[[ "${COURSE_SETUP_TEST:-}" == "1" ]] && parent="$(dirname "$DEST")"
if [[ -d "$parent" && ! -w "$parent" ]]; then
  writable=0
  log "Нет права записи в $parent"
elif [[ ! -d "$parent" && ! -w "$(dirname "$parent")" ]]; then
  writable=0
  log "Нельзя создать $parent"
else
  log "Папка курса: $DEST"
fi

pack_dir=""
pack_ok=0
work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

if verify_tree "$ROOT/course-pack/files" "$ROOT/course-pack/SHA256SUMS"; then
  pack_dir="$ROOT/course-pack/files"
  pack_ok=1
  log "Локальный пакет совпал с SHA-256."
else
  zip_line="$(head -1 "$ROOT/course-pack/ZIP.SHA256" || true)"
  zip_hash="${zip_line:0:64}"
  found_zip=""
  for candidate in "$ROOT/offline"/*.zip "$ROOT/course-pack"/*.zip "$ROOT/docs/files"/*.zip; do
    [[ -f "$candidate" ]] || continue
    if [[ "$(hash_file "$candidate")" == "$zip_hash" ]]; then
      found_zip="$candidate"
      break
    fi
    log "Архив не совпал с контрольной суммой и пропущен: $(basename "$candidate")"
  done
  if [[ -z "$found_zip" && -f "$ROOT/course-pack/download.url" ]]; then
    pack_url="$(head -1 "$ROOT/course-pack/download.url")"
    log "Пробую скачать пакет по адресу из course-pack/download.url"
    if curl -fsSL --max-time 180 -o "$work/pack.zip" "$pack_url"; then
      if [[ "$(hash_file "$work/pack.zip")" == "$zip_hash" ]]; then
        found_zip="$work/pack.zip"
      else
        log "Скачанный пакет не совпал с SHA-256. Он не будет распакован."
        rm -f "$work/pack.zip"
      fi
    else
      log "Скачать пакет не удалось. Берём запасной вариант, если он есть."
    fi
  fi
  if [[ -n "$found_zip" ]]; then
    if tar -xf "$found_zip" -C "$work"; then
      if verify_tree "$work" "$ROOT/course-pack/SHA256SUMS"; then
        pack_dir="$work"
        pack_ok=1
        log "Пакет взят из архива и прошёл SHA-256."
      else
        log "Архив распаковался, но файлы не совпали с SHA256SUMS."
      fi
    else
      log "Не удалось распаковать архив."
    fi
  fi
fi

if [[ "$pack_ok" -ne 1 ]]; then
  log "Учебный пакет недоступен или повреждён."
fi

man_ver="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/course-pack/manifest.json" | head -1)"
src_ver="$(cfg pack_version)"
if [[ -n "$man_ver" && "$man_ver" != "$src_ver" ]]; then
  pack_ok=0
  log "Версия пакета $man_ver не совпадает с config/sources.json ($src_ver)."
fi

workai=0
if [[ -d "/Applications/WorkAI.app" || -d "$HOME/Applications/WorkAI.app" ]]; then
  workai=1
fi
if [[ "$workai" -eq 0 ]]; then
  spot="$(find /Applications "$HOME/Applications" -maxdepth 2 -name "WorkAI.app" -print -quit 2>/dev/null || true)"
  [[ -n "$spot" ]] && workai=1
fi
if [[ "$workai" -eq 1 ]]; then
  log "WorkAI найден. Заново ставить его не будем."
else
  log "WorkAI в папке «Программы» не найден."
fi

local_installer=""
for candidate in "$ROOT/offline/workai"/*.dmg; do
  [[ -f "$candidate" ]] || continue
  local_installer="$candidate"
  break
done

net_workai="$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 -I -L -- "$(cfg workai_download)" || true)"
case "$net_workai" in
  2*|3*) log "Сайт WorkAI отвечает: $net_workai" ;;
  *) log "Сайт WorkAI сейчас не открылся (код ${net_workai:-000}). Установка файлов курса от этого не зависит." ;;
esac

portal="$(cfg portal_url)"
if [[ -n "$portal" ]]; then
  net_portal="$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 -I -L -- "$portal" || true)"
  case "$net_portal" in
    2*|3*) log "Учебный сайт отвечает: $net_portal" ;;
    *) log "Учебный сайт не открылся. Локальная копия: $ROOT/docs/index.html" ;;
  esac
else
  log "Адрес учебного сайта в настройках пуст. Локально откройте docs/index.html"
fi
[[ -f "$ROOT/docs/index.html" ]] || log "Рядом со скриптом нет docs/index.html"

git_ok=0
py_ok=0
if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
  git_ok=1
  log "Git уже есть: $(git --version). Менять установку не будем."
else
  log "Git не найден."
fi
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
  py_ok=1
  log "Python уже есть: $(python3 --version 2>&1). Менять установку не будем."
elif command -v python3 >/dev/null 2>&1; then
  log "Python есть, но версия ниже 3.9: $(python3 --version 2>&1). Текущую установку не удаляем."
else
  log "Python 3 не найден."
fi

if [[ -z "$MODE" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    MODE="BASIC"
    log "Режим не задан, для dry-run берём BASIC."
  elif [[ "$ASSUME_YES" -eq 1 ]]; then
    log "С ключом --yes нужен --mode basic или --mode advanced."
    exit 1
  else
    printf '%s\n' "Какой режим нужен?"
    printf '%s\n' "1 — BASIC: учебные файлы и страница WorkAI"
    printf '%s\n' "2 — ADVANCED: то же плюс Git и Python, если их ещё нет"
    read -r choice
    case "$choice" in
      2) MODE="ADVANCED" ;;
      1) MODE="BASIC" ;;
      *)
        log "Режим не выбран. Изменения не выполнялись."
        exit 0
        ;;
    esac
  fi
fi

if [[ "$MODE" != "BASIC" && "$MODE" != "ADVANCED" ]]; then
  log "Режим должен быть BASIC или ADVANCED."
  exit 1
fi

log "План, режим $MODE:"
log "1. Скопировать учебные файлы в $DEST. Ваши изменённые файлы не затираются."
if [[ "$workai" -eq 1 ]]; then
  log "2. WorkAI уже есть, установщик не открываем."
elif [[ -n "$local_installer" ]]; then
  log "2. Открыть локальный установщик WorkAI обычным мастером: $local_installer"
  log "   Тихий режим не используется: официальные параметры тихой установки не опубликованы."
else
  log "2. Открыть официальную страницу загрузки WorkAI. Войти в аккаунт нужно самим."
fi
if [[ "$MODE" == "ADVANCED" ]]; then
  if [[ "$git_ok" -eq 1 ]]; then
    log "3. Git не переустанавливаем."
  elif command -v brew >/dev/null 2>&1; then
    log "3. Поставить Git формулой Homebrew «$(cfg brew_git_formula)», если его нет."
  else
    log "3. Homebrew нет. Скрипт его не ставит. Откроем страницу Git."
  fi
  if [[ "$py_ok" -eq 1 ]]; then
    log "4. Python не переустанавливаем."
  elif command -v brew >/dev/null 2>&1; then
    log "4. Поставить формулу «$(cfg brew_python_formula)» рядом, не удаляя другую версию."
  else
    log "4. Откроем страницу Python. Установщик Homebrew скрипт не скачивает."
  fi
fi
log "Защиту macOS скрипт не отключает."

if [[ "$os_ok" -ne 1 || "$space_ok" -ne 1 || "$pack_ok" -ne 1 || "$writable" -ne 1 ]]; then
  [[ "$DRY_RUN" -eq 1 ]] && log "dry-run: изменения не выполнялись."
  finish "ТРЕБУЕТСЯ ПОМОЩЬ"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry-run: изменения не выполнялись."
  status="$(decide_status "$os_ok" "$space_ok" "$pack_ok" "$writable" "$pack_ok" "$workai" "$MODE" "$git_ok" "$py_ok")"
  finish "$status"
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  printf '%s\n' "Начать эти действия? Введите да или нет:"
  read -r answer
  case "$answer" in
    да|Да|ДА|д|y|Y|yes|YES) ;;
    *)
      log "Изменения не выполнялись."
      exit 0
      ;;
  esac
fi

mkdir -p "$DEST/logs"
state="$DEST/.course-setup.state"
printf 'pack_version=%s\nmode=%s\n' "$man_ver" "$MODE" > "$state"
if counts="$(sync_tree "$pack_dir" "$DEST" "$ROOT/course-pack/SHA256SUMS" "$state")"; then
  materials_ok=1
  log "Учебные файлы — новые, обновлены, сохранены ваши, без изменений: $counts"
else
  materials_ok=0
  log "Копирование учебных файлов прервалось."
fi

if [[ "$workai" -ne 1 ]]; then
  if [[ -n "$local_installer" ]]; then
    open_url_target="$local_installer"
    log "Открываем локальный образ WorkAI. Дальше нажимайте кнопки мастера сами."
    if [[ "${COURSE_SETUP_TEST:-}" != "1" ]]; then
      open "$local_installer" || log "Откройте образ WorkAI вручную из offline/workai."
    fi
  else
    log "Дальше установка WorkAI вручную. Скрипт не выключает Gatekeeper."
    open_url "$(cfg workai_download)"
    log "Если macOS спросит подтверждение, это штатная защита. Разрешите запуск сами, если доверяете файлу с официального сайта."
  fi
fi

if [[ "$MODE" == "ADVANCED" && "${COURSE_SETUP_TEST:-}" != "1" ]]; then
  if [[ "$git_ok" -ne 1 ]]; then
    if command -v brew >/dev/null 2>&1; then
      log "Ставлю Git через Homebrew."
      if HOMEBREW_NO_ANALYTICS=1 brew install "$(cfg brew_git_formula)"; then
        git_ok=1
        log "Git установлен: $(git --version 2>&1 || true)"
      else
        log "Homebrew не смог поставить Git."
        open_url "$(cfg git_macos_download)"
      fi
    else
      open_url "$(cfg brew_home)"
      open_url "$(cfg git_macos_download)"
    fi
  fi
  if [[ "$py_ok" -ne 1 ]]; then
    if command -v brew >/dev/null 2>&1; then
      log "Ставлю Python через Homebrew. Уже стоящий Python не удаляется."
      if HOMEBREW_NO_ANALYTICS=1 brew install "$(cfg brew_python_formula)"; then
        py_ok=1
      else
        log "Homebrew не смог поставить Python."
        open_url "$(cfg python_macos_download)"
      fi
    else
      open_url "$(cfg python_macos_download)"
    fi
  fi
fi

if [[ "$MODE" == "ADVANCED" && "${COURSE_SETUP_TEST:-}" == "1" ]]; then
  log "Тестовый режим: Git и Python не ставятся."
fi

stamp="$(date +%Y%m%d-%H%M%S)"
saved="$DEST/logs/setup-$stamp.log"
if cp "$LOG_FILE" "$saved"; then
  LOG_FILE="$saved"
fi

status="$(decide_status "$os_ok" "$space_ok" "$pack_ok" "$writable" "$materials_ok" "$workai" "$MODE" "$git_ok" "$py_ok")"
if [[ "$status" == "ЧАСТИЧНО" ]]; then
  log "Осталось сделать вручную то, что перечислено выше. Повторный запуск безопасен."
fi
if [[ "$status" == "ГОТОВО" ]]; then
  log "Можно открывать WorkAI и папку курса. Вход в аккаунт скрипт не выполняет."
fi
finish "$status"
