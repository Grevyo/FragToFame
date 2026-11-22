class_name F2FTheme
extends RefCounted
## Builds the Frag to Fame dark esports UI theme in code.
##
## Use the named type variations (set [member Control.theme_type_variation]) instead of
## per-node colour overrides, so the look stays consistent and is changed in one place.

const BG: Color = Color("0b0e13")
const PANEL: Color = Color("12171e")
const PANEL_ALT: Color = Color("1a212b")
const PANEL_HOVER: Color = Color("222b37")
const BORDER: Color = Color("2a3441")
const TEXT: Color = Color("e6edf3")
const TEXT_MUTED: Color = Color("8b98a8")
const TEXT_DISABLED: Color = Color("4d5866")
const ACCENT: Color = Color("ff6a2a")
const ACCENT_DIM: Color = Color("3a2117")
const ACCENT_ALT: Color = Color("2ec4d6")
const SUCCESS: Color = Color("3fb950")
const DANGER: Color = Color("f85149")
const WARNING: Color = Color("e3b341")
const WARNING_BG: Color = Color("2b2410")


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	_build_base(theme)
	_build_buttons(theme)
	_build_labels(theme)
	_build_panels(theme)
	_build_misc(theme)
	return theme


static func box(bg: Color, border: Color = Color.TRANSPARENT, border_width: int = 0,
		radius: int = 4, pad_h: float = 12.0, pad_v: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


static func _build_base(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"Panel", box(PANEL, Color.TRANSPARENT, 0, 0))
	theme.set_stylebox(&"panel", &"PanelContainer", box(PANEL, Color.TRANSPARENT, 0, 0))
	theme.set_color(&"font_color", &"Label", TEXT)
	theme.set_color(&"font_color", &"RichTextLabel", TEXT)
	theme.set_stylebox(&"panel", &"TooltipPanel", box(PANEL_ALT, BORDER, 1, 4, 8, 6))
	theme.set_color(&"font_color", &"TooltipLabel", TEXT)


static func _apply_button_states(theme: Theme, type: StringName, normal: StyleBoxFlat,
		hover: StyleBoxFlat, pressed: StyleBoxFlat, disabled: StyleBoxFlat) -> void:
	theme.set_stylebox(&"normal", type, normal)
	theme.set_stylebox(&"hover", type, hover)
	theme.set_stylebox(&"pressed", type, pressed)
	theme.set_stylebox(&"hover_pressed", type, pressed)
	theme.set_stylebox(&"disabled", type, disabled)
	var focus := box(Color.TRANSPARENT, ACCENT_ALT, 1, normal.corner_radius_top_left)
	theme.set_stylebox(&"focus", type, focus)
	theme.set_color(&"font_color", type, TEXT)
	theme.set_color(&"font_hover_color", type, TEXT)
	theme.set_color(&"font_pressed_color", type, TEXT)
	theme.set_color(&"font_hover_pressed_color", type, TEXT)
	theme.set_color(&"font_focus_color", type, TEXT)
	theme.set_color(&"font_disabled_color", type, TEXT_DISABLED)


static func _build_buttons(theme: Theme) -> void:
	_apply_button_states(theme, &"Button",
		box(PANEL_ALT, BORDER, 1, 4, 14, 8),
		box(PANEL_HOVER, ACCENT, 1, 4, 14, 8),
		box(ACCENT_DIM, ACCENT, 1, 4, 14, 8),
		box(PANEL, BORDER, 1, 4, 14, 8))

	# Large main-menu buttons.
	theme.set_type_variation(&"MenuButtonLarge", &"Button")
	var menu_normal := box(PANEL_ALT, BORDER, 1, 4, 24, 14)
	menu_normal.border_width_left = 4
	var menu_hover := box(PANEL_HOVER, ACCENT, 1, 4, 24, 14)
	menu_hover.border_width_left = 4
	var menu_pressed := box(ACCENT_DIM, ACCENT, 1, 4, 24, 14)
	menu_pressed.border_width_left = 4
	_apply_button_states(theme, &"MenuButtonLarge", menu_normal, menu_hover, menu_pressed,
		box(PANEL, BORDER, 1, 4, 24, 14))
	theme.set_font_size(&"font_size", &"MenuButtonLarge", 22)

	# Sidebar navigation buttons (toggle buttons in a ButtonGroup).
	theme.set_type_variation(&"SidebarButton", &"Button")
	var side_normal := box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 20, 10)
	var side_hover := box(PANEL_ALT, Color.TRANSPARENT, 0, 0, 20, 10)
	var side_pressed := box(PANEL_HOVER, ACCENT, 0, 0, 20, 10)
	side_pressed.border_width_left = 4
	_apply_button_states(theme, &"SidebarButton", side_normal, side_hover, side_pressed, side_normal)
	theme.set_color(&"font_color", &"SidebarButton", TEXT_MUTED)
	theme.set_font_size(&"font_size", &"SidebarButton", 17)

	# Sidebar group headings (click to expand or collapse the group).
	theme.set_type_variation(&"SidebarHeadingButton", &"Button")
	var heading := box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 20, 4)
	_apply_button_states(theme, &"SidebarHeadingButton", heading, box(PANEL_ALT, Color.TRANSPARENT, 0, 0, 20, 4),
		heading, heading)
	theme.set_color(&"font_color", &"SidebarHeadingButton", TEXT_MUTED)
	theme.set_color(&"font_hover_color", &"SidebarHeadingButton", ACCENT_ALT)
	theme.set_font_size(&"font_size", &"SidebarHeadingButton", 13)

	# Clickable names in tables and cards (players, teams, competitions, matches).
	theme.set_type_variation(&"NavLink", &"LinkButton")
	theme.set_color(&"font_color", &"NavLink", ACCENT_ALT)
	theme.set_color(&"font_hover_color", &"NavLink", ACCENT)
	theme.set_color(&"font_pressed_color", &"NavLink", ACCENT)
	theme.set_color(&"font_focus_color", &"NavLink", ACCENT_ALT)

	# Prominent action button.
	theme.set_type_variation(&"AccentButton", &"Button")
	_apply_button_states(theme, &"AccentButton",
		box(ACCENT_DIM, ACCENT, 1, 4, 14, 8),
		box(ACCENT.darkened(0.35), ACCENT, 1, 4, 14, 8),
		box(ACCENT.darkened(0.5), ACCENT, 1, 4, 14, 8),
		box(PANEL, BORDER, 1, 4, 14, 8))


