
-- Created by Corbin Dunn, corbin@corbinstreehouse.com, Feb 2023

if (mc.mcInEditor() == 1) then
	package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
end


package.loaded.ToolForks = nil
ToolForks = require "ToolForks"

ATCToolForkSetup = {
	SelectedToolFork = nil,
	internal = {},
	test = {}
}

function UpdateToolForkListSelection()
	if ATCToolForkSetup.SelectedToolFork ~= nil then
		if ATCToolForkSetup.SelectedToolFork.Number > ToolForks.GetToolForkCount() then
			ATCToolForkSetup.SelectedToolFork = nil
		end		
	end


	if ATCToolForkSetup.SelectedToolFork == nil then
		if ToolForks.GetToolForkCount() > 0 then
			ATCToolForkSetup.SelectedToolFork = ToolForks.GetToolForkNumber(1)
		end
	end

	if ATCToolForkSetup.SelectedToolFork ~= nil then
		local zeroBasedIndex = ATCToolForkSetup.SelectedToolFork.Number - 1
		scr.SetProperty("lstToolForks", "Selected", tostring(zeroBasedIndex))
		ToolForks.Log("Selecting: ToolFork"..ATCToolForkSetup.SelectedToolFork.Number)
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
	HandleSelectedToolForkChanged()
end

function UpdateToolForkImage() 
	local imagesMapping = {}
	imagesMapping[ToolForks.ToolForkOrientation.X_Plus] = "tool_fork_x_plus.png"
	imagesMapping[ToolForks.ToolForkOrientation.X_Minus] = "tool_fork_x_minus.png"
	imagesMapping[ToolForks.ToolForkOrientation.Y_Plus] = "tool_fork_y_plus.png"
	imagesMapping[ToolForks.ToolForkOrientation.Y_Minus] = "tool_fork_y_minus.png"

	if ATCToolForkSetup.SelectedToolFork ~= nil then
		local o = ATCToolForkSetup.SelectedToolFork.Orientation
		scr.SetProperty("imgToolForkOrientation", "Image", imagesMapping[o])
	end
end

function GetToolForkListBoxSelected() 
	local selectedStr = scr.GetProperty("lstToolForks", "Selected")
	local selectedNumber = tonumber(selectedStr) + 1
	return selectedNumber	
end

function ToolForkListBoxChanged()
	ATCToolForkSetup.SelectedToolFork = ToolForks.GetToolForkNumber(GetToolForkListBoxSelected())
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
	if ATCToolForkSetup.SelectedToolFork ~= nil then
		ToolForks.Log("Selected Tool Fork:"..ATCToolForkSetup.SelectedToolFork.Number)
		SetUIEnabled("1")
		scr.SetProperty("txtToolForkX", "Value", string.format("%.4f", ATCToolForkSetup.SelectedToolFork.X))
		scr.SetProperty("txtToolForkY", "Value", string.format("%.4f", ATCToolForkSetup.SelectedToolFork.Y))
		scr.SetProperty("txtToolForkZ", "Value", string.format("%.4f", ATCToolForkSetup.SelectedToolFork.Z))
		-- orientation..	
		UpdateToolForkImage()
	else
		ToolForks.Log("Selected Tool nil")

		SetUIEnabled("0")
	end

end

-- call when adding or removing items, or on initial load to update the list box ui
function ToolForkPositionsListChanged()
	LoadToolForksIntoListBox()
	ToolForks.SaveToolForkPositions()	
end

function ATCToolForkSetup.HandleZClearanceAssignButtonClick(...)
	local val = scr.GetProperty("droMachineZ", "Value")
	ToolForks.SetZClearanceWithNoTool(val)
	ToolForks.SaveToolForkPositions()
	scr.SetProperty("txtZClearance", "Value", string.format("%4.4f", ToolForks.GetZClearanceWithNoTool()))
	return val	
end


function HandlePositionSet(val, position) 
	ToolForks.Log(string.format("ToolFork %d position: %s, val %.4f", ATCToolForkSetup.SelectedToolFork.Number, position, val))
	val = tonumber(val) -- The value may be a number or a string. Convert as needed.
	ATCToolForkSetup.SelectedToolFork[position] = val
	ToolForks.SaveToolForkPositions()
	return val
end

