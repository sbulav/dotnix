{
  lib,
  writeShellApplication,
  wf-recorder,
  slurp,
  ffmpeg,
  libnotify,
  coreutils,
  gnugrep,
  gawk,
  gnused,
  ...
}:
writeShellApplication {
  name = "record-screen";

  meta = {
    mainProgram = "record-screen";
    platforms = lib.platforms.linux;
  };

  runtimeInputs = [
    wf-recorder
    slurp
    ffmpeg
    libnotify
    coreutils
    gnugrep
    gawk
    gnused
  ];

  text = ''
    set -euo pipefail

    OUT_DIR="''${RECORD_SCREEN_DIR:-$HOME/Pictures/Screenrec}"
    STATE_PID_FILE="/tmp/record-screen.pid"
    STATE_RAW_FILE="/tmp/record-screen.raw"
    STATE_FINAL_FILE="/tmp/record-screen.final"
    README_START="<!-- screenrec-demo:start -->"
    README_END="<!-- screenrec-demo:end -->"
    APP_NAME="record-screen"

    ensure_out_dir() {
      mkdir -p "$OUT_DIR"
    }

    usage() {
      printf '%s\n' \
        "Usage:" \
        "  record-screen toggle [name]" \
        "    Toggle region recording start/stop." \
        "" \
        "  record-screen start [name]" \
        "    Start region recording in background (stop with record-screen stop)." \
        "" \
        "  record-screen stop" \
        "    Stop active recording and save optimized MP4." \
        "" \
        "  record-screen record [name]" \
        "    Record selected area to MP4 (Ctrl+C to stop), then optimize output." \
        "" \
        "  record-screen optimize <input.mp4> [name]" \
        "    Re-encode an existing MP4 into $OUT_DIR." \
        "" \
        "  record-screen readme <video-url> [README.md]" \
        "    Insert or update demo block in README with uploaded video URL." \
        "" \
        "  record-screen latest" \
        "    Print latest recording path from $OUT_DIR."
    }

    notify_msg() {
      local title="$1"
      local message="$2"
      notify-send -a "$APP_NAME" "$title" "$message"
    }

    optimize_mp4() {
      local input="$1"
      local output="$2"

      ffmpeg -y -i "$input" \
        -vf "fps=24,scale='min(1280,iw)':-2:flags=lanczos,format=yuv420p" \
        -c:v libx264 \
        -preset veryfast \
        -crf 26 \
        -pix_fmt yuv420p \
        -movflags +faststart \
        "$output"
    }

    clear_state() {
      rm -f "$STATE_PID_FILE" "$STATE_RAW_FILE" "$STATE_FINAL_FILE"
    }

    get_active_pid() {
      if [[ -f "$STATE_PID_FILE" ]]; then
        cat "$STATE_PID_FILE"
      fi
    }

    is_active_recording() {
      local pid
      pid="$(get_active_pid || true)"
      [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
    }

    cmd_start() {
      ensure_out_dir

      local ts geometry name raw_file final_file pid

      if is_active_recording; then
        echo "Recording already in progress"
        notify_msg "Screen recording" "Recording already in progress"
        exit 1
      fi

      ts="$(date +"%Y-%m-%d_%H-%M-%S")"
      name="''${1:-screenrec-$ts}"
      raw_file="/tmp/''${name}.raw.mp4"
      final_file="$OUT_DIR/''${name}.mp4"

      geometry="$(slurp)" || {
        echo "Area selection cancelled"
        exit 1
      }

      clear_state

      nohup wf-recorder -g "$geometry" -f "$raw_file" >/tmp/record-screen.log 2>&1 &
      pid=$!

      printf '%s\n' "$pid" > "$STATE_PID_FILE"
      printf '%s\n' "$raw_file" > "$STATE_RAW_FILE"
      printf '%s\n' "$final_file" > "$STATE_FINAL_FILE"

      echo "Recording started (PID: $pid)"
      echo "Run: record-screen stop"
      notify_msg "Screen recording started" "Press Alt+Print again to stop"
    }

    cmd_stop() {
      local pid raw_file final_file

      if ! is_active_recording; then
        echo "No active recording"
        notify_msg "Screen recording" "No active recording"
        clear_state
        exit 1
      fi

      pid="$(cat "$STATE_PID_FILE")"
      raw_file="$(cat "$STATE_RAW_FILE")"
      final_file="$(cat "$STATE_FINAL_FILE")"

      kill -SIGINT "$pid"

      while kill -0 "$pid" 2>/dev/null; do
        sleep 0.2
      done

      if [[ ! -f "$raw_file" ]]; then
        echo "Recording file not found: $raw_file"
        clear_state
        exit 1
      fi

      echo "Optimizing MP4..."
      optimize_mp4 "$raw_file" "$final_file"
      rm -f "$raw_file"
      clear_state

      echo "Saved: $final_file"
      echo "Next: upload in GitHub web editor and copy generated URL."
      echo "Then run: record-screen readme <url>"
      notify_msg "Screen recording saved" "$final_file"
    }

    cmd_toggle() {
      if is_active_recording; then
        cmd_stop
      else
        cmd_start "$@"
      fi
    }

    cmd_record() {
      ensure_out_dir

      local ts raw_file final_file geometry name
      ts="$(date +"%Y-%m-%d_%H-%M-%S")"
      name="''${1:-screenrec-$ts}"
      raw_file="/tmp/''${name}.raw.mp4"
      final_file="$OUT_DIR/''${name}.mp4"

      geometry="$(slurp)" || {
        echo "Area selection cancelled"
        exit 1
      }

      echo "Recording... press Ctrl+C to stop"
      wf-recorder -g "$geometry" -f "$raw_file"

      echo "Optimizing MP4..."
      optimize_mp4 "$raw_file" "$final_file"
      rm -f "$raw_file"

      echo "Saved: $final_file"
      echo "Next: upload in GitHub web editor and copy generated URL."
      echo "Then run: record-screen readme <url>"
    }

    cmd_optimize() {
      ensure_out_dir

      local input="''${1:-}"
      local name="''${2:-}"
      local ts final_file
      ts="$(date +"%Y-%m-%d_%H-%M-%S")"

      if [[ -z "$input" ]]; then
        echo "Missing input file"
        usage
        exit 1
      fi

      if [[ ! -f "$input" ]]; then
        echo "Input file does not exist: $input"
        exit 1
      fi

      if [[ -z "$name" ]]; then
        name="screenrec-$ts"
      fi

      final_file="$OUT_DIR/''${name}.mp4"
      optimize_mp4 "$input" "$final_file"
      echo "Saved: $final_file"
    }

    cmd_readme() {
      local url="''${1:-}"
      local readme="''${2:-README.md}"
      local tmp block

      if [[ -z "$url" ]]; then
        echo "Missing video URL"
        usage
        exit 1
      fi

      if [[ ! -f "$readme" ]]; then
        echo "README file not found: $readme"
        exit 1
      fi

      printf -v block '%s\n## Demo\n\n![Screen recording demo](%s)\n%s' \
        "$README_START" \
        "$url" \
        "$README_END"

      tmp="$(mktemp)"

      if grep -Fq "$README_START" "$readme" && grep -Fq "$README_END" "$readme"; then
        awk -v start="$README_START" -v end="$README_END" -v repl="$block" '
          $0 == start {
            print repl
            in_block = 1
            next
          }
          $0 == end {
            in_block = 0
            next
          }
          !in_block { print }
        ' "$readme" > "$tmp"
      else
        cp "$readme" "$tmp"
        printf "\n\n%s\n" "$block" >> "$tmp"
      fi

      mv "$tmp" "$readme"
      echo "Updated: $readme"
    }

    cmd_latest() {
      ensure_out_dir
      local latest=""
      local latest_mtime=0
      local file mtime

      for file in "$OUT_DIR"/*.mp4; do
        [[ -e "$file" ]] || continue
        mtime="$(stat -c %Y "$file")"
        if (( mtime > latest_mtime )); then
          latest_mtime=$mtime
          latest="$file"
        fi
      done

      if [[ -n "$latest" ]]; then
        printf '%s\n' "$latest"
      fi
    }

    case "''${1:-}" in
      toggle)
        shift
        cmd_toggle "$@"
        ;;
      start)
        shift
        cmd_start "$@"
        ;;
      stop)
        cmd_stop
        ;;
      record)
        shift
        cmd_record "$@"
        ;;
      optimize)
        shift
        cmd_optimize "$@"
        ;;
      readme)
        shift
        cmd_readme "$@"
        ;;
      latest)
        cmd_latest
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  '';
}
