--!nonstrict
-- Headless capture service. Port of the old waybar akg-vu-meter script:
-- pw-cat records the matched source at 8 kHz mono s16, od streams the
-- samples, gawk computes peak dBFS per 100 ms window and applies VU
-- ballistics (fast attack 0.35, slow decay 0.10), emitting one line per
-- meaningful change. The outer shell loop re-finds the source when the
-- device disappears, so plugging the mic in later just works.
--
-- Rendering: this service also owns the analog meter face — the same SVG
-- the waybar meter drew (needle sweeping -45..+45 degrees over a colored
-- arc). Each emitted line is composed into an SVG and atomically renamed
-- into the plugin data dir; widget.luau displays it via setImage with a
-- file watch, so the rename is the frame signal.
--
-- Published state (widget.luau watches it for the tooltip):
--   vu = { status = "ok" | "muted" | "nosrc", level = 0..1 }
--
-- @PW_CAT@ / @PACTL@ / @OD@ / @GAWK@ are store paths substituted by Nix.

-- Baked by Nix as a Luau-escaped literal — the same value akg-mic-ctl greps
-- for, and deliberately not a GUI-editable setting (see plugin.toml).
local match = "@SOURCE_MATCH@"
local quotedMatch = "'" .. match:gsub("'", "'\\''") .. "'"

-- Analog face, ported from the waybar meter: 60x36 canvas, arc segments at
-- radius 28 around the needle pivot (30,36). The waybar version painted its
-- own dark card; here the background is transparent so the bar capsule's
-- theme shows through (the plugin runtime exposes no palette API to match
-- theme colors from Luau).
local SVG_OPEN = '<svg xmlns="http://www.w3.org/2000/svg" width="60" height="36" viewBox="0 0 60 36">'
local ARC_LIVE = '<path d="M 10.2 16.2 A 28 28 0 0 1 25.6 8.3" stroke="#444" stroke-width="3" fill="none"/>'
  .. '<path d="M 25.6 8.3 A 28 28 0 0 1 38.7 9.4" stroke="#2ecc40" stroke-width="3" fill="none"/>'
  .. '<path d="M 38.7 9.4 A 28 28 0 0 1 44.6 12.1" stroke="#ffdc00" stroke-width="3" fill="none"/>'
  .. '<path d="M 44.6 12.1 A 28 28 0 0 1 49.8 16.2" stroke="#ff4136" stroke-width="3" fill="none"/>'

local function liveFace(level)
  local angle = -45 + level * 90
  return SVG_OPEN
    .. ARC_LIVE
    .. '<text x="30" y="31" font-family="serif" font-size="5" text-anchor="middle" fill="#aaa">VU</text>'
    .. string.format(
      '<line x1="30" y1="36" x2="30" y2="10" stroke="#fff" stroke-width="1.5"'
        .. ' stroke-linecap="round" transform="rotate(%.2f 30 36)"/>',
      angle
    )
    .. '<circle cx="30" cy="36" r="1.5" fill="#666"/>'
    .. "</svg>"
end

local MUTED_FACE = SVG_OPEN
  .. '<path d="M 10.2 16.2 A 28 28 0 0 1 49.8 16.2" stroke="#3a3a3a" stroke-width="3" fill="none"/>'
  .. '<line x1="30" y1="36" x2="30" y2="10" stroke="#5a2020" stroke-width="1.5"'
  .. ' stroke-linecap="round" transform="rotate(-45 30 36)"/>'
  .. '<circle cx="30" cy="36" r="1.5" fill="#444"/>'
  .. '<line x1="10" y1="6" x2="50" y2="32" stroke="#ff4136" stroke-width="2.5"'
  .. ' stroke-linecap="round" opacity="0.85"/>'
  .. '<text x="30" y="31" font-family="sans-serif" font-size="4.5" font-weight="bold"'
  .. ' text-anchor="middle" fill="#ff4136">MUTE</text>'
  .. "</svg>"

local NOSRC_FACE = SVG_OPEN
  .. '<path d="M 10.2 16.2 A 28 28 0 0 1 49.8 16.2" stroke="#333" stroke-width="3" fill="none"/>'
  .. '<text x="30" y="22" font-family="sans-serif" font-size="8" text-anchor="middle" fill="#666">&#8212;</text>'
  .. '<text x="30" y="32" font-family="sans-serif" font-size="5" text-anchor="middle" fill="#666">no mic</text>'
  .. "</svg>"

local dataDir = noctalia.pluginDataDir()
local svgPath = dataDir and (dataDir .. "/vu.svg") or nil
local tmpPath = dataDir and (dataDir .. "/vu.svg.tmp") or nil

