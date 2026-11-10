--!nonstrict
-- Headless capture service. Port of the old waybar akg-vu-meter script:
-- pw-cat records the matched source at 8 kHz mono s16, od streams the
-- samples, gawk computes peak dBFS per 125 ms window and applies VU
-- ballistics, emitting one line per meaningful change. The outer shell loop
-- re-finds the source when the device disappears, so plugging the mic in
-- later just works.
--
-- Mute and gain are NOT polled by the capture pipeline: a second stream runs
-- `pactl subscribe`, and a change event on the metered source triggers one
-- get-source-mute / get-source-volume query. Luau owns the merged state
-- (source, mute, gain, last level) and is the only thing that paints.
--
-- Rendering: this service also owns the analog meter face (needle sweeping
-- -45..+45 degrees over a zoned arc). Each frame is composed into an SVG and
-- atomically renamed into the plugin data dir; widget.luau displays it via
-- setImage with a file watch, so the rename is the frame signal. The face is
-- coloured from the live theme palette (noctalia.getColor), not baked hex.
--
-- Published state (widget.luau watches it for the tooltip):
--   vu = { status = "ok" | "muted" | "nosrc", level = 0..1,
--          db = peak dBFS of the last emitted window (-60..0) | nil,
--          gain = source volume % | nil }
--
-- @PW_CAT@ / @PACTL@ / @OD@ / @GAWK@ are store paths substituted by Nix.

local PACTL = "@PACTL@"

-- Baked by Nix as a Luau-escaped literal — the same value akg-mic-ctl greps
-- for, and deliberately not a GUI-editable setting (see plugin.toml).
local match = "@SOURCE_MATCH@"
local quotedMatch = "'" .. match:gsub("'", "'\\''") .. "'"

-- ---------------------------------------------------------------------------
-- Face geometry
--
-- 44x22 canvas, i.e. exactly the 2:1 box widget.luau asks for, so the face
-- fills the 22 px bar edge to edge with no letterboxing. The needle pivot
-- (22,30) sits BELOW the canvas, as on a real VU meter where the pivot hides
-- behind the scale plate: cropping it off lets the arc be radius 27 instead
-- of ~19 (pivot on the bottom edge), i.e. a wider, rounder sweep and a longer
-- needle for the same 22 px of height. Outer arc edge touches y=1.
-- Strokes are in canvas units = logical px at the default size: a 4 px arc and
-- a 2.2 px needle stay readable at 1x, where the old 60x36 face scaled its
-- 3-unit arc down to under 2 px.
local PX, PY, R = 22, 30, 27
local ARC_W, NEEDLE_W = 4, 2.2
-- needle tip just past the arc's centreline: it crosses the coloured band, so
-- the zone under the needle reads at a glance
local NEEDLE_R = R + 1
local SVG_OPEN = '<svg xmlns="http://www.w3.org/2000/svg" width="44" height="22" viewBox="0 0 44 22">'

-- level 0..1 -> degrees from vertical (same -45..+45 sweep as the old face)
local function angleOf(level)
  return -45 + level * 90
end

local function polar(deg, r)
  local rad = math.rad(deg)
  return PX + r * math.sin(rad), PY - r * math.cos(rad)
end

-- One arc segment on the scale. Sweep flag 1 = clockwise in SVG's y-down
-- space, which is left-to-right here.
local function arc(fromLevel, toLevel, color, opacity, extra)
  local x1, y1 = polar(angleOf(fromLevel), R)
  local x2, y2 = polar(angleOf(toLevel), R)
  return string.format(
    '<path d="M %.2f %.2f A %d %d 0 0 1 %.2f %.2f" stroke="%s" stroke-width="%.1f"'
      .. ' stroke-opacity="%.2f" fill="none"%s/>',
    x1,
    y1,
    R,
    R,
    x2,
    y2,
    color,
    ARC_W,
    opacity,
    extra or ""
  )
end

-- Zone boundaries, unchanged from the waybar face (which hardcoded them as
-- arc endpoints at -9 / +18 / +31.5 degrees). With gawk's linear
-- -40..0 dBFS -> 0..1 mapping they are:
--   idle   0.00..0.40   below -24 dBFS
--   green  0.40..0.70   -24..-12 dBFS  (speech sits here)
--   yellow 0.70..0.85   -12..-6 dBFS
--   red    0.85..1.00   -6..0 dBFS     (about to clip)
local Z_GREEN, Z_YELLOW, Z_RED = 0.40, 0.70, 0.85

