relay = {}

relay.version = "1.0"

dofile("tcpsock.lua")
dofile("netfunctions.lua")

local net = relay.net

-- Variables
relay.username = gkini.ReadString("relay", "username", "relaybot")
relay.nickname = gkini.ReadString("relay", "nickname", "relaybot")
relay.password = gkini.ReadString("relay", "password", "") -- NickServ password
relay.server = gkini.ReadString("relay", "server", "irc.slashnet.org")
relay.guild = gkini.ReadString("relay", "guild", "")
relay.generalchannel = gkini.ReadString("relay", "generalchannel", "#vrelay")
relay.channels = unspickle(gkini.ReadString("relay", "channels", "''"))
relay.admins = unspickle(gkini.ReadString("relay", "admins", "''"))

local nametable, chantable, banned = {[relay.generalchannel]={}}, {}, {}

-- Toggle Variables
relay.sector = gkini.ReadInt("relay", "sector",  0) == 1
relay.system = gkini.ReadInt("relay", "system",  0) == 1
relay.group = gkini.ReadInt("relay", "group",  0) == 1
relay.channel = gkini.ReadInt("relay", "channel",  0) == 1 -- general channel relay
relay.debugprint = gkini.ReadInt("relay", "debugprint", 1) == 1
relay.updatebank = gkini.ReadInt("relay", "updatebank",  1) == 1
relay.motd = gkini.ReadInt("relay", "motd",  1) == 1
relay.ircconnects = gkini.ReadInt("relay", "ircconnects",  1) == 1
relay.guildconnects = gkini.ReadInt("relay", "guildconnects",  1) == 1
relay.allircchat = gkini.ReadInt("relay", "allircchat",  0) == 1
relay.allguildchat = gkini.ReadInt("relay", "allguildchat",  1) == 1
relay.showchan = gkini.ReadInt("relay", "showchan",  1) == 1


relay.customcmds = {}

--[[
	I provide a way to easily insert custom !commands into the relay.
	I give the message, channel, name of sender, IRC send function, and SendChat2 as args. Do whatever.
	A custom command will look like this, assuming "!cmdtest" activates the command:
]]
relay.customcmds["cmdtest"] = function(stripped_msg, channel, sendername, irc_send_func, sendchat_func)
	-- stripped_msg is the message without the "!" at the start
	local cmdarg = stripped_msg:gsub("^(%S+)(%s*)", "") -- take 'cmdtest' and leading spaces off
	irc_send_func("PRIVMSG "..channel.." :"..sendername.." sent command 'cmdtest'; args: "..cmdarg)
	--sendchat_func(stuff, "GUILD")
end


-- Local variables and functions

local lookforbankupdate = false
local desirednick = false

local sc = string.char
local r = sc(3) -- IRC color code modifier

local c = { -- irc colors
	[-1]=r.."10", -- teal
	[0]=r.."15", -- silver/grey
	[1]=r.."12", -- itani (blue)
	[2]=r.."04", -- serco (red)
	[3]=r.."07", -- orange/yellow (uit)
	b=sc(2), -- bold
	n=sc(15), -- normal
	purple=r.."06",
	yellow=r.."08",
	white=r.."00",
	black=r.."01",
	blue=r.."02", -- dark blue
	pink=r.."13",
	aqua=r.."11",
	green=r.."09", -- green that hurts your eyes...
	grey=r.."14",
}

local ranks = {
	[0] = "Member",
	[1] = "Lieutenant",
	[2] = "Council",
	[3] = "Council and Lt.",
	[4] = "Commander"
}

local function updatechannels(str)
	if str == "clear" then
		for i,v in ipairs(relay.channels) do
			nametable[v]={} chantable[v]=true
		end
		nametable[relay.generalchannel] = {}
		banned = {}
	elseif str == "update" then
		for i,v in ipairs(relay.channels) do
			nametable[v] = nametable[v] or {}
			chantable[v] = true
		end
		nametable[relay.generalchannel] = nametable[relay.generalchannel] or {}
	end
end
updatechannels("clear")

local function irc_isadmin(name)
	local ret = false
	for i,v in ipairs(relay.admins) do
		if v == name then ret = true break end
	end
	return ret
end

local function irc_customcmdmatch(msg)
	local cmdstr = msg:match("^(%S+)"):lower()
	return relay.customcmds[cmdstr] 