static func _label_variation(theme: Theme, name: StringName, size: int, color: Color) -> void:
	theme.set_type_variation(name, &"Label")
	theme.set_font_size(&"font_size", name, size)
	theme.set_color(&"font_color", name, color)


static func _build_labels(theme: Theme) -> void:
	_label_variation(theme, &"TitleLabel", 84, TEXT)
	_label_variation(theme, &"SubtitleLabel", 26, ACCENT)
	_label_variation(theme, &"HeaderLabel", 30, TEXT)
	_label_variation(theme, &"CardTitleLabel", 19, TEXT)
	_label_variation(theme, &"SectionLabel", 13, TEXT_MUTED)
	_label_variation(theme, &"MutedLabel", 15, TEXT_MUTED)
	_label_variation(theme, &"StatValueLabel", 32, TEXT)
	_label_variation(theme, &"AccentLabel", 16, ACCENT)
	_label_variation(theme, &"WarningLabel", 14, WARNING)
	_label_variation(theme, &"LogoLabel", 26, ACCENT)
	# The tear-off calendar page shown while days pass (career hub).
	_label_variation(theme, &"CalendarMonthLabel", 18, BG)
	_label_variation(theme, &"CalendarDayLabel", 88, BG)
	_label_variation(theme, &"CalendarYearLabel", 14, TEXT_DISABLED)
	_label_variation(theme, &"CalendarCellLabel", 12, TEXT)
	_label_variation(theme, &"CalendarClockLabel", 34, ACCENT_ALT)


