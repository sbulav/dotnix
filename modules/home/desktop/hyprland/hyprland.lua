-- Hyprland Lua configuration
-- Static portion; dynamic Nix-generated config (monitors, theme colors,
-- workspace assignments, keybindings, screenshot binds) is appended via
-- the home-manager module.
-- See https://wiki.hyprland.org/Configuring/

local mainMod = "SUPER"

----------------------------------------------------------------
-- Autostart
----------------------------------------------------------------
hl.on("hyprland.start", function()
  hl.exec_cmd("mako")
  hl.exec_cmd("waybar")
  hl.exec_cmd("wl-paste --watch cliphist store")
  hl.exec_cmd("wezterm")
  hl.exec_cmd("firefox")
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP --all")
  hl.exec_cmd("hyprctl setcursor Adwaita 24")
  hl.exec_cmd("nm-applet --indicator")
end)

----------------------------------------------------------------
-- Environment
----------------------------------------------------------------
hl.env("HYPRCURSOR_THEME", "Adwaita")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GDK_SCALE", "2")
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
hl.config({
  device = {
    name = "epic-mouse-v1",
    sensitivity = -0.5,
  },
})

----------------------------------------------------------------
-- Layer rules
----------------------------------------------------------------
hl.layer_rule({ match = { namespace = "waybar" }, no_anim = true })

----------------------------------------------------------------
-- Animations
----------------------------------------------------------------
hl.curve("myBezier", { type = "bezier", points = { 0.05, 0.9, 0.1, 1.05 } })
hl.animation({ leaf = "windows",     enabled = true, speed = 7,  curve = "myBezier" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 7,  curve = "default", style = "popin 80%" })
hl.animation({ leaf = "border",      enabled = true, speed = 10, curve = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8,  curve = "default" })
hl.animation({ leaf = "fade",        enabled = true, speed = 7,  curve = "default" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 6,  curve = "default" })

----------------------------------------------------------------
-- Static keybindings (navigation, workspaces, media, mouse)
----------------------------------------------------------------

-- Which-key cheatsheet
hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd("wlr-which-key"))

-- Move focus with mainMod + arrow keys / hjkl
for _, m in ipairs({
  { "left",  "l" }, { "right", "r" }, { "up",  "u" }, { "down", "d" },
  { "h",     "l" }, { "l",     "r" }, { "k",   "u" }, { "j",    "d" },
}) do
  hl.bind(mainMod .. " + " .. m[1], hl.dsp.focus({ direction = m[2] }))
end

-- Swap windows with CONTROLALT + hjkl
for _, m in ipairs({
  { "h", "l" }, { "l", "r" }, { "k", "u" }, { "j", "d" },
}) do
  hl.bind("CONTROL + ALT + " .. m[1], hl.dsp.window.swap({ direction = m[2] }))
end

-- Switch workspaces with mainMod + [0-9]
for i = 1, 9 do
  hl.bind(mainMod .. " + " .. tostring(i), hl.dsp.focus({ workspace = i }))
end
hl.bind(mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

-- ALT + down/up → workspaces 1/2 (legacy ergonomic)
hl.bind("ALT + down", hl.dsp.focus({ workspace = 1 }))
hl.bind("ALT + up",   hl.dsp.focus({ workspace = 2 }))

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 9 do
  hl.bind(mainMod .. " + SHIFT + " .. tostring(i), hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Move workspace between monitors
hl.bind(mainMod .. " + CONTROL + left",  hl.dsp.workspace.move({ monitor = "l" }))
hl.bind(mainMod .. " + CONTROL + right", hl.dsp.workspace.move({ monitor = "r" }))

-- Cycle through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind("CONTROL + ALT + right", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("CONTROL + ALT + left",  hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Audio
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { repeating = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 5%+"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"))

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
  match = { class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|feh|org.gnome.NautilusPreviewer)$" },
  opacity = "1 1",
})

-- Floating helpers
for _, c in ipairs({
  "Rofi", "viewnior", "wlogout", "file_progress", "confirm", "dialog",
  "download", "notification", "error", "splash", "confirmreset",
  "blueman-manager", "nm-connection-editor",
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
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(Tekken 8)$" },        fullscreen = true })
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(Path of Exile 2)$" }, fullscreen = true })
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(MTGA)$" },            fullscreen = true })
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(MTGA)$" },            fullscreen_state = "2 2" })

-- World of Warcraft
hl.window_rule({ match = { class = "^(steam_app_0)$", title = "^(World of Warcraft)$" }, min_size = { 5120, 1440 } })
hl.window_rule({ match = { class = "^(steam_app_0)$", title = "^(World of Warcraft)$" }, center     = true })
hl.window_rule({ match = { class = "^(steam_app_0)$", title = "^(World of Warcraft)$" }, fullscreen = true })

-- Battle.net
hl.window_rule({ match = { class = "^(steam_app).*", title = "^(Battle.net)$" }, tile = true })

-- Input / focus optimizations for games
hl.window_rule({ match = { class = "^(steam)$",       title = "^()$" }, no_focus     = true })
hl.window_rule({ match = { class = "^(steam_app).*" }, idle_inhibit = "focus" })

-- Tearing for games
hl.window_rule({ match = { class = "^(gamescope|steam_app).*" }, immediate = true })

----------------------------------------------------------------
-- Workspace rules
----------------------------------------------------------------
hl.workspace_rule({ workspace = "4", on_created_empty = "steam" })