end

local function irc_colorname(name, faction)
	if type(name) == "number" then
		faction = GetPlayerFaction(name) or 1
		name = GetPlayerName(name)
	end
	return c[faction]..name..c[-1]
end

local function irc_prettymsg(msg)
	local prettymsg = c.b..c[0].."> "..c.n..c[-1]..msg
	return prettymsg
end

local function irc_errormsg(msg, chan)
	local errormsg = "PRIVMSG "..chan.." :"..c.b.."Error: "..c.n..msg
	return errormsg
end

local function formatguildmsg(msg, name, factionid, isemote, location)
	local formatname = not isemote and "<%s%s%s>" or "%s%s%s"
	local formatstr = not location and "%s(guild) "..formatname.." %s" or "%s(guild) ["..location.."] "..formatname.." %s"
	return string.format(formatstr, c[-1], c[factionid], name, c[-1], msg)
end

local function getrank(charid, rank, name)
	local color = c[GetPlayerFaction(charid)]
	local rankstr = ranks[rank]
	return string.format("%s%s %s(%s)", color, name, c[-1], rankstr)
end

local function getguildmembers()
	if not IsConnected() then return "Error: Not logged in!" end
	local members = {}
	for i = 1, GetNumGuildMembers() do
		members[i] = getrank(GetGuildMemberInfo(i))
	end
	return table.concat(members, ', ')
end

local function getsectorplayers()
	if not IsConnected() then return "Error: Not logged in!" end
	local players = {}
	local function parseplayer(charid)
		if (not charid) or (charid == 0) then return end
		local name = GetPlayerName(charid)
		if name and not name:match("^*") then
			table.insert(players, irc_colorname(name, GetPlayerFaction(charid)))
		end
	end
	ForEachPlayer(parseplayer)
	return table.concat(players, ", ")
end

local function send(val)
    if not net.SocketIsUp("IRC") then
        relay.print("Not connected.")
    else
        relay.sock:Send(val)
    end
end

local function send_msg(msg, sendtype, channels)
	sendtype = sendtype or "PRIVMSG"
	for i, channel in ipairs(channels) do
		send(sendtype.." "..channel.." :"..msg)
	end
end

