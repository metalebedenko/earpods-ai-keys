#!/bin/sh
# EarPods AI Keys: native macOS Dictation, Backspace and Enter.
set -eu
umask 077

label=local.earpods-ai-keys
match='{"VendorID":1452,"ProductID":4363,"PrimaryUsagePage":12,"PrimaryUsage":1}'
source_dir=$(CDPATH= cd -P "$(/usr/bin/dirname "$0")" && /bin/pwd)

usage() {
    printf '%s\n' 'Usage: earpods-ai-keys.sh install|status|apply|uninstall' \
      'install    Install for this user; apply once when launchd loads the job.' \
      'status     Report files, EarPods, mapping, launchd and legacy installs.' \
      'apply      Restore the three keys when EarPods have no existing mapping.' \
      'uninstall  Stop the job, clear only our exact mapping, remove owned files.' \
      'Exit codes: 0 success, 1 failure, 2 usage, 3 device absent, 4 conflict.'
}
fail() { printf '%s\n' "Error: $*" >&2; exit 1; }
conflict() { printf '%s\n' "Conflict: $*" >&2; exit 4; }
case "${1-}" in -h|--help|help) usage; exit 0 ;; esac
if [ "$#" -ne 1 ]; then usage >&2; exit 2; fi
case "$1" in install|status|apply|uninstall) command=$1 ;; *) usage >&2; exit 2 ;; esac
case "${HOME-}" in /*) ;; *) fail 'HOME must be an absolute directory.' ;; esac
[ "$HOME" != / ] || fail 'HOME must not be the filesystem root.'
user_id=$(/usr/bin/id -u) || fail 'Cannot identify the current user.'
[ "$user_id" != 0 ] || fail 'Run as your logged-in user, without sudo.'
install_dir="$HOME/Library/Application Support/EarPods AI Keys"
plist="$HOME/Library/LaunchAgents/$label.plist"
marker="$install_dir/.earpods-ai-keys-owned"
service="gui/$user_id/$label"

# Missing service is an expected result; other launchctl failures are errors.
probe_service() {
    if service_output=$(/bin/launchctl print "$1" 2>&1); then
        service_present=yes
    else
        case "$service_output" in
          *'Could not find service'*) service_present=no ;;
          *) fail "Cannot inspect launchd service $1: $service_output" ;;
        esac
    fi
}
find_legacy() {
    legacy=none
    for old_label in local.earpods-macos-dictation local.earpods-gpt-dictation; do
        if [ -e "$HOME/Library/LaunchAgents/$old_label.plist" ] ||
           [ -L "$HOME/Library/LaunchAgents/$old_label.plist" ]; then
            legacy=$old_label
            return
        fi
        probe_service "gui/$user_id/$old_label"
        if [ "$service_present" = yes ]; then legacy=$old_label; return; fi
    done
}
reject_legacy() {
    find_legacy
    [ "$legacy" = none ] || conflict "Legacy $legacy found. Keep it or remove it separately; this package does not migrate it."
}

# Parse only known hidutil output. Unknown/nonempty values are never replaced.
inspect_mapping() {
    state=$(/usr/bin/hidutil property --matching "$match" --get UserKeyMapping) || fail 'Cannot read the EarPods HID mapping.'
    compact=$(printf '%s' "$state" | /usr/bin/tr -d '[:space:]')
    # With no matching services macOS can return successful, empty stdout;
    # An empty table header is accepted too. Neither result permits a write.
    case "$compact" in ''|RegistryIDKeyValue) mapping_state=absent; return ;; esac
    rows=$(printf '%s\n' "$state" | /usr/bin/awk '$2 == "UserKeyMapping" {n++} END {print n+0}')
    [ "$rows" -gt 0 ] || fail 'Unrecognized hidutil response; no changes made.'
    if [ "$rows" -ne 1 ]; then mapping_state=foreign; return; fi
    payload=$(printf '%s\n' "$state" | /usr/bin/awk '
      $2 == "UserKeyMapping" {sub(/^.*UserKeyMapping[[:space:]]*/, ""); print; found=1; next}
      found {print}')
    compact=$(printf '%s' "$payload" | /usr/bin/tr -d '[:space:]')
    case "$compact" in '(null)'|'()'|'[]') mapping_state=empty; return ;; esac
    if printf '%s\n' "$payload" | /usr/bin/awk '
      /^[[:space:]]*\([[:space:]]*$/ {next}
      /^[[:space:]]*\)[[:space:]]*$/ {next}
      /^[[:space:]]*\{[[:space:]]*$/ {s=""; d=""; blocks++; next}
      /^[[:space:]]*HIDKeyboardModifierMappingSrc = [0-9]+;[[:space:]]*$/ {ns++; s=$3+0; next}
      /^[[:space:]]*HIDKeyboardModifierMappingDst = [0-9]+;[[:space:]]*$/ {nd++; d=$3+0; next}
      /^[[:space:]]*\},?[[:space:]]*$/ {
        if (s==51539607757 && d==51539607759) c++;
        else if (s==51539607786 && d==30064771114) b++;
        else if (s==51539607785 && d==30064771112) e++;
        else bad++;
        next
      }
      /^[[:space:]]*$/ {next}
      {bad++}
      END {exit !(blocks==3 && ns==3 && nd==3 && c==1 && b==1 && e==1 && bad==0)}'; then
        mapping_state=ours
    else
        mapping_state=foreign
    fi
}
plist_value() { /usr/bin/plutil -extract "$1" raw -expect "$2" -- "$3"; }
validate_mapping_file() {
    file=$1
    [ -f "$file" ] && [ ! -L "$file" ] || fail 'The mapping.json asset is missing or a symlink.'
    count=$(plist_value UserKeyMapping array "$file") || fail 'Invalid mapping.json.'
    [ "$count" = 3 ] || fail 'mapping.json must contain exactly three pairs.'
    index=0
    for pair in '51539607757:51539607759' '51539607786:30064771114' '51539607785:30064771112'; do
        src=$(plist_value "UserKeyMapping.$index.HIDKeyboardModifierMappingSrc" integer "$file") || fail 'Invalid source in mapping.json.'
        dst=$(plist_value "UserKeyMapping.$index.HIDKeyboardModifierMappingDst" integer "$file") || fail 'Invalid destination in mapping.json.'
        [ "$src:$dst" = "$pair" ] || fail 'mapping.json differs from the supported three-key scheme.'
        index=$((index+1))
    done
    keys=$(/usr/bin/plutil -convert xml1 -o - -- "$file" | /usr/bin/awk '
      /<key>/ {n++; if ($0 !~ /<key>(UserKeyMapping|HIDKeyboardModifierMappingSrc|HIDKeyboardModifierMappingDst)<\/key>/) bad++}
      END {print n ":" bad+0}')
    [ "$keys" = 7:0 ] || fail 'mapping.json contains extra properties.'
}
apply_mapping() {
    reject_legacy
    inspect_mapping
    case "$mapping_state" in
      absent) printf '%s\n' 'EarPods are absent. Connect them and run apply.'; exit 3 ;;
      foreign) conflict 'Existing or unrecognized EarPods mapping preserved.' ;;
      ours) printf '%s\n' 'The three EarPods AI Keys are already active.'; return ;;
    esac
    validate_mapping_file "$source_dir/mapping.json"
    mapping=$(/bin/cat "$source_dir/mapping.json") || fail 'Cannot read mapping.json.'
    /usr/bin/hidutil property --matching "$match" --set "$mapping" >/dev/null || fail 'Cannot apply the EarPods mapping.'
    inspect_mapping
    [ "$mapping_state" = ours ] || fail 'HID readback does not match the three keys; inspect status before retrying.'
    printf '%s\n' 'Active HID mapping: center = VoiceCommand, minus = Backspace, plus = Enter.' \
      'Dictation with this profile was tested with Siri off; this script does not change Siri.'
}

