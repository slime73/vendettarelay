relay.ui = {}

relay.ui.toggles = iup.vbox{
	iup.stationtoggle{title="Sector Chat", action=function() relay.toggle("sector") end},
	iup.stationtoggle{title="System Chat", action=function() relay.toggle("system") end},
	iup.stationtoggle{title="Group Chat", action=function() relay.toggle("group") end},
	iup.stationtoggle{title="Channel Chat", action=function() relay.toggle("channel") end},
	iup.stationtoggle{title="Debug Print", action=function() relay.toggle("debugprint") end},
	iup.stationtoggle{title="Bank Updates", action=function() relay.toggle("updatebank") end},
	iup.stationtoggle{title="MOTD Command", action=function() relay.toggle("motd") end},
	iup.stationtoggle{title="Relay All IRC Chat", action=function() relay.toggle("allircchat") end},
	iup.stationtoggle{title="Relay All Guild Chat", action=function() relay.toggle("allguildchat") end},
	iup.stationtoggle{title="Format As [#chan] instead of [irc]", action=function() relay.toggle("showchan") end},
}

local function textaction(self, c, newval)
	relay[self.name] = newval
	gkini.WriteString("relay", self.name, newval)
end
relay.ui.username = iup.text{expand="HORIZONTAL", name="username", action=textaction}
relay.ui.nickname = iup.text{expand="HORIZONTAL", name="nickname", action=textaction}
relay.ui.password = iup.text{expand="HORIZONTAL", name="password", action=textaction}
relay.ui.server = iup.text{expand="HORIZONTAL", name="server", action=textaction}
relay.ui.guild = iup.text{expand="HORIZONTAL", name="guild", action=textaction}
relay.ui.generalchannel = iup.text{expand="HORIZONTAL", name="generalchannel", action=textaction}
relay.ui.texts = iup.vbox{
	iup.hbox{iup.label{title="IRC Username:"}, relay.ui.username, gap=5},
	iup.hbox{iup.label{title="IRC Nickname:"}, relay.ui.nickname, gap=5},
	iup.hbox{iup.label{title="IRC Server:"}, relay.ui.server, gap=5},
	iup.hbox{iup.label{title="NickServ Password:"}, relay.ui.password, gap=5},
	iup.hbox{iup.label{title="Guild Acronym:"}, relay.ui.guild, gap=5},
	iup.hbox{iup.label{title="Channel Relay Channel:"}, relay.ui.generalchannel, gap=5},
}

