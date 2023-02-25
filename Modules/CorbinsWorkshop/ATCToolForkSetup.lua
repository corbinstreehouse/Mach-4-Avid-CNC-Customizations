
-- Created by Corbin Dunn, corbin@corbinstreehouse.com, Feb 2023

package.loaded.ToolForks = nil
ToolForks = require "ToolForks"

local ATCToolForkSetup = {}

local SelectedToolFork = nil

function UpdateToolForkListSelection()
	if SelectedToolFork ~= nil then
		local zeroBasedIndex = SelectedToolFork.Number - 1
		scr.SetProperty("lstToolForks", "Selected", tostring(zeroBasedIndex))
		ToolForks.Log("Selecting: ToolFork"..SelectedToolFork.Number)
	else
		ToolForks.Log("No selection");
		scr.SetProperty("lstToolForks", "Selected", "0")		
	end	
end

function LoadToolForksIntoListBox() 
	ToolForks.Log("Updating list box")
	local toolForkValues = "";
	ToolForks.Log(string.format("count: %d", ToolForks.GetToolForkCount()))
	for i=1, ToolForks.GetToolForkCount() do
		if toolForkValues ~= "" then
			toolForkValues = toolForkValues.."\n"
		end
		toolForkValues = toolForkValues..string.format("ToolFork%d", i)
	end
	if toolForkValues == "" then
		toolForkValues = "No Tool Forks"
	end

	scr.SetProperty("lstToolForks", "Strings", toolForkValues)

	UpdateToolForkListSelection()
end

function UpdateToolForkImage() 
	local imagesMapping = {}
	imagesMapping[ToolForks.ToolForkOrientation.X_Plus] = "tool_fork_x_plus.png"
	imagesMapping[ToolForks.ToolForkOrientation.X_Minus] = "tool_fork_x_minus.png"
	imagesMapping[ToolForks.ToolForkOrientation.Y_Plus] = "tool_fork_y_plus.png"
	imagesMapping[ToolForks.ToolForkOrientation.Y_Minus] = "tool_fork_y_minus.png"
	
	if SelectedToolFork ~= nil then
		local o = SelectedToolFork.Orientation
		scr.SetProperty("imgToolForkOrientation", "Image", imagesMapping[o])
	end
end

function GetToolForkListBoxSelected() 
	local selectedStr = scr.GetProperty("lstToolForks", "Selected")
	local selectedNumber = tonumber(selectedStr) + 1
	return selectedNumber	
end

function ToolForkListBoxChanged()
	SelectedToolFork = ToolForks.GetToolForkNumber(GetToolForkListBoxSelected())
	HandleSelectedToolForkChanged()
end


function SetUIPropertyEnabled(ctrlName, enabled)
	scr.SetProperty(ctrlName, "Enabled", enabled)
end

function SetUIEnabled(enabled)
	SetUIPropertyEnabled("txtToolForkX", enabled)
	SetUIPropertyEnabled("txtToolForkY", enabled)
	SetUIPropertyEnabled("txtToolForkZ", enabled);	

	SetUIPropertyEnabled("btnOrientationYNeg", enabled)
	SetUIPropertyEnabled("btnOrientationXNeg", enabled)
	SetUIPropertyEnabled("btnOrientationYPos", enabled)
	SetUIPropertyEnabled("btnOrientationXPos", enabled)
	SetUIPropertyEnabled("btnAssignX", enabled)
	SetUIPropertyEnabled("btnAssignY", enabled)
	SetUIPropertyEnabled("btnAssignZ", enabled)

	SetUIPropertyEnabled("lstToolForks", enabled)
	SetUIPropertyEnabled("btnRemoveLastToolFork", enabled)
end

function HandleSelectedToolForkChanged()
	if SelectedToolFork ~= nil then
		ToolForks.Log("Selected Tool Fork:"..SelectedToolFork.Number)
		SetUIEnabled("1")
		scr.SetProperty("txtToolForkX", "Value", string.format("%.4f", SelectedToolFork.X))
		scr.SetProperty("txtToolForkY", "Value", string.format("%.4f", SelectedToolFork.Y))
		scr.SetProperty("txtToolForkZ", "Value", string.format("%.4f", SelectedToolFork.Z))
		-- orientation..	
		UpdateToolForkImage()
	else
		ToolForks.Log("Selected Tool nil")

		SetUIEnabled("0")
	end

end

-- call when adding or removing items, or on initial load to update the list box ui
function ToolForkPositionsListChanged()
	-- try to and restore the selected one..
	local selected = ""
	if SelectedToolFork ~= nil then
		selected = string.format("ToolFork%d", SelectedToolFork.Number)
	end

	LoadToolForksIntoListBox()
	SelectedToolFork = ToolForks.ToolForkPositions[selected] -- may be nil
	if SelectedToolFork == nil and ToolForks.GetToolForkCount() > 0 then
		SelectedToolFork = ToolForks.GetToolForkNumber(1)
	end

	HandleSelectedToolForkChanged()
	ToolForks.SaveToolForkPositions()	
end

function HandlePositionSet(val, position) 
	ToolForks.Log(string.format("ToolFork %d position: %s, val %.4f", SelectedToolFork.Number, position, val))
	val = tonumber(val) -- The value may be a number or a string. Convert as needed.
	SelectedToolFork[position] = val
	ToolForks.SaveToolForkPositions()
	return val
end

function ATCToolForkSetup.LoadToolForksAndSetSelected() 
	if ToolForks.GetToolForkCount() > 0 then
		SelectedToolFork = ToolForks.GetToolForkNumber(1)
	else
		SelectedToolFork = nil
	end
end

function HandleOnEnterToolForkTab()
	ATCToolForkSetup.LoadToolForksAndSetSelected()
	LoadToolForksIntoListBox() 
	HandleSelectedToolForkChanged()
	-- setup the global UI options
	scr.SetProperty("txtSlideDistance", "Value", string.format("%.4f", ToolForks.GetSlideDistance()))
	scr.SetProperty("txtWaitTime", "Value", string.format("%.4f", ToolForks.GetDwellTime()))
end

function HandleOnExitToolForkTab()
	SelectedToolFork = nil
end

function HandleToolForkListBoxSelectionChanged()
	-- no notification for when the list box selection changes, so we have to poll it
	if SelectedToolFork ~= nil then
		if SelectedToolFork.Number ~= GetToolForkListBoxSelected() then
			ToolForks.Log("Selection changed..updating UI")
			ToolForkListBoxChanged()
		end
	end
end

function HandleSlideDistanceChanged(value)
	ToolForks.SetSlideDistance(value)
	ToolForks.SaveToolForkPositions()
end

function HandleWaitTimeChanged(value)
	ToolForks.SetDwellTime(value)
	ToolForks.SaveToolForkPositions()
end

return ATCToolForkSetup