
-- ToolChange.lua
-- by Corbin Dunn
-- Feb 21, 2023
-- corbin@corbinstreehouse.com or corbin@corbinsworkshop.com
-- Blog: https://www.corbinstreehouse.com
-- Files/Prodcuts: https://www.corbinsworkshop.com
-- (c) 2023 Corbin Dunn
-- Software provided as-is. For redistribution rights, please contact me.

-- TODO: UI customization for this ... or pass it in from M6
local DRAWBAR_SIGNAL_OUTPUT = mc.OSIG_OUTPUT6

local ToolChange = {
    internal = {
        inst = nil,
        drawBarSigHandle = nil,        
    }
}

package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
local ToolForks = require 'ToolForks'

local TEST_AT_Z_0 = true -- set to true to debug the slide at z 0...don't have any tools in, otherwise they will get dropped!
local USE_SLOW_FEED_RATES = true -- if true, G01 at F25. if false, G0.

-----------------------

-- must be the first thing called, and this file calls it.
function ToolChange.internal.Initialize()
    ToolChange.internal.inst = mc.mcGetInstance("ToolChange.lua")
    ToolChange.internal.drawBarSigHandle, rc = mc.mcSignalGetHandle(ToolChange.internal.inst, DRAWBAR_SIGNAL_OUTPUT)
    ToolChange.internal.CheckForNoError(rc, "Getting drawbar signal")
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
    local rc = mc.mcSignalSetState(ToolChange.internal.drawBarSigHandle, 1)
    return ToolChange.internal.CheckForNoError(rc, "OpenDrawBar")
end

function ToolChange.CloseDrawBar()
    local rc = mc.mcSignalSetState(ToolChange.internal.drawBarSigHandle, 0)
    return ToolChange.internal.CheckForNoError(rc, "CloseDrawBar")
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
    -- compute the slide amount
    local x = 0.0
    local y = 0.0
	local slideDistance = ToolForks.GetSlideDistance()
    if orientation == ToolForks.ToolForkOrientation.X_Plus then
        -- Facing right, slide left (Minuative)
        x = -1.0 * slideDistance
    elseif orientation == ToolForks.ToolForkOrientation.X_Minus then
        -- Facing left, slide right
        x = slideDistance
    elseif orientation == ToolForks.ToolForkOrientation.Y_Plus then
        -- facing back, slide forward (negative)
        y = -1.0 * slideDistance
    elseif orientation == ToolForks.ToolForkOrientation.Y_Minus then
        -- fadcing forward, slide back (positive)
        y = slideDistance
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
    local initialX = toolForkPosition.X - slideX
    local initialY = toolForkPosition.Y - slideY
    return initialX, initialY
end

function ToolChange.internal.GetRapidFeedGCode()
    if USE_SLOW_FEED_RATES then
        return "G01 F25"
    else
        return "G00"
    end
end

