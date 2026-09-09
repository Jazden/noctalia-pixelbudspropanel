--!nonstrict
-- Bar widget for Pixel Buds Pro

local SNAPSHOT_KEY = "pixelbuds_snapshot"

local snapshot = noctalia.state.get(SNAPSHOT_KEY) or {}
local hideWhenDisconnected = noctalia.getConfig("hide_when_disconnected") ~= false

local function getModeName(mode)
	if mode == "active" or mode == "anc" then
		return noctalia.tr("panel.mode.active")
	elseif mode == "aware" or mode == "transparency" then
		return noctalia.tr("panel.mode.aware")
	elseif mode == "off" then
		return noctalia.tr("panel.mode.off")
	end
	return mode or ""
end

local function render()
	local connected = snapshot.connected == true
	local nearby = snapshot.nearby == true

	if hideWhenDisconnected then
		barWidget.setVisible(connected or nearby)
	else
		barWidget.setVisible(true)
	end

	local container = barWidget.isVertical() and ui.column or ui.row

	if not connected then
		if nearby then
			barWidget.render(container({ gap = 4, align = "center" }, {
				ui.glyph({ name = "headphones", color = "secondary" }),
				ui.glyph({ name = "broadcast", color = "secondary", size = 13 }),
			}))
			local rssiStr = snapshot.rssi and string.format("%d dBm", snapshot.rssi) or "Detected"
			barWidget.setTooltip({
				{ key = snapshot.device_name or snapshot.model_name or noctalia.tr("panel.title"), value = noctalia.tr("panel.nearby_detected") or "Nearby (Fast Pair detected)" },
				{ key = "Status", value = noctalia.tr("widget.available_to_connect") or "Available to connect" },
				{ key = "Signal", value = rssiStr },
				{ key = noctalia.tr("widget.action.left_click"), value = noctalia.tr("panel.title") }
			})
		else
			barWidget.render(container({ gap = 4, align = "center" }, {
				ui.glyph({ name = "headphones-off", color = "on_surface_variant" }),
			}))
			barWidget.setTooltip({
				{ key = noctalia.tr("panel.title"), value = noctalia.tr("widget.not_connected") },
				{ key = noctalia.tr("widget.action.left_click"), value = noctalia.tr("panel.title") }
			})
		end
		return
	end

	local mode = snapshot.noise_mode or "off"
	local glyphName = "headphones"
	local glyphColor = "on_surface"

	if mode == "active" or mode == "anc" then
		glyphName = "shield-check"
		glyphColor = "primary"
	elseif mode == "aware" or mode == "transparency" then
		glyphName = "ear"
		glyphColor = "secondary"
	end

	-- Pick battery level to show on bar (minimum of active buds, or whichever is available)
	local bLevel = -1
	local l = snapshot.battery_left or -1
	local r = snapshot.battery_right or -1

	if l >= 0 and r >= 0 then
		bLevel = math.min(l, r)
	elseif l >= 0 then
		bLevel = l
	elseif r >= 0 then
		bLevel = r
	end

	local children = {
		ui.glyph({ name = glyphName, color = glyphColor }),
	}

	if bLevel >= 0 and not barWidget.isVertical() then
		table.insert(children, ui.label({ text = tostring(bLevel) .. "%" }))
	end

	barWidget.render(container({ gap = 4, align = "center" }, children))

	-- Build detailed tooltip rows
	local tooltipRows = {
		{ key = "Device", value = snapshot.device_name or snapshot.model_name or noctalia.tr("panel.title") },
		{ key = noctalia.tr("widget.mode"), value = getModeName(mode) },
	}

	if l >= 0 then
		local chargingStr = snapshot.charging_left and (" (" .. noctalia.tr("panel.charging") .. ")") or ""
		table.insert(tooltipRows, { key = noctalia.tr("panel.left"), value = tostring(l) .. "%" .. chargingStr })
	end

	if r >= 0 then
		local chargingStr = snapshot.charging_right and (" (" .. noctalia.tr("panel.charging") .. ")") or ""
		table.insert(tooltipRows, { key = noctalia.tr("panel.right"), value = tostring(r) .. "%" .. chargingStr })
	end

	if snapshot.battery_case and snapshot.battery_case >= 0 then
		local metaStr = ""
		if snapshot.charging_case then
			metaStr = " (" .. noctalia.tr("panel.charging") .. ")"
		end
		table.insert(tooltipRows, { key = noctalia.tr("panel.case"), value = tostring(snapshot.battery_case) .. "%" .. metaStr })
	end

	table.insert(tooltipRows, { key = "Left Click", value = noctalia.tr("widget.action.left_click") })
	table.insert(tooltipRows, { key = "Right Click", value = noctalia.tr("widget.action.right_click") })

	barWidget.setTooltip(tooltipRows)
end

noctalia.state.watch(SNAPSHOT_KEY, function(value)
	if type(value) == "table" then
		snapshot = value
		render()
	end
end)

function onConfigChanged()
	hideWhenDisconnected = noctalia.getConfig("hide_when_disconnected") ~= false
	render()
end

render()
