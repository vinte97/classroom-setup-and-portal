#!/bin/bash
# Общие решения установщика. Подключается из install-macos.sh.

plan_action() {
  local cur="$1" exp="$2" prev="$3"
  if [[ -z "$cur" ]]; then
    printf '%s\n' "COPY"
    return 0
  fi
  if [[ "$cur" == "$exp" ]]; then
    printf '%s\n' "UNCHANGED"
    return 0
  fi
  if [[ -n "$prev" && "$cur" == "$prev" ]]; then
    printf '%s\n' "UPDATE"
    return 0
  fi
  printf '%s\n' "KEEP"
}

decide_status() {
  local os_ok="$1" space_ok="$2" pack_ok="$3" writable="$4" materials="$5"
  local workai="$6" mode="$7" git_ok="$8" py_ok="$9"
  if [[ "$os_ok" != 1 || "$space_ok" != 1 || "$pack_ok" != 1 || "$writable" != 1 || "$materials" != 1 ]]; then
    printf '%s\n' "ТРЕБУЕТСЯ ПОМОЩЬ"
    return 0
  fi
  if [[ "$workai" == 1 ]]; then
    if [[ "$mode" != "ADVANCED" || ( "$git_ok" == 1 && "$py_ok" == 1 ) ]]; then
      printf '%s\n' "ГОТОВО"
      return 0
    fi
  fi
  printf '%s\n' "ЧАСТИЧНО"
}

redact_line() {
  # shortcut: прячем значения после маркера, не весь журнал
  printf '%s\n' "$1" | sed -E \
    -e 's/([Aa]uthorization[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[скрыто]/g' \
    -e 's/([Bb]earer[[:space:]]+)[^[:space:]]+/\1[скрыто]/g' \
    -e 's/([Tt]oken|[Pp]assword|[Ss]ecret|[Aa]pi[_-]?[Kk]ey)([[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1\2[скрыто]/g'
}

hash_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

read_state_hash() {
  local state="$1" path="$2" line
  [[ -f "$state" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      *$'\t'*)
        if [[ "${line%%$'\t'*}" == "$path" ]]; then
          printf '%s\n' "${line#*$'\t'}"
          return 0
        fi
        ;;
    esac
  done < "$state"
}

verify_tree() {
  local src="$1" sums="$2" line hash path got
  [[ -f "$sums" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    hash="${line:0:64}"
    path="${line:66}"
    [[ -n "$path" && -f "$src/$path" ]] || return 1
    got="$(hash_file "$src/$path")"
    [[ "$got" == "$hash" ]] || return 1
  done < "$sums"
}

sync_tree() {
  local src="$1" dest="$2" sums="$3" state="$4"
  local line hash path got prev action n_copy=0 n_update=0 n_keep=0 n_same=0
  local tmp_state
  tmp_state="$(mktemp)"
  if [[ -f "$state" ]]; then
    grep -v $'\t' "$state" > "$tmp_state" || true
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    hash="${line:0:64}"
    path="${line:66}"
    if [[ -f "$dest/$path" ]]; then
      got="$(hash_file "$dest/$path")"
    else
      got=""
    fi
    prev="$(read_state_hash "$state" "$path")"
    action="$(plan_action "$got" "$hash" "$prev")"
    case "$action" in
      COPY|UPDATE)
        mkdir -p "$(dirname "$dest/$path")" || return 1
        cp -p "$src/$path" "$dest/$path" || return 1
        printf '%s\t%s\n' "$path" "$hash" >> "$tmp_state"
        if [[ "$action" == COPY ]]; then
          n_copy=$((n_copy + 1))
        else
          n_update=$((n_update + 1))
        fi
        ;;
      UNCHANGED)
        printf '%s\t%s\n' "$path" "$hash" >> "$tmp_state"
        n_same=$((n_same + 1))
        ;;
      KEEP)
        if [[ -n "$prev" ]]; then
          printf '%s\t%s\n' "$path" "$prev" >> "$tmp_state"
        fi
        n_keep=$((n_keep + 1))
        ;;
    esac
  done < "$sums"
  mv "$tmp_state" "$state"
  printf '%s %s %s %s\n' "$n_copy" "$n_update" "$n_keep" "$n_same"
}

run_self_check() {
  local fail=0
  check() {
    local got="$1" want="$2" name="$3"
    if [[ "$got" != "$want" ]]; then
      printf 'FAIL %s: получено [%s], ожидалось [%s]\n' "$name" "$got" "$want"
      fail=1
    fi
  }
  check "$(plan_action "" "abc" "")" "COPY" "missing"
  check "$(plan_action "abc" "abc" "abc")" "UNCHANGED" "same"
  check "$(plan_action "old" "new" "old")" "UPDATE" "our previous file"
  check "$(plan_action "user" "new" "old")" "KEEP" "user edit"
  check "$(plan_action "user" "new" "")" "KEEP" "foreign file"
  check "$(decide_status 1 1 1 1 1 1 BASIC 0 0)" "ГОТОВО" "basic ready"
  check "$(decide_status 1 1 1 1 1 0 BASIC 0 0)" "ЧАСТИЧНО" "no workai"
  check "$(decide_status 1 1 1 1 1 1 ADVANCED 0 1)" "ЧАСТИЧНО" "no git"
  check "$(decide_status 1 0 1 1 1 1 BASIC 1 1)" "ТРЕБУЕТСЯ ПОМОЩЬ" "no space"
  check "$(decide_status 1 1 0 1 1 1 BASIC 1 1)" "ТРЕБУЕТСЯ ПОМОЩЬ" "bad pack"
  check "$(decide_status 1 1 1 1 1 1 ADVANCED 1 1)" "ГОТОВО" "advanced ready"
  local hidden
  hidden="$(redact_line "url?token=supersecret value")"
  case "$hidden" in
    *supersecret*) check "leaked" "hidden" "redact token" ;;
  esac
  case "$hidden" in
    *"[скрыто]"*) ;;
    *) check "no-mark" "mark" "redact mark" ;;
  esac
  local plain
  plain="$(redact_line "Обычная строка про токены без значения")"
  check "$plain" "Обычная строка про токены без значения" "redact keeps prose"
  if [[ "$fail" -ne 0 ]]; then
    return 1
  fi
  printf '%s\n' "self-check ok"
}
