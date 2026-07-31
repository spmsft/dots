        # Ensure byobu (tmux-backed) session exists (create detached if not)
        if ! "$byobu" list-sessions -F '#S' 2>/dev/null | grep -qx "$session_name"; then
          nohup env TERM="xterm-256color" "$byobu" new-session -d -s "$session_name" </dev/null >/dev/null 2>&1 &
          sleep 0.5
        fi

        # Find existing scratchpad window
        win_json="$(niri msg -j windows 2>/dev/null | "$py" -c 'import sys,json; wins=json.load(sys.stdin); s=[w for w in wins if w.get("app_id")=="'"$scratch_app_id"'"]; print(json.dumps(s[-1]) if s else "")')" || true

        if [ -n "$win_json" ]; then
          win_id="$(printf %s "$win_json" | "$py" -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')"
          is_focused="$(printf %s "$win_json" | "$py" -c 'import sys,json; print("1" if json.load(sys.stdin).get("is_focused") else "0")')"
          win_pid="$(printf %s "$win_json" | "$py" -c 'import sys,json; print(json.load(sys.stdin).get("pid",""))')"

          if [ "$is_focused" = "1" ]; then
            kill "$win_pid" 2>/dev/null || true
            exit 0
          fi

          target_ws_idx="$(niri msg -j workspaces 2>/dev/null | "$py" -c 'import sys,json; ws=[w for w in json.load(sys.stdin) if w.get("is_focused")]; print(str(ws[0].get("idx","")) if ws else "")')" || target_ws_idx=""
          
          niri msg action focus-window --id "$win_id" 2>/dev/null || true
          if [ -n "$target_ws_idx" ]; then
            niri msg action move-window-to-workspace "$target_ws_idx" 2>/dev/null || true
          fi
          exit 0
        fi

        "$term" --class="$scratch_app_id" -e "$byobu" attach-session -t "$session_name" >/dev/null 2>&1 &