# Fingerprints protect files changed or replaced after installation. They are
# an ownership check, not a security boundary against somebody controlling HOME.
fingerprint() { /usr/bin/cksum < "$1"; }
expected_marker() {
    cli_sig=$(fingerprint "$1/earpods-ai-keys.sh") || return 1
    map_sig=$(fingerprint "$1/mapping.json") || return 1
    plist_sig=$(fingerprint "$2") || return 1
    printf '%s\n' 'earpods-ai-keys-owned-v1'
    printf 'cli %s\n' "$cli_sig"
    printf 'mapping %s\n' "$map_sig"
    printf 'plist %s\n' "$plist_sig"
}
inspect_files() {
    files_state=absent
    if [ ! -e "$install_dir" ] && [ ! -L "$install_dir" ] && [ ! -e "$plist" ] && [ ! -L "$plist" ]; then return; fi
    files_state=unrecognized
    [ -d "$install_dir" ] && [ ! -L "$install_dir" ] || return 0
    for file in "$marker" "$install_dir/earpods-ai-keys.sh" "$install_dir/mapping.json" "$plist"; do
        [ -f "$file" ] && [ ! -L "$file" ] || return 0
    done
    expected=$(expected_marker "$install_dir" "$plist") || fail 'Cannot fingerprint installation files.'
    actual=$(/bin/cat "$marker") || fail 'Cannot read the ownership marker.'
    if [ "$expected" = "$actual" ]; then files_state=ours; fi
}
show_status() {
    inspect_files
    printf 'installation: %s\n' "$files_state"
    find_legacy
    printf 'legacy: %s\n' "$legacy"
    inspect_mapping
    case "$mapping_state" in absent) printf '%s\n' 'device: absent' ;; *) printf '%s\n' 'device: present' ;; esac
    printf 'mapping: %s\n' "$mapping_state"
    probe_service "$service"
    if [ "$service_present" = yes ]; then
        printf '%s\n' 'agent: registered'
    else
        printf '%s\n' 'agent: not registered'
    fi
}
cleanup_install() {
    if [ "$committed" = no ]; then
        if [ "$made_dir" = yes ]; then
            # Same-directory mv is atomic. Remove only unchanged files that
            # this attempt placed; never recursively remove a directory.
            for name in earpods-ai-keys.sh mapping.json .earpods-ai-keys-owned; do
                case "$name" in
                  earpods-ai-keys.sh) sig=$staged_cli_sig ;;
                  mapping.json) sig=$staged_map_sig ;;
                  *) sig=$staged_marker_sig ;;
                esac
                target="$install_dir/$name"
                if [ -f "$target" ] && [ ! -L "$target" ]; then
                    current_sig=$(fingerprint "$target") || current_sig=unreadable
                    if [ "$current_sig" = "$sig" ]; then /bin/rm -f "$target"; fi
                fi
            done
            /bin/rmdir "$install_dir" 2>/dev/null || :
        fi
        if [ "$made_plist" = yes ] && [ -f "$plist" ] && [ ! -L "$plist" ]; then
            current_inode=$(/usr/bin/stat -f %i "$plist") || current_inode=unknown
            if [ "$current_inode" = "$plist_inode" ]; then /bin/rm -f "$plist"; fi
        fi
    fi
    /bin/rm -f "$stage/earpods-ai-keys.sh" "$stage/mapping.json" "$stage/agent.plist" "$stage/.earpods-ai-keys-owned"
    /bin/rmdir "$stage" 2>/dev/null || :
}
install_package() {
    reject_legacy
    inspect_files
    case "$files_state" in
      ours) printf '%s\n' 'Already installed. Use status or apply.'; return ;;
      unrecognized) conflict 'Existing installation paths are not recognized as ours; nothing overwritten.' ;;
    esac
    probe_service "$service"
    [ "$service_present" = no ] || conflict 'This launchd label is already registered without our owned files.'
    inspect_mapping
    [ "$mapping_state" != foreign ] || conflict 'Existing or unrecognized EarPods mapping preserved; installation stopped.'
    validate_mapping_file "$source_dir/mapping.json"
    template="$source_dir/launchagent.template.plist"
    [ -f "$template" ] && [ ! -L "$template" ] || fail 'The launchagent template is missing or a symlink.'
    template_label=$(plist_value Label string "$template") || fail 'Invalid launchagent template.'
    [ "$template_label" = "$label" ] || fail 'Unexpected launchagent label.'
    for key in StartInterval KeepAlive; do
        if /usr/bin/plutil -extract "$key" raw -- "$template" >/dev/null 2>&1; then fail 'Polling or persistent jobs are not supported.'; fi
    done
    [ "$(plist_value RunAtLoad bool "$template")" = true ] || fail 'RunAtLoad must be true.'
    [ "$(plist_value ProgramArguments array "$template")" = 3 ] || fail 'Unexpected launchagent arguments.'
    [ "$(plist_value ProgramArguments.0 string "$template")" = /bin/sh ] || fail 'Unexpected launchagent interpreter.'
    [ "$(plist_value ProgramArguments.1 string "$template")" = '__USER_HOME__/Library/Application Support/EarPods AI Keys/earpods-ai-keys.sh' ] || fail 'Unexpected launchagent command.'
    [ "$(plist_value ProgramArguments.2 string "$template")" = apply ] || fail 'Unexpected launchagent action.'
    template_keys=$(/usr/bin/plutil -convert xml1 -o - -- "$template" | /usr/bin/awk '
      /<key>/ {n++; if ($0 !~ /<key>(Label|ProgramArguments|RunAtLoad|ProcessType)<\/key>/) bad++}
      END {print n ":" bad+0}')
    [ "$template_keys" = 4:0 ] || fail 'Unexpected launchagent properties.'
    [ "$(plist_value ProcessType string "$template")" = Background ] || fail 'Unexpected process type.'
    /bin/mkdir -p "$HOME/Library/Application Support" "$HOME/Library/LaunchAgents" || fail 'Cannot create user installation parents.'
    stage=$(/usr/bin/mktemp -d "$HOME/Library/Application Support/.earpods-ai-keys.XXXXXX") || fail 'Cannot create staging directory.'
    committed=no; made_dir=no; made_plist=no; plist_inode=unknown
    staged_cli_sig=unknown; staged_map_sig=unknown; staged_marker_sig=unknown
    trap cleanup_install 0
    trap 'exit 1' HUP INT TERM
    /bin/cp "$source_dir/earpods-ai-keys.sh" "$stage/earpods-ai-keys.sh" || fail 'Cannot stage the CLI.'
    /bin/cp "$source_dir/mapping.json" "$stage/mapping.json" || fail 'Cannot stage the mapping.'
    /bin/cp "$template" "$stage/agent.plist" || fail 'Cannot stage the launchagent.'
    # Remove then insert: replacing an array element can behave as insertion
    # with some plutil builds. Both steps still escape the path as plist data.
    /usr/bin/plutil -remove ProgramArguments.1 -- "$stage/agent.plist" || fail 'Cannot prepare the user path.'
    /usr/bin/plutil -insert ProgramArguments.1 -string "$install_dir/earpods-ai-keys.sh" -- "$stage/agent.plist" || fail 'Cannot generate the user path.'
    [ "$(plist_value ProgramArguments array "$stage/agent.plist")" = 3 ] || fail 'Generated launchagent has unexpected arguments.'
    [ "$(plist_value ProgramArguments.1 string "$stage/agent.plist")" = "$install_dir/earpods-ai-keys.sh" ] || fail 'Generated user path does not match.'
    /usr/bin/plutil -lint -- "$stage/agent.plist" >/dev/null || fail 'Generated plist is invalid.'
    /bin/chmod 700 "$stage/earpods-ai-keys.sh" || fail 'Cannot set CLI permissions.'
    /bin/chmod 600 "$stage/mapping.json" "$stage/agent.plist" || fail 'Cannot set asset permissions.'
    expected_marker "$stage" "$stage/agent.plist" > "$stage/.earpods-ai-keys-owned" || fail 'Cannot write the ownership marker.'
    staged_cli_sig=$(fingerprint "$stage/earpods-ai-keys.sh") || fail 'Cannot fingerprint staged CLI.'
    staged_map_sig=$(fingerprint "$stage/mapping.json") || fail 'Cannot fingerprint staged mapping.'
    staged_marker_sig=$(fingerprint "$stage/.earpods-ai-keys-owned") || fail 'Cannot fingerprint staged marker.'
    # Recheck after staging so an existing target is never overwritten.
    [ ! -e "$install_dir" ] && [ ! -L "$install_dir" ] && [ ! -e "$plist" ] && [ ! -L "$plist" ] || conflict 'Installation paths appeared during preparation.'
    /bin/mkdir "$install_dir" || fail 'Cannot create installation directory.'
    made_dir=yes
    for name in earpods-ai-keys.sh mapping.json .earpods-ai-keys-owned; do
        /bin/mv "$stage/$name" "$install_dir/$name" || fail 'Cannot place installation files.'
    done
    # noclobber rejects an existing plist, including a path created concurrently.
    (set -C; : > "$plist") || fail 'Cannot create launchagent without overwriting a file.'
    made_plist=yes
    plist_inode=$(/usr/bin/stat -f %i "$plist") || fail 'Cannot identify the created launchagent.'
    /bin/cat "$stage/agent.plist" > "$plist" || fail 'Cannot write the launchagent.'
    /bin/chmod 600 "$plist" || fail 'Cannot set launchagent permissions.'
    inspect_files
    [ "$files_state" = ours ] || fail 'Installed files do not match their ownership marker.'
    committed=yes
    /bin/launchctl enable "$service" || fail 'Files installed, but launchd enable failed; use uninstall to remove them.'
    /bin/launchctl bootstrap "gui/$user_id" "$plist" || fail 'Files installed, but launchd bootstrap failed; use uninstall to remove them.'
    printf '%s\n' 'Installed. launchd applies the mapping once when loaded and at login.' \
      'Keep EarPods connected at login; after a late connection, run apply manually.' \
      'For the tested center-button Dictation behavior, turn Siri off manually in System Settings.'
}
uninstall_package() {
    inspect_files
    case "$files_state" in
      absent) printf '%s\n' 'Not installed; no mapping or service changed.'; return ;;
      unrecognized) conflict 'Modified, missing or unrecognized files preserved; removal stopped.' ;;
    esac
    probe_service "$service"
    loaded=$service_present
    /bin/launchctl disable "$service" || fail 'Cannot disable the job.'
    if [ "$loaded" = yes ]; then /bin/launchctl bootout "$service" || fail 'Cannot unload the job.'; fi
    find_legacy
    if [ "$legacy" != none ]; then
        printf '%s\n' 'Legacy installation found; HID mapping preserved.'
    else
        inspect_mapping
        if [ "$mapping_state" = ours ]; then
            /usr/bin/hidutil property --matching "$match" --set '{"UserKeyMapping":[]}' >/dev/null || fail 'Cannot clear our mapping; owned files left for retry.'
            inspect_mapping
            case "$mapping_state" in empty|absent) ;; *) fail 'Clear readback failed; owned files left for retry.' ;; esac
        else
            printf '%s\n' 'Absent, empty, foreign or unrecognized HID mapping preserved.'
        fi
    fi
    # No recursive removal: extra files in the directory belong to their owner.
    /bin/rm "$plist" "$install_dir/earpods-ai-keys.sh" "$install_dir/mapping.json" "$marker" || fail 'Cannot remove owned files.'
    if ! /bin/rmdir "$install_dir" 2>/dev/null; then printf '%s\n' 'Extra files kept in the installation directory.'; fi
    printf '%s\n' 'Uninstalled. No periodic checks or resident process remain.'
}
case "$command" in
  status) show_status ;;
  apply) apply_mapping ;;
  install) install_package ;;
  uninstall) uninstall_package ;;
esac