local function writeFace(svg)
  if svgPath == nil then
    return
  end
  -- write-then-rename: the file watcher fires on IN_MOVED_TO, so the widget
  -- never reads a half-written frame. Rename only a fully-written temp —
  -- a failed/partial write (disk full) must not clobber the last good face.
  if noctalia.writeFile(tmpPath, svg) then
    noctalia.renameFile(tmpPath, svgPath)
  end
end

noctalia.state.set("vu", { status = "nosrc", level = 0 })
writeFace(NOSRC_FACE)

-- LC_ALL=C keeps gawk's printf decimal point a dot regardless of locale.
local cmd = "MATCH=" .. quotedMatch .. "\n" .. [[
while :; do
  # Node-name column only, and never a monitor source: a USB mic contributes
  # both alsa_input.* and alsa_output.*.monitor, the monitor sorts first, and
  # matching $0 would meter (and mute-poll) the playback loopback instead.
  src=$(@PACTL@ list sources short 2>/dev/null \
    | @GAWK@ -v m="$MATCH" '$2 !~ /[.]monitor$/ && $2 ~ m { print $2; exit }')
  if [ -z "$src" ]; then echo NOSRC; sleep 3; continue; fi
  @PW_CAT@ --record --raw --target "$src" \
    --rate 8000 --channels 1 --format s16 - 2>/dev/null \
    | @OD@ -An -td2 -w2 -v \
    | LC_ALL=C @GAWK@ -v pactl=@PACTL@ -v src="$src" '
      BEGIN {
        window   = 800    # 100 ms at 8 kHz
        count    = 0
        peak     = 0
        needle   = 0      # normalized 0..1 meter position
        db_floor = -60
        is_muted = 0
        was_muted = -1    # force first emit
        last     = -1
        poll     = 0
        confirm  = 0
      }
      {
        v = $1; if (v < 0) v = -v
        if (v > peak) peak = v
        count++
        if (count >= window) {
          # poll mute state every 10 windows (~1 s)
          poll++
          if (poll >= 10) {
            poll = 0
            # poll the matched source, not the default source - they can differ
            cmd = pactl " get-source-mute '\''" src "'\'' 2>/dev/null"
            line = ""
            cmd | getline line
            close(cmd)
            is_muted = (line ~ /yes/) ? 1 : 0
          }

          if (peak <= 0) db = db_floor
          else           db = 20.0 * log(peak / 32767.0) / log(10)
          if (db < db_floor) db = db_floor
          if (db > 0)        db = 0

          # linear -40..0 dBFS -> 0..1
          if (db <= -40) target = 0
          else           target = (db + 40) / 40.0

          # ballistic smoothing: fast attack, slow decay
          if (target > needle) needle += (target - needle) * 0.35
          else                 needle += (target - needle) * 0.10

          # snap the decay tail to rest: below ~0.02 the per-window delta
          # drops under the emit threshold, which would freeze the needle
          # visibly off zero after speech stops
          if (target <= 0 && needle < 0.02) needle = 0

          changed = (is_muted != was_muted)
          moved   = ((needle - last) ^ 2 > 0.00002)
          if (changed || (!is_muted && moved)) {
            if (is_muted) print "MUTED"
            else          printf "%.3f\n", needle
            fflush()
            was_muted = is_muted
            last = needle
            confirm = 3
          } else if (confirm > 0 && --confirm == 0) {
            # trailing confirm frame, 3 windows (~300 ms) after a burst ends:
            # the widget-side file watcher drops rename events that land
            # < 100 ms after the previous one, so a burst-final frame can be
            # lost and freeze the needle. One duplicate at a guaranteed-safe
            # distance repaints the true resting face.
            if (is_muted) print "MUTED"
            else          printf "%.3f\n", needle
            fflush()
            last = needle
          }

          peak = 0
          count = 0
        }
      }'
  echo NOSRC
  sleep 2
done
]]

noctalia.runStream(cmd, function(line)
  line = noctalia.string.trim(line)
  if line == "NOSRC" then
    noctalia.state.set("vu", { status = "nosrc", level = 0 })
    writeFace(NOSRC_FACE)
  elseif line == "MUTED" then
    noctalia.state.set("vu", { status = "muted", level = 0 })
    writeFace(MUTED_FACE)
  else
    local level = tonumber(line)
    if level ~= nil then
      level = math.clamp(level, 0, 1)
      noctalia.state.set("vu", { status = "ok", level = level })
      writeFace(liveFace(level))
    end
  end
end)
