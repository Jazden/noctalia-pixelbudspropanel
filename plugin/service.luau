--!nonstrict
-- Service for Google Pixel Buds Pro
-- Controls and polls earbuds via scripts/pixelbuds_ctl.py

local SNAPSHOT_KEY = "pixelbuds_snapshot"
local COMMAND_KEY = "pixelbuds_command"

local scriptPath = noctalia.pluginDir() .. "/scripts/pixelbuds_ctl.py"

local function sanitizeWord(val)
	if type(val) ~= "string" then
		return nil
	end
	if string.match(val, "^[%w%-]+$") then
		return val
	end
	return nil
end

local function sanitizeBool(val)
	if val == true or val == "true" or val == 1 or val == "1" then
		return "true"
	end
	return "false"
end

local function safeArg(val)
	local s = tostring(val)
	if string.match(s, "^[%w%.%-%+]+$") then
		return s
	end
	return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function getCliCmd(...)
	local parts = { "python3", '"' .. scriptPath .. '"' }
	for _, a in ipairs({ ... }) do
		table.insert(parts, safeArg(a))
	end
	return table.concat(parts, " ")
end

local function updateSnapshot(data)
	if type(data) == "table" then
		noctalia.state.set(SNAPSHOT_KEY, data)
	end
end

local function mutateSnapshot(modifier)
	local cur = noctalia.state.get(SNAPSHOT_KEY)
	if type(cur) == "table" then
		modifier(cur)
		noctalia.state.set(SNAPSHOT_KEY, cur)
	end
end

local function pollStatus(force)
	local cmd = force and getCliCmd("status", "--force") or getCliCmd("status")
	noctalia.runAsync(cmd, function(result)
		if result and result.stdout and result.stdout ~= "" then
			local ok, parsed = pcall(function()
				return noctalia.json.decode(result.stdout)
			end)
			if ok and parsed then
				updateSnapshot(parsed)
			end
		end
	end)
end

local function notifyMode(mode)
	local modeKey = "panel.mode." .. tostring(mode)
	local modeLabel = noctalia.tr(modeKey) or tostring(mode)
	local curState = noctalia.state.get(SNAPSHOT_KEY)
	local devName = (curState and (curState.device_name or curState.model_name)) or "Pixel Buds Pro"
	local fmt = noctalia.tr("notify.mode_changed") or "Noise Control: %s"
	pcall(function()
		noctalia.notify(devName, string.format(fmt, modeLabel), "headphones")
	end)
end

local function notifyGesture(action, side)
	local label = (action == "anc") and (noctalia.tr("panel.gesture_anc") or "Noise Cancellation") or (noctalia.tr("panel.gesture_assistant") or "Assistant")
	local curState = noctalia.state.get(SNAPSHOT_KEY)
	local devName = (curState and (curState.device_name or curState.model_name)) or "Pixel Buds Pro"
	local msg
	if side == "left" then
		msg = string.format("Left Ear: %s", label)
	elseif side == "right" then
		msg = string.format("Right Ear: %s", label)
	else
		local fmt = noctalia.tr("notify.gesture_changed") or "Hold Gesture: %s"
		msg = string.format(fmt, label)
	end
	pcall(function()
		noctalia.notify(devName, msg, "headphones")
	end)
end

local eqRunning = false
local pendingEqArgs = nil

local function dispatchEq(b1, b2, b3, b4, b5)
	local args = { b1, b2, b3, b4, b5 }
	if eqRunning then
		pendingEqArgs = args
		return
	end
	eqRunning = true
	local cmd = getCliCmd("set-eq", args[1], args[2], args[3], args[4], args[5])
	noctalia.runAsync(cmd, function(result)
		eqRunning = false
		if pendingEqArgs then
			local nextArgs = pendingEqArgs
			pendingEqArgs = nil
			dispatchEq(nextArgs[1], nextArgs[2], nextArgs[3], nextArgs[4], nextArgs[5])
		end
	end)
end

