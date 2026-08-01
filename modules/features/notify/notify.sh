_notify_help() {
  cat <<'EOF'
Usage: notify [OPTIONS] TITLE [MESSAGE]

Send a desktop/toast notification. Backend is auto-selected per-machine
by config.core.platformBackend:
  - wayland/x11: notify-send (libnotify)
  - wsl:         a Windows toast (NotifyIcon balloon tip) via pwsh.exe or
                 powershell.exe
  - macos:       osascript

Options:
  -u, --urgency LEVEL   low|normal|critical (default: normal)
  -i, --icon PATH       Icon file. Linux: passed straight to notify-send.
                        WSL: a WSL path is auto-converted to a Windows
                        path via wslpath -w.
  -t, --timeout MS      Expiry/duration in milliseconds (default: 5000)
  -a, --app-name NAME   Application name shown as the notification source
                        (default: "dots")
  -h, --help            Show this help

Examples:
  notify "Build finished" "All tests passed"
  notify -u critical -a ci "Build failed" "See log for details"
EOF
}

urgency="normal"
icon=""
timeout="5000"
app_name="dots"
positional=()

while [ $# -gt 0 ]; do
  case "$1" in
    -u|--urgency)  urgency="$2"; shift 2 ;;
    -i|--icon)     icon="$2"; shift 2 ;;
    -t|--timeout)  timeout="$2"; shift 2 ;;
    -a|--app-name) app_name="$2"; shift 2 ;;
    -h|--help)     _notify_help; exit 0 ;;
    --) shift; positional+=("$@"); break ;;
    -*) echo "notify: unknown option: $1" >&2; _notify_help; exit 1 ;;
    *) positional+=("$1"); shift ;;
  esac
done

title="${positional[0]:-}"
message="${positional[1]:-}"

if [ -z "$title" ]; then
  echo "notify: TITLE is required" >&2
  _notify_help
  exit 1
fi

case "$urgency" in
  low|normal|critical) ;;
  *) echo "notify: invalid --urgency '$urgency' (want low|normal|critical)" >&2; exit 1 ;;
esac

case "$NOTIFY_BACKEND" in
  wsl)
    # Prefer pwsh.exe (PowerShell 7+) when reachable, opportunistically -
    # via $PATH (WSL interop) first, then its one common fixed install
    # location. The guaranteed fallback is powershell.exe's fixed,
    # always-present System32 path (NOT a bare "powershell.exe" lookup -
    # that depends on WSL's [interop] appendWindowsPath setting, which
    # some machines disable; the /mnt/c mount itself is far more
    # fundamental to WSL2 than that PATH-interop convenience).
    ps_bin=""
    if command -v pwsh.exe >/dev/null 2>&1; then
      ps_bin="pwsh.exe"
    elif [ -x "/mnt/c/Program Files/PowerShell/7/pwsh.exe" ]; then
      ps_bin="/mnt/c/Program Files/PowerShell/7/pwsh.exe"
    elif [ -x "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
      ps_bin="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    else
      ps_bin="powershell.exe"
    fi

    title_b64=$(printf '%s' "$title" | base64 -w0)
    message_b64=$(printf '%s' "$message" | base64 -w0)

    icon_win=""
    if [ -n "$icon" ]; then
      icon_win=$(wslpath -w "$icon" 2>/dev/null || true)
    fi

    ps1_win=$(wslpath -w "$NOTIFY_TOAST_PS1")

    "$ps_bin" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$ps1_win" \
      -TitleB64 "$title_b64" -MessageB64 "$message_b64" -IconPath "$icon_win" \
      -TimeoutMs "$timeout" -Urgency "$urgency" -AppName "$app_name" >/dev/null
    ;;
  wayland|x11)
    notify_args=(-a "$app_name" -u "$urgency" -t "$timeout")
    [ -n "$icon" ] && notify_args+=(-i "$icon")
    "$NOTIFY_SEND_BIN" "${notify_args[@]}" "$title" "$message"
    ;;
  macos)
    esc_title=${title//\"/\\\"}
    esc_message=${message//\"/\\\"}
    osascript -e "display notification \"$esc_message\" with title \"$esc_title\""
    ;;
  *)
    echo "notify: unsupported backend '$NOTIFY_BACKEND'" >&2
    exit 1
    ;;
esac
