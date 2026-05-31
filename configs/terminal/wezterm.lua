local wezterm = require("wezterm")
local config = {}

if wezterm.config_builder then
	config = wezterm.config_builder()
end

config.color_scheme = "Tokyo Night Storm"

config.font = wezterm.font("JetBrains Mono", { weight = "Medium" })
config.font_size = 11

config.line_height = 1.2

config.window_padding = {
	left = 8,
	right = 8,
	top = 8,
	bottom = 8,
}

config.window_background_opacity = 0.92

config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.tab_bar_at_bottom = false
config.show_tab_index_in_tab_bar = true

config.window_decorations = "RESIZE|TITLE"
config.window_close_confirmation = "NeverPrompt"

config.enable_scroll_bar = false

config.cursor_blink_rate = 800
config.default_cursor_style = "BlinkingBlock"

config.mouse_bindings = {
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "NONE",
		action = wezterm.action.CompleteSelection("ClipboardAndPrimarySelection"),
	},
}

config.colors = {
	tab_bar = {
		background = "#1a1a2e",
		active_tab = {
			bg_color = "#7aa2f7",
			fg_color = "#1a1a2e",
			italic = false,
		},
		inactive_tab = {
			bg_color = "#414868",
			fg_color = "#a9b1d6",
		},
		inactive_tab_hover = {
			bg_color = "#565f89",
			fg_color = "#c0caf5",
		},
		new_tab = {
			bg_color = "#1a1a2e",
			fg_color = "#565f89",
		},
		new_tab_hover = {
			bg_color = "#565f89",
			fg_color = "#c0caf5",
		},
	},
	selection_fg = "#c0caf5",
	selection_bg = "#33467c",
	scrollbar_thumb = "#565f89",
}

config.launch_menu = {}

config.keys = {
	{ key = "t", mods = "CTRL|SHIFT", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
	{ key = "w", mods = "CTRL|SHIFT", action = wezterm.action.CloseCurrentTab({ confirm = false }) },
	{ key = "Enter", mods = "CTRL", action = wezterm.action.SpawnCommandInNewTab({ args = {} }) },
	{ key = "c", mods = "CTRL", action = wezterm.action.CopyTo("Clipboard") },
	{ key = "v", mods = "CTRL", action = wezterm.action.PasteFrom("Clipboard") },
	{ key = "Tab", mods = "CTRL", action = wezterm.action.ActivateTabRelative(1) },
	{ key = "Tab", mods = "CTRL|SHIFT", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "-", mods = "CTRL", action = wezterm.action.DecreaseFontSize },
	{ key = "=", mods = "CTRL", action = wezterm.action.IncreaseFontSize },
	{ key = "0", mods = "CTRL", action = wezterm.action.ResetFontSize },
}

config.mouse_bindings = {
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "NONE",
		action = wezterm.action.CompleteSelection("ClipboardAndPrimarySelection"),
	},
	{
		event = { Up = { streak = 1, button = "Middle" } },
		mods = "NONE",
		action = wezterm.action.PasteFrom("PrimarySelection"),
	},
}

config.front_end = "WebGpu"

return config
