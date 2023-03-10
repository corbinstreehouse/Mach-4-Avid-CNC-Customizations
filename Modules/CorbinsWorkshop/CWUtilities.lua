

local CWUtilities = {
	toolHeightsWereActive = false,
	startingZ = 0.0,
	startingMachineZ = 0.0
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
	local inst = CWUtilities.inst

	CWUtilities.toolHeightsWereActive = CWUtilities.IsToolHeightActive()

	-- if a tool is in...and it doesn't have a 0 height, and it isn't active, then that is also bad
	-- because we will touch off as though it isn't in there..and that will cause a bad problem
	if not CWUtilities.toolHeightsWereActive then
		local toolNumber = mc.mcToolGetCurrent(inst)
		if toolNumber > 0 then
			local height, rc = mc.mcToolGetData(inst, mc.MTOOL_MILL_HEIGHT, toolNumber)	
			if height ~= 0 then
				local rc = wx.wxMessageBox(
					"Tool heights are NOT active, and your tool has a height. \nActivate tool heights before continuing (G43)?", 
					"Tool height check", wx.wxYES_NO)
				if (rc == wx.wxYES) then
					-- Just save it as though it was active so, so we set it back to true and do the next bit of code.
					CWUtilities.toolHeightsWereActive = true					
				end
			end
		end
	end

	if CWUtilities.toolHeightsWereActive then

		mc.mcCntlSetLastError(inst, "Disabling tool heights because it causes lots of trouble")		
		CWUtilities.SetToolHeightActive(false)

		CWUtilities.startingZ = mc.mcAxisGetPos(inst, mc.Z_AXIS) -- see if the axis was changed
		CWUtilities.startingMachineZ = mc.mcAxisGetMachinePos(inst, mc.Z_AXIS)
	end
end

function CWUtilities.RestoreToolHeightActiveState()
	local inst = CWUtilities.inst

	if CWUtilities.toolHeightsWereActive ~= nil and CWUtilities.toolHeightsWereActive then
		mc.mcCntlSetLastError(inst, "Touch Plate: Restoring tool heights being active again.")		
		-- they are probably doing something on a timer.'
		wx.wxMilliSleep(100)
		CWUtilities.SetToolHeightActive(true)

		wx.wxMilliSleep(100)

		-- set the offset if the z did change by the routine
		local toolNumber = mc.mcToolGetCurrent(inst)
		if toolNumber > 0 then
			local height, rc = mc.mcToolGetData(inst, mc.MTOOL_MILL_HEIGHT, toolNumber)	
			if height ~= 0 then
				-- have a height, see if the position changed (ie: routine was run)
				-- this is a weak attempt to make sure it ran...though it may not have touched off..which
				-- might be bad..
				local machineZ = mc.mcAxisGetMachinePos(inst, mc.Z_AXIS)
				local currentZ = mc.mcAxisGetPos(inst, mc.Z_AXIS)
				if machineZ ~= CWUtilities.startingMachineZ and currentZ ~= CWUtilities.startingZ then
					local msg = string.format("Touch Plate: Adding T%d height %.3f from Z offset to account for tool length",
						toolNumber, height)
					mc.mcCntlSetLastError(inst, msg)					

					-- okay it did..maybe.
					currentZ = currentZ + height
					-- set the pos to account for the tool height
					mc.mcAxisSetPos(inst, mc.Z_AXIS, currentZ)

				end				
			end						
		end
	end
end




if (mc.mcInEditor() == 1) then
--	CWUtilities.SaveToolHeightActiveStateAndDisable()
--	CWUtilities.RestoreToolHeightActiveState()
end





return CWUtilities