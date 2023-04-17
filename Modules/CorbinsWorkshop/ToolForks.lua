-- ToolForks.lua
-- by Corbin Dunn
-- Feb 21, 2023
-- corbin@corbinstreehouse.com or corbin@corbinsworkshop.com
-- Blog: https://www.corbinstreehouse.com
-- Files/Products: https://www.corbinsworkshop.com
-- (c) 2023 Corbin Dunn
-- Software provided as-is. For redistribution rights, please contact me.

package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
local inifile = require 'inifile'

--ToolForkPositions is a table. 
-- The keys are: "ToolForkData" and "ToolFork%d", where %d is replaced with the Tool Fork's Number.
-- Tool Fork Number is 1-based.
-- It is saved to an ini file named "ToolForks.tls in the Profile's ToolTables directory.

local ToolForks = { 
	internal = {},
	ToolForkPositions = nil, -- maybe rename to ToolForks? kind of confusing for ToolForks.ToolForks. Maybe "Items"?	
	-- An orientation for a tool fork. Don't change the values, as the UI needs them to be this.
	ToolForkOrientation = { X_Plus = 0, X_Minus = 1, Y_Plus = 2, Y_Minus = 3}
}

-- A ToolFork is a table. They keys:
-- Number, X, Y, Z, Orientation, Tool
-- The DummyToolFork helps with code completion and to copy initial parameters when there are none to start with.
local DummyToolFork = {}
DummyToolFork.Number = 0
DummyToolFork.X = 0.0
DummyToolFork.Y = 0.0
DummyToolFork.Z = 0.0
DummyToolFork.Orientation = ToolForks.ToolForkOrientation.X_Plus
DummyToolFork.Tool = 0

local inst = mc.mcGetInstance("ToolForks.lua") -- TODO: make it an item in the table? better for data encapsulation.

function ToolForks.internal.InitializeToolForkPositions() 
	local data = {}
	data.ToolForkCount = 0
	data.SlideDistance = 2.5
	data.DwellTime = 5.0
	data.ZBump = 0.100
	data.TestAtZMax = false
	data.ZClearanceWithNoTool = 0.0
	data.ShouldUseCasePressurization = false
	ToolForks.ToolForkPositions = {}
	ToolForks.ToolForkPositions.ToolForkData = data
end

function ToolForks.GetZBump()
	return ToolForks.GetToolForkData().ZBump
end

function ToolForks.SetZBump(value)
	ToolForks.GetToolForkData().ZBump = value
end

function ToolForks.SetZClearanceWithNoTool(value)
	ToolForks.GetToolForkData().ZClearanceWithNoTool = value
end

function ToolForks.GetZClearanceWithNoTool() 
	return ToolForks.GetToolForkData().ZClearanceWithNoTool
end

function ToolForks.SetShouldUseCasePressurization(value)
	ToolForks.GetToolForkData().ShouldUseCasePressurization= value
end

function ToolForks.GetShouldUseCasePressurization() 
	return ToolForks.GetToolForkData().ShouldUseCasePressurization
end


function ToolForks.SetSlideDistance(value) 
	ToolForks.GetToolForkData().SlideDistance = value
end

function ToolForks.GetSlideDistance() 
	return ToolForks.GetToolForkData().SlideDistance
end

function ToolForks.SetDwellTime(value) 
	ToolForks.GetToolForkData().DwellTime = value
end

function ToolForks.GetDwellTime() 
	return ToolForks.GetToolForkData().DwellTime
end

-- might return nil if not in the table; convenience function
-- TODO: rename to: GetToolForkForNumber()
function ToolForks.GetToolForkNumber(number)
	local key = string.format("ToolFork%d", number)
	return ToolForks.ToolForkPositions[key]
end

function ToolForks.GetToolForkData()
	return ToolForks.ToolForkPositions.ToolForkData
end

-- conveninence function to get the count
function ToolForks.GetToolForkCount()
	ToolForks.internal.EnsureToolForks()
	return ToolForks.GetToolForkData().ToolForkCount