-- returns true if it worked; false otherwise and should stop next stuff
-- Post conditin: spindle left open!
function ToolChange.PutToolBackInForkAtPosition(toolForkPosition, toolNumber)
    ToolChange.internal.VerifyToolForkPreConditions(toolForkPosition)

    local initialX, initialY = ToolChange.internal.GetToolForkEntryPosition(toolForkPosition)
    local zPos = toolForkPosition.Z
    if (TEST_AT_Z_0) then
        zPos = 0
    end
    local feedRate = ToolChange.internal.GetRapidFeedGCode()
    -- G00 - Rapid
    -- G90 – Absolute position mode
    -- G53 – Machine Coordinate System
    -- G01 - Linear Feed Move; needs a feed rate
    local GCode = ""
    GCode = GCode .. "G00 G90 G53 Z0.0\n" -- Rapid to z0 
    ---------- Put the tool back in the fork
    GCode = GCode .. string.format("%s G53 X%.4f Y%.4f\n", feedRate, initialX, initialY) -- Go to the X/Y position for the slide in to start
    GCode = GCode .. string.format("%s G53 Z%.4f\n", feedRate, zPos)  -- Go down to the Z position
    GCode = GCode .. string.format("G01 F25 G53 X%.4f Y%.4f\n", feedRate, toolForkPosition.X, toolForkPosition.Y) -- Slide slowly (maybe make this faster...or consider G00, which some other scripts have done)

    ToolForks.Log("Putting T"..toolNumber.." back and executing GCode:")
    ToolForks.Log(GCode)

    local rc = mc.mcCntlGcodeExecuteWait(ToolChange.internal.inst, GCode)

    -- don't continue to open the drawbar if we had an error! We could be dropping a tool.    
    if ToolChange.internal.CheckForNoError(rc, "ToolChange.PutToolBackInForkAtPosition") then
        if OpenDrawBar() then
            ------ Raise spindle, after releasing tool at 50 IPM (probably doesn't have to go to Z0)
            -- TODO: corbin - raise height can be some relative height from the Z to clear everything, or we could rapid to it after slowly moving up a certain distance.
            GCode = "" 
            GCode = GCode .. string.format("G01 G90 G53 Z0.00 F50.0\n")
            rc = mc.mcCntlGcodeExecuteWait(ToolChange.internal.inst, GCode)
            if ToolChange.internal.CheckForNoError("ToolChange.PutToolBackInForkAtPosition") then
                return true
            end
        end
    end
    return false
end

-- Precondition: Spindle open!
-- Post condition: spindle closed
function ToolChange.LoadToolAtForkPosition(toolForkPosition, toolNumber)
    ToolChange.internal.VerifyToolForkPreConditions(toolForkPosition)

    local finalX, finalY = ToolChange.internal.GetToolForkEntryPosition(toolForkPosition)
    local zPos = toolForkPosition.Z
    if (TEST_AT_Z_0) then
        zPos = 0
    end
    local feedRate = ToolChange.internal.GetRapidFeedGCode()

    local GCode = ""
    -- Go to the fork's x/y
    GCode = GCode .. string.format("%s G90 G53 X%.4f Y%.4f\n", feedRate, XPos, YPos) -- rapid here is okay
    -- Go to the fork's z to put in the tool
    GCode = GCode .. string.format("%s G90 G53 Z%.4f\n", feedRate, ZPos + ToolForks.ZBump) -- rapid here seems scary..but okay

    local rc = mc.mcCntlGcodeExecuteWait(ToolChange.internal.inst, GCode) -- 
    if ToolChange.internal.CheckForNoError(rc, "ToolChange.LoadToolAtForkPosition 1") then
        if CloseDrawBar() then
            GCode = ""
            -- Goes back down to zPos after being higher by the ToolForks.ZBump ...so we can slide out safely
            GCode = GCode .. string.format("G01 G90 G53 Z%.4f F50.0\n", ZPos)
            -- Slide out
            GCode = GCode .. string.format("%s G90 G53 X%.4f Y%.4f\n", feedRate, finalX, finalY)
            rc = mc.mcCntlGcodeExecuteWait(ToolChange.internal.inst, GCode) 
            if ToolChange.internal.CheckForNoError(rc, "ToolChange.LoadToolAtForkPosition 2") then
                ------ Move Z to home position ------
                GCode = string.format("%s G90 G53 Z0.0\n", feedRate)
                rc = mc.mcCntlGcodeExecuteWait(ToolChange.internal.inst, GCode)
                if ToolChange.internal.CheckForNoError(rc, "ToolChange.LoadToolAtForkPosition 3") then
                    return true
                end
            end                        
        end
    end
    return false
end

function ToolChange.GotoManualToolChangeLocation()
        -- TOD: go to a nice spot to do this

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

function ToolChange.internal.TurnOffSpindleAndWait()
    -- TODO: start x/y movement while this is happening..do a time to make sure it lasts at least the dwell time, and if it hasn't..dwell for a while
    local GCode = ""
    GCode = GCode .. "M5\n"
    GCode = GCode .. string.format("G04 P%.4f\n", ToolForks.GetDwellTime())
    local rc = mc.mcCntlGcodeExecuteWait(ToolChange.internal.inst, GCode)
    return ToolChange.internal.CheckForNoError(rc, "TurnOffSpindleAndWait")
end


function ToolChange.DoToolChange()
    local selectedTool = mc.mcToolGetSelected(ToolChange.internal.inst)
    local currentTool = mc.mcToolGetCurrent(ToolChange.internal.inst)
    ToolChange.DoToolChangeFromTo(currentTool, selectedTool)
end

function ToolChange.DoToolChangeFromTo(currentTool, selectedTool)

    if (selectedTool == currentTool) then
        -- not really an error..but useful to see
        ToolForks.Error(string.format("Tool %d already selected. Skipping tool change.", selectedTool))
        do return end
    end

--    if ToolForkPositions == nil then
--        wx.wxMessageBox("ToolChange: Invalid setup; nil ToolForkPositions! This is a coding error.\nPerforming Cycle Stop")
--        mc.mcCntlCycleStop(ToolChange.internal.inst)
--        do return end
--    end

    local currentPosition = ToolForks.GetToolForkNumberForTool(currentTool)
    if currentPosition == 0 then
        -- Current tool has to be manually removed. The user has to remove it and then insert the next tool..which might be in a fork. We could make this better by checking that ..but continuing after a stop requires more logic that I'm not sure how to handle, especially if the user has to measure the tool height.
        local message = string.format("Current tool T%d has no tool fork holder to go back to.\nRemove it and manually install tool T%d and continue", currentTool, selectedTool)
        ToolChange.DoManualToolChangeWithMessage(message)
        do return end
    end

    local state = ToolChange.internal.SaveState() -- don't do returns in the middle of a method after this

    -- TODO: start a timer, so we can do the rest of the wait after the moves.
    if ToolChange.internal.TurnOffSpindleAndWait() then 
        ToolChange.PutToolBackInForkAtPosition(currentPosition, currentTool)

        local selectedPosition = ToolForks.GetToolForkNumberForTool(selectedTool)
        -- If the next selected tool does not have a position, then the user has to insert it. At least we dropped off the current tool before doing this.
        if selectedPosition > 0 then
            if ToolChange.LoadToolAtForkPosition(selectedPosition, selectedTool) then
                -- set the new tool on success    
                mc.mcToolSetCurrent(ToolChange.internal.inst, selectedTool)

                -- Not an error..but a message to the user that it worked (for now..)
                ToolForks.Error("Tool change done. Current tool now: T%d", selectedTool)
            end
        else
            local message = string.format("Selected Tool T%d has no Tool Fork Position.\nManuall install it and continue.", selectedTool)
            ToolChange.DoManualToolChangeWithMessage(message)
        end
    else
        ToolForks.Error("Failed to turn off spindle!")
    end

    ToolChange.internal.RestoreState(state)
end

function ToolChange.internal.TestToolChange()
	ToolChange.DoToolChangeFromTo(1, 3)
	
end


if (mc.mcInEditor() == 1) then
	ToolChange.internal.TestToolChange()
end


return ToolChange
