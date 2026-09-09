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

local function getCliCmd(args)
	return 'python3 "' .. scriptPath .. '" ' .. args
end

local function updateSnapshot(data)
	if type(data) == "table" then
		noctalia.state.set(SNAPSHOT_KEY, data)
	end
end

local function pollStatus(force)
	local flag = force and " --force" or ""
	local cmd = getCliCmd("status" .. flag)
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
	local modeKey = "panel.mode." .. mode
	local modeLabel = noctalia.tr(modeKey)
	local curState = noctalia.state.get(SNAPSHOT_KEY)
	local devName = (curState and (curState.model_name or curState.device_name)) or "Pixel Buds Pro"
	noctalia.notify(devName, string.format(noctalia.tr("notify.mode_changed"), modeLabel), "headphones")
end

local function notifyGesture(action)
	local label = (action == "anc") and (noctalia.tr("panel.gesture_anc") or "Noise Cancellation") or (noctalia.tr("panel.gesture_assistant") or "Assistant")
	local curState = noctalia.state.get(SNAPSHOT_KEY)
	local devName = (curState and (curState.model_name or curState.device_name)) or "Pixel Buds Pro"
	noctalia.notify(devName, string.format(noctalia.tr("notify.gesture_changed") or "Hold Gesture: %s", label), "headphones")
end

local function executeCommand(cmdObj)
	if type(cmdObj) ~= "table" or not cmdObj.action then
		return
	end

	if cmdObj.action == "set-noise" and cmdObj.value then
		local mode = sanitizeWord(tostring(cmdObj.value))
		if mode then
			local cmd = getCliCmd("set-anc " .. mode)
			noctalia.runAsync(cmd, function(result)
				if result and result.stdout then
					local ok, parsed = pcall(function() return noctalia.json.decode(result.stdout) end)
					if ok and parsed and parsed.mode then
						notifyMode(parsed.mode)
					end
				end
				pollStatus(true)
			end)
		end
	elseif cmdObj.action == "cycle-noise" then
		local cmd = getCliCmd("cycle-anc")
		noctalia.runAsync(cmd, function(result)
			if result and result.stdout then
				local ok, parsed = pcall(function() return noctalia.json.decode(result.stdout) end)
				if ok and parsed and parsed.mode then
					notifyMode(parsed.mode)
				end
			end
			pollStatus(true)
		end)
	elseif cmdObj.action == "set-eq" and type(cmdObj.value) == "table" then
		local bands = cmdObj.value
		local args = string.format("%.1f %.1f %.1f %.1f %.1f", tonumber(bands[1]) or 0, tonumber(bands[2]) or 0, tonumber(bands[3]) or 0, tonumber(bands[4]) or 0, tonumber(bands[5]) or 0)
		local cmd = getCliCmd("set-eq " .. args)
		noctalia.runAsync(cmd, function(result)
			pollStatus(true)
		end)
	elseif cmdObj.action == "set-ohd" then
		local cmd = getCliCmd("set-ohd " .. sanitizeBool(cmdObj.value))
		noctalia.runAsync(cmd, function(result)
			pollStatus(true)
		end)
	elseif cmdObj.action == "set-speech-detection" then
		local cmd = getCliCmd("set-speech-detection " .. sanitizeBool(cmdObj.value))
		noctalia.runAsync(cmd, function(result)
			pollStatus(true)
		end)
	elseif cmdObj.action == "set-gesture-control" then
		local target = (cmdObj.value == "anc" or cmdObj.value == true or cmdObj.value == "true") and "anc" or "assistant"
		local cmd = getCliCmd("set-gesture " .. target)
		noctalia.runAsync(cmd, function(result)
			if result and result.stdout then
				local ok, parsed = pcall(function() return noctalia.json.decode(result.stdout) end)
				if ok and parsed and parsed.gesture_control then
					notifyGesture(parsed.gesture_control)
				end
			end
			pollStatus(true)
		end)
	elseif cmdObj.action == "toggle-gesture-control" then
		local cmd = getCliCmd("toggle-gesture")
		noctalia.runAsync(cmd, function(result)
			if result and result.stdout then
				local ok, parsed = pcall(function() return noctalia.json.decode(result.stdout) end)
				if ok and parsed and parsed.gesture_control then
					notifyGesture(parsed.gesture_control)
				end
			end
			pollStatus(true)
		end)
	elseif cmdObj.action == "refresh" then
		pollStatus(true)
	end
end

function onIpc(event, payload)
	if event == "cycle-noise" then
		local cmd = getCliCmd("cycle-anc")
		noctalia.runAsync(cmd, function(result)
			if result and result.stdout then
				local ok, parsed = pcall(function() return noctalia.json.decode(result.stdout) end)
				if ok and parsed and parsed.mode then
					notifyMode(parsed.mode)
				end
			end
			pollStatus(true)
		end)
	elseif event == "set-noise" and payload then
		local mode = sanitizeWord(tostring(payload))
		if mode then
			local cmd = getCliCmd("set-anc " .. mode)
			noctalia.runAsync(cmd, function(result)
				if result and result.stdout then
					local ok, parsed = pcall(function() return noctalia.json.decode(result.stdout) end)
					if ok and parsed and parsed.mode then
						notifyMode(parsed.mode)
					end
				end
				pollStatus(true)
			end)
		end
	elseif event == "toggle-gesture" then
		local cmd = getCliCmd("toggle-gesture")
		noctalia.runAsync(cmd, function(result)
			if result and result.stdout then
				local ok, parsed = pcall(function() return noctalia.json.decode(result.stdout) end)
				if ok and parsed and parsed.gesture_control then
					notifyGesture(parsed.gesture_control)
				end
			end
			pollStatus(true)
		end)
	elseif event == "set-gesture" and payload then
		local target = (payload == "anc" or payload == true or payload == "true") and "anc" or "assistant"
		local cmd = getCliCmd("set-gesture " .. target)
		noctalia.runAsync(cmd, function(result)
			if result and result.stdout then
				local ok, parsed = pcall(function() return noctalia.json.decode(result.stdout) end)
				if ok and parsed and parsed.gesture_control then
					notifyGesture(parsed.gesture_control)
				end
			end
			pollStatus(true)
		end)
	elseif event == "refresh" then
		pollStatus(true)
	end
end

noctalia.state.watch(COMMAND_KEY, executeCommand)

-- Initial fast poll, then interval polling every 4 seconds
pollStatus(false)
noctalia.setUpdateInterval(7000)

function update()
	pollStatus(false)
end
