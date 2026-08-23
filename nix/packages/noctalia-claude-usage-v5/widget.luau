local PANEL_ID = "giodamelio/claude_usage:detail"
local GAUGE_LENGTH = 22
local GAUGE_THICKNESS = 4

local function utilizationColor(util)
	if util >= 80 then
		return "error"
	elseif util >= 60 then
		return "tertiary"
	end
	return "primary"
end

local function gauge(entry)
	local util = entry and entry.util or 0
	return ui.progress({
		progress = math.clamp(util / 100, 0, 1),
		fill = utilizationColor(util),
		track = "on_surface/0.2",
		width = GAUGE_LENGTH,
		height = GAUGE_THICKNESS,
		radius = GAUGE_THICKNESS / 2,
	})
end

local function render()
	local usage = noctalia.state.get("usage")
	local glyphColor = "primary"
	local tooltip = "Claude usage: waiting for first fetch"

	if usage and not usage.ok then
		glyphColor = "error"
		tooltip = "Claude usage: " .. tostring(usage.error)
	elseif usage and usage.ok then
		local five = math.floor((usage.fiveHour and usage.fiveHour.util or 0) + 0.5)
		local seven = math.floor((usage.sevenDay and usage.sevenDay.util or 0) + 0.5)
		tooltip = string.format("Claude usage: %d%% of 5-hour, %d%% of 7-day", five, seven)
	end

	local gauges = ui.column({ gap = 2, justify = "center", align = "start" }, {
		gauge(usage and usage.fiveHour),
		gauge(usage and usage.sevenDay),
	})

	local container = barWidget.isVertical() and ui.column or ui.row
	barWidget.render(container({ gap = 4, align = "center" }, {
		ui.glyph({ name = "sparkles", size = 14, color = glyphColor }),
		gauges,
	}))
	barWidget.setTooltip(tooltip)
end

function onClick()
	noctalia.togglePanel(PANEL_ID)
end

function update()
	render()
end

noctalia.state.watch("usage", function()
	render()
end)

-- The first paint comes from update(); the service usually publishes before
-- then and the watch above redraws immediately.
noctalia.setUpdateInterval(5000)
