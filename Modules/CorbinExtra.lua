
-- corbin's functions 

local CorbinExtra = {}

local CD_SIG_PRESSURIZED_AIR = mc.OSIG_OUTPUT7 

-- return true if we did the full sleep, otherwise return false because of an error...
function CorbinExtra.Sleep(duration)
	wx.wxSleep(duration)
	return true
end

-- set pressured air
function CorbinExtra.SetAirPressure(state)
	local inst = mc.mcGetInstance()
	
	mc.mcCntlSetLastError(inst, "Turning air pressure and fan to state: "..state)
	local hndlSigAirPressure = mc.mcSignalGetHandle(inst, CD_SIG_PRESSURIZED_AIR)
	mc.mcSignalSetState(hndlSigAirPressure, state)	
end


return CorbinExtra -- Module End