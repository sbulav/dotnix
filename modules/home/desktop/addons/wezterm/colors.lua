-- -- cyberdream theme for wezterm
local colors_cyberdream = {
	bg = "#1B2B34",
	bg_dark = "#343D46",
	bg_highlight = "#4F5B66",
	comment = "#65737E",
	fg_dark = "#A7ADBA",
	fg = "#C0C5CE",
	fg_gutter = "#CDD3DE",
	fg_light = "#D8DEE9", -- TODO: this doesn't make sesne

	scrollbar_thumb = "#16181a",
	split = "#16181a",
	red = "#ff6e5e",
	orange = "#F99157",
	yellow = "#ffbd5e",
	green_dark = "#11ab49",
	cyan = "#5ef1ff",
	blue = "#5ea1ff",
	purple = "#bd5eff",
	magenta = "#C594C5",
	black = "#000000",
	white = "#dedcdc",
}

local colors_oceanic = {
	bg = "#1B2B34",
	bg_dark = "#343D46",
	bg_highlight = "#4F5B66",
	comment = "#65737E",
	fg_dark = "#A7ADBA",
	fg = "#C0C5CE",
	fg_gutter = "#CDD3DE",
	fg_light = "#D8DEE9", -- TODO: this doesn't make sesne

	red = "#EC5f67",
	orange = "#F99157",
	yellow = "#FAC863",
	-- green = "#99C794",
	green_dark = "#11ab49",
	cyan = "#5FB3B3",
	blue = "#6699CC",
	purple = "#C594C5",
	magenta = "#C594C5",
	black = "#000000",
	white = "#dedcdc",
}

-- dark green theme for wezterm (used on macOS)
local colors_darkgreen = {
	bg = "#0b1a12",
	bg_dark = "#0e2018",
	bg_highlight = "#13362a",
	comment = "#5f7a6b",
	fg_dark = "#8fae9c",
	fg = "#c4d8cb",
	fg_gutter = "#a9c2b4",
	fg_light = "#d6e8dc",

	scrollbar_thumb = "#13362a",
	split = "#0e2018",
	red = "#e06c75",
	orange = "#d19a66",
	yellow = "#e5c07b",
	green_dark = "#2ea043",
	cyan = "#56b6c2",
	blue = "#61afef",
	purple = "#c678dd",
	magenta = "#c594c5",
	black = "#06120c",
	white = "#d6e8dc",
}

-- On macOS use the dark green palette and ignore the Linux desktop palette
-- (custom_theme drives waybar/hyprland and clashes with the green scheme).
local is_darwin = wezterm.target_triple == "aarch64-apple-darwin"
local theme = is_darwin and colors_darkgreen or colors_cyberdream
local ct = (not is_darwin) and custom_theme or nil

local tab_bar_bg = (ct and ct.base) or theme.black
local inactive_tab_bg = (ct and ct.panel) or theme.bg_dark
local active_tab_bg = (ct and ct.violet) or theme.green_dark
local active_tab_fg = (ct and ct.text) or theme.fg

-- config.color_scheme = "Oceanic-Next"
config.command_palette_bg_color = theme.black
-- https://wezfurlong.org/wezterm/config/appearance.html#retro-tab-bar-appearance
config.colors = {
	-- The default text color
	foreground = theme.white,
	-- The default background color
	background = theme.black,
	tab_bar = {
		background = tab_bar_bg,
		active_tab = {
			bg_color = active_tab_bg,
			fg_color = active_tab_fg,
		},
		inactive_tab = {
			-- bg_color = base16_colors.bg_dark,
			bg_color = inactive_tab_bg,
			fg_color = theme.fg_dark,
		},
		new_tab = {
			bg_color = inactive_tab_bg,
			fg_color = theme.fg_dark,
		},
	},
}
