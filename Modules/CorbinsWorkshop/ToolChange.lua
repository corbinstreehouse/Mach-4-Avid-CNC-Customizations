
-- ToolChange.lua
-- by Corbin Dunn
-- Feb 21, 2023
-- corbin@corbinstreehouse.com or corbin@corbinsworkshop.com
-- Blog: https://www.corbinstreehouse.com
-- Files/Prodcuts: https://www.corbinsworkshop.com
-- (c) 2023 Corbin Dunn
-- Software provided as-is. For redistribution rights, please contact me.

-- NOTE: IF YOU CHANGE THIS FILE, YOU HAVE TO RESTART MACH 4.
-- It is loaded as a module; the UI may respect changes, but the M6 script will not until a restart.
-- I usually debug this in the ScriptEditor. When I'm happy with the changes, I restart Mach 4.


-- TODO: UI customization for this ... or pass it in from M6
local DRAWBAR_SIGNAL_OUTPUT = mc.OSIG_OUTPUT6

local ToolChange = {
	lastSpindleStopTime = os.clock(), -- in seconds; The m5 script should set this when it turns off the spindle
	lastX = 0.0,
	lastY = 0.0,
	internal = {
		inst = nil,
		drawBarSigHandle = nil,		
	},
	debug = {
		TEST_AT_Z_0 = false,  -- set to true to debug the slide at z 0. DON'T HAVE ANY TOOLS IN THE MACHINE..IT WILL DROP THEM!
	}
}

package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
local ToolForks = require 'ToolForks'

-- must be the first thing called, and this file calls it.
function ToolChange.internal.Initialize()
	ToolChange.internal.inst = mc.mcGetInstance("ToolChange.lua")
	ToolChange.internal.drawBarSigHandle, rc = mc.mcSignalGetHandle(ToolChange.internal.inst, DRAWBAR_SIGNAL_OUTPUT)
	ToolChange.internal.CheckForNoError(rc, "Getting drawbar signal")
end

local function MCTry(msg, f, ...)
	local rc = f(...)
	if (rc ~= mc.MERROR_NOERROR) then
		local message = string.format("ToolChange ERROR %d: %s", rc, msg)
		error(message) -- throws the exception
	end
end

local function MCCntlGcodeExecuteWait(gcode, ...)
	gcode = string.format(gcode, ...)
	local message = "Executing: "..gcode
	MCTry(message, mc.mcCntlGcodeExecuteWait, ToolChange.internal.inst, gcode)
end


function ToolChange.internal.CheckForNoError(rc, message)
	if (rc ~= mc.MERROR_NOERROR) then
		ToolForks.Error("Tool Change FATAL ERROR %d: %s", rc, message)
		return false
	else
		return true
	end
end

ToolChange.internal.Initialize()

function ToolChange.OpenDrawBar()
	MCTry("OpenDrawBar", mc.mcSignalSetState, ToolChange.internal.drawBarSigHandle, 1)
end

function ToolChange.CloseDrawBar()
	MCTry("CloseDrawBar", mc.mcSignalSetState, ToolChange.internal.drawBarSigHandle, 0)
end

function ToolChange.DoManualToolChangeWithMessage(message)
	local rc = mc.mcCntlCycleStop(ToolChange.internal.inst) 
	ToolChange.internal.CheckForNoError(rc, "CycleStop")
	ToolChange.GotoManualToolChangeLocation()
	wx.wxMessageBox(message)

	-- COPIED from Avid m6.mcs
	-- TODO: make this better....and look at how Avid's code handles the "In_Progress" register
	-- Set state for tool change output signal
	local hreg_inProgress, rc = mc.mcRegGetHandle(ToolChange.internal.inst, "iRegs0/AvidCNC/ToolChange/MTC/In_Progress");
	if (rc ~= mc.MERROR_NOERROR) then
		-- Failure to acquire register handle
		mc.mcCntlLog(ToolChange.internal.inst, "Avid: Manual tool change, failure to acquire register handle. rc="..rc, "", -1);
	else
		mc.mcRegSetValue(hreg_inProgress, 1);
	end

