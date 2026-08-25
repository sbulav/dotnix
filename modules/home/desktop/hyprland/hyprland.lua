-- Hyprland Lua configuration
-- Static portion; dynamic Nix-generated config (monitors, theme colors,
-- workspace assignments, keybindings, screenshot binds) is appended via
-- the home-manager module.
-- See https://wiki.hyprland.org/Configuring/

local mainMod = "SUPER"
local uwsmApp = "/run/current-system/sw/bin/uwsm-app -- "

local function bind(keys, description, dispatcher, options)
	options = options or {}
	options.description = description
	return hl.bind(keys, dispatcher, options)
end

----------------------------------------------------------------
-- Autostart
----------------------------------------------------------------
hl.on("hyprland.start", function()
	hl.exec_cmd(uwsmApp .. "wezterm")
	hl.exec_cmd(uwsmApp .. "firefox")
	hl.exec_cmd("hyprctl setcursor Adwaita 24")
end)

----------------------------------------------------------------
-- Environment
----------------------------------------------------------------
hl.env("HYPRCURSOR_THEME", "Adwaita")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

----------------------------------------------------------------
-- Core config blocks
----------------------------------------------------------------
hl.config({
	xwayland = {
		force_zero_scaling = true,
	},
	ecosystem = {
		no_update_news = true,
		no_donation_nag = true,
	},
	input = {
		kb_layout = "dh,ru",
		kb_options = "grp:caps_toggle",
		follow_mouse = 1,
		sensitivity = 0,
		touchpad = {
			natural_scroll = false,
		},
	},
	cursor = {
		no_hardware_cursors = false,
		enable_hyprcursor = true,
		sync_gsettings_theme = true,
		-- The pointer never moves on its own. Every focus-driven warp goes
		-- through warpCursorTo and this kills them all: clicking an app icon
		-- in noctalia's taskbar (dispatch focuswindow -> warp to window
		-- middle), xdg-activation via focus_on_activate below, and keyboard
		-- movefocus/focuswindow binds.
		no_warps = true,
	},
	decoration = {
		rounding = 10,
		blur = {
			enabled = true,
			size = 3,
			passes = 1,
		},
		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = "rgba(1a1a1aee)",
		},
	},
	dwindle = {
		preserve_split = true,
	},
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		focus_on_activate = true,
	},
})

-- Per-device tweaks
hl.device({
	name = "epic-mouse-v1",
	sensitivity = -0.5,
})

----------------------------------------------------------------
-- Layer rules
----------------------------------------------------------------
hl.layer_rule({ match = { namespace = "waybar" }, no_anim = true })

-- noctalia surfaces: frosted instead of transparent. The bar runs
-- background_opacity 0.29; blur alone does nothing there without
-- ignore_alpha, since Hyprland skips blur behind fully-transparent pixels.
-- Namespace is always "noctalia-bar-<name>" (never bare "noctalia-bar");
-- the launcher surfaces as "noctalia-panel". Values are Hyprland regexes,
-- not Lua patterns.
hl.layer_rule({
	match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd)$" },
	blur = true,
	ignore_alpha = 0.5,
	no_anim = true,
})
hl.layer_rule({ match = { namespace = "^noctalia-backdrop$" }, no_anim = true })

----------------------------------------------------------------
-- Animations
----------------------------------------------------------------
hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default" })

----------------------------------------------------------------
-- Static keybindings (navigation, workspaces, media, mouse)
----------------------------------------------------------------

-- Move focus with mainMod + arrow keys / hjkl
for _, m in ipairs({
	{ "left", "l" },
	{ "right", "r" },
	{ "up", "u" },
	{ "down", "d" },
	{ "h", "l" },
	{ "l", "r" },
	{ "k", "u" },
	{ "j", "d" },
}) do
	bind(mainMod .. " + " .. m[1], "Focus " .. m[1], hl.dsp.focus({ direction = m[2] }))
end

-- Swap windows with CONTROLALT + hjkl
for _, m in ipairs({
	{ "h", "l" },
	{ "l", "r" },
	{ "k", "u" },
	{ "j", "d" },
}) do
	bind("CONTROL + ALT + " .. m[1], "Swap window " .. m[1], hl.dsp.window.swap({ direction = m[2] }))
end

-- Switch workspaces with mainMod + [0-9]
for i = 1, 9 do
	bind(mainMod .. " + " .. tostring(i), "Switch to workspace " .. tostring(i), hl.dsp.focus({ workspace = i }))
end
bind(mainMod .. " + 0", "Switch to workspace 10", hl.dsp.focus({ workspace = 10 }))