function ATCToolForkSetup.LoadToolForksAndSetSelected() 
	if ToolForks.GetToolForkCount() > 0 then
		ATCToolForkSetup.SelectedToolFork = ToolForks.GetToolForkNumber(1)
	else
		ATCToolForkSetup.SelectedToolFork = nil
	end
end

function ATCToolForkSetup.UpdateCasePresButton()
	if ToolForks.GetShouldUseCasePressurization() then
		scr.SetProperty('btnCasePressurization', 'Image', 'toggle_ON.png')	
	else
		scr.SetProperty('btnCasePressurization', 'Image', 'toggle_OFF.png')	
	end
end

function ATCToolForkSetup.ToggleCasePressButton()
	local v = not ToolForks.GetShouldUseCasePressurization()
	ToolForks.SetShouldUseCasePressurization(v)
	ToolForks.SaveToolForkPositions()
	ATCToolForkSetup.UpdateCasePresButton()
end

function ATCToolForkSetup.HandleOnEnterToolForkTab()
	ATCToolForkSetup.LoadToolForksAndSetSelected()
	LoadToolForksIntoListBox() 
	-- setup the global UI options
	scr.SetProperty("txtSlideDistance", "Value", string.format("%.4f", ToolForks.GetSlideDistance()))
	scr.SetProperty("txtWaitTime", "Value", string.format("%.4f", ToolForks.GetDwellTime()))
	scr.SetProperty("txtZBump", "Value", string.format("%.4f", ToolForks.GetZBump()))
	scr.SetProperty("txtZClearance", "Value", string.format("%4.4f", ToolForks.GetZClearanceWithNoTool()))
	
	
	ATCToolForkSetup.UpdateCasePresButton()

	
	
	
end


function HandleOnExitToolForkTab()
	ATCToolForkSetup.SelectedToolFork = nil
end

function HandleToolForkListBoxSelectionChanged()
	-- no notification for when the list box selection changes, so we have to poll it
	if ATCToolForkSetup.SelectedToolFork ~= nil then
		if ATCToolForkSetup.SelectedToolFork.Number ~= GetToolForkListBoxSelected() then
			ToolForks.Log("Selection changed..updating UI")
			ToolForkListBoxChanged()
		end
	end
end

function ATCToolForkSetup.HandleSlideDistanceChanged(value)
	ToolForks.SetSlideDistance(value)
	ToolForks.SaveToolForkPositions()
end

function ATCToolForkSetup.HandleWaitTimeChanged(value)
	ToolForks.SetDwellTime(value)
	ToolForks.SaveToolForkPositions()
end

function ATCToolForkSetup.HandleZBumpChanged(...)
	local val = select(1,...)
	ToolForks.SetZBump(val)
	ToolForks.SaveToolForkPositions()
	return val
end

function ATCToolForkSetup.HandleZClearanceChanged(...)
	local val = select(1, ...)
	ToolForks.SetZClearanceWithNoTool(val)
	ToolForks.SaveToolForkPositions()
	return val
end

-- some unit tests to debug any issues
function ATCToolForkSetup.test.TestAdd()
	ToolForks.internal.EnsureToolForks()

	ATCToolForkSetup.SelectedToolFork = ToolForks.AddToolForkPosition()
	ToolForkPositionsListChanged()
	print("Selected:"..ATCToolForkSetup.SelectedToolFork.Number)
end

function ATCToolForkSetup.HandleAddToolForkClicked()
	ATCToolForkSetup.SelectedToolFork = ToolForks.AddToolForkPosition()
	ToolForkPositionsListChanged()
end

function ATCToolForkSetup.RemoveLastToolForkClicked()
	ATCToolForkSetup.SelectedToolFork = ToolForks.RemoveLastToolForkPosition()
	ToolForkPositionsListChanged()
end

function ATCToolForkSetup.OrientationClicked(...)
	local ctrlName = select(1, ...)
	local orientation = string.match(ctrlName, "%d")
	orientation = tonumber(orientation)
	ToolForks.Log("Orientation clicked: %s %d", ctrlName, orientation)
	ATCToolForkSetup.SelectedToolFork.Orientation = orientation
	UpdateToolForkImage()
	ToolForks.SaveToolForkPositions()
end


if (mc.mcInEditor() == 1) then



end


return ATCToolForkSetup