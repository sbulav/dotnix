local arrow_solid = ""
local arrow_thin = ""
local icons = {
	["C:\\WINDOWS\\system32\\cmd.exe"] = wezterm.nerdfonts.md_console_line,
	["Topgrade"] = wezterm.nerdfonts.md_rocket_launch,
	["bash"] = wezterm.nerdfonts.cod_terminal_bash,
	["btm"] = wezterm.nerdfonts.mdi_chart_donut_variant,
	["btop"] = wezterm.nerdfonts.md_chart_areaspline,
	["cargo"] = wezterm.nerdfonts.dev_rust,
	["curl"] = wezterm.nerdfonts.mdi_flattr,
	["docker"] = wezterm.nerdfonts.linux_docker,
	["docker-compose"] = wezterm.nerdfonts.linux_docker,
	["fish"] = wezterm.nerdfonts.md_fish,
	["gh"] = wezterm.nerdfonts.dev_github_badge,
	["git"] = wezterm.nerdfonts.dev_git,
	["go"] = wezterm.nerdfonts.seti_go,
	["htop"] = wezterm.nerdfonts.md_chart_areaspline,
	["kubectl"] = wezterm.nerdfonts.md_kubernetes,
	["k9s"] = wezterm.nerdfonts.md_kubernetes,
	["kuberlr"] = wezterm.nerdfonts.linux_docker,
	["lazydocker"] = wezterm.nerdfonts.linux_docker,
	["lazygit"] = wezterm.nerdfonts.cod_github,
	["lua"] = wezterm.nerdfonts.seti_lua,
	["make"] = wezterm.nerdfonts.seti_makefile,
	["node"] = wezterm.nerdfonts.mdi_hexagon,
	["nvim"] = wezterm.nerdfonts.linux_neovim,
	["nix"] = wezterm.nerdfonts.md_nix,
	["nixt"] = wezterm.nerdfonts.md_nix,
	["psql"] = wezterm.nerdfonts.dev_postgresql,
	["pwsh.exe"] = wezterm.nerdfonts.md_console,
	["ruby"] = wezterm.nerdfonts.cod_ruby,
	["sudo"] = wezterm.nerdfonts.fa_hashtag,
	["vim"] = wezterm.nerdfonts.linux_neovim,
	["wget"] = wezterm.nerdfonts.mdi_arrow_down_box,
	["zsh"] = wezterm.nerdfonts.dev_terminal,
}

---@param tab MuxTabObj
---@param max_width number
local function title(tab, max_width)
	local t = (tab.tab_title and #tab.tab_title > 0) and tab.tab_title or tab.active_pane.title
	local process, other = t:match("^(%S+)%s*%-?%s*%s*(.*)$")
	if icons[process] then
		t = icons[process] .. " " .. (other or "")
	end

	local is_zoomed = false
	for _, pane in ipairs(tab.panes) do
		if pane.is_zoomed then
			is_zoomed = true
			break
		end
	end
	if is_zoomed then
		t = " " .. t
	end

	local w = math.max(1, (max_width or 1) - 3) -- 👈 clamp
	t = wezterm.truncate_right(t, w)
	return " " .. t .. " "
end

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local title = title(tab, max_width)
	local colors = config.resolved_palette
	local active_bg = colors.tab_bar.active_tab.bg_color
	local inactive_bg = colors.tab_bar.inactive_tab.bg_color

	local tab_idx = 1
	for i, t in ipairs(tabs) do
		if t.tab_id == tab.tab_id then
			tab_idx = i
			break
		end
	end
	-- local tab_idx = tab.tab_index + 1
	local is_last = tab_idx == #tabs
	local next_tab = tabs[tab_idx + 1]
	local next_is_active = next_tab and next_tab.is_active
	local arrow = (tab.is_active or is_last or next_is_active) and arrow_solid or arrow_thin
	local arrow_bg = inactive_bg
	local arrow_fg = colors.tab_bar.inactive_tab_edge
		or (colors.tab_bar.inactive_tab and colors.tab_bar.inactive_tab.fg_color)
		or colors.foreground

	if is_last then
		arrow_bg = colors.tab_bar.background
		arrow_fg = (tab.is_active and active_bg or inactive_bg) or arrow_fg
	elseif tab.is_active then
		arrow_bg = inactive_bg
		arrow_fg = active_bg or arrow_fg
	elseif next_is_active then
		arrow_bg = active_bg
		arrow_fg = inactive_bg or arrow_fg
	end

	local ret = tab.is_active
			and {
				{ Attribute = { Intensity = "Bold" } },
				-- { Attribute = { Italic = true } },
			}
		or {}

	ret[#ret + 1] = { Text = " " .. tab_idx .. ":" .. title }

	ret[#ret + 1] = { Foreground = { Color = arrow_fg } }
	ret[#ret + 1] = { Background = { Color = arrow_bg } }
	ret[#ret + 1] = { Text = arrow }
	return ret
end)