local function executeCommand(cmdObj)
	if type(cmdObj) ~= "table" or not cmdObj.action then
		return
	end

	if cmdObj.action == "set-noise" and cmdObj.value then
		local mode = sanitizeWord(tostring(cmdObj.value))
		if mode then
			mutateSnapshot(function(s) s.noise_mode = mode end)
			notifyMode(mode)
			local cmd = getCliCmd("set-anc", mode)
			noctalia.runAsync(cmd, function(result)
				if result and result.exitCode ~= 0 then
					pollStatus(true)
				end
			end)
		end
	elseif cmdObj.action == "cycle-noise" then
		local cur = noctalia.state.get(SNAPSHOT_KEY)
		local curMode = (cur and cur.noise_mode) or "off"
		local nextMode = (curMode == "active") and "aware" or ((curMode == "aware") and "off" or "active")
		mutateSnapshot(function(s) s.noise_mode = nextMode end)
		notifyMode(nextMode)
		local cmd = getCliCmd("set-anc", nextMode)
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif cmdObj.action == "set-eq" and type(cmdObj.value) == "table" then
		local bands = cmdObj.value
		local b1 = string.format("%.1f", math.max(-6.0, math.min(6.0, tonumber(bands[1]) or 0)))
		local b2 = string.format("%.1f", math.max(-6.0, math.min(6.0, tonumber(bands[2]) or 0)))
		local b3 = string.format("%.1f", math.max(-6.0, math.min(6.0, tonumber(bands[3]) or 0)))
		local b4 = string.format("%.1f", math.max(-6.0, math.min(6.0, tonumber(bands[4]) or 0)))
		local b5 = string.format("%.1f", math.max(-6.0, math.min(6.0, tonumber(bands[5]) or 0)))
		dispatchEq(b1, b2, b3, b4, b5)
	elseif cmdObj.action == "set-ohd" then
		local val = (cmdObj.value == true or cmdObj.value == "true" or cmdObj.value == 1 or cmdObj.value == "1")
		mutateSnapshot(function(s) s.ohd = val end)
		local cmd = getCliCmd("set-ohd", sanitizeBool(cmdObj.value))
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif cmdObj.action == "set-speech-detection" then
		local val = (cmdObj.value == true or cmdObj.value == "true" or cmdObj.value == 1 or cmdObj.value == "1")
		mutateSnapshot(function(s) s.speech_detection = val end)
		local cmd = getCliCmd("set-speech-detection", sanitizeBool(cmdObj.value))
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif cmdObj.action == "set-gesture-side" and type(cmdObj.value) == "table" then
		local side = cmdObj.value.side or "left"
		local target = (cmdObj.value.action == "anc" or cmdObj.value.action == true or cmdObj.value.action == "true") and "anc" or "assistant"
		mutateSnapshot(function(s)
			if side == "left" then
				s.gesture_left = target
			elseif side == "right" then
				s.gesture_right = target
			end
			s.gesture_control = s.gesture_left or target
			s.hold_anc = (s.gesture_control == "anc")
		end)
		notifyGesture(target, side)
		local cmd = getCliCmd("set-gesture", side, target)
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif cmdObj.action == "set-gesture-control" then
		local target = (cmdObj.value == "anc" or cmdObj.value == true or cmdObj.value == "true") and "anc" or "assistant"
		mutateSnapshot(function(s)
			s.gesture_left = target
			s.gesture_right = target
			s.gesture_control = target
			s.hold_anc = (target == "anc")
		end)
		notifyGesture(target, "both")
		local cmd = getCliCmd("set-gesture", target)
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif cmdObj.action == "toggle-gesture-control" then
		local cur = noctalia.state.get(SNAPSHOT_KEY)
		local curAction = (cur and cur.gesture_control) or "assistant"
		local nextAction = (curAction == "anc") and "assistant" or "anc"
		mutateSnapshot(function(s)
			s.gesture_control = nextAction
			s.hold_anc = (nextAction == "anc")
		end)
		notifyGesture(nextAction)
		local cmd = getCliCmd("set-gesture", nextAction)
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif cmdObj.action == "refresh" then
		pollStatus(true)
	end
end

function onIpc(event, payload)
	if event == "cycle-noise" then
		local cur = noctalia.state.get(SNAPSHOT_KEY)
		local curMode = (cur and cur.noise_mode) or "off"
		local nextMode = (curMode == "active") and "aware" or ((curMode == "aware") and "off" or "active")
		mutateSnapshot(function(s) s.noise_mode = nextMode end)
		notifyMode(nextMode)
		local cmd = getCliCmd("set-anc", nextMode)
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif event == "set-noise" and payload then
		local mode = sanitizeWord(tostring(payload))
		if mode then
			mutateSnapshot(function(s) s.noise_mode = mode end)
			notifyMode(mode)
			local cmd = getCliCmd("set-anc", mode)
			noctalia.runAsync(cmd, function(result)
				if result and result.exitCode ~= 0 then
					pollStatus(true)
				end
			end)
		end
	elseif event == "toggle-gesture" then
		local cur = noctalia.state.get(SNAPSHOT_KEY)
		local curAction = (cur and cur.gesture_control) or "assistant"
		local nextAction = (curAction == "anc") and "assistant" or "anc"
		mutateSnapshot(function(s)
			s.gesture_control = nextAction
			s.hold_anc = (nextAction == "anc")
		end)
		notifyGesture(nextAction)
		local cmd = getCliCmd("set-gesture", nextAction)
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif event == "set-gesture" and payload then
		local target = (payload == "anc" or payload == true or payload == "true") and "anc" or "assistant"
		mutateSnapshot(function(s)
			s.gesture_control = target
			s.hold_anc = (target == "anc")
		end)
		notifyGesture(target)
		local cmd = getCliCmd("set-gesture", target)
		noctalia.runAsync(cmd, function(result)
			if result and result.exitCode ~= 0 then
				pollStatus(true)
			end
		end)
	elseif event == "refresh" then
		pollStatus(true)
	end
end

noctalia.state.watch(COMMAND_KEY, executeCommand)

-- Initial poll, then interval polling every 5 seconds
pollStatus(false)
noctalia.setUpdateInterval(5000)

function update()
	pollStatus(false)
end