end

function ToolChange.GetSlideValuesForOrientation(orientation)
	-- compute the slide amount; based on the center of the tool fork, where do we need to be
	-- to remove the tool 
	-- or where do we need to be at the start to put the tool back before the final position
	local x = 0.0
	local y = 0.0
	local slideDistance = ToolForks.GetSlideDistance()
	if orientation == ToolForks.ToolForkOrientation.X_Plus then
		-- Facing right, slide left. So we have to start furter away on the x pos axis
		x = slideDistance
	elseif orientation == ToolForks.ToolForkOrientation.X_Minus then
		-- Facing left, slide right..so we have to start further towards x minus
		x = -1.0 * slideDistance
	elseif orientation == ToolForks.ToolForkOrientation.Y_Plus then
		-- facing back, we have to be further away and add the value
		y = slideDistance
	elseif orientation == ToolForks.ToolForkOrientation.Y_Minus then
		-- faccing forward, we have to be closer, so we subtract
		y = -1.0 * slideDistance
	else
		assert("Unknown orientation: "..orientation)
	end
	return x, y
end

function ToolChange.internal.VerifyToolForkPreConditions(toolForkPosition)
	assert(toolForkPosition ~= nil)
	-- all 0's is probably bad data or corruption. 
	assert(not (toolForkPosition.X == 0 and toolForkPosition.Y == 0 and toolForkPosition.Z == 0))
	-- TODO: assert that the spindle is off
end

function ToolChange.internal.GetToolForkEntryPosition(toolForkPosition)
	local slideX, slideY = ToolChange.GetSlideValuesForOrientation(toolForkPosition.Orientation)
	local initialX = toolForkPosition.X + slideX
	local initialY = toolForkPosition.Y + slideY
	return initialX, initialY
end

-- returns true if it worked; false otherwise and should stop next stuff
-- Post conditin: spindle left open!
function ToolChange.PutToolBackInForkAtPosition(toolForkPosition)
	ToolChange.internal.VerifyToolForkPreConditions(toolForkPosition)

	local initialX, initialY = ToolChange.internal.GetToolForkEntryPosition(toolForkPosition)
	local zPos = toolForkPosition.Z
	if (ToolChange.debug.TEST_AT_Z_0) then
		zPos = -1.0
	end

	ToolForks.Log("Putting T"..toolForkPosition.Tool.." back to pocket "..toolForkPosition.Number)

	-- G00 - Rapid
	-- G90 – Absolute position mode
	-- G53 – Machine Coordinate System
	-- G01 - Linear Feed Move; needs a feed rate

	-- Rapid to z0 so we are at a safe distance
	MCCntlGcodeExecuteWait("G00 G90 G53 Z0.0")

	---------- Put the tool back in the fork
	-- Go to the X/Y position for the slide in to start
	MCCntlGcodeExecuteWait("G00 G53 X%.4f Y%.4f", initialX, initialY) 
	
	ToolChange.DoWaitFromLastSpindleStop() -- wait for the spindle to stop, if needed.
	
	  -- Go down to the Z position
	MCCntlGcodeExecuteWait("G00 G53 Z%.4f", zPos)

	-- Slide into the fork/pocket
	MCCntlGcodeExecuteWait("G00 G53 X%.4f Y%.4f\n", toolForkPosition.X, toolForkPosition.Y)

	-- Dwell for a brief moment; if the user e-stops the above movements, we will sometimes execute the next line.
	-- we don't want to drop the tool, so a quick dwell will throw an exception if we are now in an eStop state
	MCCntlGcodeExecuteWait("G04 P%.4f", 0.1)

	ToolChange.OpenDrawBar()

	-- give the tool a brief moment to pop out. I tried it without this, and it almost pulled my fork off.
	-- my machine takes a bit for the tool to pop out.
	MCCntlGcodeExecuteWait("G04 P%.4f", 0.3) 

	-- Tool is released; raise the spindle up to the clearance height
	local ZClearanceWithNoTool = ToolForks.GetZClearanceWithNoTool()

	MCCntlGcodeExecuteWait("G00 G90 G53 Z%.4f", ZClearanceWithNoTool)
