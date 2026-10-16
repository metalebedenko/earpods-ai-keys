#!/bin/sh
# One-off D8 trial for the author's second Mac. No installer/files/settings edits.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

match='{"VendorID":1452,"ProductID":4363,"PrimaryUsagePage":12,"PrimaryUsage":1}'
original='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":51539607757,"HIDKeyboardModifierMappingDst":51539607759},{"HIDKeyboardModifierMappingSrc":51539607786,"HIDKeyboardModifierMappingDst":30064771114},{"HIDKeyboardModifierMappingSrc":51539607785,"HIDKeyboardModifierMappingDst":30064771112}]}'
trial='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":51539607757,"HIDKeyboardModifierMappingDst":51539607768},{"HIDKeyboardModifierMappingSrc":51539607786,"HIDKeyboardModifierMappingDst":30064771114},{"HIDKeyboardModifierMappingSrc":51539607785,"HIDKeyboardModifierMappingDst":30064771112}]}'

fail() { printf '\nОшибка: %s\n' "$*" >&2; exit 1; }
recovery_hint() {
    printf '%s\n' 'Подключи EarPods и запусти этот файл ещё раз: если пробное правило осталось, он вернёт установленную схему.' \
      'Либо из папки с файлом: /bin/sh ./EarPods-Dictation-Test.command --restore' >&2
}

# Recognize exactly one matching service and exactly the supported three pairs.
# Unknown/multiple/changed rules are never overwritten.
inspect_mapping() {
    state=$(/usr/bin/hidutil property --matching "$match" --get UserKeyMapping) || return 1
    compact=$(printf '%s' "$state" | /usr/bin/tr -d '[:space:]')
    if [ "$compact" = RegistryIDKeyValue ]; then map_state=absent; return 0; fi
    rows=$(printf '%s\n' "$state" | /usr/bin/awk '$2 == "UserKeyMapping" {n++} END {print n+0}')
    if [ "$rows" -ne 1 ]; then map_state=foreign; return 0; fi
    payload=$(printf '%s\n' "$state" | /usr/bin/awk '
      $2 == "UserKeyMapping" {sub(/^.*UserKeyMapping[[:space:]]*/, ""); print; found=1; next}
      found {print}')
    compact=$(printf '%s' "$payload" | /usr/bin/tr -d '[:space:]')
    case "$compact" in '(null)'|'()'|'[]') map_state=empty; return 0 ;; esac
    map_state=$(printf '%s\n' "$payload" | /usr/bin/awk '
      /^[[:space:]]*\([[:space:]]*$/ {next}
      /^[[:space:]]*\)[[:space:]]*$/ {next}
      /^[[:space:]]*\{[[:space:]]*$/ {s=""; d=""; blocks++; next}
      /^[[:space:]]*HIDKeyboardModifierMappingSrc = [0-9]+;[[:space:]]*$/ {ns++; s=$3+0; next}
      /^[[:space:]]*HIDKeyboardModifierMappingDst = [0-9]+;[[:space:]]*$/ {nd++; d=$3+0; next}
      /^[[:space:]]*\},?[[:space:]]*$/ {
        if (s==51539607757 && (d==51539607759 || d==51539607768)) {c++; center=d}
        else if (s==51539607786 && d==30064771114) b++;
        else if (s==51539607785 && d==30064771112) e++;
        else bad++;
        next
      }
      /^[[:space:]]*$/ {next}
      {bad++}
      END {
        if (blocks!=3 || ns!=3 || nd!=3 || c!=1 || b!=1 || e!=1 || bad!=0) print "foreign";
        else if (center==51539607759) print "original";
        else print "trial";
      }')
}

restore_mapping() {
    inspect_mapping || { printf '%s\n' 'Не удалось проверить правило для возврата.' >&2; return 1; }
    case "$map_state" in
      original) printf '%s\n' 'Установленная схема уже на месте.'; return 0 ;;
      trial) ;;
      *) printf '%s\n' 'Правило отсутствует либо изменилось: автоматический возврат остановлен, чужие настройки сохранены.' >&2; return 1 ;;
    esac
    /usr/bin/hidutil property --matching "$match" --set "$original" >/dev/null || return 1
    inspect_mapping || return 1
    [ "$map_state" = original ] || return 1
    printf '%s\n' 'Возврат проверен: центр = прежний VoiceCommand, минус = Backspace, плюс = Enter.'
}

