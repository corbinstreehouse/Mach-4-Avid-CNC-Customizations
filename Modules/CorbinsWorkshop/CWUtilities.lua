

local CWUtilities = {
	toolHeightsWereActive = false
}

CWUtilities.inst = mc.mcGetInstance("CWUtilities")

-- sleep in seconds
function CWUtilities.Sleep(duration)
	wx.wxSleep(duration)
end


function CWUtilities.IsToolHeightActive() 
	-- MOD group 8
	local HOState = mc.mcCntlGetPoundVar(CWUtilities.inst, 4008)
	if (HOState == 43) then -- G43 active
		return true
	else	
		return false -- G49 active
	end
end

function CWUtilities.SetToolHeightActive(isActive)
	if (isActive) then
		local rc = mc.mcCntlMdiExecute(CWUtilities.inst, "G43")
		if (rc ~= mc.MERROR_NOERROR) then
			local msg = "error doing G43 to restore heights: "..rc
			mc.mcCntlLog(inst, msg, "", -1)
			mc.mcCntlSetLastError(inst, msg)
			
		end
	else
		mc.mcCntlMdiExecute(CWUtilities.inst, "G49")
	end
end


function CWUtilities.SaveToolHeightActiveStateAndDisable()
	CWUtilities.toolHeightsWereActive = CWUtilities.IsToolHeightActive()
	mc.mcCntlSetLastError(CWUtilities.inst, "SaveToolHeightActiveStateAndDisable")
	
	if CWUtilities.toolHeightsWereActive then
		mc.mcCntlSetLastError(CWUtilities.inst, "Disabling tool heights because it causes lots of trouble")		
		CWUtilities.SetToolHeightActive(false)
	end
end

function CWUtilities.RestoreToolHeightActiveState()
	if CWUtilities.toolHeightsWereActive ~= nil and CWUtilities.toolHeightsWereActive then
		mc.mcCntlSetLastError(CWUtilities.inst, "Touch Plate: Restoring tool heights being active again.")		
		-- they are probably doing something on a timer.'
		wx.wxMilliSleep(100)
		CWUtilities.SetToolHeightActive(true)
	end
end




if (mc.mcInEditor() == 1) then
--	if CWUtilities.IsToolHeightActive() then		
--		print("active")
		
--	end
--	CWUtilities.SetToolHeightActive(not CWUtilities.IsToolHeightActive())
end





return CWUtilities