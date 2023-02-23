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
-- The keys are: "ToolForkCount" and "ToolFork#", where # is replaced with the Tool Fork's Number.
-- Tool Fork Number is 1-based.
-- The data is saved to an ini file named "ToolForks.tls in the Profile's ToolTables directory.
local ToolForkPositions = {}

-- A ToolFork is a table. They keys:
-- Number, X, Y, Z, Orientation
local DummyToolFork = {}
DummyToolFork.Number = 0
DummyToolFork.X = 0.0
DummyToolFork.Y = 0.0
DummyToolFork.Z = 0.0
DummyToolFork.Orientation = 0



-- i'm not fond of having a count exposed, but the Lua table methods only have deprecated things that walk the table.
--- So, we have to keep it in sync here, which means onoly adding and removing from the list via this file's 'API
function ToolForks.GetToolForkCount()
	return ToolForkCount
end

function ToolForks.GetToolForkPositions()
	return ToolForkPositions
end

ToolForks.ToolForkOrientation = { X_Plus = 0, X_Neg = 1, Y_Plus = 2, Y_Neg = 3}

local inst = mc.mcGetInstance()

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
		file.close()
		ToolForkPositions = inifile.parse(path)
	else 
		ToolForkPositions = nil
	end

	ToolForkCount = 0
	if ToolForkPositions ~= nil then
		for toolForkNumber, toolValues in ipairs(ToolForkPositions) do 
			ToolForks.Log(string.format("loaded toolForkNumber: %d", toolForkNumber))
			assert(ToolForkPositions[ToolForkCount] ~= nil) -- TODO: remove this, corbin..just making sure the list is loading with numbers and not strings
			ToolForkCount = ToolForkCount + 1
		end
	else
		ToolForkPositions = {} -- empty
	end
end

function ToolForks.SaveToolForkPositions()
	if ToolForkPositions ~= nil then
		local path = GetToolForkFilePath()
		inifile.save(path, ToolForkPositions)
		ToolForks.Log("Saved ToolForkPositions to: "..path)
	else
		ToolForks.Log("Save: nil ToolForkPositions")
	end
end

-- Adds a tool fork; caller should do a SaveToolForkPositions to write it to the file after this.
function ToolForks.AddToolForkPosition()
	if ToolForkPositions == nil then
		ToolForkPositions = {}
	end

	local newToolFork = {}
	if ToolForkCount > 0 then		
		local lastToolFork = ToolForkPositions[ToolForkCount - 1] -- coult be nil on error
		ToolForks.Log("copying last tool fork")
		newToolFork.ToolForkNumber = lastToolFork.ToolForkNumber + 1
		newToolFork.X = lastToolFork.X
		newToolFork.Y = lastToolFork.Y
		newToolFork.Z = lastToolFork.Z
		newToolFork.Orientation = lastToolFork.Orientation		
	else 
		ToolForks.Log("No tool forks; adding a new basic one at 0000")
		newToolFork.ToolForkNumber = 1
		newToolFork.X = 0.0
		newToolFork.Y = 0.0
		newToolFork.Z = 0.0
		newToolFork.Orientation = ToolForks.ToolForkOrientation.Y_Plus
	end
	-- Initialize a new one with the last one's data; usually you will vary the x or y but nothing else
	ToolForkPositions[ToolForkCount] = newToolFork
	ToolForkCount = ToolForkCount + 1
	ToolForks.Log("added a tool fork; totalcount: "..ToolForkCount)
	return newToolFork
end

function ToolForks.DeleteLastToolForkPosition()
	LogToolForks.Log("Deleting the last tool fork")
	if ToolForkCount > 0 then
		ToolForks.Log("Deleting: ToolFork"..ToolForkCount)
		table.remove(ToolForkPositions, ToolForkCount - 1)
		ToolForkCount = ToolForkCount - 1
	else 
		ToolForks.Log("Not deleting anything, because we have no items")
	end
end

ToolForks.LoadToolForkPositions() -- Load the toolfork positions on startup

if (mc.mcInEditor() == 1) then
	-- Easier testing.. to do stuff here
--	ToolForks.AddToolForkPosition()
--	SaveToolForkPositions()

end


return ToolForks -- Module End