
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
	MaxToolForkCount = 10 -- Increase if you have more tools, and update the UI to have more items
}

package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
local ToolForks = require 'ToolForks'

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
	ToolForks.LoadToolForkPositions()
	local lastFork = 0

	for i=1, ToolForks.GetToolForkCount() do
		local toolFork = ToolForks.GetToolForkNumber(i)
		assert(i == toolFork.Number)
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
	for i = lastFork, ATCTools.MaxToolForkCount do
		s = string.format("grpToolFork%d", i)
		scr.SetProperty(s, "Hidden", "0") -- could be disabled from earlier
	end

end


function ATCTools.OnModifyToolForkForTool(toolForkNumber, toolValue)
	ToolForks.Log("OnModifyToolForkForTool%d, %s", toolForkNumber, toolValue)

	local tool = tonumber(toolValue)
	-- validation? 

	--- is the tool already in another fork?
	local existingTF = ToolForks.GetToolForkForTool(tool)
    local tf = ToolForks.GetToolForkNumber(toolForkNumber)
    
	local keepGoing = true

	if (existingTF ~= nil) and (tf ~= existingTF)  then
		local message = string.format("T%d is already in Tool Fork %d. First remove it from that Tool Fork and then try again.", tool, existingTF.Number)
		local rc = wx.wxMessageBox(message, "Tool Setup Error")
		keepGoing = false
		tool = tf.Tool -- go back to whatever it had in it before
	end

	if keepGoing then 
		-- does the fork already have a tool in it that isn't this tool?
		if tf.Tool > 0 and tf.Tool ~= tool then
			local message = string.format("Tool Fork %d already contains T%d.\nOverwrite the tool with T%d?", toolForkNumber, tf.Tool, tool)
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
	local s = string.format("droToolForToolFork%d", toolForkNumber)
	scr.SetProperty(s, "Value", tostring(tool))
end

function ATCTools.OnModifyToolDescription(toolForkNumber, value)
	-- get the tool that is set for this fork
	local tf = ToolForks.GetToolForkNumber(toolForkNumber)
	-- checks should always pass when this is called..
	if tf ~= nil and tf.Tool > 0 then
		ToolForks.SetToolDescription(tf.Tool, value)
	end
end

function ATCTools.OnFetchButtonClicked(toolForkNumber)

end

function ATCTools.OnRemoveButtonClicked(toolForkNumber) 
	local tf = ToolForks.GetToolForkNumber(toolForkNumber)
	if tf ~= nil then
		tf.Tool = 0
		ToolForks.SaveToolForkPositions()
		ATCTools.OnToolForkToolChanged(tf)
	end

end

function ATCTools.OnTouchOffClicked(toolNumber)


end

function ATCTools.CurrentToolChanged()
	ATCTools.OnTabShow() -- reload to show the active tool in green
end



if (mc.mcInEditor() == 1) then
	-- Easier testing.. to do stuff here

--	ToolForks.LoadToolForkPositions()
--	ATCTools.OnModifyToolForkForTool(1, "5")
--	print("done")

--	ToolForks.AddToolForkPosition()
--	SaveToolForkPositions()

end


return ATCTools