end

-- Post condition: spindle closed, but only on success (returning true)
function ToolChange.LoadToolAtForkPosition(toolForkPosition, toolWasDroppedOff)
	ToolChange.internal.VerifyToolForkPreConditions(toolForkPosition)
	
	ToolForks.Log("Loading T"..toolForkPosition.Tool.." from Pocket "..toolForkPosition.Number)

	local finalX, finalY = ToolChange.internal.GetToolForkEntryPosition(toolForkPosition)
	local startX = toolForkPosition.X
	local startY = toolForkPosition.Y
	local zPos = toolForkPosition.Z

	if (ToolChange.debug.TEST_AT_Z_0) then
		zPos = -1.0
	end

	------ Move Z to home position to avoid hitting anything when moving to the ATC rack;
	-- we don't have to do this if we dropped of a tool, and use our clearance height for that.
	local zClearanceWithNoTool = 0.0
	if toolWasDroppedOff then
		zClearanceWithNoTool  = ToolForks.GetZClearanceWithNoTool()
	end
	
	MCCntlGcodeExecuteWait("G00 G90 G53 Z%.4f", zClearanceWithNoTool)

	-- Go to the fork's x/y
	MCCntlGcodeExecuteWait("G00 G90 G53 X%.4f Y%.4f", startX, startY) -- rapid here is okay

	ToolChange.DoWaitFromLastSpindleStop() -- wait for the spindle to stop...we should always have a stopped spindle at this point

	-- Dwell for a brief moment; if the user e-stops the above movements, we will sometimes execute the next line.
	-- we don't want to drop the tool, so a quick dwell will throw an exception if we are now in an eStop state
	MCCntlGcodeExecuteWait("G04 P%.4f", 0.1)

	-- Make sure the drawbar is open
	ToolChange.OpenDrawBar()

	-- Go to the fork's z to get the tool, going a little higher by the zbump
	MCCntlGcodeExecuteWait("G00 G90 G53 Z%.4f", zPos + ToolForks.GetZBump()) -- rapid here seems scary..but okay

	ToolChange.CloseDrawBar()

	MCCntlGcodeExecuteWait("G04 P%.4f", 0.2)

	-- Goes back down to zPos after being higher by the ToolForks.ZBump ...so we can slide out safely
	MCCntlGcodeExecuteWait("G01 G90 G53 Z%.4f F50.0\n", zPos)
	-- Slide out
	MCCntlGcodeExecuteWait("G0 G90 G53 X%.4f Y%.4f\n", finalX, finalY)

	------ Move Z to home position ------
	MCCntlGcodeExecuteWait("G00 G90 G53 Z0.0\n")
end

function ToolChange.GotoManualToolChangeLocation()
	-- TODO: go to a nice spot to do this
	-- re use the avid spot..
	

end

-- returns the current state
function ToolChange.internal.SaveState()
	savedState = {}
	savedState.feedRate = mc.mcCntlGetPoundVar(ToolChange.internal.inst, 2134)  --  mc.FEEDRATE ? 
	savedState.feedMode = mc.mcCntlGetPoundVar(ToolChange.internal.inst, 4001) -- 4001 // Group 1 // active G-code for motion ????????
	savedState.absMode = mc.mcCntlGetPoundVar(ToolChange.internal.inst, 4003) -- 4003 // Group 3 // absolute or incremental
	return savedState
end

function ToolChange.internal.RestoreState(state)
	assert(state ~= nil)
	mc.mcCntlSetPoundVar(ToolChange.internal.inst, 2134, state.feedRate) -- mc.FEEDRATE?
	mc.mcCntlSetPoundVar(ToolChange.internal.inst, 4001, state.feedMode)
	mc.mcCntlSetPoundVar(ToolChange.internal.inst, 4003, state.absMode)