relay.ui.channels = iup.pdasubsublist{size=160, expand="VERTICAL"}
relay.ui.removechannelbutton = iup.stationbutton{size=160, title="Remove Channel", font=Font.H5,
	action=function(self)
		local val = relay.ui.channels.value
		if val == 0 then return end
		table.remove(relay.channels, val)
		gkini.WriteString("relay", "channels", spickle(relay.channels))
		relay.updatechannels("update")
		iup.SetAttributes(relay.ui.channels, 1, "") -- clear list
		for i, channel in ipairs(relay.channels) do relay.ui.channels[i] = channel end
	end,
}
relay.ui.addchannelbutton = iup.stationbutton{size=160, title="Add Channel", font=Font.H5,
	action=function(self)
		local channel = relay.ui.addchannel.value
		if channel == "" then return end
		table.insert(relay.channels, channel)
		relay.updatechannels("update")
		gkini.WriteString("relay", "channels", spickle(relay.channels))
		relay.ui.channels[#relay.channels] = channel
		relay.ui.addchannel.value = ""
	end,
}
relay.ui.addchannel = iup.text{size=160, action=function(self, c, val) if c == 13 and #val > 0 then relay.ui.addchannelbutton:action() end end}
relay.ui.channelbox = iup.vbox{
	iup.label{title="IRC Channels"},
	relay.ui.addchannel,
	relay.ui.addchannelbutton,
	relay.ui.channels,
	relay.ui.removechannelbutton,
}


relay.ui.admins = iup.pdasubsublist{size=160, expand="VERTICAL"}
relay.ui.removeadminbutton = iup.stationbutton{size=160, title="Remove Admin", font=Font.H5,
	action=function(self)
		local val = relay.ui.admins.value
		if val == 0 then return end
		table.remove(relay.admins, val)
		gkini.WriteString("relay", "admins", spickle(relay.admins))
		iup.SetAttributes(relay.ui.admins, 1, "") -- clear list
		for i, name in ipairs(relay.admins) do relay.ui.admins[i] = name end
	end,
}
relay.ui.addadminbutton = iup.stationbutton{size=160, title="Add Admin", font=Font.H5,
	action=function(self)
		local name = relay.ui.addadmin.value
		if name == "" then return end
		table.insert(relay.admins, name)
		gkini.WriteString("relay", "admins", spickle(relay.admins))
		relay.ui.admins[#relay.admins] = name
		relay.ui.addadmin.value = ""
	end,
}
relay.ui.addadmin = iup.text{size=160, action=function(self, c, val) if c == 13 and #val > 0 then relay.ui.addadminbutton:action() end end}
relay.ui.adminbox = iup.vbox{
	iup.label{title="IRC Admins"},
	relay.ui.addadmin,
	relay.ui.addadminbutton,
	relay.ui.admins,
	relay.ui.removeadminbutton,
}


relay.ui.toggle = iup.stationbutton{expand="HORIZONTAL", title="Start Relay", action=function() if relay.isactive() then relay.disconnect() else relay.connect() end end}

relay.ui.close = iup.stationbutton{expand="HORIZONTAL", title="Close", action=function() HideDialog(relay.ui.dlg) end}

relay.ui.version = iup.label{title="Version: "..relay.version}

relay.ui.main = iup.pdarootframe{
	iup.pdasubframebg{
		iup.vbox{
			relay.ui.toggle,
			iup.hbox{
				iup.vbox{
					relay.ui.texts,
					relay.ui.toggles,
					gap=5,
				},
				relay.ui.channelbox,
				relay.ui.adminbox,
				gap=5,
			},
			relay.ui.close,
			gap=5,
		},
	},
	size="HALFx",
	expand="NO",
}

relay.ui.dlg = iup.dialog{
	iup.vbox{
		iup.fill{},
		iup.hbox{iup.fill{}, relay.ui.version, iup.fill{}},
		iup.fill{size=12},
		iup.hbox{
			iup.fill{},
			relay.ui.main,
			iup.fill{},
		},
		iup.fill{size=12},
		iup.label{title=""},
		iup.fill{},
	},
	fullscreen="YES",
	border="NO",
	topmost="YES",
	resize="NO",
	menubox="NO",
	bgcolor="0 0 0 128 *",
	defaultesc=relay.ui.close,
}

function relay.ui.dlg:show_cb() -- initialize ui values
	FadeControl(relay.ui.version, 3, 3, 0)
	
	relay.ui.toggles[1].value = relay.sector and "ON" or "OFF"
	relay.ui.toggles[2].value = relay.system and "ON" or "OFF"
	relay.ui.toggles[3].value = relay.group and "ON" or "OFF"
	relay.ui.toggles[4].value = relay.channel and "ON" or "OFF"
	relay.ui.toggles[5].value = relay.debugprint and "ON" or "OFF"
	relay.ui.toggles[6].value = relay.updatebank and "ON" or "OFF"
	relay.ui.toggles[7].value = relay.motd and "ON" or "OFF"
	relay.ui.toggles[8].value = relay.allircchat and "ON" or "OFF"
	relay.ui.toggles[9].value = relay.allguildchat and "ON" or "OFF"
	relay.ui.toggles[10].value = relay.showchan and "ON" or "OFF"
	
	if relay.guild == "" and IsConnected() and GetGuildTag() then
		relay.guild = GetGuildTag()
		gkini.WriteString("relay", "guild", relay.guild)
	end
	
	relay.ui.username.value = relay.username
	relay.ui.nickname.value = relay.nickname
	relay.ui.password.value = relay.password
	relay.ui.server.value = relay.server
	relay.ui.guild.value = relay.guild
	relay.ui.generalchannel.value = relay.generalchannel
	
	iup.SetAttributes(relay.ui.channels, 1, "") -- clear list
	for i, channel in ipairs(relay.channels) do relay.ui.channels[i] = channel end
	
	iup.SetAttributes(relay.ui.admins, 1, "") -- clear list
	for i, name in ipairs(relay.admins) do relay.ui.admins[i] = name end
end

function relay.ui.dlg:hide_cb()
	FadeStop(relay.ui.version)
end

