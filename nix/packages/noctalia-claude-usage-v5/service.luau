local API_URL = "https://api.anthropic.com/api/oauth/usage"
local USER_AGENT = "noctalia-claude-usage/1.0.0"
local STATE_KEY = "usage"

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

local function publish(snapshot)
	noctalia.state.set(STATE_KEY, snapshot)
end

local function fail(message)
	noctalia.log("claude-usage: " .. message)
	publish({ ok = false, error = message, fetchedAt = nowEpoch() })
end

local function bucket(node)
	if type(node) ~= "table" or type(node.utilization) ~= "number" then
		return nil
	end
	return { util = node.utilization, resetsAt = parseIso8601(node.resets_at) }
end

local function fetchUsage(token)
	local accepted = noctalia.http({
		url = API_URL,
		method = "GET",
		headers = {
			"Authorization: Bearer " .. token,
			"anthropic-beta: oauth-2025-04-20",
			"User-Agent: " .. USER_AGENT,
		},
	}, function(response)
		if not response.ok or response.status ~= 200 then
			fail("API error: " .. tostring(response.status))
			return
		end
		local data, err = noctalia.json.decode(response.body)
		if not data then
			fail("Failed to parse response: " .. tostring(err))
			return
		end
		local fiveHour = bucket(data.five_hour)
		if not fiveHour then
			fail("Response missing five_hour utilization")
			return
		end
		publish({
			ok = true,
			fetchedAt = nowEpoch(),
			fiveHour = fiveHour,
			sevenDay = bucket(data.seven_day),
			opus = bucket(data.seven_day_opus),
			sonnet = bucket(data.seven_day_sonnet),
		})
	end)
	if not accepted then
		fail("Could not start usage request")
	end
end

local function refresh()
	local path = noctalia.getConfig("credentials_path")
	local raw = noctalia.readFile(path)
	if not raw then
		fail("Credentials not found at " .. tostring(path))
		return
	end
	local creds = noctalia.json.decode(raw)
	local oauth = creds and creds.claudeAiOauth
	if type(oauth) ~= "table" or type(oauth.accessToken) ~= "string" then
		fail("No OAuth token in credentials")
		return
	end
	fetchUsage(oauth.accessToken)
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