end

function ToolForks.Log(message, ...)
	local eventMessage = string.format(message, ...)	
	-- Comment out for speed; uncomment for more logging
--	print(eventMessage)
	mc.mcCntlLog(inst, eventMessage, "", -1)
--	mc.mcCntlSetLastError(inst, eventMessage) -- for debugging	
end

function ToolForks.Error(message, ...)
	-- Log and set the error for better tracing of problems
	local eventMessage = string.format(message, ...)	
--	print(eventMessage)
	mc.mcCntlLog(inst, eventMessage, "", -1)
	mc.mcCntlSetLastError(inst, eventMessage)
end

function ToolForks.GetToolForkFilePath() 
	local profile = mc.mcProfileGetName(inst)
	local machDirPath = mc.mcCntlGetMachDir(inst)
	-- not sure why tls extension is used, but the tool table does it..so I'm doing it
	local toolForkFilePath = machDirPath .. "\\Profiles\\" .. profile .. "\\ToolTables\\ToolForks.tls" 
	return toolForkFilePath
end

function ToolForks.ValidateToolFork(tf, index)
	if tf == nil then
		return false
	end
	if tf.Number == nil or tf.Number ~= index then
		return false
	end
	-- TODO: verify other data
	return true
end

function ToolForks.internal.EnsureToolForks()
	if ToolForks.ToolForkPositions == nil then
		ToolForks.LoadToolForkPositions()
	end
end

-- Be careful to not call functions from here that might re-enter the code
function ToolForks.LoadToolForkPositions()
	local path = ToolForks.GetToolForkFilePath()
	-- make sure it exists..otherwise an exception is thrown
	local file = io.open(path, "r")
	if file ~= nil then
		file:close()
		ToolForks.ToolForkPositions = inifile.parse(path)
	else 
		ToolForks.ToolForkPositions = nil
	end

	if ToolForks.ToolForkPositions ~= nil then
		if ToolForks.ToolForkPositions.ToolForkData == nil then
			-- bad file format for now...reset and log
			ToolForks.Error("Corrupted Tool Forks file: %s", path)
			-- TODO: Maybe present this error to the user..as it is kind of a big deal..
			ToolForks.internal.InitializeToolForkPositions()
		else
			-- verify the data a bit so we don't get other surprises
			local count = ToolForks.ToolForkPositions.ToolForkData.ToolForkCount
			if count > 50 then
				ToolForks.Error("Too many tool forks - %d Bad Tool Forks file at: %s. Setting count to 50.",  count, ToolForks.GetToolForkFilePath())
				count  = 50
				ToolForks.ToolForkPositions.ToolForkData.ToolForkCount = count
			end

			for i=1, count do
				local toolFork = ToolForks.GetToolForkNumber(i)
				if not ToolForks.ValidateToolFork(toolFork, i) then
					ToolForks.Error("Bad tool fork %d. Corrupted tool Forks file at: %s", i, ToolForks.GetToolForkFilePath())
					-- force it to the last good number
					count = i - 1
					ToolForks.ToolForkPositions.ToolForkData.ToolForkCount = count
				end
			end

			if ToolForks.ToolForkPositions.ToolForkData.ZBump == nil then
				ToolForks.ToolForkPositions.ToolForkData.ZBump = 0.100 -- added later, so could be nil
			end

			if ToolForks.ToolForkPositions.ToolForkData.ZClearanceWithNoTool == nil then
				ToolForks.ToolForkPositions.ToolForkData.ZClearanceWithNoTool = 0.0 -- added later; default to z 0
			end
			
			if ToolForks.ToolForkPositions.ToolForkData.ShouldUseCasePressurization  == nil then
				ToolForks.ToolForkPositions.ToolForkData.ShouldUseCasePressurization = false
			end

			ToolForks.Log("Loaded ToolForks. Count: %d", count)			
		end
	else
		ToolForks.internal.InitializeToolForkPositions()
	end
end

