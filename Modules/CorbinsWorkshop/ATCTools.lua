
-- ATCTools.lua
-- by Corbin Dunn
-- Feb 21, 2023
-- corbin@corbinstreehouse.com or corbin@corbinsworkshop.com
-- Blog: https://www.corbinstreehouse.com
-- Files/Prodcuts: https://www.corbinsworkshop.com
-- (c) 2023 Corbin Dunn
-- Software provided as-is. For redistribution rights, please contact me.

-- These are called from the ATC Tools tab. It is way easier to track changes in a text file rather than a binary file.

-- PLC Script must call ATCTools.PLCScript() for the Height offset LED to work right

local ATCTools = {
	MaxToolForkCount = 10, -- Increase if you have more tools, and update the UI to have more items
	Visible = false
}

package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
local ToolForks = require 'ToolForks'

if ToolChange == nil then
	ToolChange = require 'ToolChange'
end

function ATCTools.OnToolForkToolChanged(toolFork)
	local s = string.format("droToolForToolFork%d", toolFork.Number)
	scr.SetProperty(s, "Value", tostring(toolFork.Tool))

	s = string.format("txtToolDescForToolFork%d", toolFork.Number)
	local v = ""
	if toolFork.Tool > 0 then            
		v = ToolForks.GetToolDescription(toolFork.Tool)
		scr.SetProperty(s, "Enabled", "1")
	else
		scr.SetProperty(s, "Enabled", "0")
	end
	scr.SetProperty(s, "Value", v)

	s = string.format("lblHeightForToolFork%d", toolFork.Number)
	if toolFork.Tool > 0 then
		local height, rc = mc.mcToolGetData(inst, mc.MTOOL_MILL_HEIGHT, toolFork.Tool)	
		v = string.format("%3.4f", height)
	else
		v = ""		
	end
	scr.SetProperty(s, "Label", v)

	s = string.format("grpToolFork%d", toolFork.Number)
	local currentTool = mc.mcToolGetCurrent(inst)
	if currentTool == toolFork.Tool and currentTool > 0 then
		scr.SetProperty(s, "Bg Color", "#80FF80") -- green
	else
		scr.SetProperty(s, "Bg Color", "#FFFFFF") -- white
	end


end

function ATCTools.PLCScript()
	-- Update the LED for the height offset.
	local HOState = mc.mcCntlGetPoundVar(inst, 4008)
	if (HOState == 49) then
		scr.SetProperty("ledATCHeightActive", "Value", "0")
	else
		scr.SetProperty("ledATCHeightActive", "Value", "1")
	end	

end


function ATCTools.OnTabShow()
	ATCTools.Visible = true
	ToolForks.LoadToolForkPositions()
	local lastFork = 0

	local count = ToolForks.GetToolForkCount() 
	if count > 50 then
		ToolForks.Error("Too many tool pockets - %d Bad Tool Pockets file at: %s",  count, ToolForks.GetToolForkFilePath())
		do return end
	end

	for i=1, count do
		local toolFork = ToolForks.GetToolForkNumber(i)
		if toolFork == nil or toolFork.Number ~= i then
			ToolForks.Error("No tool pocket? Bad Tool Pockets file at: %s", ToolForks.GetToolForkFilePath())
			do return end
		end

		local s = nil
		local v = nil

		s = string.format("grpToolFork%d", i)
		scr.SetProperty(s, "Hidden", "0") -- could be disabled from earlier

		s = string.format("lblToolFork%d", i)
		scr.SetProperty(s, "Label", tostring(i))

		ATCTools.OnToolForkToolChanged(toolFork)
		lastFork = i
	end
	-- disable the UI & groups past this
	for i = lastFork+1, ATCTools.MaxToolForkCount do
		s = string.format("grpToolFork%d", i)
		scr.SetProperty(s, "Hidden", "1") -- could be disabled from earlier
	end

end

function ATCTools.OnTabHide()
	ATCTools.Visible = false

end

function ATCTools.ValidateOnModifyArgs(...)
	local value = select(1, ...)
	local ctrlName = select(2, ...)

	assert(value ~= nil)
	assert(ctrlName ~= nil)

	local toolForkNumber = string.match(ctrlName, "%d")
	if toolForkNumber == nil then
		wx.wxMessageBox("Programming Error", "ATCTools - caller doesn't have the control name setup right")
	end
	return toolForkNumber, value, ctrlName
end


function ATCTools.OnModifyToolForkForTool(...)
	local toolForkNumber, value, ctrlName = ATCTools.ValidateOnModifyArgs(...)
	if toolForkNumber == nil then
		return
	end

	ToolForks.Log("OnModifyToolForkForTool TF%d %s %s", toolForkNumber, ctrlName, value)
	local tool = tonumber(value)
	-- validation? 

	--- is the tool already in another fork?
	local existingTF = ToolForks.GetToolForkPositionForTool(tool)
	local tf = ToolForks.GetToolForkNumber(toolForkNumber)

	local keepGoing = true

	if (existingTF ~= nil) and (tf ~= existingTF)  then
		local message = string.format("T%d is already in Tool Pocket %d. First remove it from that Tool Procket and then try again.", tool, existingTF.Number)
		local rc = wx.wxMessageBox(message, "Tool Setup Error")
		keepGoing = false
		tool = tf.Tool -- go back to whatever it had in it before
	end

	if keepGoing then 
		-- does the fork already have a tool in it that isn't this tool?
		if tf.Tool > 0 and tf.Tool ~= tool then
			local message = string.format("Tool Pocket %d already contains T%d.\nOverwrite the tool with T%d?", toolForkNumber, tf.Tool, tool)
			local rc = wx.wxMessageBox(message, "Tool Setup Error", wx.wxYES_NO)
			if rc ~= wx.wxYES then
				-- go back to the prior value (TODO: TEST)
				tool = tf.Tool
			end
		end
		if tf.Tool ~= tool then
			tf.Tool = tool
			ToolForks.SaveToolForkPositions()
			ATCTools.OnToolForkToolChanged(tf)
		end
	end

	-- update the text in case we went back to the old value
	scr.SetProperty(ctrlName, "Value", tostring(tool))
