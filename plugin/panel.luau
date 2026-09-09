--!nonstrict
-- Panel for Google Pixel Buds Pro
-- Symmetrical battery indicators, ANC/Transparency modes, 5-band EQ, and feature toggles.

local SNAPSHOT_KEY = "pixelbuds_snapshot"
local COMMAND_KEY = "pixelbuds_command"

local snapshot = noctalia.state.get(SNAPSHOT_KEY) or {}
local eqExpanded = false

local commandSeq = 0
local function sendCommand(action, value)
	commandSeq += 1
	noctalia.state.set(COMMAND_KEY, {
		action = action,
		value = value,
		nonce = tostring(noctalia.nowMs()) .. "-" .. tostring(commandSeq),
	})
end

local function levelFraction(level)
	local n = tonumber(level)
	if n == nil or n < 0 then
		return 0
	end
	return math.max(0, math.min(100, n)) / 100
end

local function isLow(level, charging)
	return level ~= nil and level >= 0 and level <= 20 and not charging
end

local function batteryColumn(iconName, label, level, charging, isClosed)
	local hasLevel = level ~= nil and level >= 0
	local text = hasLevel and (tostring(level) .. "%") or "--%"
	local meta = ""
	local metaColor = "on_surface_variant"
	if charging then
		meta = noctalia.tr("panel.charging")
		metaColor = "secondary"
	elseif isClosed then
		meta = noctalia.tr("panel.case_offline")
		metaColor = "on_surface_variant"
	end

	local low = isLow(level, charging)
	local fillRole = "primary"
	if low then
		fillRole = "error"
	elseif charging then
		fillRole = "secondary"
	elseif not hasLevel then
		fillRole = "outline"
	end

	local iconSuffix = noctalia.isDarkMode() and ".svg" or "-light.svg"
	local iconPath = "icons/" .. iconName .. iconSuffix

	return ui.column({
		align = "center",
		justify = "center",
		gap = 4,
		flexGrow = 1,
	}, {
		ui.row({ align = "center", gap = 4 }, {
			ui.image({
				path = iconPath,
				width = 16,
				height = 16,
				fit = "contain",
				opacity = hasLevel and 0.85 or 0.4,
			}),
			ui.label({
				text = label,
				fontSize = 12,
				fontWeight = "medium",
				color = "on_surface_variant",
			}),
		}),
		ui.label({
			text = text,
			fontSize = 15,
			fontWeight = "bold",
			color = low and "error" or (hasLevel and "on_surface" or "on_surface_variant"),
			textAlign = "center",
		}),
		ui.progress({
			progress = levelFraction(level),
			height = 4,
			radius = 2,
			fill = fillRole,
			width = 80,
		}),
		ui.label({
			text = (meta ~= "") and meta or " ",
			fontSize = 11,
			color = metaColor,
			textAlign = "center",
		}),
	})
end

local function headerIconPath()
	return "icons/" .. (noctalia.isDarkMode() and "pixel-buds.svg" or "pixel-buds-light.svg")
end

local eqBandNames = {
	"Low Bass",
	"Bass",
	"Mid",
	"Treble",
	"Upper Treble"
}

