-- ToolForks.lua
-- by Corbin Dunn
-- Feb 21, 2023
-- corbin@corbinstreehouse.com or corbin@corbinsworkshop.com
-- Blog: https://www.corbinstreehouse.com
-- Files/Prodcuts: https://www.corbinsworkshop.com
-- (c) 2023 Corbin Dunn
-- Software provided as-is. For redistribution rights, please contact me.

package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
local inifile = require 'inifile'

local ToolForks = {}

--ToolForkPositions is a table. 
-- The keys are: "ToolForkData" and "ToolFork%d", where %d is replaced with the Tool Fork's Number.
-- Tool Fork Number is 1-based.
-- Ot is saved to an ini file named "ToolForks.tls in the Profile's ToolTables directory.
ToolForks.ToolForkPositions = nil

-- An orientation for a tool fork
ToolForks.ToolForkOrientation = { X_Plus = 0, X_Minus = 1, Y_Plus = 2, Y_Minus = 3}

-- A ToolFork is a table. They keys:
-- Number, X, Y, Z, Orientation
-- The DummyToolFork helps with code completion and to copy initial parameters from
local DummyToolFork = {}
DummyToolFork.Number = 0
DummyToolFork.X = 0.0
DummyToolFork.Y = 0.0
DummyToolFork.Z = 0.0
DummyToolFork.Orientation = ToolForks.ToolForkOrientation.X_Plus

local inst = mc.mcGetInstance()

function InitializeToolForkPositions() 
	local data = {}
	data.ToolForkCount = 0
	data.SlideDistance = 2.5
	data.DwellTime = 5.0
	ToolForks.ToolForkPositions = {}
	ToolForks.ToolForkPositions.ToolForkData = data
end

-- might return nil if not in the table; convenience function
function ToolForks.GetToolForkNumber(number)
	local key = string.format("ToolFork%d", number)
	return ToolForks.ToolForkPositions[key]
end

-- call with nil to remove it
function SetToolForkAtNumber(number, toolFork)
	local key = string.format("ToolFork%d", number)
	ToolForks.ToolForkPositions[key] = toolFork
end

function ToolForks.GetToolForkData()
	return ToolForks.ToolForkPositions.ToolForkData
end

-- conveninence function to get the count
function ToolForks.GetToolForkCount()
	return ToolForks.GetToolForkData().ToolForkCount
end

function ToolForks.Log(message)
	-- Comment out for speed; uncomment for more logging
	print(message)
	mc.mcCntlLog(inst, message, "", -1)
end

function ToolForks.Error(message)
	-- Log and set the error for better tracing of problems
	print(message)
	mc.mcCntlLog(inst, message, "", -1)
	mc.mcCntlSetLastError(inst, message)
end

function GetToolForkFilePath() 
	local profile = mc.mcProfileGetName(inst)
	local machDirPath = mc.mcCntlGetMachDir(inst)
	ToolForks.Log(machDirPath)
	-- not sure why tls extension is used, but the tool table does it..so I'm doing it
	local toolForkFilePath = machDirPath .. "\\Profiles\\" .. profile .. "\\ToolTables\\ToolForks.tls" 
	return toolForkFilePath
end

function ToolForks.LoadToolForkPositions()
	local path = GetToolForkFilePath()
	-- make sure it exists..otherwise an exception is thrown
	local file = io.open(path, "r")
	if file ~= nil then
		file:close()
		ToolForks.ToolForkPositions = inifile.parse(path)
	else 
		ToolForks.ToolForkPositions = nil
	end

	if ToolForks.ToolForkPositions ~= nil then
		-- TODO: Maybe verify the data we are reading in..like the count and values?
		if ToolForks.ToolForkPositions.ToolForkData == nil then
			-- bad file format for now...reset and log
			ToolForks.Error("Bad ToolForks.tls file!!")
			-- TODO: Maybe present this error to the user..as it is kind of a big deal..
			InitializeToolForkPositions()
		else 
			ToolForks.Log(string.format("Loaded ToolForks. Count: %d", ToolForks.GetToolForkCount()))
		end
	else
		InitializeToolForkPositions()
	end
end

function ToolForks.SaveToolForkPositions()
	if ToolForks.ToolForkPositions ~= nil then
		local path = GetToolForkFilePath()
		inifile.save(path, ToolForks.ToolForkPositions)
		ToolForks.Log("Saved ToolForkPositions to: "..path)
	else
		ToolForks.Log("Save: nil ToolForkPositions")
	end
end

-- Adds a tool fork; caller should do a SaveToolForkPositions to write it to the file after this.
function ToolForks.AddToolForkPosition()
	if ToolForks.ToolForkPositions == nil then
		InitializeToolForkPositions()
	end

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
	newToolFork.Orientation = lastToolFork.Orientation

	SetToolForkAtNumber(newToolFork.Number, newToolFork)
	ToolForks.GetToolForkData().ToolForkCount = count + 1
	ToolForks.Log("added a tool fork; totalcount: "..ToolForks.GetToolForkCount())
	return newToolFork
end

-- return the next last one or nil
function ToolForks.RemoveLastToolForkPosition()
	ToolForks.Log("Deleting the last tool fork")
	local count = ToolForks.GetToolForkCount()
	if count > 0 then
		ToolForks.Log("Deleting: ToolFork"..count)
		SetToolForkAtNumber(count, nil)
		ToolForks.GetToolForkData().ToolForkCount = count - 1
		if count > 1 then
			return ToolForks.GetToolForkNumber(count -1)
		end
	else 
		ToolForks.Log("Not deleting anything, because we have no items")
	end
	return nil
end

-- ToolForks.LoadToolForkPositions() -- Load the toolfork positions on startup?

if (mc.mcInEditor() == 1) then
	-- Easier testing.. to do stuff here

	ToolForks.LoadToolForkPositions()
	ToolForks.AddToolForkPosition()
	ToolForks.RemoveLastToolForkPosition()
	ToolForks.SaveToolForkPositions()
	print("done")

--	ToolForks.AddToolForkPosition()
--	SaveToolForkPositions()

end


return ToolForks -- Module End