end

function ATCTools.OnModifyToolDescription(...)
	local toolForkNumber, value, ctrlName = ATCTools.ValidateOnModifyArgs(...)
	if toolForkNumber == nil then
		return
	end
	-- get the tool that is set for this fork
	local tf = ToolForks.GetToolForkNumber(toolForkNumber)
	-- checks should always pass when this is called..
	if tf ~= nil and tf.Tool > 0 then
		ToolForks.SetToolDescription(tf.Tool, value)
	end
end

function ATCTools.OnFetchButtonClicked(...)
	if not ATCTools.IsHomed() then
		wx.wxMessageBox("Machine is not homed, it is not safe\nto fetch a tool.", "Automatic Tool Change")		
		return
	end
	
	local ctrlName = select(1, ...)
	local toolForkNumber = string.match(ctrlName, "%d")
	assert(toolForkNumber ~= nil, "Bad UI setup for tool forks, ctrlName:"..ctrlName)

	local tf = ToolForks.GetToolForkNumber(toolForkNumber)
	if tf == nil then
		ToolForks.Error("ATCTools Error: No tool pocket for position #%d",  toolForkNumber)		
		return
	end
--TODO: use the GCode calling wrappers I have in ToolChange, so it throws on an error
	local GCode = string.format("M6 T%d G43 H%d", tf.Tool, tf.Tool)
	local rc = mc.mcCntlMdiExecute(ToolChange.internal.inst, GCode)
	if not ToolChange.internal.CheckForNoError(rc, "Fetch tool: "..GCode) then
		return
	end	

	-- bring it to the MTC location?	
end

function ATCTools.OnRemoveButtonClicked(...) 
	local ctrlName = select(1, ...)
	local toolForkNumber = string.match(ctrlName, "%d")
	local tf = ToolForks.GetToolForkNumber(toolForkNumber)
	if tf ~= nil then
		tf.Tool = 0
		ToolForks.SaveToolForkPositions()
		ATCTools.OnToolForkToolChanged(tf)
	end

end

function ATCTools.OnTouchOffClicked(...)
	local ctrlName = select(1, ...)
	local toolForkNumber = string.match(ctrlName, "%d")
	-- TODO: code..
end

function ATCTools.CurrentToolChanged()
	if ATCTools.Visible then
		ATCTools.OnTabShow() -- reload to show the active tool in green
	end
end

function ATCTools.IsHomed()
	local xHomed = mc.mcAxisIsHomed(ToolChange.internal.inst, mc.X_AXIS)
	local yHomed = mc.mcAxisIsHomed(ToolChange.internal.inst, mc.Y_AXIS)
	local zHomed = mc.mcAxisIsHomed(ToolChange.internal.inst, mc.Z_AXIS)
	return xHomed and yHomed and zHomed
end

function ATCTools.PutBackCurrentTool()
	if not ATCTools.IsHomed() then
		wx.wxMessageBox("Machine is not homed, it is not safe\nto put back a tool.", "Automatic Tool Change")		
		return
	end	
	
	local currentTool = mc.mcToolGetCurrent(ToolChange.internal.inst)
	if currentTool > 0 then
		ToolChange.DoToolChangeFromTo(currentTool, 0)
	else
		
	end
end



function ATCTools.DoM6G43(tool)
	tool = tonumber(tool)
	-- If that tool is in a pocket, then maybe ask the user if we should go get it?
--	local tf = ToolForks.GetToolForkPositionForTool(tool)
--	if tf ~= nil then
--		local message = string.format("Tool T%d is in Pocket %d.\nWould you like to fetch it from the rack?",
--			tf.Tool, tf.Number)
--		local rc = wx.wxMessageBox(message, "Fetch the tool?", wx.wxYES_NO)
--		if rc == wx.wxYES then	
--			-- TODO: Manually call the ToolChange function here.
--			-- doing an M6 won't work, because the current tool will already be set by the DRO, and it wouldn't do anything
			
--		end
--	else
--		-- If it isn't in a pocket, assume they put it there manually. 
--		-- Activate the height; the DRO should already have set the tool.	
--	end

	local GCode = string.format("G43 H%d", tool)
	ToolForks.Error("Executing: "..GCode)
	
	local rc = mc.mcCntlMdiExecute(ToolChange.internal.inst, GCode)
	if not ToolChange.internal.CheckForNoError(rc, "Error setting tool height:"..GCode) then
		return
	end		
end



if (mc.mcInEditor() == 1) then
	-- Easier testing.. to do stuff here
	--ATCTools.DoM6G43(0)

end


return ATCTools