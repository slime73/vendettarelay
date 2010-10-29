-- credit to a1k0n, firsm, and jexkerome for their codes

local buffer = {
	["CHANNEL"] = {timer=Timer(), active=false},
	["SECTOR"] = {timer=Timer(), active=false},
	["GROUP"] = {timer=Timer(), active=false},
	["GUILD"] = {timer=Timer(), active=false},
	["PRIVATE"] = {timer=Timer(), active=false},
	["SYSTEM"] = {timer=Timer(), active=false},
	["STATION"] = {timer=Timer(), active=false},
}

local function sendchat(str, chan, name)
	chan = chan:upper()
	chan = chan == "SAY" and "SECTOR" or chan
	if not buffer[chan].active then
		buffer[chan].active = true
		SendChat(str, chan, name)
		buffer[chan].timer:SetTimeout(360, function()
			if buffer[chan][1] then
				local tosend = table.remove(buffer[chan], 1)
				SendChat(tosend[1], tosend[2], tosend[3])
				buffer[chan].timer:SetTimeout(360)
			else
				buffer[chan].active = false
			end
		end)
	else
		table.insert(buffer[chan], {str, chan, name})
	end
end

function SendChat2(str, chan, name) -- buffered SendChat function
	chan = chan:upper()
	local num = 1
	for i = 1, 50 do -- don't want to spam chat TOO much
		local newstr = str:sub(num, num+256)
		if not newstr or newstr == "" then break end
		sendchat(newstr, chan, name)
		num = num+256
	end
end
	
	
dofile("relay.lua")
dofile("ui.lua")