local function render()
	local connected = snapshot.connected == true
	local body = {}

	if connected then
		-- 1. 3-Column Battery Section (Left, Case, Right)
		table.insert(body, ui.row({
			align = "center",
			justify = "space_between",
			padding = 4,
		}, {
			batteryColumn("earbud-left", noctalia.tr("panel.left"), snapshot.battery_left, snapshot.charging_left, snapshot.placement_left == "in case"),
			batteryColumn("case", noctalia.tr("panel.case"), snapshot.battery_case, snapshot.charging_case, false),
			batteryColumn("earbud-right", noctalia.tr("panel.right"), snapshot.battery_right, snapshot.charging_right, snapshot.placement_right == "in case"),
		}))


		table.insert(body, ui.separator({ thickness = 1, color = "outline/0.2" }))

		-- 2. Noise Control Section
		local currentMode = snapshot.noise_mode or "off"
		table.insert(body, ui.column({ gap = 6 }, {
			ui.label({
				text = noctalia.tr("panel.noise_control"),
				fontSize = 11,
				fontWeight = "bold",
				color = "on_surface_variant",
			}),
			ui.row({ align = "center", gap = 4 }, {
				ui.button({
					key = "mode-anc",
					flexGrow = 1,
					text = "Noise Cancelling",
					glyph = "shield-check",
					variant = (currentMode == "active" or currentMode == "anc") and "primary" or "ghost",
					selected = (currentMode == "active" or currentMode == "anc"),
					onClick = function()
						sendCommand("set-noise", "active")
					end,
				}),
				ui.button({
					key = "mode-transparency",
					flexGrow = 1,
					text = "Transparency",
					glyph = "ear",
					variant = (currentMode == "aware" or currentMode == "transparency") and "secondary" or "ghost",
					selected = (currentMode == "aware" or currentMode == "transparency"),
					onClick = function()
						sendCommand("set-noise", "aware")
					end,
				}),
				ui.button({
					key = "mode-off",
					flexGrow = 1,
					text = "Off",
					glyph = "volume-off",
					variant = (currentMode == "off") and "outline" or "ghost",
					selected = (currentMode == "off"),
					onClick = function()
						sendCommand("set-noise", "off")
					end,
				}),
			}),
		}))

		table.insert(body, ui.separator({ thickness = 1, color = "outline/0.2" }))

		-- 3. 5-Band Equalizer Section (Collapsible)
		local eqHeader = ui.row({
			align = "center",
			justify = "space_between",
			onClick = function()
				eqExpanded = not eqExpanded
				render()
			end,
		}, {
			ui.row({ align = "center", gap = 6 }, {
				ui.glyph({ name = "adjustments-horizontal", size = 14, color = "on_surface_variant" }),
				ui.label({
					text = noctalia.tr("panel.equalizer"),
					fontSize = 11,
					fontWeight = "bold",
					color = "on_surface_variant",
				}),
			}),
			ui.button({
				glyph = eqExpanded and "chevron-up" or "chevron-down",
				variant = "ghost",
				controlSize = "sm",
				onClick = function()
					eqExpanded = not eqExpanded
					render()
				end,
			}),
		})

		if eqExpanded then
			local curEq = snapshot.eq or { 0.0, 0.0, 0.0, 0.0, 0.0 }
			local eqSliders = {}
			for i = 1, 5 do
				local bandVal = curEq[i] or 0.0
				local bandName = eqBandNames[i] or ("Band " .. tostring(i))
				local sign = (bandVal > 0) and "+" or ""
				local displayVal = string.format("%s%.1f dB", sign, bandVal)
				table.insert(eqSliders, ui.row({ align = "center", gap = 8 }, {
					ui.row({ minWidth = 90, width = 90, align = "center" }, {
						ui.label({
							text = bandName,
							fontSize = 12,
							color = "on_surface",
						}),
					}),
					ui.slider({
						key = "eq-band-" .. tostring(i),
						flexGrow = 1,
						min = -6.0,
						max = 6.0,
						step = 0.5,
						value = bandVal,
						onChange = function(newVal)
							local num = tonumber(newVal)
							if num then
								local newEq = {
									curEq[1] or 0.0,
									curEq[2] or 0.0,
									curEq[3] or 0.0,
									curEq[4] or 0.0,
									curEq[5] or 0.0,
								}
								newEq[i] = num
								snapshot.eq = newEq
								sendCommand("set-eq", newEq)
								render()
							end
						end,
					}),
					ui.row({ minWidth = 52, width = 52, justify = "end", align = "center" }, {
						ui.label({
							text = displayVal,
							fontSize = 11,
							color = "on_surface_variant",
							textAlign = "end",
						}),
					}),
				}))
			end

			table.insert(body, ui.column({ gap = 6 }, {
				eqHeader,
				ui.column({ gap = 3 }, eqSliders),
			}))
		else
			table.insert(body, ui.column({ gap = 0 }, {
				eqHeader,
			}))
		end

		table.insert(body, ui.separator({ thickness = 1, color = "outline/0.2" }))

		-- 4. Features Section (In-Ear Detection & Conversation Awareness)
		table.insert(body, ui.column({ gap = 6 }, {
			ui.label({
				text = noctalia.tr("panel.features"),
				fontSize = 11,
				fontWeight = "bold",
				color = "on_surface_variant",
			}),
			ui.row({ align = "center", justify = "space_between", gap = 8 }, {
				ui.column({ flexGrow = 1, gap = 1 }, {
					ui.label({ text = noctalia.tr("panel.ohd"), fontSize = 13, color = "on_surface" }),
					ui.label({ text = noctalia.tr("panel.ohd_desc"), fontSize = 11, color = "on_surface_variant" }),
				}),
				ui.toggle({
					checked = snapshot.ohd == true,
					onChange = function(v)
						local enabled = (v == true or v == "true")
						snapshot.ohd = enabled
						sendCommand("set-ohd", enabled)
						render()
					end,
				}),
			}),
			ui.row({ align = "center", justify = "space_between", gap = 8 }, {
				ui.column({ flexGrow = 1, gap = 1 }, {
					ui.label({ text = noctalia.tr("panel.speech_detection"), fontSize = 13, color = "on_surface" }),
					ui.label({ text = noctalia.tr("panel.speech_detection_desc"), fontSize = 11, color = "on_surface_variant" }),
				}),
				ui.toggle({
					checked = snapshot.speech_detection == true,
					onChange = function(v)
						local enabled = (v == true or v == "true")
						snapshot.speech_detection = enabled
						sendCommand("set-speech-detection", enabled)
						render()
					end,
				}),
			}),
			ui.row({ align = "center", justify = "space_between", gap = 8 }, {
				ui.column({ flexGrow = 1, gap = 1 }, {
					ui.label({ text = noctalia.tr("panel.gesture_control"), fontSize = 13, color = "on_surface" }),
					ui.label({ text = noctalia.tr("panel.gesture_control_desc"), fontSize = 11, color = "on_surface_variant" }),
				}),
				ui.toggle({
					checked = snapshot.hold_anc == true or snapshot.gesture_control == "anc",
					onChange = function(v)
						local enabled = (v == true or v == "true")
						snapshot.hold_anc = enabled
						snapshot.gesture_control = enabled and "anc" or "assistant"
						sendCommand("set-gesture-control", enabled and "anc" or "assistant")
						render()
					end,
				}),
			}),
		}))
	else
		-- Not connected state
		table.insert(body, ui.column({ align = "center", gap = 12, padding = 24 }, {
			ui.image({
				path = headerIconPath(),
				width = 96,
				height = 96,
				fit = "contain",
				opacity = 0.35,
			}),
			ui.label({
				text = noctalia.tr("widget.not_connected"),
				fontSize = 15,
				fontWeight = "bold",
				color = "on_surface",
				textAlign = "center",
			}),
			ui.label({
				text = noctalia.tr("panel.guidance"),
				fontSize = 12,
				color = "on_surface_variant",
				textAlign = "center",
			}),
		}))
	end

	local titleText = snapshot.device_name or snapshot.model_name or noctalia.tr("panel.title")
	local statusText = connected and noctalia.tr("panel.status.connected") or noctalia.tr("panel.status.disconnected")
	if connected and snapshot.mac then
		statusText = statusText .. " • " .. snapshot.mac
	end




panel.render(ui.column({ flexGrow = 1, gap = 8, padding = 12 }, {
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.image({
				path = headerIconPath(),
				width = 28,
				height = 28,
				fit = "contain",
				opacity = connected and 1 or 0.45,
			}),
			ui.column({ flexGrow = 1, gap = 2 }, {
				ui.label({
					text = titleText,
					fontSize = 15,
					fontWeight = "bold",
					color = "on_surface",
					maxLines = 1,
				}),
				ui.label({
					text = statusText,
					fontSize = 11,
					color = connected and "secondary" or "on_surface_variant",
					maxLines = 1,
				}),
			}),
			ui.button({
				glyph = "close",
				variant = "ghost",
				onClick = "onCloseClicked",
			}),
		}),
		ui.column({ flexGrow = 1, gap = 8 }, body),
	}))
end

noctalia.state.watch(SNAPSHOT_KEY, function(value)
	if type(value) == "table" then
		snapshot = value
		render()
	end
end)

function onOpen(_context)
	sendCommand("refresh", nil)
	render()
end

function onCloseClicked()
	panel.close()
end
