{
  pkgs,
  lib,
  writeShellApplication,
  bash,
  coreutils,
  ffmpeg,
  findutils,
  gawk,
  gnugrep,
  gnused,
  gpu-screen-recorder,
  hyprland,
  jq,
  libnotify,
  mpv,
  procps,
  python3,
  util-linux,
  v4l-utils,
  ...
}:
writeShellApplication {
  name = "record-screen";

  meta = {
    description = "GPU-accelerated Hyprland screen recorder with smart region selection";
    mainProgram = "record-screen";
    platforms = lib.platforms.linux;
  };

  runtimeInputs = [
    bash
    pkgs.custom.capture-region
    coreutils
    ffmpeg
    findutils
    gawk
    gnugrep
    gnused
    gpu-screen-recorder
    hyprland
    jq
    libnotify
    mpv
    procps
    util-linux
    v4l-utils
  ];

  text = ''
    set -euo pipefail

    OUT_DIR="''${RECORD_SCREEN_DIR:-$HOME/Pictures/Screenrec}"
    STATE_DIR="''${XDG_RUNTIME_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}}/record-screen"
    PID_FILE="$STATE_DIR/pid"
    OUTPUT_FILE="$STATE_DIR/output"
    ACTIVE_FILE="$STATE_DIR/active"
    STARTING_FILE="$STATE_DIR/starting"
    CANCEL_FILE="$STATE_DIR/cancel"
    LOCK_FILE="$STATE_DIR/lock"
    WEBCAM_PID_FILE="$STATE_DIR/webcam-pid"
    WEBCAM_LOG="$STATE_DIR/webcam.log"
    LOG_FILE="$STATE_DIR/record-screen.log"
    README_START="<!-- screenrec-demo:start -->"
    README_END="<!-- screenrec-demo:end -->"
    APP_NAME="record-screen"

    ensure_state() {
      umask 077
      mkdir -p "$STATE_DIR"
      [[ -d $STATE_DIR && ! -L $STATE_DIR && -O $STATE_DIR ]] || {
        echo "Refusing unsafe recording state directory: $STATE_DIR" >&2
        return 1
      }
      chmod 700 "$STATE_DIR"
    }

    ensure_dirs() {
      ensure_state
      mkdir -p "$OUT_DIR"
    }

    usage() {
      printf '%s\n' \
        "Usage:" \
        "  record-screen toggle [options] [name]" \
        "  record-screen start [options] [name]" \
        "  record-screen stop" \
        "  record-screen status" \
        "  record-screen watch" \
        "  record-screen latest" \
        "  record-screen optimize <input.mp4> [name]" \
        "  record-screen readme <video-url> [README.md]" \
        "" \
        "Options:" \
        "  --desktop-audio       Record the default output" \
        "  --microphone-audio    Record the default input" \
        "  --webcam              Show and record a webcam overlay" \
        "  --webcam-device=PATH  Select the webcam device" \
        "  --resolution=WxH      Scale the recorded video" \
        "  --portal              Use the XDG portal capture backend" \
        "  --debug               Preserve gpu-screen-recorder logs"
    }

    read_pid() {
      [[ -r $PID_FILE ]] && printf '%s\n' "$(<"$PID_FILE")"
    }

    is_recorder_pid() {
      local pid="$1" executable
      [[ $pid =~ ^[0-9]+$ ]] || return 1
      kill -0 "$pid" 2>/dev/null || return 1
      executable=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
      [[ $executable == */gpu-screen-recorder ]]
    }

    is_active() {
      [[ -r $ACTIVE_FILE ]] && is_recorder_pid "$(read_pid || true)"
    }

    end_recorder() {
      local pid="$1" count=0
      is_recorder_pid "$pid" || return 0
      kill -SIGINT "$pid" 2>/dev/null || true
      while is_recorder_pid "$pid" && ((count < 50)); do
        sleep 0.1
        count=$((count + 1))
      done
      if is_recorder_pid "$pid"; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
      wait "$pid" 2>/dev/null || true
    }

    cleanup_state() {
      rm -f "$PID_FILE" "$OUTPUT_FILE" "$ACTIVE_FILE" "$STARTING_FILE" "$CANCEL_FILE"
    }

    cleanup_start() {
      if [[ -r $STARTING_FILE && $(<"$STARTING_FILE") == "$$" ]]; then
        [[ -n ''${starting_recorder:-} ]] && end_recorder "$starting_recorder"
        cleanup_webcam
        cleanup_state
      fi
    }

    cleanup_webcam() {
      local pid="" executable=""
      [[ -r $WEBCAM_PID_FILE ]] && pid=$(cat "$WEBCAM_PID_FILE")
      if [[ $pid =~ ^[0-9]+$ ]]; then
        executable=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
        [[ $executable == */ffplay ]] && kill "$pid" 2>/dev/null || true
      fi
      rm -f "$WEBCAM_PID_FILE"
    }

    notify_msg() {
      notify-send -a "$APP_NAME" "$@"
    }

    capture_target() {
      local geometry sx sy sw sh monitor
      geometry=$(capture-region) || return 1
      [[ $geometry =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || return 1
      sx=''${BASH_REMATCH[1]}
      sy=''${BASH_REMATCH[2]}
      sw=''${BASH_REMATCH[3]}
      sh=''${BASH_REMATCH[4]}

      monitor=$(hyprctl monitors -j | jq -r \
        --argjson x "$sx" --argjson y "$sy" --argjson w "$sw" --argjson h "$sh" '
          .[]
          | (.width / .scale | floor) as $logicalWidth
          | (.height / .scale | floor) as $logicalHeight
          | if .transform == 1 or .transform == 3 then
              $logicalHeight as $width | $logicalWidth as $height
            else
              $logicalWidth as $width | $logicalHeight as $height
            end
          | select(.x == $x and .y == $y and $width == $w and $height == $h)
          | .name
        ' | head -n 1)

      if [[ -n $monitor ]]; then
        printf 'monitor:%s\n' "$monitor"
      else
        printf 'region:%sx%s+%s+%s\n' "$sw" "$sh" "$sx" "$sy"
      fi
    }

    position_webcam() {
      local target="$1" pid="$2" address="" client="" count=0
      local sx sy sw sh ww wh x y monitor

      while ((count < 30)); do
        client=$(hyprctl clients -j | jq -c --argjson pid "$pid" \
          '[.[] | select(.pid == $pid and .title == "WebcamOverlay")] | last // empty')
        [[ -n $client ]] && break
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.1
        count=$((count + 1))
      done
      [[ -n $client ]] || return 1

      address=$(jq -r '.address' <<< "$client")
      ww=$(jq -r '.size[0]' <<< "$client")
      wh=$(jq -r '.size[1]' <<< "$client")

      case "$target" in
        region:*)
          [[ ''${target#region:} =~ ^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$ ]] || return 0
          sw=''${BASH_REMATCH[1]}
          sh=''${BASH_REMATCH[2]}
          sx=''${BASH_REMATCH[3]}
          sy=''${BASH_REMATCH[4]}
          ;;
        monitor:*)
          monitor=''${target#monitor:}
          read -r sx sy sw sh < <(
            hyprctl monitors -j | jq -r --arg monitor "$monitor" '
              .[] | select(.name == $monitor) |
              (.width / .scale | floor) as $width |
              (.height / .scale | floor) as $height |
              if .transform == 1 or .transform == 3 then
                "\(.x) \(.y) \($height) \($width)"
              else
                "\(.x) \(.y) \($width) \($height)"
              end
            '
          )
          [[ -n ''${sx:-} ]] || return 0
          ;;
        *) return 0 ;;
      esac

      # Keep the preview fully inside the exact rectangle sent to the KMS
      # recorder. This matters for click-to-record-window: a monitor-pinned
      # preview can otherwise be visible on the desktop but outside the video.
      x=$((sx + sw - ww - 20))
      y=$((sy + sh - wh - 20))
      ((x < sx + 20)) && x=$((sx + 20))
      ((y < sy + 20)) && y=$((sy + 20))
      hyprctl dispatch \
        "hl.dsp.window.move({ x = $x, y = $y, window = 'address:$address' })" \
        >/dev/null
    }

    start_webcam() {
      local requested="$1" target="$2" device formats resolution="" scale width pid

      cleanup_webcam
      device="$requested"
      if [[ -z $device ]]; then
        device=$(v4l2-ctl --list-devices 2>/dev/null \
          | awk '/^[[:space:]]*\/dev\/video/ { gsub(/^[[:space:]]+/, ""); print; exit }')
      fi
      [[ -n $device ]] || {
        notify_msg -u critical "Screen recording" "No webcam found"
        return 1
      }

      formats=$(v4l2-ctl --list-formats-ext -d "$device" 2>/dev/null || true)
      for candidate in 640x360 1280x720 1920x1080; do
        if grep -q "$candidate" <<< "$formats"; then
          resolution="$candidate"
          break
        fi
      done

      scale=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .scale')
      width=$(awk -v scale="$scale" 'BEGIN { printf "%.0f", 360 * scale }')

      local -a size_args=()
      [[ -n $resolution ]] && size_args=(-video_size "$resolution")
      : > "$WEBCAM_LOG"
      ffplay -f v4l2 "''${size_args[@]}" -framerate 30 "$device" \
        -vf "crop=iw/2:ih,scale=$width:-1" \
        -window_title WebcamOverlay -noborder \
        -fflags nobuffer -flags low_delay -probesize 32 -analyzeduration 0 \
        -loglevel warning >"$WEBCAM_LOG" 2>&1 9>&- &
      pid=$!
      printf '%s\n' "$pid" > "$WEBCAM_PID_FILE"
      if ! position_webcam "$target" "$pid"; then
        cleanup_webcam
        notify_msg -u critical "Screen recording" "Webcam preview failed; see $WEBCAM_LOG"
        return 1
      fi
    }

    start_recording() {
      ensure_dirs

      if is_active; then
        notify_msg "Screen recording" "A recording is already active"
        return 1
      fi
      local desktop_audio=false microphone_audio=false webcam=false portal=false debug=false
      local webcam_device="" resolution="" name="" target filename pid
      local -a capture_args audio_args=()

      while (($# > 0)); do
        case "$1" in
          --desktop-audio|--with-desktop-audio) desktop_audio=true ;;
          --microphone-audio|--with-microphone-audio) microphone_audio=true ;;
          --webcam|--with-webcam) webcam=true ;;
          --webcam-device=*) webcam_device=''${1#*=} ;;
          --resolution=*) resolution=''${1#*=} ;;
          --portal) portal=true ;;
          --debug) debug=true ;;
          --*) echo "unknown option: $1" >&2; return 2 ;;
          *) name="$1" ;;
        esac
        shift
      done

      if [[ $portal == true ]]; then
        target=portal
        capture_args=(-w portal)
      else
        target=$(capture_target 9>&-) || return 1
        case "$target" in
          monitor:*) capture_args=(-w "''${target#monitor:}") ;;
          region:*) capture_args=(-w "''${target#region:}") ;;
          *) return 1 ;;
        esac
      fi
      [[ ! -e $CANCEL_FILE ]] || return 1
      [[ -n $resolution ]] && capture_args+=(-s "$resolution")

      if [[ $webcam == true ]]; then
        # Webcam recordings are conversational by default: the preview is
        # included in the picture and the default microphone in the audio.
        microphone_audio=true
        if ! start_webcam "$webcam_device" "$target"; then
          cleanup_state
          return 1
        fi
      fi
      [[ ! -e $CANCEL_FILE ]] || return 1

      local audio_devices=""
      [[ $desktop_audio == true ]] && audio_devices=default_output
      if [[ $microphone_audio == true ]]; then
        [[ -n $audio_devices ]] && audio_devices+="|"
        audio_devices+=default_input
      fi
      [[ -n $audio_devices ]] && audio_args=(-a "$audio_devices" -ac aac)

      [[ -n $name ]] || name="screenrecording-$(date +'%Y-%m-%d_%H-%M-%S')"
      filename="$OUT_DIR/$name.mp4"
      [[ $debug == true ]] || : > "$LOG_FILE"

      gpu-screen-recorder "''${capture_args[@]}" \
        -k auto -f 60 -fm cfr -fallback-cpu-encoding yes \
        "''${audio_args[@]}" -o "$filename" >> "$LOG_FILE" 2>&1 9>&- &
      pid=$!
      starting_recorder=$pid

      local count=0
      # A portal picker can legitimately await the user longer than five
      # seconds. KMS capture must create its output within the deadline.
      while kill -0 "$pid" 2>/dev/null && [[ ! -f $filename ]]; do
        if [[ -e $CANCEL_FILE ]] || { [[ $portal == false ]] && ((count >= 50)); }; then
          end_recorder "$pid"
          rm -f "$filename"
          return 1
        fi
        sleep 0.1
        count=$((count + 1))
      done

      if ! is_recorder_pid "$pid" || [[ ! -f $filename || -e $CANCEL_FILE ]]; then
        end_recorder "$pid"
        rm -f "$filename"
        notify_msg -u critical "Screen recording failed" "See $LOG_FILE"
        return 1
      fi

      printf '%s\n' "$pid" > "$PID_FILE"
      printf '%s\n' "$filename" > "$OUTPUT_FILE"
      printf '%s\n' "$filename" > "$ACTIVE_FILE"
      rm -f "$STARTING_FILE"
      # A cancellation can arrive while the ready state is being published.
      if [[ -e $CANCEL_FILE ]]; then
        end_recorder "$pid"
        cleanup_webcam
        cleanup_state
        rm -f "$filename"
        return 1
      fi
      notify_msg -u low "Screen recording started" "Use the red REC indicator or the shortcut to stop"
      printf '%s\n' "$filename"
    }

    finalize_recording() {
      local file="$1" processed
      local -a video_codec
      [[ -f $file ]] || return 1

      video_codec=(-c:v copy)
      if ffprobe -v error -select_streams v:0 -read_intervals %+0.2 \
        -show_entries packet=flags -of csv=p=0 "$file" 2>/dev/null | grep -q D; then
        video_codec=(-c:v libx264 -preset veryfast -crf 20)
      fi

      processed="''${file%.mp4}-processed.mp4"
      local -a args=(-y -ss 0.1 -i "$file" "''${video_codec[@]}")
      if ffprobe -v error -select_streams a -show_entries stream=codec_type \
        -of csv=p=0 "$file" 2>/dev/null | grep -q audio; then
        args+=(-af "volume=enable='lt(t,0.4)':volume=0,afade=t=in:st=0.4:d=0.05,loudnorm=I=-14:TP=-1.5:LRA=11" -c:a aac)
      fi

      if ffmpeg "''${args[@]}" "$processed" -loglevel quiet 2>/dev/null; then
        mv "$processed" "$file"
      else
        rm -f "$processed"
      fi
    }

    stop_recording() {
      ensure_dirs
      if ! is_active; then
        cleanup_state
        cleanup_webcam
        notify_msg "Screen recording" "No recording is active"
        return 1
      fi

      local pid file count=0 preview action
      pid=$(cat "$PID_FILE")
      file=$(cat "$OUTPUT_FILE")
      is_recorder_pid "$pid" && kill -SIGINT "$pid" 2>/dev/null || true

      while is_recorder_pid "$pid" && ((count < 50)); do
        sleep 0.1
        count=$((count + 1))
      done
      if is_recorder_pid "$pid"; then
        kill -KILL "$pid" 2>/dev/null || true
        notify_msg -u critical "Screen recording error" "Recorder had to be killed; the video may be incomplete"
      fi

      cleanup_webcam
      rm -f "$ACTIVE_FILE"
      finalize_recording "$file" || true
      cleanup_state

      preview="''${file%.mp4}-preview.png"
      ffmpeg -y -ss 0.1 -i "$file" -frames:v 1 -q:v 2 "$preview" -loglevel quiet 2>/dev/null || true
      (
        action=$(notify-send -a "$APP_NAME" -t 10000 -i "$preview" -A default=open \
          "Screen recording saved" "$file" || true)
        [[ $action == default ]] && mpv "$file"
        rm -f "$preview"
      ) >/dev/null 2>&1 9>&- &
      printf '%s\n' "$file"
    }

    optimize_mp4() {
      local input="$1" output="$2"
      ffmpeg -y -i "$input" \
        -vf "fps=24,scale='min(1280,iw)':-2:flags=lanczos,format=yuv420p" \
        -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p \
        -movflags +faststart "$output"
    }

    optimize_command() {
      local input="''${1:-}" name="''${2:-}" output
      [[ -f $input ]] || { echo "input file not found: $input" >&2; return 1; }
      [[ -n $name ]] || name="screenrec-$(date +'%Y-%m-%d_%H-%M-%S')"
      output="$OUT_DIR/$name.mp4"
      ensure_dirs
      optimize_mp4 "$input" "$output"
      printf '%s\n' "$output"
    }

    readme_command() {
      local url="''${1:-}" readme="''${2:-README.md}" tmp block
      [[ -n $url ]] || { usage; return 2; }
      [[ -f $readme ]] || { echo "README file not found: $readme" >&2; return 1; }
      printf -v block '%s\n## Demo\n\n![Screen recording demo](%s)\n%s' \
        "$README_START" "$url" "$README_END"
      tmp=$(mktemp)
      if grep -Fq "$README_START" "$readme" && grep -Fq "$README_END" "$readme"; then
        awk -v start="$README_START" -v end="$README_END" -v replacement="$block" '
          $0 == start { print replacement; inside = 1; next }
          $0 == end { inside = 0; next }
          !inside { print }
        ' "$readme" > "$tmp"
      else
        cp "$readme" "$tmp"
        printf '\n\n%s\n' "$block" >> "$tmp"
      fi
      mv "$tmp" "$readme"
    }

    latest_command() {
      ensure_dirs
      find "$OUT_DIR" -maxdepth 1 -type f -name '*.mp4' -printf '%T@ %p\n' \
        | sort -nr | head -n 1 | cut -d' ' -f2-
    }

    case "''${1:-}" in
      toggle|start|stop)
        action=$1
        shift
        ensure_dirs
        exec 9>>"$LOCK_FILE"
        if ! flock -n 9; then
          # A pending picker/start is cancelled immediately instead of
          # queueing another toggle that would unexpectedly start again.
          if [[ $action != start && -r $STARTING_FILE ]] \
            && starter=$(<"$STARTING_FILE") \
            && [[ $starter =~ ^[0-9]+$ ]] \
            && kill -0 "$starter" 2>/dev/null; then
            touch "$CANCEL_FILE"
            # If publication just finished, complete this request as a stop
            # after the lock is released instead of losing the cancellation.
            if [[ ! -r $STARTING_FILE ]]; then
              flock 9
              if is_active; then stop_recording; fi
            fi
            exit 0
          fi
          flock 9
        fi
        if [[ $action == stop ]]; then
          stop_recording
        elif is_active; then
          if [[ $action == toggle ]]; then
            stop_recording
          else
            notify_msg "Screen recording" "A recording is already active"
            exit 1
          fi
        else
          cleanup_webcam
          cleanup_state
          printf '%s\n' "$$" > "$STARTING_FILE"
          trap cleanup_start EXIT
          trap 'exit 130' INT
          trap 'exit 143' TERM
          start_recording "$@"
        fi
        ;;
      status)
        if is_active; then
          cat "$ACTIVE_FILE"
        else
          # Observation must never remove files another invocation is
          # publishing. Mutating commands own recovery of stale state.
          exit 1
        fi
        ;;
      watch)
        ensure_state
        exec ${python3}/bin/python3 ${./watch.py} "$STATE_DIR"
        ;;
      latest) latest_command ;;
      optimize) shift; optimize_command "$@" ;;
      readme) shift; readme_command "$@" ;;
      *) usage; exit 2 ;;
    esac
  '';
}
