
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
	Visible = false,
	CurrentOffset = 0, -- For more than 10 tools
}

package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"

if ToolForks == nil then
	ToolForks = require 'ToolForks'
end

if ToolChange == nil then
	ToolChange = require 'ToolChange'
end

if CWUtilities == nil then
	CWUtilities= require 'CWUtilities'
end

ATCTools.inst = mc.mcGetInstance("ATCTools.lua")

function ATCTools.OnToolForkToolChanged(toolFork)
	local inst = ATCTools.inst
	local uiIndex = toolFork.Number - ATCTools.CurrentOffset
	
	local s = string.format("droToolForToolFork%d", uiIndex)
	scr.SetProperty(s, "Value", tostring(toolFork.Tool))

	s = string.format("txtToolDescForToolFork%d", uiIndex)
	local v = ""
	if toolFork.Tool > 0 then            
		v = ToolForks.GetToolDescription(toolFork.Tool)
		scr.SetProperty(s, "Enabled", "1")
	else
		scr.SetProperty(s, "Enabled", "0")
	end
	scr.SetProperty(s, "Value", v)

	s = string.format("lblHeightForToolFork%d", uiIndex)
	if toolFork.Tool > 0 then
		local height, rc = mc.mcToolGetData(inst, mc.MTOOL_MILL_HEIGHT, toolFork.Tool)	
		v = string.format("%3.4f", height)
	else
		v = ""		
	end
	scr.SetProperty(s, "Label", v)

	s = string.format("grpToolFork%d", uiIndex)
	local currentTool = mc.mcToolGetCurrent(inst)
	if currentTool == toolFork.Tool and currentTool > 0 then
		scr.SetProperty(s, "Bg Color", "#80FF80") -- green
	else
		scr.SetProperty(s, "Bg Color", "#FFFFFF") -- white
	end


end

function ATCTools.PLCScript()
	local inst = ATCTools.inst
	-- Update the LED for the height offset.
	local HOState = mc.mcCntlGetPoundVar(inst, 4008)
	if (HOState == 49) then
		scr.SetProperty("ledATCHeightActive", "Value", "0")
	else
		scr.SetProperty("ledATCHeightActive", "Value", "1")
	end	

end

function ATCTools.UpdateUI()

	local toolPocketCount = ToolForks.GetToolForkCount() 
	--  some sanity checks...no one has more than 509 pockets
	if toolPocketCount > 50 then
		ToolForks.Error("Too many tool pockets - %d Bad Tool Pockets file at: %s", toolPocketCount, ToolForks.GetToolForkFilePath())
		do return end
	end

	local count = ATCTools.MaxToolForkCount -- UI max is 10, hardcoded
	if toolPocketCount < count then
		count = toolPocketCount
	end
	
	local lastIndex = 0
	
	-- Handle deleting one..
	if ATCTools.CurrentOffset >= toolPocketCount then
		ATCTools.CurrentOffset = 0
	end

	for i=1, count do
		local toolPocketNumber = i + ATCTools.CurrentOffset
		
		local toolFork = ToolForks.GetToolForkNumber(toolPocketNumber)
		if toolFork == nil or toolFork.Number ~= toolPocketNumber then
			ToolForks.Error("No tool pocket? Bad Tool Pockets file at: %s", ToolForks.GetToolForkFilePath())
			do return end
		end

		local s = nil
		local v = nil

		s = string.format("grpToolFork%d", i)
		scr.SetProperty(s, "Hidden", "0") -- could be disabled from earlier

		s = string.format("lblToolFork%d", i)
		scr.SetProperty(s, "Label", tostring(toolPocketNumber))

		ATCTools.OnToolForkToolChanged(toolFork)
		lastIndex = i
		if toolPocketNumber >= toolPocketCount then
			break
		end
	end
	-- disable the UI & groups past this
	for i = lastIndex+1, ATCTools.MaxToolForkCount do
		s = string.format("grpToolFork%d", i)
		scr.SetProperty(s, "Hidden", "1") -- could be disabled from earlier
	end	
	
	

	-- Update the Previous/Next 10 buttons
	if ATCTools.CurrentOffset > 0 then
		scr.SetProperty("btnPrevious10", "Enabled", "1")
	else
		scr.SetProperty("btnPrevious10", "Enabled", "0")		
	end
	
	local lastPocketShown = ATCTools.CurrentOffset + lastIndex
	if toolPocketCount > lastPocketShown then
		scr.SetProperty("btnNext10", "Enabled", "1")
	else
		scr.SetProperty("btnNext10", "Enabled", "0")	
	end
	--ToolForks.Log("CurrentOffset: %d, lastPocketShown %d, toolPocketCount %d",  
	-- ATCTools.CurrentOffset, lastPocketShown, toolPocketCount)
	
	
end

function ATCTools.OnTabShow()
	ATCTools.Visible = true
	ToolForks.LoadToolForkPositions()
	ATCTools.UpdateUI()

end

function ATCTools.OnTabHide()
	ATCTools.Visible = false
end

function ATCTools.ValidateOnModifyArgs(...)
	local value = select(1, ...)
	local ctrlName = select(2, ...)

	assert(value ~= nil)
	assert(ctrlName ~= nil)

	local toolForkNumber = string.match(ctrlName, "%d+")
	if toolForkNumber == nil then
		wx.wxMessageBox("Programming Error", "ATCTools - caller doesn't have the control name setup right")
	end
	-- add in the page offset
	toolForkNumber = toolForkNumber + ATCTools.CurrentOffset
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

