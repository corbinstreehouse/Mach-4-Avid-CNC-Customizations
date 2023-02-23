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

-- ToolForkPositions has: ToolIndex, X, Y, Z, Orientation
local ToolForkPositions = {}
local ToolForkCount = 0

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

	if ToolForkPositions ~= nil then
		-- count them ; table.getn? deprecated. #? I need to learn Lua
		ToolForkCount = 0
		for toolForkNumber, toolValues in ipairs(ToolForkPositions) do 
			ToolForks.Log(string.format("loaded toolForkNumber: %d", toolForkNumber))
			ToolForkCount = ToolForkCount + 1
		end
	else
		ToolForkPositions = {} -- empty
		ToolForkCount = 0
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

	local lastToolFork = nil
	if ToolForkCount > 0 then
		local lastToolForkIndex = ToolForkCount -- 1 based, not 0 based
		lastToolFork = ToolForkPositions[lastToolForkIndex] -- coult be nil on error
		ToolForks.Log("copying last tool fork")
	end
	if lastToolFork == nil then
		ToolForks.Log("No tool forks; adding a new basic one at 0000")
		lastToolFork = {}
		lastToolFork.X = 0.0
		lastToolFork.Y = 0.0
		lastToolFork.Z = 0.0
		lastToolFork.Orientation = ToolForks.ToolForkOrientation.Y_Plus
	end

	ToolForkCount = ToolForkCount + 1
	-- Initialize a new one with the last one's data; usually you will vary the x or y but nothing else
	ToolForkPositions[ToolForkCount] = lastToolFork
	ToolForks.Log("added a tool fork; totalcount: "..ToolForkCount)
	return lastToolFork
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