end

function ToolChange.internal.TurnOffSpindle()
	-- OKAY! Some post processors will turn off the spindle; if they did, the m5 script
	-- can set the lastSpindleStopTime, and we can wait the appropriate amount of time
	-- If it didn't..or it didn't set the bit..then we don't wait..which might be bad.
	-- I'm not sure a better way to do this...maybe a PLC check
	
	-- Just turn it off... calling M5 via gcode was hanging for me if the script was customized,
	-- but we can call if it is not nil meaning it is around in the process. A work around.
	-- The m5 script should set the lastSpindleStopTime variable when it did turn off the spindle, but just in 
	-- case, we will set it here if the spindle is running
	local dir, rc = mc.mcSpindleGetDirection(ToolChange.internal.inst)
	if dir ~= mc.MC_SPINDLE_OFF then
		ToolChange.lastSpindleStopTime = os.clock()
	end	
	
	if m5 ~= nil then
		-- is this global
		ToolForks.Log("calling M5 directly")
		m5()
	else
		ToolForks.Log("No m5 to call...doing gcode")
		MCCntlGcodeExecuteWait("M5") -- spindle stop
		ToolChange.lastSpindleStopTime = os.clock() -- make sure we wait...because there wasn't a customized script		
	end
end

function ToolChange.DoToolChange()
	-- Always get the latest from the file; the UI may have edited it, which is in a different process
	ToolForks.LoadToolForkPositions()
	local selectedTool = mc.mcToolGetSelected(ToolChange.internal.inst)
	local currentTool = mc.mcToolGetCurrent(ToolChange.internal.inst)
	ToolChange.DoToolChangeFromTo(currentTool, selectedTool)
end


function ToolChange.DoToolChangeFromTo(currentTool, selectedTool) 	
	local result, errorMessage = pcall(ToolChange._TryDoToolChangeFromTo, currentTool, selectedTool)
	if not result then
		-- try to cycle stop!
		mc.mcCntlCycleStop(ToolChange.internal.inst) 
		ToolForks.Error(errorMessage)
	end
end

function ToolChange.DoWaitFromLastSpindleStop()
	local secondsSinceSpindleStopped = os.clock() - ToolChange.lastSpindleStopTime
	local waitTime = ToolForks.GetDwellTime() -- in seconds
	if secondsSinceSpindleStopped > 0 then -- should always be > 0..if it isn't, then we use the full dwell, because something is wrong
		waitTime = waitTime - secondsSinceSpindleStopped		
	else
		error("Negative wait time...")
	end
	
	ToolForks.Log("Wait time: %.3f", waitTime);
	if waitTime > ToolForks.GetDwellTime() then
		ToolForks.Log("What? Bad wait time?")
		waitTime = ToolForks.GetDwellTime()
	end
	
	
	if waitTime > 0 then
		MCCntlGcodeExecuteWait("G04 P%.4f", waitTime)
	end
end

function ToolChange.SaveCurrentLocation()	
	local inst = ToolChange.internal.inst
	ToolChange.lastX = mc.mcAxisGetMachinePos(inst, mc.X_AXIS)
	ToolChange.lastY = mc.mcAxisGetMachinePos(inst, mc.Y_AXIS)
	ToolForks.Log("Saved machine X: "..ToolChange.lastX.." Y:".. ToolChange.lastY);	
end

function ToolChange.RestoreLastLocation() 
	-- Rapid to z0 so we are at a safe distance
	MCCntlGcodeExecuteWait("G00 G90 G53 Z0.0")
	
	MCCntlGcodeExecuteWait("G00 G53 X%.4f Y%.4f", ToolChange.lastX, ToolChange.lastY)	
end