local function parseline(line) -- function by jexkerome
	local ln
	local prefix,command
	prefix, ln = line:match("^%:([^ ]+) +(.+)$")
	if prefix then line = ln end
	command, ln = line:match("^([A-Za-z_][^ ]*)(.*)$")
	if not command then
		command, ln = line:match("^([0-9][0-9][0-9])( +.+)$")
		if not command then return else command = tonumber(command) end
	elseif command:gsub("[^-A-Za-z0-9_]", "") ~= command then
		return
	end
	line = ln
	local ret = {prefix=prefix, command=command}
	repeat
		local param
		param, ln = line:match("^ +([^:\10\13 ][^\10\13 ]*)(.*)$")
		if not param then
			param = line:match("^ +:([^\10\13]*)$")
			if not param then return ret end
			ret[#ret+1]=param
			return ret
		else
			ret[#ret+1]=param
			line = ln
		end
	until false
	return ret
end

local irc_rank = {["+"]=1, ["%"]=2, ["@"]=3}

local function namesort(a,b)
	local arank, brank = irc_rank[a:match("[%+%%@]")] or 0, irc_rank[b:match("[%+%%@]")] or 0
	if arank ~= brank then return arank > brank else return a:gsub("[%+%%@]", ""):lower() < b:gsub("[%+%%@]", ""):lower() end
end

function string.clean(str)
	return str:gsub("[^%a%d%p%s]", "")
end

local function ConnectionMade(reason)
	if relay.ui then relay.ui.toggle.title = "Stop Relay" end
	purchaseprint(reason)
	send("NICK "..relay.nickname)
	send("USER "..relay.username.." 8 * :"..relay.nickname)
	updatechannels("clear")
end
local function ConnectionFailed(reason)
	if relay.ui then relay.ui.toggle.title = "Start Relay" end
	relay.print(reason)
end
local function ConnectionLost(reason)
	if relay.ui then relay.ui.toggle.title = "Start Relay" end
	relay.chat("server", "Shutting down relay. ("..reason..")", "GUILD")
	relay.print(reason)
end
local function LineReceived(line) -- function for parsing incoming IRC lines
	for msg in line:gmatch("([^\r\n]+)") do -- split received data so we can parse each line individually (in case they"re clumped) - Is this necessary?
		relay.print(msg)
		relay.parsecommand(parseline(msg))	-- parse everything besides messages (joins, kicks, etc)
	end
end


-- Global relay functions and events	

relay.updatechannels = updatechannels

function relay.isactive()
	return net.SocketIsUp("IRC")
end

function relay.print(line)
	if not relay.debugprint then return end
	line = string.clean(line)
	line = string.format("%s[%sirc\127o] %s%s\127o", "\127DD3333", "\127dd6666", "\12777FF55", line)
	if IsConnected() then print(line) else console_print(line) end
end

function relay.chat(chan, msg, chantype, name)
	local chanstr = chan == "server" and "[server]" or "[irc]"
	if relay.showchan and chantype == "GUILD" then chanstr = "["..chan.."]" end
	local begin = "/me "
	if chantype == "SYSTEM" or chantype == "GROUP" then begin = "" end -- they don't support emotes
	SendChat2(begin..chanstr.." "..msg, chantype, name)
end

function relay.parsecommand(p)
	if p.command == "PING" then
		send("PONG :"..p[1])
	elseif p.command == "PRIVMSG" then
		local name, user, host = p.prefix:match("^(.+)!(.+)@(.+)$")
		local chan, msg = p[1], p[2]
		name = name:gsub("[%+%%@]", "")
		local rmsg = msg:gsub("^!", "")
		local formatname = name
		if not rmsg:match("^/me ") then formatname = "<"..name..">" else rmsg = rmsg:gsub("^/me ", "") end
		local strippedmsg = rmsg:gsub("^(%S+)(%s*)", "")
		if msg:match("^!") and chantable[chan] then -- recognized command/keyword and recognized channel
			if not IsConnected() then
				send(irc_errormsg("not logged in", chan))
				
			-- IRC Commands
			elseif rmsg:match("^online$") then
				send("PRIVMSG "..chan.." :"..irc_prettymsg("Online: "..getguildmembers()))
			elseif rmsg:match("^listsector$") then
				send(relay.sector and "PRIVMSG "..chan.." :"..irc_prettymsg("In "..ShortLocationStr(GetCurrentSectorid())..": "..getsectorplayers())
					or irc_errormsg("sector chat disabled", chan))
			elseif rmsg:match("^bank$") then
				send(relay.updatebank and "PRIVMSG "..chan.." :"..irc_prettymsg("Bank: "..c.n..GetGuildBalance() ..c[-1].." credits.")
					or irc_errormsg("bank status disabled", chan))
			elseif rmsg:match("^motd$") then
				if relay.motd then
					local motd = filter_colorcodes(GetGuildMOTD())
					for motdline in motd:gmatch("([^\n]+)") do
						send("PRIVMSG "..chan.." :"..irc_prettymsg(motdline))
					end
				else
					send(irc_errormsg("motd disabled", chan))
				end
				
			-- IRC -> ingame relay chat type keywords
			elseif rmsg:match("^sector%s*") or rmsg:match("^s%s") then
				if relay.sector then
					relay.chat(chan, formatname.." "..strippedmsg, "SECTOR")
				else
					send(irc_errormsg("sector chat disabled", chan))
				end
			elseif rmsg:match("^system%s*") or rmsg:match("^sys%s") then
				if relay.system then
					relay.chat(chan, formatname.." "..strippedmsg, "SYSTEM")
				else
					send(irc_errormsg("system chat disabled", chan))
				end
			elseif rmsg:match("^group%s*") or rmsg:match("^g%s") then
				if relay.group then
					relay.chat(chan, formatname.." "..strippedmsg, "GROUP")
				else
					send(irc_errormsg("group chat disabled", chan))
				end
				
			elseif irc_customcmdmatch(rmsg) then -- Custom command
				relay.print("custom")
				local cmd = irc_customcmdmatch(rmsg)
				cmd(rmsg, chan, name, send, SendChat2) -- I give the message, channel, name of sender, IRC send function, and SendChat2 as args. Do whatever.
				
			elseif not relay.allircchat then
				relay.chat(chan, formatname.." "..rmsg, "GUILD")
			end
		elseif msg:match("^!") and chan == relay.generalchannel then
			if relay.channel then
				relay.chat(chan, formatname.." "..rmsg, "CHANNEL")
			else
				send(irc_errormsg("channel chat disabled", chan))
			end
		elseif chan == relay.nickname and name ~= "vo" and not host:match(relay.server:gsub("^(%w+)(%.)", "")) then
			if irc_isadmin(name) and msg:match("^remote ") then -- admins can remote lua with keyword
				local luastuff = msg:gsub("^remote ", "")
				loadstring(luastuff)()
				send("NOTICE "..name.." :Remote command executed")
			else
				if relay.channel then
					relay.chat(chan, formatname.." "..rmsg, "CHANNEL")
				else
					send(irc_errormsg("channel chat disabled", name))
				end
			end
		elseif relay.allircchat and chantable[chan] then
			relay.chat(chan, formatname.." "..msg, "GUILD")
		elseif chan:match("^#") and not chantable[chan] then
			--send("PART "..chan)
		end
	elseif p.command == "NOTICE" then
		local name, user, host = p.prefix:match("^(.+)!(.+)@(.+)$")
		local chan, msg = p[1], p[2]
		name = name:gsub("[%+%%@]", "")
		if name == "NickServ" then
			if chan == relay.nickname and msg:match("^This nickname is registered and protected.") and relay.password ~= "" then -- identify
				send("PRIVMSG NickServ :IDENTIFY "..relay.password)
			elseif msg:match("^Ghost with your nickname has been killed.") and desirednick then -- successfully ghosted
				send("NICK "..desirednick)
			end
		end
	elseif p.command == "JOIN" then
		local name = p.prefix:match("^(.+)!")
		local chan = p[1]
		nametable[chan] = nametable[chan] or {}
		nametable[chan][name] = true
		if not relay.ircconnects then return end
		if name ~= relay.nickname then
			if chantable[chan] then relay.chat(chan, "-> "..name.." joined "..chan, "GUILD") end
		else
			nametable[chan].__waitforlist = true
		end
	elseif p.command == "PART" then
		local name = p.prefix:match("^(.+)!")
		local chan = p[1]
		nametable[chan][name] = false
		if not relay.ircconnects then return end
		if name ~= relay.nickname then
			if chantable[chan] then relay.chat(chan, "-> "..name.." left "..chan, "GUILD") end
		else
			relay.chat("server", "-> No longer connected to "..chan, "GUILD")
		end
	elseif p.command == "QUIT" then
		local name = p.prefix:match("^(.+)!")
		local found = false
		for k,v in pairs(nametable) do
			if v[name] then
				if v ~= relay.generalchannel then found = true end
				v[name] = false
			end
		end
		if not relay.ircconnects then return end
		if found then relay.chat("server", "-> "..name.." quit IRC ("..p[1]..")", "GUILD") end
	elseif p.command == "NICK" then
		local name = p.prefix:match("^(.+)!")
		local newname = p[1]
		for k,v in pairs(nametable) do
			if v[name] then
				v[name] = false
				v[newname] = true
			end
		end
		if name == relay.nickname then
			relay.nickname = newname
			desirednick = desirednick == relay.nickname and false or desirednick
			relay.chat("server", "-> I am now known as "..newname, "GUILD")
		else
			relay.chat("server", "-> "..name.." is now known as "..newname, "GUILD")
		end
	elseif p.command == "KICK" then
		local name = p.prefix:match("^(.+)!")
		local chan, name2, kickmsg = p[1], p[2], p[3]
		nametable[chan][name2] = false
		if not relay.ircconnects then return end
		if chantable[chan] then relay.chat(chan, "-> "..name.." kicked "..name2.." from "..chan.." ("..kickmsg..")", "GUILD") end
	elseif p.command == 353 then -- userlist
		local userliststr = p[4]
		local channel = p[3]
		local justjoined = nametable[channel] and nametable[channel].__waitforlist
		nametable[channel] = {}
		local userlist = {}
		for v in userliststr:gmatch("(%S+)") do
			local name = v:gsub("[%+%%@]", "")
			table.insert(userlist, name)
			nametable[channel][name] = true
		end
		table.sort(userlist, namesort)
		if justjoined then 
			relay.chat("server", "-> Connected to "..channel.." - users: "..table.concat(userlist, ", "), "GUILD")
		else
			relay.chat("server", "-> Users in "..channel..": "..table.concat(userlist, ", "), "GUILD")
		end
	elseif p.command == 433 then -- nickname already in use
		if relay.password ~= "" then -- we have a nickserv password
			desirednick = relay.nickname -- we want our old nick back
		end
		relay.nickname = relay.nickname.."_"
		send("NICK "..relay.nickname)
	elseif p.command == 376 then -- end of server MOTD
		if desirednick then send("PRIVMSG NickServ :GHOST "..desirednick.." "..relay.password) end
		for i,v in ipairs(relay.channels) do send("JOIN "..v) end
		if relay.channel then send("JOIN "..relay.generalchannel) end
	elseif p.command == 404 then -- trying to send message to channel you aren't joined to
		local chan = p[2]
		if chantable[chan] and not banned[chan] then send("JOIN "..chan) end
	elseif p.command == 474 then -- can't join channel (banned)
		local chan = p[2]
		banned[chan] = true
	end
end


function relay:OnEvent(event, data, ...)
	if not net.SocketIsUp("IRC") then return end
	if data and type(data) == "table" and data.msg and data.name and data.msg:match("^%[(.-)%] (.-)") and data.name == GetPlayerName(GetCharacterID()) then return end
	if event == "UNLOAD_INTERFACE" then
		self.disconnect()
		
	elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_GUILD_EMOTE" then
		local msg = data.msg:lower()
		if msg:match("^!") then
			if msg:match("!online") then
				for i, channel in ipairs(self.channels) do send("NAMES "..channel) end
			elseif not self.allguildchat then
				send_msg(formatguildmsg(data.msg, data.name, data.faction, event:match("EMOTE") and true, SystemNames[GetSystemID(data.location)]), "PRIVMSG", self.channels)
			end
		elseif self.allguildchat then
			send_msg(formatguildmsg(data.msg, data.name, data.faction, event:match("EMOTE") and true, SystemNames[GetSystemID(data.location)]), "PRIVMSG", self.channels)
		end
	elseif (event == "CHAT_MSG_CHANNEL_ACTIVE" or event == "CHAT_MSG_CHANNEL_EMOTE_ACTIVE") and self.channel then
		local formatstr = not event:match("EMOTE") and "%s[%d]%s <%s> %s" or "%s[%d]%s %s %s"
		local sendmsg = string.format(formatstr, c.grey, data.channelid, c[-1], irc_colorname(data.name, data.faction), data.msg)
		send_msg(sendmsg, "PRIVMSG", {self.generalchannel})
	elseif (event == "CHAT_MSG_SECTOR" or event == "CHAT_MSG_SECTOR_EMOTE") and self.sector then
		local formatstr = not event:match("EMOTE") and "%s(sector) <%s%s> %s" or "%s(sector) %s%s %s"
		local sendmsg = string.format(formatstr, c.aqua, irc_colorname(data.name, data.faction), c.aqua, data.msg)
		send_msg(sendmsg, "PRIVMSG", self.channels)
	elseif event == "CHAT_MSG_SYSTEM" and self.system then
		send_msg(c.purple.."(system) ["..ShortLocationStr(data.location).."] <"..irc_colorname(data.name, data.faction)..c.purple.."> "..data.msg, "PRIVMSG", self.channels)
	elseif event == "CHAT_MSG_GROUP" and self.group then
		send_msg(c.yellow.."(group) <"..irc_colorname(data.name, data.faction)..c.yellow.."> "..data.msg, "PRIVMSG", self.channels)
		
	elseif event == "CHAT_MSG_SERVER_GUILD" then
		if not data.msg:match(" logged (%w+).$") then
			local msg
			if data.msg:match("joined the guild") then
				local membername = data.msg:match("(.-) joined the guild")
				local membercharid
				for i=1, GetNumGuildMembers() do
					local charid, rank, name1 = GetGuildMemberInfo(i)
					if name1 == membername then membercharid = charid break end
				end
				local faction = GetPlayerFaction(membercharid) or 1
				membername = c[faction]..membername..c[-1]
				msg = irc_prettymsg(membername.." joined the guild.")
			elseif data.msg:match("has left the guild.") then
				local membername = data.msg:match("(.-) has left the guild")
				msg = irc_prettymsg(membername.." has left the guild.")
			else
				msg = irc_prettymsg(msg)
			end
			send_msg(msg, "NOTICE", self.channels)
		end
	elseif event == "GUILD_MEMBER_ADDED" and self.guildconnects then
		local t= Timer()
		t:SetTimeout(700, function()
			local msg = irc_colorname(data)
			send_msg(irc_prettymsg(msg.." logged on."), "NOTICE", self.channels)
		end)
	elseif event == "GUILD_MEMBER_REMOVED" and self.guildconnects then
		local msg = irc_colorname(data)
		send_msg(irc_prettymsg(msg.." logged off."), "NOTICE", self.channels)
	elseif event == "GUILD_BALANCE_UPDATED" and self.updatebank then
		lookforbankupdate = true
		Guild.getbanklogpage(1)
	elseif event == "GUILD_BANK_LOG" and lookforbankupdate then
		lookforbankupdate = false
		local bankdata = data[1]
		local str = "added to"
		local reason = bankdata.description ~= "" and " (reason: "..bankdata.description..")" or "" 
		local amount
		if bankdata.action == "deposit" then
			amount = bankdata.current - bankdata.previous
		else
			str = "subtracted from"
			amount = bankdata.previous - bankdata.current
		end
		local plural = amount ~= 1 and "s have" or " has"
		send_msg(irc_prettymsg(c.n..amount.." credit"..plural.." been "..str.." the Guild bank by "..bankdata.charname..reason), "NOTICE", self.channels)
	elseif event == "SECTOR_LOADED" and (not GetGuildTag() or GetGuildTag() ~= self.guild) then
		self.disconnect()
	end
end
relay.events = {
	["UNLOAD_INTERFACE"] = true,
	["GUILD_MEMBER_ADDED"] = true,
	["GUILD_MEMBER_REMOVED"] = true,
	["CHAT_MSG_GUILD"] = true,
	["CHAT_MSG_GUILD_EMOTE"] = true,
	["CHAT_MSG_SECTOR"] = true,
	["CHAT_MSG_SECTOR_EMOTE"] = true,
	["GUILD_BALANCE_UPDATED"] = true,
	["CHAT_MSG_SYSTEM"] = true,
	["CHAT_MSG_SERVER_GUILD"] = true,
	["SECTOR_LOADED"] = true,
	["PLAYER_LOGGED_OUT"] = true,
	["CHAT_MSG_GROUP"] = true,
	["GUILD_BANK_LOG"] = true,
	["CHAT_MSG_CHANNEL_ACTIVE"] = true,
	["CHAT_MSG_CHANNEL_EMOTE_ACTIVE"] = true,
}
for event in pairs(relay.events) do RegisterEvent(relay, event) end

function relay.connect()
	if not net.SocketIsUp("IRC") then
		if not relay.channels[1] then purchaseprint("Please add a channel to connect to") return end
		relay.sock = net.make_client(6667, relay.server, ConnectionMade, ConnectionFailed, LineReceived, ConnectionLost, "IRC")
	end
end

function relay.disconnect()
	if net.SocketIsUp("IRC") then
		relay.sock:Disconnect()
		purchaseprint("Quitting IRC Relay.")
	end
end

function relay.command(blank, data)
	if not data then 
		ShowDialog(relay.ui.dlg)
		return
	end
	local cmd = table.remove(data, 1):lower()
	if cmd == "toggle" then
		if not net.SocketIsUp("IRC") then relay.connect() else relay.disconnect() end
	elseif cmd == "open" or cmd == "interface" or cmd == "show" then
		ShowDialog(relay.ui.dlg)
	else
		local errorcode = relay.toggle(cmd)
		if errorcode then send(cmd.." "..table.concat(data, " ")) end
	end
end

function relay.toggle(var)
	var = var:lower()
	if relay[var] == nil then return 0 elseif type(relay[var]) ~= "boolean" then return 1 end
	relay[var] = not relay[var]
	gkini.WriteInt("relay", var, relay[var] and 1 or 0)
	purchaseprint(relay[var] and var.." \12722ff22enabled" or var.." \127ff2222disabled")
	if var == "channel" and net.SocketIsUp("IRC") then
		send(relay[var] and "JOIN "..relay.generalchannel or "PART "..relay.generalchannel)
	end
end

RegisterUserCommand("relay", relay.command)