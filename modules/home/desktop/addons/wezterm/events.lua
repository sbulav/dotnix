-- Update window title
-- {{{
wezterm.on("format-window-title", function(tab, _, tabs)
	local index = ""
	if #tabs > 1 then
		index = "[" .. tab.tab_index + 1 .. "/" .. #tabs .. "]"
	end

	return index .. tab.window_title
end)
-- }}}
-- Update status on the right side
-- {{{
-- Icons: https://wezfurlong.org/wezterm/config/lua/wezterm/nerdfonts.html
-- https://wezfurlong.org/wezterm/config/lua/window-events/update-right-status.html
-- === K8s status (cached, portable, resilient) ===============================
-- Dependencies: kubectl (no hard dep on kubectx/kubens)
-- It caches results for a short TTL to avoid blocking the UI.
local KUBE_TTL_SECONDS = 3
local kube_cache = {
	last = 0,
	ctx = "-",
	ns = "-",
}

-- replace your now_seconds() with this:
local function now_seconds()
	return os.time() -- simple, stable integer seconds
end

local function trim(s)
	if type(s) ~= "string" then
		return ""
	end
	return (s:gsub("[\r\n]+", ""))
end

local function read_cmd(argv)
	-- Returns stdout on success, nil otherwise
	local success, stdout, _ = wezterm.run_child_process(argv)
	if not success then
		return nil
	end
	if type(stdout) ~= "string" then
		return nil
	end
	-- trim trailing newlines/whitespace
	return (stdout:gsub("[\r\n%s]+$", ""))
end

local function detect_env_color(theme, ctx, ns)
	-- Heuristics for fast risk awareness. Adjust patterns to your naming.
	local lc = (ctx .. ":" .. ns):lower()
	if lc:find("prod") or lc:find("production") then
		return theme.red
	elseif lc:find("staging") or lc:find("stage") then
		return theme.orange or theme.yellow
	elseif lc:find("dev") or lc:find("sandbox") then
		return theme.green_dark
	elseif ns == "kube-system" or ns == "kube-public" then
		return theme.comment
	end
	-- default accent
	return theme.magenta
end

local function refresh_kube_cache()
	local t = now_seconds()
	-- ensure kube_cache.last is numeric
	if type(kube_cache.last) ~= "number" then
		kube_cache.last = 0
	end
	if (t - kube_cache.last) < KUBE_TTL_SECONDS then
		return
	end

	-- the rest unchanged...
	local ctx = read_cmd({ "kubectl", "config", "current-context" }) or "-"
	local ns = read_cmd({
		"kubectl",
		"config",
		"view",
		"--minify",
		"--output",
		"jsonpath={..namespace}",
	})
	if not ns or ns == "" then
		ns = "default"
	end

	kube_cache.ctx = ctx
	kube_cache.ns = ns
	kube_cache.last = t
end

wezterm.on("update-right-status", function(window)
	refresh_kube_cache()
	local ctx = kube_cache.ctx
	local ns = kube_cache.ns

	-- quick one-shot proof in the log:
	-- wezterm.log_info(("k8s status: ctx='%s' ns='%s'"):format(tostring(ctx), tostring(ns)))

	local date = wezterm.strftime("[%H:%M]")
	local env_color = detect_env_color(theme, ctx, ns)

	window:set_right_status(wezterm.format({
		{ Foreground = { Color = theme.blue } },
		{ Text = wezterm.nerdfonts.md_kubernetes },
		{ Foreground = { Color = env_color } },
		{ Text = " " .. ctx },
		{ Foreground = { Color = theme.cyan } },
		{ Text = ":" .. ns },
		{ Foreground = { Color = theme.red } },
		{ Text = " " .. date },
	}))
end)
-- ============================================================================
-- }}}