-- may throw an exception/error
function ToolChange._TryDoToolChangeFromTo(currentTool, selectedTool)
	if (selectedTool == currentTool) then
		-- not really an error..but useful to see
		ToolForks.Error(string.format("TOOL CHANGE: Tool %d already selected. Skipping tool change.", selectedTool))
		return 
	end
	
	ToolChange.internal.TurnOffSpindle()
	ToolChange.SaveCurrentLocation()

	if (ToolChange.debug.TEST_AT_Z_0) then
		-- warn the user to not have any tools in the thing, otherwise they will get dropped
		local rc = wx.wxMessageBox("WARNING: Test height enabled - make sure there are no tools in the spindle. \nWould you like to continue?", 
			"Tool Warning", wx.wxYES_NO)
		if rc ~= wx.wxYES then
			ToolForks.Error("User stopped the test tool change.")
			do return end
		end
	end

	local currentPosition = ToolForks.GetToolForkPositionForTool(currentTool)
	local selectedPosition = ToolForks.GetToolForkPositionForTool(selectedTool)
	if currentPosition ~= nil and selectedPosition ~= nil then
		ToolForks.Log("Doing tool change from %d to %d, from pocket %d to pocket %d", currentTool, selectedTool, 
			currentPosition.Number, selectedPosition.Number)
	end


	-- TODO: If currentTool is tool 0, ask the user to ensure the spindle has no tool in it!
	if currentPosition == nil then		
		if currentTool == 0 then
			-- Maybe don't awlays show this warning..I'm starting to not like it
			local rc = wx.wxMessageBox("Starting from Tool 0. Ensure the spindle is empty. \nWould you like to continue?", 
				"Tool Warning", wx.wxYES_NO)
			if rc ~= wx.wxYES then
				error("User aborted tool change")
			end
		else		
			-- Current tool has to be manually removed. The user has to remove it and then insert the next tool..which might be in a fork. 
			-- We could make this better by checking that ..but continuing after a stop requires more logic that I'm not sure how to handle, especially if the user has to measure the tool height.
			local message = string.format("Current tool T%d has no tool fork holder to go back to.\nRemove it and manually install tool T%d and continue", currentTool, selectedTool)
			ToolChange.DoManualToolChangeWithMessage(message)
			do return end -- not an error...early return
		end
	end

	local state = ToolChange.internal.SaveState() -- don't do returns in the middle of a method after this
	-- Maybe do a pcall to ensure we can restore the state (which may not work!)
	-- and re-throw the error if caught..however, restoring state will fail because gcode calls fail on the estop state
	-- until the user clears it...so, don't worry about it
	if currentPosition ~= nil then
		ToolChange.PutToolBackInForkAtPosition(currentPosition)
	end

	-- If the next selected tool does not have a position, then the user has to insert it. 
	-- At least we dropped off the current tool before doing this to save them some time.
	if selectedPosition ~= nil then
		local toolWasDroppedOff = currentPosition ~= nil
		ToolChange.LoadToolAtForkPosition(selectedPosition, toolWasDroppedOff)
		mc.mcToolSetCurrent(ToolChange.internal.inst, selectedTool)
		ToolForks.Error("Tool change done. Current tool now: T%d", selectedTool)
	elseif selectedTool == 0 then
		-- going to tool 0 means having no tool in the holder
		ToolChange.CloseDrawBar()
		mc.mcToolSetCurrent(ToolChange.internal.inst, selectedTool)
		ToolForks.Error("Tool change done. Current tool now: T%d", selectedTool)
	else
		local message = string.format("Selected Tool T%d has no Tool Fork Position.\nManually install it and continue.", selectedTool)
		ToolChange.CloseDrawBar()
		ToolChange.DoManualToolChangeWithMessage(message)
	end

	ToolChange.RestoreLastLocation() 

	ToolChange.internal.RestoreState(state)
end

function ToolChange.internal.TestToolChange()
	local currentTool = mc.mcToolGetCurrent(ToolChange.internal.inst)
	ToolChange.DoToolChangeFromTo(currentTool, 0)
end

if (mc.mcInEditor() == 1) then
	--ToolChange.internal.TestToolChange()
end

return ToolChange