mode=${1-}
[ "$#" -le 1 ] || fail 'Допустим только необязательный аргумент --restore.'
case "$mode" in ''|--restore) ;; *) fail 'Допустим только необязательный аргумент --restore.' ;; esac
model=$(/usr/sbin/sysctl -n hw.model) || fail 'Не удалось определить модель Mac.'
[ "$model" = Mac15,13 ] || fail 'Этот пробный файл подготовлен для второго Mac (Mac15,13). Настройки не изменены.'
printf '%s\n' 'EarPods AI Keys — временная проверка запуска диктовки' "Mac: $model"

if [ "$mode" = --restore ]; then
    restore_mapping || { recovery_hint; exit 1; }
    exit 0
fi
[ -t 0 ] || fail 'Запусти двойным кликом в Finder или вручную в интерактивном Терминале.'
inspect_mapping || fail 'Не удалось прочитать текущее правило EarPods.'
case "$map_state" in
  trial)
    printf '%s\n' 'Обнаружена незавершённая предыдущая проба. Возвращаю установленную схему.'
    restore_mapping || { recovery_hint; exit 1; }
    printf '%s\n' 'Для новой проверки запусти файл повторно.'
    exit 0 ;;
  original) ;;
  absent) fail 'EarPods не обнаружены. Подключи их и запусти файл снова.' ;;
  empty) fail 'Установленное правило не активно. Сначала выполни apply основного пакета.' ;;
  *) fail 'Текущее правило отличается от нашей схемы. Оно сохранено без изменений.' ;;
esac

printf '\n%s\n' 'Проверим только центр: временно назначим HID D8 (Start/Stop Voice Dictation).' \
  'Enter и Backspace сохраняются. Настройки диктовки, Siri и автозапуска не меняются.' \
  'После проверки файл вернёт правило установленного пакета. Это ещё не полный uninstall.' \
  'Оставь EarPods подключёнными и окно Терминала открытым до ввода результата.' \
  'Нажми Enter, чтобы начать, или Ctrl+C, чтобы выйти.'
read -r ready || exit 1

armed=no
cleanup() {
    result=$?
    trap - 0 HUP INT TERM
    if [ "$armed" = yes ]; then
        if ! restore_mapping; then
            printf '%s\n' 'Автоматический возврат не завершён.' >&2
            recovery_hint
            result=1
        fi
    fi
    exit "$result"
}
trap cleanup 0
trap 'exit 130' INT
trap 'exit 129' HUP
trap 'exit 143' TERM
# Recheck after the user's preparation; never replace a newly changed rule.
inspect_mapping || fail 'Не удалось повторно проверить правило.'
[ "$map_state" = original ] || fail 'Правило изменилось до начала проверки; проба остановлена.'
armed=yes
/usr/bin/hidutil property --matching "$match" --set "$trial" >/dev/null || fail 'Пробное назначение не применилось.'
inspect_mapping || fail 'Не удалось проверить пробное назначение.'
[ "$map_state" = trial ] || fail 'Прочитанное правило не совпало с пробным.'

printf '\n%s\n' 'Пробное правило активно.' \
  '1. Открой пустой документ TextEdit и поставь курсор.' \
  '2. Коротко нажми и отпусти центр, произнеси фразу.' \
  '3. Если диктовка запустилась, повторным коротким нажатием проверь остановку.' \
  '4. Вернись в это окно Терминала и введи результат:' \
  '   1 — диктовка запускается и останавливается' \
  '   2 — ничего не происходит' \
  '   3 — появляется Siri' \
  '   4 — другой результат'
while :; do
    printf 'Результат (1–4): '
    read -r answer || exit 1
    case "$answer" in
      1) outcome='Диктовка запускается и останавливается' ;;
      2) outcome='Ничего не происходит' ;;
      3) outcome='Появляется Siri' ;;
      4) outcome='Другой результат' ;;
      *) continue ;;
    esac
    break
done
restore_mapping || { recovery_hint; exit 1; }
armed=no
printf '\nРезультат пользователя: %s\n' "$outcome"
printf '%s\n' 'Установленное правило восстановлено. Можно продолжать проверку uninstall основного пакета.' \
  'Пришли результат в чат. Нажми Enter, чтобы завершить.'
read -r finished || :
exit 0
