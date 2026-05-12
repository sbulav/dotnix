local status = {}

local KUBE_DEFAULT_TTL_SECONDS = 15
local kube_cache = {
	last = 0,
	ctx = "-",
	ns = "-",
	path = false,
}

local function read_cmd(argv)
	local success, stdout = wezterm.run_child_process(argv)
	if not success or type(stdout) ~= "string" then
		return nil
	end

	return (stdout:gsub("[\r\n%s]+$", ""))
end

local function kubectl_path()
	if kube_cache.path ~= false then
		return kube_cache.path
	end

	local from_path = read_cmd({ "sh", "-c", "command -v kubectl" })
	if from_path and from_path ~= "" then
		kube_cache.path = from_path
		return kube_cache.path
	end

	kube_cache.path = read_cmd({
		"sh",
		"-c",
		"test -x /run/current-system/sw/bin/kubectl && printf %s /run/current-system/sw/bin/kubectl",
	})
	if kube_cache.path then
		return kube_cache.path
	end

	local user = os.getenv("USER") or ""
	kube_cache.path = read_cmd({
		"sh",
		"-c",
		"test -x /etc/profiles/per-user/"
			.. user
			.. "/bin/kubectl && printf %s /etc/profiles/per-user/"
			.. user
			.. "/bin/kubectl",
	})

	return kube_cache.path
end

local function detect_env_color(theme, ctx, ns)
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

	return theme.magenta
end

local function refresh_kube_cache(opts)
	opts = opts or {}
	local ttl = opts.refresh_seconds or KUBE_DEFAULT_TTL_SECONDS
	local now = os.time()
	if (now - kube_cache.last) < ttl then
		return
	end

	local kubectl = kubectl_path()
	if not kubectl then
		kube_cache.ctx = "-"
		kube_cache.ns = "-"
		kube_cache.last = now
		return
	end

	local ctx = read_cmd({ kubectl, "config", "current-context" }) or "-"
	local ns = read_cmd({
		kubectl,
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
	kube_cache.last = now
end

function status.kubernetes(theme, opts)
	opts = opts or {}
	if opts.enabled == false then
		return nil
	end

	refresh_kube_cache(opts)
	if kube_cache.ctx == "-" or kube_cache.ctx == "" then
		return nil
	end

	local label = kube_cache.ctx .. ":" .. kube_cache.ns
	return {
		icon = wezterm.nerdfonts.md_kubernetes,
		label = label,
		color = detect_env_color(theme, kube_cache.ctx, kube_cache.ns),
	}
end

function status.clock(theme, opts)
	opts = opts or {}
	if opts.enabled == false then
		return nil
	end

	return {
		label = wezterm.strftime(opts.format or "%H:%M"),
		color = theme.red,
	}
end

function status.render(theme, segments)
	local cells = {}
	local visible = {}

	for _, segment in ipairs(segments) do
		if segment and segment.label and segment.label ~= "" then
			visible[#visible + 1] = segment
		end
	end

	for index, segment in ipairs(visible) do
		if index > 1 then
			cells[#cells + 1] = { Foreground = { Color = theme.comment } }
			cells[#cells + 1] = { Text = " | " }
		end

		cells[#cells + 1] = { Foreground = { Color = segment.color or theme.fg } }
		if segment.icon then
			cells[#cells + 1] = { Text = segment.icon .. " " }
		end
		cells[#cells + 1] = { Text = segment.label }
	end

	return wezterm.format(cells)
end