function ToolForks.SaveToolForkPositions()
	if ToolForks.ToolForkPositions ~= nil then
		local path = ToolForks.GetToolForkFilePath()
		inifile.save(path, ToolForks.ToolForkPositions)
		ToolForks.Log("Saved ToolForkPositions to: "..path)
	else
		ToolForks.Log("Save: nil ToolForkPositions")
	end
end

-- Adds a tool fork; caller should do a SaveToolForkPositions to write it to the file after this.
function ToolForks.AddToolForkPosition()
	ToolForks.internal.EnsureToolForks()

	local count = ToolForks.GetToolForkCount()
	local lastToolFork = nil
	if count > 0 then		
		lastToolFork = ToolForks.GetToolForkNumber(count)
	end
	if lastToolFork == nil then
		lastToolFork = DummyToolFork
	end

	local newToolFork = {}
	newToolFork.Number = lastToolFork.Number + 1
	newToolFork.X = lastToolFork.X
	newToolFork.Y = lastToolFork.Y
	newToolFork.Z = lastToolFork.Z
	newToolFork.Tool = 0 -- always start out without a tool
	newToolFork.Orientation = lastToolFork.Orientation

	local key = string.format("ToolFork%d", newToolFork.Number)
	ToolForks.ToolForkPositions[key] = newToolFork

	local newCount = count + 1
	assert(newToolFork.Number == newCount)
	ToolForks.GetToolForkData().ToolForkCount = newCount
	ToolForks.Log("added a tool fork %d, totalcount %d",  newToolFork.Number, newCount)
	return newToolFork
end

function ToolForks.GetToolForkPositionForTool(toolNumber)
	-- Just look it up so I don't have to keep two lists (one in the tool file and one in the fork file)
	if toolNumber == 0 then -- 0 is special
		return nil
	end
	for i=1, ToolForks.GetToolForkCount() do
		local tf = ToolForks.GetToolForkNumber(i)
		if tf.Tool == toolNumber then
			return tf
		end
	end
	return nil
end


-- returns 0 if it isn't set
function ToolForks.GetToolForkNumberForTool(toolNumber)
	local tf = ToolForks.GetToolForkPositionForTool(toolNumber)
	if tf ~= nil then
		return tf.Number
	end
	return 0
end

function ToolForks.GetToolDescription(tool) 
	local desc, rc = mc.mcToolGetDesc(inst, tool)
	if rc == mc.MERROR_NOERROR then
		return desc
	else
		return ""
	end
end

function ToolForks.SetToolDescription(tool, desc)
	local rc = mc.mcToolSetDesc(inst, tool, desc)
	rc = mc.mcToolSaveFile(inst)

end

function ToolForks.SaveTools()
	local rc = mc.mcToolSaveFile(inst)
	--CheckForNoError(rc, "SaveTools")
end

-- return the next last one or nil
function ToolForks.RemoveLastToolForkPosition()
	ToolForks.Log("Deleting the last tool fork")
	local count = ToolForks.GetToolForkCount()
	if count > 0 then
		local tf = ToolForks.GetToolForkNumber(count)
		ToolForks.Log("Deleting: ToolFork"..count)
		local key = string.format("ToolFork%d", count)
		ToolForks.ToolForkPositions[key] = nil

		ToolForks.GetToolForkData().ToolForkCount = count - 1
		if count > 1 then
			return ToolForks.GetToolForkNumber(count - 1)
		end
	else 
		ToolForks.Log("Not deleting anything, because we have no items")
	end
	return nil
end

-- ToolForks.LoadToolForkPositions() -- Load the toolfork positions on startup?

if (mc.mcInEditor() == 1) then
	-- Easier testing.. to do stuff here
	ToolForks.internal.EnsureToolForks()

	--ToolForks.AddToolForkPosition()
	--ToolForks.RemoveLastToolForkPosition()
	--ToolForks.SaveToolForkPositions()
	--print("done")

--	ToolForks.AddToolForkPosition()
--	SaveToolForkPositions()

end

-- Load the fork positions when we load this module
ToolForks.internal.EnsureToolForks()

return ToolForks -- Module End