-- ---------------------------------------------------------------------------
-- Palette
--
-- noctalia.getColor(role) (plugin API 31) returns the live palette's
-- #RRGGBB for a role; it lives in the base library every entry kind gets
-- (luau_host.cpp kNoctaliaBaseLib), so it works in a [[service]], and reads a
-- mutex-guarded snapshot (lib/ui/palette.cpp colorForRoleSnapshot), so it is
-- safe off the UI thread. It returns nil for an unknown role — the hex
-- fallbacks cover that and a runtime too old to have the role at all.
--
-- The palette has no green or yellow role (lib/ui/palette.h
-- kColorRoleTokens: primary/secondary/tertiary/error + surfaces), so the
-- three zones are a fixed traffic-light set, picked per mode: bright on a
-- dark bar, deep on a light one (pure #ffdc00 vanishes on a light surface).
-- Red is deliberately NOT the palette's `error` here: M3 dark schemes put
-- `error` at tone 80, a pastel pink that reads as a fourth zone next to
-- saturated green and yellow, not as "about to clip". `error` is used where
-- it means error/off — the muted face.
local ZONE_HEX = {
  dark = { green = "#3fd06a", yellow = "#f5c518", red = "#ff5a4e" },
  light = { green = "#1a8f3c", yellow = "#b58300", red = "#c62828" },
}
local FALLBACK = {
  dark = { on_surface = "#e6e1e5", on_surface_variant = "#cac4d0", error = "#ffb4ab" },
  light = { on_surface = "#1c1b1f", on_surface_variant = "#49454f", error = "#ba1a1a" },
}

local pal = {}
local palKey = ""

-- Re-read every role the face uses; returns true when anything changed.
local function readPalette()
  local mode = noctalia.isDarkMode() and "dark" or "light"
  local function role(name)
    return noctalia.getColor(name) or FALLBACK[mode][name]
  end
  local next = {
    needle = role("on_surface"),
    idle = role("on_surface_variant"),
    mute = role("error"),
    green = ZONE_HEX[mode].green,
    yellow = ZONE_HEX[mode].yellow,
    red = ZONE_HEX[mode].red,
  }
  local key = table.concat({ mode, next.needle, next.idle, next.mute }, ",")
  if key == palKey then
    return false
  end
  pal = next
  palKey = key
  return true
end

-- ---------------------------------------------------------------------------
-- Faces — the three states differ in SHAPE first, colour second, so they
-- stay distinguishable at 22 px and for colour-blind eyes (no text: at bar
-- size a 5-unit "MUTE" was ~3 px tall and unreadable anyway):
--   live    solid zoned arc + needle
--   muted   solid arc in `error` + diagonal slash, no needle
--   nosrc   dashed, faded arc, no needle, no slash

local function liveFace(level)
  local x1, y1 = polar(angleOf(level), NEEDLE_R)
  -- The needle is drawn from the pivot; the part below y=22 is simply
  -- clipped by the viewBox.
  return SVG_OPEN
    .. arc(0, Z_GREEN, pal.idle, 0.45)
    .. arc(Z_GREEN, Z_YELLOW, pal.green, 1)
    .. arc(Z_YELLOW, Z_RED, pal.yellow, 1)
    .. arc(Z_RED, 1, pal.red, 1)
    .. string.format(
      '<line x1="%d" y1="%d" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>',
      PX,
      PY,
      x1,
      y1,
      pal.needle,
      NEEDLE_W
    )
    .. "</svg>"
end

local function mutedFace()
  return SVG_OPEN
    .. arc(0, 1, pal.mute, 0.7)
    -- the universal "off" slash, corner to corner of the arc's bounding box
    .. string.format(
      '<line x1="9" y1="20" x2="35" y2="2" stroke="%s" stroke-width="2.6" stroke-linecap="round"/>',
      pal.mute
    )
    .. "</svg>"
end

local function nosrcFace()
  -- dashes of ~one stroke width: reads as "absent / placeholder", the same
  -- idiom as a disconnected-device outline. 8 dashes + 7 gaps = 42.4, the
  -- quarter-circle arc length (27 * pi / 2), so it ends on a whole dash.
  return SVG_OPEN .. arc(0, 1, pal.idle, 0.6, ' stroke-dasharray="3.2 2.4"') .. "</svg>"
end

-- ---------------------------------------------------------------------------
-- State

local src = nil -- { idx = "57", name = "alsa_input...." } | nil
local muted = nil -- true/false once queried; nil = unknown (just found)
local gain = nil -- volume % from get-source-volume
local level = 0
local db = nil
local status = "nosrc"

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

local function currentFace()
  if status == "muted" then
    return mutedFace()
  elseif status == "nosrc" then
    return nosrcFace()
  end
  return liveFace(level)
end

-- Luau-side twin of gawk's confirm frame. The widget's file watcher drops a
-- rename that lands < 100 ms after the previous one for the same watch, so a
-- face painted from a mute event or a palette change (which can land right
-- behind a gawk frame) may never be shown. update() repaints once more at a
-- guaranteed-safe distance; gawk frames need no help, they bring their own.
local confirmAt = nil
local CONFIRM_MS = 200

local function paint(confirm)
  writeFace(currentFace())
  if confirm then
    confirmAt = noctalia.nowMs() + CONFIRM_MS
  end
end

local function publish()
  noctalia.state.set("vu", { status = status, level = level, db = db, gain = gain })
end

-- Recompute status from the merged state; repaint only on an actual change
-- (NOSRC repeats every 3 s while the mic is unplugged).
local function setStatus()
  local next
  if src == nil then
    next = "nosrc"
  elseif muted == nil then
    -- just (re)found, first mute query still in flight: keep the old face
    -- rather than flash "live" and then "muted" 10 ms later
    return
  elseif muted then
    next = "muted"
  else
    next = "ok"
  end
  local changed = next ~= status
  status = next
  publish()
  if changed then
    paint(true)
  end
end

-- ---------------------------------------------------------------------------
-- Mute / gain queries
--
-- At most one query in flight. Events that arrive meanwhile only set
-- `again`, so a burst of N change events (pavucontrol drag, pw-cat start
-- toggling the source RUNNING/SUSPENDED) costs at most two query rounds, not
-- N. argv form (API 24): the source name is data, never shell-parsed.
local inFlight, again = false, false

local function queryMic()
  if src == nil then
    return
  end
  if inFlight then
    again = true
    return
  end
  inFlight = true
  local name = src.name

  local function finish()
    inFlight = false
    if again then
      again = false
      queryMic()
    end
  end

  local ok = noctalia.runAsync({ PACTL, "get-source-mute", name }, function(m)
    local isMuted = nil
    if m.exitCode == 0 then
      isMuted = m.stdout:match("Mute:%s*yes") ~= nil
    end
    local okVol = noctalia.runAsync({ PACTL, "get-source-volume", name }, function(v)
      -- discard a result for a source that went away / was replaced meanwhile
      if src ~= nil and src.name == name then
        -- a failed mute query (source vanishing under us) keeps the last
        -- known value; "unknown" degrades to live so the meter never sticks
        -- on the pre-query face
        if isMuted ~= nil then
          muted = isMuted
        elseif muted == nil then
          muted = false
        end
        gain = (v.exitCode == 0) and tonumber(v.stdout:match("(%d+)%%")) or nil
        setStatus()
      end
      finish()
    end)
    if not okVol then
      finish()
    end
  end)
  if not ok then
    inFlight = false
  end
end

-- ---------------------------------------------------------------------------
-- Streams

readPalette()
publish()
paint(true)

-- LC_ALL=C keeps gawk's printf decimal point a dot regardless of locale.
local captureCmd = "MATCH=" .. quotedMatch .. "\n" .. [[
while :; do
  # Index + node-name columns only, and never a monitor source: a USB mic
  # contributes both alsa_input.* and alsa_output.*.monitor, the monitor sorts
  # first, and matching $0 would meter (and mute-track) the playback loopback
  # instead. The index is what `pactl subscribe` events name the source by.
  set -- $(@PACTL@ list sources short 2>/dev/null \
    | @GAWK@ -v m="$MATCH" '$2 !~ /[.]monitor$/ && $2 ~ m { print $1, $2; exit }')
  if [ $# -lt 2 ]; then echo NOSRC; sleep 3; continue; fi
  echo "SRC $1 $2"
  @PW_CAT@ --record --raw --target "$2" \
    --rate 8000 --channels 1 --format s16 - 2>/dev/null \
    | @OD@ -An -td2 -w2 -v \
    | LC_ALL=C @GAWK@ '
      BEGIN {
        # 125 ms at 8 kHz. 100 ms (800) beat against the widget file
        # watcher, which drops a rename < 100 ms after the previous one:
        # back-to-back frames 100 ms apart, minus pipe/scheduling jitter,
        # regularly fell inside that window and were lost mid-sweep.
        window   = 1000
        count    = 0
        peak     = 0
        needle   = 0      # normalized 0..1 meter position
        db_floor = -60
        last     = -1     # force first emit
        confirm  = 0
        # Ballistics were tuned per 100 ms step (attack 0.35, decay 0.10).
        # A first-order smoother covers 1-(1-a)^n of the gap in n steps, so
        # the same time constants at a 125 ms step are 1-(1-a)^(125/100):
        # attack ~0.416, decay ~0.123.
        attack = 1 - (1 - 0.35) ^ (window / 800)
        decay  = 1 - (1 - 0.10) ^ (window / 800)
      }
      {
        v = $1; if (v < 0) v = -v
        if (v > peak) peak = v
        count++
        if (count >= window) {
          if (peak <= 0) db = db_floor
          else           db = 20.0 * log(peak / 32767.0) / log(10)
          if (db < db_floor) db = db_floor
          if (db > 0)        db = 0

          # linear -40..0 dBFS -> 0..1
          if (db <= -40) target = 0
          else           target = (db + 40) / 40.0

          # ballistic smoothing: fast attack, slow decay
          if (target > needle) needle += (target - needle) * attack
          else                 needle += (target - needle) * decay

          # snap the decay tail to rest: the decay is geometric, so without
          # this the needle creeps toward 0 forever, trickling a frame every
          # few windows and finally parking up to one emit threshold
          # (~0.0045) off zero. Below 0.02 (under 2 degrees) jump to an
          # exact 0 — the jump itself exceeds the threshold, so it emits.
          if (target <= 0 && needle < 0.02) needle = 0

          if ((needle - last) ^ 2 > 0.00002) {
            printf "%.3f %.1f\n", needle, db
            fflush()
            last = needle
            confirm = 2
          } else if (confirm > 0 && --confirm == 0) {
            # trailing confirm frame, 2 windows (250 ms) after a burst ends:
            # the widget-side file watcher drops rename events that land
            # < 100 ms after the previous one, so a burst-final frame can be
            # lost and freeze the needle. One duplicate at a guaranteed-safe
            # distance repaints the true resting face. (One window would
            # already clear 100 ms; the second is margin for pipe jitter.)
            printf "%.3f %.1f\n", needle, db
            fflush()
          }

          peak = 0
          count = 0
        }
      }'
  echo NOSRC
  sleep 2
done
]]

noctalia.runStream(captureCmd, function(line)
  line = noctalia.string.trim(line)
  if line == "NOSRC" then
    src, muted, gain, db, level = nil, nil, nil, nil, 0
    setStatus()
    return
  end

  local idx, name = line:match("^SRC (%d+) (%S+)$")
  if idx ~= nil then
    -- (re)found, possibly under a new index after a replug: mute state is
    -- unknown until queried, so the face holds until the answer lands
    src, muted, gain = { idx = idx, name = name }, nil, nil
    queryMic()
    return
  end

  local n, d = line:match("^(%S+) (%S+)$")
  local lv = tonumber(n)
  if lv ~= nil then
    level = math.clamp(lv, 0, 1)
    db = tonumber(d)
    publish()
    -- Every gawk line paints, duplicates included: the trailing confirm
    -- frame is a deliberate duplicate whose whole point is a second rename.
    -- While muted the face doesn't move, but repainting it is what lets the
    -- confirm frame recover a mute paint the watcher dropped.
    if muted ~= nil then
      paint(false)
    end
  end
end)

-- Event-driven mute/gain. `pactl subscribe` prints one line per server event
-- ("Event 'change' on source #57"); gawk keeps only source change events
-- (not source-output, i.e. not every client stream starting), and Luau then
-- drops any whose index isn't the metered source — so unrelated device churn
-- costs a line on a pipe, never a fork. Hot-plug needs no event here: unplug
-- ends pw-cat (-> NOSRC), replug is found by the capture loop (-> SRC, which
-- queries). SUB marks every (re)connect, e.g. after a pipewire-pulse restart
-- killed the previous subscriber, and re-syncs whatever changed while it was
-- down.
local eventsCmd = [[
while :; do
  echo SUB
  @PACTL@ subscribe 2>/dev/null \
    | LC_ALL=C @GAWK@ '/^Event \047change\047 on source #[0-9]+$/ { sub(/^.*#/, ""); print "EV " $0; fflush() }'
  sleep 2
done
]]

noctalia.runStream(eventsCmd, function(line)
  line = noctalia.string.trim(line)
  if line == "SUB" then
    queryMic()
    return
  end
  local idx = line:match("^EV (%d+)$")
  if idx ~= nil and src ~= nil and idx == src.idx then
    queryMic()
  end
end)

-- Palette follow. The runtime delivers no palette-change event to scripts:
-- onConfigChanged fires only for config paths read via getSetting, and that
-- snapshot is published before the theme service resolves the new palette;
-- the `colors_changed` hook fires on the first tick of a 400 ms animated
-- palette lerp (theme_service.cpp kTransitionDurationMs), so either would
-- read a half-blended palette. Polling the handful of roles the face uses
-- is a few mutex-guarded lookups, no fork and no I/O; it repaints only when
-- the palette actually differs, and simply catches the settled palette on a
-- later tick. That also covers the case that matters most: the mic is
-- silent, gawk emits nothing, and the face would otherwise keep the old theme
-- until the next sound.
noctalia.setUpdateInterval(250)

function update()
  if readPalette() then
    paint(true)
  elseif confirmAt ~= nil and noctalia.nowMs() >= confirmAt then
    confirmAt = nil
    paint(false)
  end
end