static func _panel_variation(theme: Theme, name: StringName, style: StyleBoxFlat) -> void:
	theme.set_type_variation(name, &"PanelContainer")
	theme.set_stylebox(&"panel", name, style)


static func _build_panels(theme: Theme) -> void:
	_panel_variation(theme, &"BackgroundPanel", box(BG, Color.TRANSPARENT, 0, 0, 0, 0))
	_panel_variation(theme, &"CardPanel", box(PANEL_ALT, BORDER, 1, 6, 18, 16))
	var sidebar := box(PANEL, BORDER, 0, 0, 0, 16)
	sidebar.border_width_right = 1
	_panel_variation(theme, &"SidebarPanel", sidebar)
	var top_bar := box(PANEL, BORDER, 0, 0, 24, 14)
	top_bar.border_width_bottom = 1
	_panel_variation(theme, &"TopBarPanel", top_bar)
	_panel_variation(theme, &"DevBadgePanel", box(WARNING_BG, WARNING, 1, 4, 10, 4))
	_panel_variation(theme, &"OverlayPanel", box(Color(PANEL, 0.96), BORDER, 1, 8, 32, 28))
	_panel_variation(theme, &"HudPanel", box(Color(BG, 0.72), Color.TRANSPARENT, 0, 4, 12, 8))
	_panel_variation(theme, &"TableHeaderPanel", box(PANEL, Color.TRANSPARENT, 0, 0, 10, 6))
	_panel_variation(theme, &"TableRowPanel", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 10, 6))
	_panel_variation(theme, &"DimPanel", box(Color(BG, 0.78), Color.TRANSPARENT, 0, 0, 0, 0))
	var page := box(TEXT, BORDER, 1, 6, 0, 0)
	page.content_margin_bottom = 12
	_panel_variation(theme, &"CalendarPagePanel", page)
	var strip := box(ACCENT, Color.TRANSPARENT, 0, 6, 12, 6)
	strip.corner_radius_bottom_left = 0
	strip.corner_radius_bottom_right = 0
	_panel_variation(theme, &"CalendarStripPanel", strip)
	_panel_variation(theme, &"CalendarCell", box(PANEL, BORDER, 1, 3, 2, 2))
	_panel_variation(theme, &"CalendarPassedCell", box(ACCENT_DIM, ACCENT_DIM.lightened(0.2), 1, 3, 2, 2))
	_panel_variation(theme, &"CalendarTodayCell", box(ACCENT, ACCENT, 1, 3, 2, 2))


static func _build_misc(theme: Theme) -> void:
	theme.set_stylebox(&"background", &"ProgressBar", box(PANEL, BORDER, 1, 3, 0, 0))
	theme.set_stylebox(&"fill", &"ProgressBar", box(ACCENT, Color.TRANSPARENT, 0, 3, 0, 0))
	theme.set_color(&"font_color", &"ProgressBar", TEXT)

	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	theme.set_stylebox(&"separator", &"HSeparator", sep)
	theme.set_constant(&"separation", &"HSeparator", 12)

	theme.set_stylebox(&"panel", &"PopupMenu", box(PANEL_ALT, BORDER, 1, 4, 6, 6))
	theme.set_stylebox(&"hover", &"PopupMenu", box(PANEL_HOVER, Color.TRANSPARENT, 0, 2, 6, 4))
	theme.set_color(&"font_color", &"PopupMenu", TEXT)
	theme.set_color(&"font_hover_color", &"PopupMenu", TEXT)

	var scroll_grabber := box(BORDER, Color.TRANSPARENT, 0, 4, 4, 4)
	theme.set_stylebox(&"grabber", &"VScrollBar", scroll_grabber)
	theme.set_stylebox(&"grabber_highlight", &"VScrollBar", box(TEXT_MUTED, Color.TRANSPARENT, 0, 4, 4, 4))
	theme.set_stylebox(&"grabber_pressed", &"VScrollBar", box(ACCENT, Color.TRANSPARENT, 0, 4, 4, 4))
	theme.set_stylebox(&"scroll", &"VScrollBar", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 4, 4))
