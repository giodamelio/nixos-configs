local API_URL = "https://api.anthropic.com/api/oauth/usage"
local USER_AGENT = "noctalia-claude-usage/1.0.0"
local STATE_KEY = "usage"
local NATS = "@nats@"
local BUCKET = "claude-usage"
local KEY = "current"
-- The API 429s easily, so it is only hit when KV has nothing fresh, and backs
-- off further on each failure.
local FALLBACK_COOLDOWN_MIN = 300
local FALLBACK_COOLDOWN_MAX = 1800

local function nowEpoch()
	return tonumber(noctalia.formatTime("%s")) or 0
end

-- Howard Hinnant's days_from_civil. Luau ships no date parser, and os.time()
-- would read the fields as local time, which would shift the API's UTC values.
local function daysFromCivil(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

local function parseIso8601(text)
	if type(text) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s = text:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	local epoch = daysFromCivil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
		+ tonumber(h) * 3600
		+ tonumber(mi) * 60
		+ tonumber(s)
	local sign, oh, om = text:match("([%+%-])(%d%d):?(%d%d)$")
	if sign then
		local offset = tonumber(oh) * 3600 + tonumber(om) * 60
		epoch = epoch + (sign == "-" and offset or -offset)
	end
	return epoch
end

local lastGood = nil
local fallbackCooldown = FALLBACK_COOLDOWN_MIN
local nextFallbackAt = 0
local inFlight = false

local function publish(snapshot)
	noctalia.state.set(STATE_KEY, snapshot)
end

local function isWindow(node)
	return type(node) == "table" and type(node.util) == "number"
end

-- Statusline writes carry no model-scoped limits, so keep the last known ones
-- until their window resets.
local function carryModelScoped(usage)
	if usage.modelScoped or not lastGood or not lastGood.modelScoped then
		return
	end
	local now = nowEpoch()
	local kept = {}
	for _, entry in ipairs(lastGood.modelScoped) do
		if entry.resetsAt and entry.resetsAt > now then
			table.insert(kept, entry)
		end
	end
	usage.modelScoped = #kept > 0 and kept or nil
end

local function accept(usage)
	carryModelScoped(usage)
	lastGood = {
		ok = true,
		source = usage.source,
		fetchedAt = usage.writtenAt,
		fiveHour = usage.fiveHour,
		sevenDay = isWindow(usage.sevenDay) and usage.sevenDay or nil,
		modelScoped = usage.modelScoped,
	}
	publish(lastGood)
end

local function fail(message)
	noctalia.log("claude-usage: " .. message)
	if lastGood then
		local stale = table.clone(lastGood)
		stale.error = message
		publish(stale)
	else
		publish({ ok = false, error = message, fetchedAt = nowEpoch() })
	end
end

local function natsCommand(...)
	return { NATS, "--server", noctalia.getConfig("nats_url"), "--timeout", "2s", ... }
end

local function writeBack(usage)
	local started = noctalia.runAsync(
		natsCommand("kv", "put", BUCKET, KEY, noctalia.json.encode(usage)),
		function(result)
			if result.exitCode ~= 0 then
				noctalia.log("claude-usage: KV write-back failed: " .. noctalia.string.trim(result.stderr))
			end
		end
	)
	if not started then
		noctalia.log("claude-usage: could not start KV write-back")
	end
end

local function apiWindow(node)
	if type(node) ~= "table" or type(node.utilization) ~= "number" then
		return nil
	end
	return { util = node.utilization, resetsAt = parseIso8601(node.resets_at) }
end

local function apiModelScoped(limits)
	if type(limits) ~= "table" then
		return nil
	end
	local scoped = {}
	for _, limit in ipairs(limits) do
		local model = type(limit.scope) == "table" and type(limit.scope.model) == "table" and limit.scope.model
		if
			limit.kind == "weekly_scoped"
			and model
			and type(model.display_name) == "string"
			and type(limit.percent) == "number"
		then
			table.insert(
				scoped,
				{ name = model.display_name, util = limit.percent, resetsAt = parseIso8601(limit.resets_at) }
			)
		end
	end
	return #scoped > 0 and scoped or nil
end

local function backOff(message)
	fallbackCooldown = math.min(fallbackCooldown * 2, FALLBACK_COOLDOWN_MAX)
	nextFallbackAt = nowEpoch() + fallbackCooldown
	fail(message)
end

local function fetchFromApi(token)
	local accepted = noctalia.http({
		url = API_URL,
		method = "GET",
		headers = {
			"Authorization: Bearer " .. token,
			"anthropic-beta: oauth-2025-04-20",
			"User-Agent: " .. USER_AGENT,
		},
	}, function(response)
		inFlight = false
		if not response.ok or response.status ~= 200 then
			backOff("API error: " .. tostring(response.status))
			return
		end
		local data, err = noctalia.json.decode(response.body)
		if not data then
			backOff("Failed to parse response: " .. tostring(err))
			return
		end
		local fiveHour = apiWindow(data.five_hour)
		if not fiveHour then
			backOff("Response missing five_hour utilization")
			return
		end
		fallbackCooldown = FALLBACK_COOLDOWN_MIN
		nextFallbackAt = nowEpoch() + FALLBACK_COOLDOWN_MIN
		local usage = {
			source = "api",
			writtenAt = nowEpoch(),
			fiveHour = fiveHour,
			sevenDay = apiWindow(data.seven_day),
			modelScoped = apiModelScoped(data.limits),
		}
		accept(usage)
		writeBack(usage)
	end)
	if not accepted then
		inFlight = false
		fail("Could not start usage request")
	end
end

local function fallback(natsError)
	if nowEpoch() < nextFallbackAt then
		inFlight = false
		if natsError then
			fail(natsError)
		end
		return
	end
	if natsError then
		noctalia.log("claude-usage: " .. natsError)
	end
	local path = noctalia.getConfig("credentials_path")
	local raw = noctalia.readFile(path)
	if not raw then
		inFlight = false
		fail("Credentials not found at " .. tostring(path))
		return
	end
	local creds = noctalia.json.decode(raw)
	local oauth = creds and creds.claudeAiOauth
	if type(oauth) ~= "table" or type(oauth.accessToken) ~= "string" then
		inFlight = false
		fail("No OAuth token in credentials")
		return
	end
	fetchFromApi(oauth.accessToken)
end

local function refresh()
	if inFlight then
		return
	end
	inFlight = true
	local started = noctalia.runAsync(natsCommand("kv", "get", BUCKET, KEY, "--raw"), function(result)
		if result.exitCode == 0 then
			local usage = noctalia.json.decode(result.stdout)
			if type(usage) == "table" and isWindow(usage.fiveHour) and type(usage.writtenAt) == "number" then
				inFlight = false
				accept(usage)
				return
			end
			fallback("Malformed KV value: " .. noctalia.string.trim(result.stdout))
		elseif string.find(result.stderr, "key not found", 1, true) then
			-- Bucket TTL expired the value: nothing fresh, not an error.
			fallback(nil)
		else
			fallback("NATS read failed: " .. noctalia.string.trim(result.stderr))
		end
	end, 5000)
	if not started then
		fallback("Could not start NATS read")
	end
end

local function applyInterval()
	noctalia.setUpdateInterval(noctalia.getConfig("refresh_seconds") * 1000)
end

applyInterval()
refresh()

function update()
	refresh()
end

-- Defined so a settings edit updates in place instead of restarting the service.
function onConfigChanged()
	applyInterval()
	refresh()
end
