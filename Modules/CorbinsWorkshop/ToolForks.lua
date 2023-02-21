local ToolForks = {}




-- ToolForkPositions have: index, x, y, z, and orientation
global ToolForkPositions = {} 

require 'inifile'

local inst = mc.mcGetInstance()

-- wish there was a better way to do this...like how to get the current profile path?
local ToolForkFileRelPath = "\\"

function GetToolForkFilePath() 
	machDirPath, rc = mc.mcCntlGetMachDir(inst)
	
	
end


buf, rc = int mcCntlGetMachDir(
		number mInst)




inifile.parse('example.ini')
inifile.save('example.ini', iniTable)




local CSVPath = wx.wxGetCwd() .. "\\Profiles\\YourProfile\\Modules\\ToolChangePositions.csv"
ToolNum = 0;
--[[
Open the file and read out the data
--]]
io.input(io.open(CSVPath,"r"))
local line;
for line in io.lines(CSVPath) do
	tkz = wx.wxStringTokenizer(line, ",");
	TC_Positions[ToolNum] = {}-- make a blank table in the positions table to hold the tool data 
	local token = tkz:GetNextToken();
	TC_Positions[ToolNum] ["Tool_Number"] = token;
	TC_Positions[ToolNum] ["X_Position"] = tkz:GetNextToken();
	TC_Positions[ToolNum] ["Y_Position"] = tkz:GetNextToken();
	TC_Positions[ToolNum] ["Z_Position"] = tkz:GetNextToken();
	TC_Positions["Max"] = ToolNum --Set the max tool number
	ToolNum = ToolNum + 1 --Increment the tool number
end
io.close()


function LoadToolForkPositions()




end




return ToolForks -- Module End