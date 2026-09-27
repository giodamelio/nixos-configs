local function nowEpoch()
	return tonumber(noctalia.formatTime("%s")) or 0
end

local function utilizationColor(util)
	if util >= 80 then
		return "error"
	elseif util >= 60 then
		return "tertiary"
	end
	return "primary"
end

local function plural(value, unit)
	return value .. (value == 1 and (" " .. unit) or (" " .. unit .. "s"))
end

local function formatLongDuration(totalSeconds)
	totalSeconds = math.floor(totalSeconds)
	local days = math.floor(totalSeconds / 86400)
	local hours = math.floor((totalSeconds % 86400) / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)

	local parts = {}
	if days > 0 then
		table.insert(parts, plural(days, "day"))
	end
	if hours > 0 then
		table.insert(parts, plural(hours, "hour"))
	end
	if minutes > 0 then
		table.insert(parts, plural(minutes, "minute"))
	end
	if #parts == 0 then
		return "less than a minute"
	end
	return table.concat(parts, " ")
end

local function formatTimeUntil(epoch)
	local clock = noctalia.formatTime("%-I:%M%P", epoch)
	local seconds = epoch - nowEpoch()
	if seconds <= 0 then
		return clock .. " (now)"
	end
	return clock .. " (in " .. formatLongDuration(seconds) .. ")"
end

local function usageRow(label, entry)
	if not entry then
		return nil
	end
	return ui.row({ gap = 10, align = "center" }, {
		ui.label({ text = label, fontSize = 12, color = "on_surface_variant", width = 56 }),
		ui.progress({
			progress = math.clamp(entry.util / 100, 0, 1),
			fill = utilizationColor(entry.util),
			track = "on_surface/0.2",
			width = 120,
			height = 8,
			radius = 4,
		}),
		ui.label({
			text = string.format("%d%%", math.floor(entry.util + 0.5)),
			fontSize = 12,
			color = "on_surface_variant",
			width = 40,
		}),
		ui.label({
			text = entry.resetsAt and formatTimeUntil(entry.resetsAt) or "",
			fontSize = 11,
			color = "outline",
		}),
	})
end

local isOpen = false

local function render()
	if not isOpen then
		return
	end
	local usage = noctalia.state.get("usage")
	local children = {}

	if not usage then
		table.insert(children, ui.label({ text = "Waiting for first fetch…", fontSize = 12, color = "outline" }))
	else
		local rows = {
			usageRow("5-hour", usage.fiveHour),
			usageRow("7-day", usage.sevenDay),
		}
		for _, entry in ipairs(usage.modelScoped or {}) do
			table.insert(rows, usageRow(entry.name, entry))
		end
		for _, row in ipairs(rows) do
			table.insert(children, row)
		end

		local footer = {}
		if usage.error then
			table.insert(footer, ui.label({ text = usage.error, fontSize = 11, color = "error" }))
		end
		table.insert(footer, ui.spacer({ flexGrow = 1 }))
		if usage.fetchedAt then
			local age = nowEpoch() - usage.fetchedAt
			local text = age < 60 and "Fetched just now" or ("Fetched " .. formatLongDuration(age) .. " ago")
			if usage.source then
				text = text .. " via " .. (usage.source == "api" and "API" or "statusline")
			end
			table.insert(footer, ui.label({ text = text, fontSize = 11, color = "outline" }))
		end
		table.insert(children, ui.separator({ spacing = 4 }))
		table.insert(children, ui.row({ gap = 8, align = "center" }, footer))
	end

	panel.render(ui.column({ gap = 6, padding = 12 }, children))
end

function onOpen()
	isOpen = true
	panel.setWantsSecondTicks(true)
	render()
end

function onClose()
	isOpen = false
	panel.setWantsSecondTicks(false)
end

function update()
	render()
end

noctalia.state.watch("usage", function()
	render()
end)