-- ALT + down/up → workspaces 1/2 (legacy ergonomic)
bind("ALT + down", "Switch to workspace 1", hl.dsp.focus({ workspace = 1 }))
bind("ALT + up", "Switch to workspace 2", hl.dsp.focus({ workspace = 2 }))

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 9 do
	bind(mainMod .. " + SHIFT + " .. tostring(i), "Move window to workspace " .. tostring(i), hl.dsp.window.move({ workspace = i }))
end
bind(mainMod .. " + SHIFT + 0", "Move window to workspace 10", hl.dsp.window.move({ workspace = 10 }))

-- Move workspace between monitors
bind(mainMod .. " + CONTROL + left", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
bind(mainMod .. " + CONTROL + right", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))

-- Cycle through workspaces
bind(mainMod .. " + mouse_down", "Switch to next workspace", hl.dsp.focus({ workspace = "e+1" }))
bind(mainMod .. " + mouse_up", "Switch to previous workspace", hl.dsp.focus({ workspace = "e-1" }))
bind("CONTROL + ALT + right", "Switch to next workspace", hl.dsp.focus({ workspace = "e+1" }))
bind("CONTROL + ALT + left", "Switch to previous workspace", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB
bind(mainMod .. " + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
bind(mainMod .. " + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

-- Audio
bind("XF86AudioRaiseVolume", "Raise output volume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
bind("XF86AudioLowerVolume", "Lower output volume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true })
bind("XF86AudioMute", "Mute output audio", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { repeating = true })
bind("XF86AudioMicMute", "Mute microphone", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { repeating = true })
bind("XF86AudioPlay", "Play or pause media", hl.dsp.exec_cmd("playerctl play-pause"))
bind("XF86AudioPause", "Play or pause media", hl.dsp.exec_cmd("playerctl play-pause"))
bind("XF86AudioNext", "Play next track", hl.dsp.exec_cmd("playerctl next"))
bind("XF86AudioPrev", "Play previous track", hl.dsp.exec_cmd("playerctl previous"))
bind("XF86MonBrightnessUp", "Raise display brightness", hl.dsp.exec_cmd("display-brightness up"))
bind("XF86MonBrightnessDown", "Lower display brightness", hl.dsp.exec_cmd("display-brightness down"))

----------------------------------------------------------------
-- Window rules
----------------------------------------------------------------

-- Defaults
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ match = { class = ".*" }, opacity = "0.97 0.9" })

-- XWayland anonymous dragging fix
hl.window_rule({
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- No transparency on media windows
hl.window_rule({
	match = {
		class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|feh|org.gnome.NautilusPreviewer)$",
	},
	opacity = "1 1",
})

-- Floating helpers
for _, c in ipairs({
	"Rofi",
	"viewnior",
	"wlogout",
	"file_progress",
	"confirm",
	"dialog",
	"download",
	"notification",
	"error",
	"splash",
	"confirmreset",
	"blueman-manager",
	"nm-connection-editor",
}) do
	hl.window_rule({ match = { class = "^(" .. c .. ")$" }, float = true })
end

-- QEMU windows go to workspace 5
hl.window_rule({ match = { title = ".*QEMU.*" }, workspace = "5" })

----------------------------------------------------------------
-- Steam & gaming rules
----------------------------------------------------------------

-- Steam client → workspace 4
hl.window_rule({ match = { class = "^(Steam|steam)$" }, workspace = "4 silent" })
hl.window_rule({ match = { class = "^(Steam|steam).", title = "^(Steam|steam)$" }, workspace = "4 silent" })
hl.window_rule({ match = { class = "^(gamescope|steam_app).*" }, workspace = "4 silent" })

-- Fullscreen for all Steam games
hl.window_rule({ match = { class = "^(steam_app).*" }, fullscreen = true })

-- Specific game tweaks
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(Tekken 8)$" }, fullscreen = true })
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(Path of Exile 2)$" }, fullscreen = true })
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(MTGA)$" }, fullscreen = true })
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(MTGA)$" }, fullscreen_state = "2 2" })

-- World of Warcraft
hl.window_rule({ match = { class = "^(steam_app_0)$", title = "^(World of Warcraft)$" }, min_size = { 5120, 1440 } })
hl.window_rule({ match = { class = "^(steam_app_0)$", title = "^(World of Warcraft)$" }, center = true })
hl.window_rule({ match = { class = "^(steam_app_0)$", title = "^(World of Warcraft)$" }, fullscreen = true })

-- Battle.net
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(Battle.net)$" }, tile = true })

-- Input / focus optimizations for games
hl.window_rule({ match = { class = "^(steam)$", title = "^()$" }, no_focus = true })
hl.window_rule({ match = { class = "^(steam_app).*" }, idle_inhibit = "focus" })

-- Tearing for games
hl.window_rule({ match = { class = "^(gamescope|steam_app).*" }, immediate = true })