function ATCTools.ToolForkForUIItem(ctrlName)
	local toolForkNumber = string.match(ctrlName, "%d+")
	assert(toolForkNumber ~= nil, "Bad UI setup for tool forks, ctrlName:"..ctrlName)

	-- Add in the offset
	toolForkNumber = toolForkNumber + ATCTools.CurrentOffset

	local tf = ToolForks.GetToolForkNumber(toolForkNumber)
	return tf -- may be nil
end


function ATCTools.OnFetchButtonClicked(...)
	if not CWUtilities.IsHomed() then
		wx.wxMessageBox("Machine is not homed, it is not safe\nto fetch a tool.", "Automatic Tool Change")		
		return
	end

	local ctrlName = select(1, ...)
	local tf = ATCTools.ToolForkForUIItem(ctrlName)
	if tf == nil then
		ToolForks.Error("ATCTools Error: No tool pocket for position #%d",  toolForkNumber)		
		return
	end
	ToolForks.Log("Fetching %d from pocket %d, using M6 call on MDI", tf.Tool, tf.Number)
	
--TODO: use the GCode calling wrappers I have in ToolChange, so it throws on an error
	
	local GCode = string.format("M6 T%d G43 H%d", tf.Tool, tf.Tool)	
	local rc = mc.mcCntlMdiExecute(ATCTools.inst, GCode)
	if not ToolChange.internal.CheckForNoError(rc, "Fetch tool: "..GCode) then
		return
	end	

	-- bring it to the MTC location?	
end

function ATCTools.OnRemoveButtonClicked(...) 
	local ctrlName = select(1, ...)
	local tf = ATCTools.ToolForkForUIItem(ctrlName)
	if tf ~= nil then
		tf.Tool = 0
		ToolForks.SaveToolForkPositions()
		ATCTools.OnToolForkToolChanged(tf)
	end

end

function ATCTools.OnTouchOffClicked(...)
	local ctrlName = select(1, ...)
	local tf = ATCTools.ToolForkForUIItem(ctrlName)
	-- TODO: code..
end

function ATCTools.CurrentToolChanged()
	if ATCTools.Visible then
		ATCTools.OnTabShow() -- reload to show the active tool in green
	end
end

function ATCTools.IsHomed()
	-- TODO: Use same method that is in CWUtilities
	return CWUtilities.IsHomed()
end

function ATCTools.PutBackCurrentTool()
	if not CWUtilities.IsHomed() then
		wx.wxMessageBox("Machine is not homed, it is not safe\nto put back a tool.", "Automatic Tool Change")		
		return
	end	
	
	local currentTool = mc.mcToolGetCurrent(ATCTools.inst)
	if currentTool > 0 then
		-- stalls the UI when doing GCode calls, so do an MDI
		--ToolChange.DoToolChangeFromTo(currentTool, 0)
		local GCode = "M6 T0 G43 H0"
		local rc = mc.mcCntlMdiExecute(ATCTools.inst, GCode)
	else
		-- warn user no tool?
	end
end



function ATCTools.DoM6G43(tool)
	tool = tonumber(tool)
	-- If that tool is in a pocket, then maybe ask the user if we should go get it?

	local GCode = string.format("G43 H%d", tool)
	ToolForks.Error("Executing: "..GCode)
	
	local rc = mc.mcCntlMdiExecute(ATCTools.inst, GCode)
	if not ToolChange.internal.CheckForNoError(rc, "Error setting tool height:"..GCode) then
		return
	end		
end

function ATCTools.PreviousTenButtonClicked()
	ATCTools.CurrentOffset = ATCTools.CurrentOffset - 10
	if ATCTools.CurrentOffset < 0 then
		ATCTools.CurrentOffset = 0
	end
	ATCTools.UpdateUI()
end

function ATCTools.NextTenButtonClicked()
	ATCTools.CurrentOffset = ATCTools.CurrentOffset + 10
	ATCTools.UpdateUI()	
end

function ATCTools.SetMainScreenButtonTitles()
	local count = 12 -- currently what i have showing..
	
	for i=1, count do	
		local toolForkNumber = i -- could do an offset like some other stuff
		local ctrlName = string.format("btnFetchToolPocket%d", i)
		local title = ""
		local toolFork = ToolForks.GetToolForkNumber(toolForkNumber)
		if toolFork ~= nil and toolFork.Tool > 0 then
			local toolDesc = ToolForks.GetToolDescription(toolFork.Tool)
			if toolDesc ~= "" then
				title = string.match(toolDesc, "%[.+%]")
				if title == nil then
					title = string.sub(toolDesc, 1,5)
				else
					-- whack off the []
					title = string.sub(title, 2, -2)
				end
			end			
			scr.SetProperty(ctrlName, "Enabled", "1")
		else
			scr.SetProperty(ctrlName, "Enabled", "0")
		end

		local ctrlTitle = string.format("%d\n%s", toolForkNumber, title)
		scr.SetProperty(ctrlName, "Label", ctrlTitle)
	end
end




if (mc.mcInEditor() == 1) then
	-- Easier testing.. to do stuff here
ATCTools.SetMainScreenButtonTitles()

end


return ATCTools