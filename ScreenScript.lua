-- For ZeroBrane debugging.
package.path = package.path .. ";./ZeroBraneStudio/lualibs/mobdebug/?.lua"

-- For installed profile modules support.
package.path = package.path .. ";./Profiles/AvidCNC/Modules/?.lua"
package.path = package.path .. ";./Profiles/AvidCNC/Modules/?.luac"
package.path = package.path .. ";./Profiles/AvidCNC/Modules/?.mcs"
package.path = package.path .. ";./Profiles/AvidCNC/Modules/?.mcc"
package.cpath = package.cpath .. ";./Profiles/AvidCNC/Modules/?.dll"

-- For installed global modules support.
package.path = package.path .. ";./Modules/?.lua"
package.path = package.path .. ";./Modules/?.luac"
package.path = package.path .. ";./Modules/?.mcs"
package.path = package.path .. ";./Modules/?.mcc"
package.cpath = package.cpath .. ";./Modules/?.dll"

-- PMC genearated module load code.
package.path = package.path .. ";./Pmc/?.lua"
package.path = package.path .. ";./Pmc/?.luac"


-- PMC genearated module load code.
function Mach_Cycle_Pmc()
end

-- Screen load script (Global)
---------------------------------------------------------------
-- Load modules
---------------------------------------------------------------
inst = mc.mcGetInstance()
local profile = mc.mcProfileGetName(inst)
local path = mc.mcCntlGetMachDir(inst)

-- package.path = path .. "\\Profiles\\" .. profile .. "\\Modules\\?.lua;" .. path .. "\\Modules\\?.lua;" .. path .. "\\AvidCNC\\?.luac;"
--package.path = path .. "\\Modules\\?.lua;" .. path .. "\\Profiles\\" ..  profile .. "\\Modules\\?.lua;"
package.path = package.path .. ";" .. path .. "\\Modules\\AvidCNC\\?.luac;"
package.path = package.path .. ";" .. path .. "\\Modules\\AvidCNC\\?.lua;"
package.path = package.path .. ";" .. path .. "\\Modules\\AvidCNC\\?.mcs;"
package.path = package.path .. ";" .. path .. "\\Modules\\AvidCNC\\?.mcc;"
package.path = package.path .. ";" .. path .. "\\Modules\\AvidCNC\\?.dll;"
package.path = package.path .. ";" .. path .. "\\Modules\\CorbinsWorkshop\\?.lua;"

package.loaded.ToolForks = nil
ToolForks = require 'ToolForks'

--Master module
package.loaded.MasterModule = nil
mm = require "mcMasterModule"

-- fixes the touch plate issue with tool heights active
package.loaded.CWUtilities = nil
CWUtilities = require "CWUtilities"	

package.loaded.ATCTools = nil
ATCTools = require "ATCTools"

package.loaded.ToolForks = nil
ToolForks = require "ToolForks"

--Probing module
-- package.loaded.Probing = nil
-- prb = require "mcProbing"
--mc.mcCntlSetLastError(inst, "Probe Version " .. prb.Version());

--AutoTool module
-- package.loaded.AutoTool = nil
-- at = require "mcAutoTool"

--ErrorCheck module Added 11-4-16
package.loaded.mcErrorCheck = nil
ec = require "mcErrorCheck"

--Panel Functions module
package.loaded.PanelFunctions = nil
pf = require "PanelFunctions"

-- Avid CNC dialogs
package.loaded.AvidDialogs = nil
avd = require "AvidDialogs"
    
pageId = 0
screenId = 0
testcount = 0
machState = 0
machStateOld = -1
machEnabled = 0
machWasEnabled = 0

LastStateUnitsMode = mc.mcCntlGetUnitsCurrent(inst)
LastStateConfigSettingsSaved = 0  -- config settings from Avid Machine Config
LastStateOfTorchRelayRegister = -1;
LastStateOfThcAllowedRegister = -1;
LastStateOfResumeGCode = -1;
LastStateEssStateRegister = 0;
LastStateMtcInProgress = 0;

Tframe = nil	--Touch Plate frame handle
TframeShown = false
ASframe = nil	--Touch Plate Advanced Settings frame handle
co_swu = nil
warmUpRunning = false

AvidConfigJson = pf.ReadJSON("\\Modules\\AvidCNC\\AvidCNC.json");
AvidConfigVars = {} -- Avid Config var table
FeedHoldAndThenStop = 0
FeedHoldRequested = 0
THCConfigSettings = pf.ReadJSON("\\Modules\\AvidCNC\\Config\\THCConfig.json")
-- mc.mcProfileWriteInt(inst, "AvidCNC_Profile", "iToolChangeResumeGCode", 0)  -- reset on screen load
callSuccess = nil;
ignoreToolChangeFileList = {};

valEssResumeCuttingCounter = 0
hEssArcOkay = mc.mcRegGetHandle(inst, "ESS/HC/ARC_OKAY");
hEss_HeightControl_ResumeCutting_DelayUntilArcOkay = mc.mcRegGetHandle(inst, "ESS/HC/Resume_Cutting__Delay_Until_Arc_Okay");

---------------------------------------------------------------
-- Signal Library --
---------------------------------------------------------------
SigLib = {
[mc.OSIG_MACHINE_ENABLED] = function (state)	
    machEnabled = state;
	local stateReverse = state == 1 and 0 or 1
	local cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "not found")
	
    scr.SetProperty('btnRefAll', 'Enabled', tostring(state));
    scr.SetProperty('btnRefAll2', 'Enabled', tostring(state));
    scr.SetProperty('btnGotoZero', 'Enabled', tostring(state));
    scr.SetProperty('btnGotoMachineHome', 'Enabled', tostring(state));	
    scr.SetProperty('tabJogging', 'Enabled', tostring(state));
	scr.SetProperty('luaSelectTool', 'Enabled', tostring(stateReverse))
   
	if (state == 1) then
		EnableKeyboard()
        ButtonEnable()
		-- Set enabled states for 4th axis specific buttons --
		rc = mc.mcAxisIsEnabled(inst,3)
		scr.SetProperty('btnRefAOnly', 'Enabled', tostring(rc))
		
		-- Change peirce limit value DRO to read only --
		scr.SetProperty("droPierceLimit", "Editor", "3")	-- in place editor
		scr.SetProperty("droPierceLimit", "Fg Color", "#000000")	-- black fg color
		scr.SetProperty("droPierceLimit", "Bg Color", "")	-- no bg color
			
	elseif ( state == 0 ) then
		DisableKeyboard()
		local hsig_CoolantOn, hsig_MistOn, rc
		
		--Disable COOLANT with machine disable
		hsig_CoolantOn, rc = mc.mcSignalGetHandle(inst, mc.OSIG_COOLANTON)
		if (rc ~= mc.MERROR_NOERROR) then
			mc.mcCntlLog(inst, 'Failure to aquire handle for OSIG_COOLANTON', "", -1)
		else
			rc = mc.mcSignalSetState(hsig_CoolantOn, 0)	--Turn Coolant OFF if machine disabled
			if (rc ~= mc.MERROR_NOERROR) then
				mc.mcCntlLog(inst, 'Failure to set OSIG_COOLANTON state to 0', "", -1)
			end
		end
		
		--Disable  MIST with machine disable
		hsig_MistOn, rc = mc.mcSignalGetHandle(inst, mc.OSIG_MISTON)
		if (rc ~= mc.MERROR_NOERROR) then
			mc.mcCntlLog(inst, 'Failure to aquire handle for OSIG_MISTON', "", -1)
		else
			mc.mcSignalSetState(hsig_MistOn, 0)	--Turn Mist OFF if machine disabled
			if (rc ~= mc.MERROR_NOERROR) then
				mc.mcCntlLog(inst, 'Failure to set OSIG_MISTON state to 0', "", -1)
			end
		end
		
		-- Change peirce limit value DRO to in place --
		scr.SetProperty("droPierceLimit", "Editor", "1")	-- keypad editor
		scr.SetProperty("droPierceLimit", "Fg Color", "#00FF00")	-- green fg color
		scr.SetProperty("droPierceLimit", "Bg Color", "#000000")	-- black bg color
		
		-- reset manual tool change
		StopManualToolChange(false);
		
		-- Reset soft limit enabled states
		if (cuttingTool == "Plasma") then ResetSoftLimitEnabledStates() end;
			
		-- Kill spindle warm-up coroutine
		warmUpRunning = false
			
    end
end,

[mc.ISIG_EMERGENCY] = function(state)
	if (state == 1) then
		-- Kill spindle warm-up coroutine
		warmUpRunning = false
	end
end,

[mc.ISIG_INPUT0] = function (state)
    if (state == 1) then 
		SetJogIncToValue(.0001)
    end
end,

[mc.ISIG_INPUT1] = function (state)
    if (state == 1) then 
		SetJogIncToValue(.001)
    end
end,

[mc.ISIG_INPUT2] = function (state)
    if (state == 1) then 
		SetJogIncToValue(.01)
    end
end,

[mc.ISIG_INPUT3] = function (state)
    if (state == 1) then 
		SetJogIncToValue(.1)
    end
end,


[mc.ISIG_INPUT10] = function (state)
	if ( state == 1 ) then
		rc = mc.mcCntlEStop(inst)
		mc.mcCntlSetLastError(inst, 'PTC Fault signal triggered')
	elseif ( state == 0 ) then
		--mc.mcCntlSetLastError(inst, 'PTC Fault signal cleared')
	end
end,

[mc.ISIG_PROBE] = function (state)
	if (state == 1) then
		scr.SetProperty('lblProbeSigLED', 'Bg Color', '#0080FF');
		scr.SetProperty('lblProbeSigLED', 'Fg Color', '#FFFFFF');
		scr.SetProperty('lblProbeSigLED', 'Label', 'ACTIVE');
	else
		scr.SetProperty('lblProbeSigLED', 'Bg Color', '#002929');
		scr.SetProperty('lblProbeSigLED', 'Fg Color', '#FFFFFF');
		scr.SetProperty('lblProbeSigLED', 'Label', 'INACTIVE');
	end
end,

[mc.OSIG_JOG_CONT] = function (state)
    if( state == 1) then 
       scr.SetProperty('labJogMode', 'Label', 'Continuous');
       scr.SetProperty('txtJogInc', 'Bg Color', '#C0C0C0');--Light Grey
       scr.SetProperty('txtJogInc', 'Fg Color', '#808080');--Dark Grey
    end
end,

[mc.OSIG_JOG_INC] = function (state)
    if( state == 1) then
        scr.SetProperty('labJogMode', 'Label', 'Incremental');
        scr.SetProperty('txtJogInc', 'Bg Color', '#FFFFFF');--White    
        scr.SetProperty('txtJogInc', 'Fg Color', '#000000');--Black
   end
end,

[mc.OSIG_JOG_MPG] = function (state)
    if( state == 1) then
        scr.SetProperty('labJogMode', 'Label', '');
        scr.SetProperty('txtJogInc', 'Bg Color', '#C0C0C0');--Light Grey
        scr.SetProperty('txtJogInc', 'Fg Color', '#808080');--Dark Grey
        --add the bits to grey jog buttons becasue buttons can't be MPGs
    end
end,

[mc.OSIG_SPINDLEON] = function (state)
	if( state == 0) then
		scr.SetProperty('bmbSpindleOnOff', 'Image', 'toggle_OFF.png')
		scr.SetProperty('bmbRouterOnOff', 'Image', 'toggle_OFF.png')
	elseif ( state == 1 ) then
		scr.SetProperty('bmbSpindleOnOff', 'Image', 'toggle_ON.png')
		scr.SetProperty('bmbRouterOnOff', 'Image', 'toggle_ON.png')
	end
end,

[mc.OSIG_COOLANTON] = function (state)
	local valCuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "Spindle")
	local valConfigTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sConfigTool", "Spindle")
	
	if ( state == 0 ) then
		scr.SetProperty('bmbRelay1', 'Image', 'toggle_OFF.png')
		if ( valCuttingTool == 'Router' ) or (valConfigTool == "Router_Plasma") then
			scr.SetProperty('bmbRelay2', 'Image', 'toggle_OFF.png')
		end
	elseif ( state == 1 ) then
		scr.SetProperty('bmbRelay1', 'Image', 'toggle_ON.png')
		if ( valCuttingTool == 'Router' ) or (valConfigTool == "Router_Plasma") then
			scr.SetProperty('bmbRelay2', 'Image', 'toggle_ON.png')
		end
	end
end,

[mc.OSIG_MISTON] = function (state)
	local valCuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "Spindle")
	
	if ( valCuttingTool == 'Spindle' ) or (valCuttingTool == "Plasma") then
		if ( state == 0 ) then
			scr.SetProperty('bmbRelay2', 'Image', 'toggle_OFF.png')
		elseif ( state == 1 ) then
			scr.SetProperty('bmbRelay2', 'Image', 'toggle_ON.png')
		end
	end
end,

[mc.ISIG_MOTOR0_PLUS] = function (state)
	local inst = mc.mcGetInstance("Sig Lib: ISIG_MOTOR0_PLUS")
	local valSensors = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigSensorConfig", 1)
	local valConfigRotary = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigRotary", 0)
	
	-- 6 sensor config without rotary, X++ sensor needs to trip X limit LED
	if (valSensors == 2) and (valConfigRotary == 0) then
		if (state == 1) then
			scr.SetProperty("ledMotor0--", "Value", "1")
		else
			local hsig_Motor0Minus = mc.mcSignalGetHandle(inst, mc.ISIG_MOTOR0_MINUS)
			if (hsig_Motor0Minus == 0) then
				mc.mcCntlLog(inst, "Failure to aquire signal handle", "", -1)
			else
				local Motor0MinusState = mc.mcSignalGetState(hsig_Motor0Minus)
				if (Motor0MinusState == 0) then
					scr.SetProperty("ledMotor0--", "Value", "0")
				end
			end
		end
  end
  if (AvidConfigVars.model == "PRO CNC") or (AvidConfigVars.electronics == "CRP100") then
    EnableLimitOverride(state)  -- enable axis limits override if single limit switch for axis
  end
	-- EnableLimitOverride(state)

end,

[mc.ISIG_MOTOR0_MINUS] = function (state)
	local inst = mc.mcGetInstance("Sig Lib: ISIG_MOTOR0_MINUS")
	local valSensors = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigSensorConfig", 1)
	local valConfigRotary = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigRotary", 0)

	
	if (state == 1) then
		scr.SetProperty("ledMotor0--", "Value" , "1")
	else
		local hsig_Motor0Plus = mc.mcSignalGetHandle(inst, mc.ISIG_MOTOR0_PLUS)
		-- 6 sensor config without rotary, check motor 0++ limit state before turning off X LED
		if (valSensors == 2) and (valConfigRotary == 0) then
			if (hsig_Motor0Plus == 0) then
				mc.mcCntlLog(inst, "Failure to aquire signal handle", "", -1)
			else 
				local Motor0PlusState = mc.mcSignalGetState(hsig_Motor0Plus)
				if (Motor0PlusState == 0) then
					scr.SetProperty("ledMotor0--", "Value", "0")
				end
			end
		else
			scr.SetProperty("ledMotor0--", "Value", "0")
		end
	end
  if (AvidConfigVars.model == "PRO CNC") or (AvidConfigVars.electronics == "CRP100") then
    EnableLimitOverride(state)  -- enable axis limits override if single limit switch for axis
  end
	-- EnableLimitOverride(state)

end,

[mc.ISIG_MOTOR1_PLUS] = function (state)
  if (AvidConfigVars.electronics == "CRP100") then
    EnableLimitOverride(state)  -- enable axis limits override if single limit switch for axis
  end

end,

[mc.ISIG_MOTOR1_MINUS] = function (state)
  if (AvidConfigVars.electronics == "CRP100") then
    EnableLimitOverride(state)  -- enable axis limits override if single limit switch for axis
  end

end,

[mc.ISIG_MOTOR4_HOME] = function (state)
	local inst = mc.mcGetInstance("Sig Lib: ISIG_MOTOR4_HOME")
	local valRotaryActive = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iRotaryActive", 0)
	
	if (valRotaryActive == 1) then
		if (state == 1) then
			scr.SetProperty("ledAHome", "Value", "1")
		else
			scr.SetProperty("ledAHome", "Value", "0")
		end
	end
end,

[mc.OSIG_MACHINE_CORD] = function (state)
	if (state == 1) then
		scr.SetProperty("btnMachCoord", "Label", "Switch to\nWork Coordinates")
		scr.SetProperty("btnMachCoordOffsetsTab", "Label", "Switch to\nWork Coordinates")
	else
		scr.SetProperty("btnMachCoord", "Label", "Switch to\nMachine Coordinates")
		scr.SetProperty("btnMachCoordOffsetsTab", "Label", "Switch to\nMachine Coordinates")
	end
end,

[mc.OSIG_RUNNING_GCODE] = function (state)
	if (state == 1) then
		scr.SetProperty("droFeedRateCur", "DRO Code", "17")	-- show current feed rate while GCode running
		scr.SetProperty("droSpindleSpeed", "Editor", "3")	-- in place editor
		scr.SetProperty("droSpindleSpeed", "Fg Color", "#000000")	-- black fg color
		scr.SetProperty("droSpindleSpeed", "Bg Color", "")	-- no bg color
	else
		scr.SetProperty("droFeedRateCur", "DRO Code", "-1")	-- don't show current feed rate whie GCode running
		scr.SetProperty("droFeedRateCur", "Value", "0")
		scr.SetProperty("droSpindleSpeed", "Editor", "1")	-- keypad editor
		scr.SetProperty("droSpindleSpeed", "Fg Color", "#00FF00")	-- green fg color
		scr.SetProperty("droSpindleSpeed", "Bg Color", "#000000")	-- black bg color
	end
end,

-- Finished part, state set in m30 macro
[mc.OSIG_PRTSF] = function(state)
	if (state == 1) then
		local curFileName = mc.mcCntlGetGcodeFileName(inst);
		local fileList = ignoreToolChangeFileList or {};
		local resetReg = true;
		local cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "not found");
		local ignore = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigIgnoreToolChanges", 0);
    local hreg, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/ToolChange/Ignore_Tool_Changes");
      
		-- Reset register for ignoring tool changes
		if (rc ~= mc.MERROR_NOERROR) then
			mc.mcCntlLog(inst, "Sig Lib, mc.OSIG_PRTSF: Failure to acquire register handle, rc="..rc, "", -1);
		elseif (ignore == 1) then
			-- ignoreToolChangeFileList contains file user wants to respect tool changes for
			for _,fileName in pairs(fileList) do
				if (fileName == curFileName) then
					mc.mcRegSetValue(hreg, 0);
					resetReg = false;
					break;
				end
			end
			if resetReg then
				mc.mcRegSetValue(hreg, ignore);
			end
		end
		
		-- Reset soft limit enabled states
		if (cuttingTool == "Plasma") then ResetSoftLimitEnabledStates() end;
					
		-- Set part finished signal low
		local hsig, rc = mc.mcSignalGetHandle(inst, mc.OSIG_PRTSF);
		if (rc ~= mc.MERROR_NOERROR) then
			mc.mcCntlLog(inst, "Sig Lib, mc.OSIG_PRTSF: Failure to acquire signal handle, rc="..rc, "", -1);
		else
			mc.mcSignalSetState(hsig, 0);
		end
	end
end,

}

---------------------------------------------------------------
-- Keyboard Inputs Toggle() function. Updated 5-16-16
---------------------------------------------------------------

function SetJogIncToValue(value)
	mc.mcJogSetInc(inst, mc.X_AXIS, value);		
	mc.mcJogSetInc(inst, mc.Y_AXIS, value);
	mc.mcJogSetInc(inst, mc.Z_AXIS, value);
end


-- corbin - use this function in other places so it is enabled only when the machine is enabled. 
-- It was driving me crazy that it was taking over the keyboard when I had the machine disabled.
function SetKeyboardInputsEnabled(enabled)
		local iReg = mc.mcIoGetHandle (inst, "Keyboard/Enable")
    local iReg2 = mc.mcIoGetHandle (inst, "Keyboard/EnableKeyboardJog")
	if (iReg ~= nil) and (iReg2 ~= nil) then
		mc.mcIoSetState(iReg, enabled)
		mc.mcIoSetState(iReg2, enabled);
	end
end

function GetKeyboardInputsEnabled() 
	local iReg = mc.mcIoGetHandle (inst, "Keyboard/Enable")
    local iReg2 = mc.mcIoGetHandle (inst, "Keyboard/EnableKeyboardJog")
	if (iReg ~= nil) and (iReg2 ~= nil) then
		return mc.mcIoGetState(iReg);
	else
		return 0
	end
end



function KeyboardInputsToggle()
	local isEnabled = GetKeyboardInputsEnabled()

	if (isEnabled == 1) then
		DisableKeyboard()
	else
		EnableKeyboard()
	end
end

---------------------------------------------------------------
-- Remember Position function.
---------------------------------------------------------------
function RememberPosition()
    local Xpos = mc.mcAxisGetMachinePos(inst, 0) -- Get current X (0) Machine Coordinates
    mc.mcProfileWriteString(inst, "RememberPos", "X", string.format (Xpos)) --Create a register and write the machine coordinates to it
    local Ypos = mc.mcAxisGetMachinePos(inst, 1) -- Get current Y (1) Machine Coordinates
    mc.mcProfileWriteString(inst, "RememberPos", "Y", string.format (Ypos)) --Create a register and write the machine coordinates to it
    local Zpos = mc.mcAxisGetMachinePos(inst, 2) -- Get current Z (2) Machine Coordinates
    mc.mcProfileWriteString(inst, "RememberPos", "Z", string.format (Zpos)) --Create a register and write the machine coordinates to it
    local PosUnits = mc.mcCntlGetUnitsCurrent(inst)
    mc.mcProfileWriteInt(inst, "RememberPos", "PosUnits", PosUnits)
	
	return Xpos, Ypos, Zpos
end

---------------------------------------------------------------
-- Return to Position function.
---------------------------------------------------------------
function ReturnToPosition()
  if not (pf.IsHomed()) then
    wx.wxMessageBox("Machine is not homed, it is not safe\nto return to MTC location.", "Manual Tool Change")
    do return end
  end

  local inst = mc.mcGetInstance("ReturnToPosition()")
  local m_CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3) -- G90/G91 modal
  local unitsMode = mc.mcCntlGetUnitsCurrent(inst)	-- get current units mode
  local defaultUnits = mc.mcCntlGetUnitsDefault(inst)	-- get machine setup units
  local posUnits = mc.mcProfileGetInt(inst, "RememberPos", "PosUnits", 200) -- get units MTC location was set with
  local pos, feedRate = {"X", "Y", "Z"}, {"X", "Y", "Z"}
  local posConvert = 1  -- convert factor if "set MTC" units differ from current user units
  local feedConvert = 1 -- convert factor if default units differ from current user units
  local val, axis
  local zOffset = -0.25

  if (unitsMode == 210) then zOffset = -6.35 end
  if (posUnits == 200) and (unitsMode == 210) then posConvert = 25.4 elseif (posUnits == 210) and (unitsMode == 200) then posConvert = 1 / 25.4 end -- convert factor for positions
  if (defaultUnits == 200) and (unitsMode == 210) then feedConvert = 25.4 elseif (defaultUnits == 210) and (unitsMode == 200) then feedConvert = 1 / 25.4 end -- convert factor for feed rates

  for i = 1,3,1 do
    axis = pos[i]
    val = mc.mcProfileGetString(inst, "RememberPos", axis, "NotFound") -- Get the ini position value
    if (val == "NotFound") then
      wx.wxMessageBox("MTC position not found.\nYou must set MTC location first.")
      do return end
    else
      pos[axis] = val * posConvert  -- convert as needed
    end

    feedRate[axis] = string.format("%0.4f", (mc.mcMotorGetMaxVel(inst, i -1) * 60 / mc.mcMotorGetCountsPerUnit(inst, i -1)) * (mc.mcJogGetRate(inst, i -1) / 100)) * feedConvert  -- get feed rate, based on cur jog rate
  end

  mc.mcCntlMdiExecute(
    inst,
    "G90\n" ..
    "G01 G53 Z" .. zOffset .. " F" .. feedRate.Z .. "\n" ..
    "G01 G53 X" .. pos.X .. " Y" ..pos.Y .. " F" .. feedRate.X .. "\n" ..
    "G01 G53 Z" .. pos.Z ..  " F" .. feedRate.Z .. "\n" ..
    "G" .. m_CurAbsMode
  )

end

---------------------------------------------------------------
-- Spin CW function.
---------------------------------------------------------------
function SpinCW()
    local sigh = mc.mcSignalGetHandle(inst, mc.OSIG_SPINDLEON);
    local sigState = mc.mcSignalGetState(sigh);
    
    if (sigState == 1) then 
        mc.mcSpindleSetDirection(inst, 0);
      -- Spindle warm-up procedure checks.
      if warmUpRunning and co_swu then
        local co_state = coroutine.status(co_swu)
        if (co_state == "suspended") or (co_state == "running") then
          mc.mcCntlCycleStop(inst)
          warmUpRunning = false
        end
      end
    else 
        mc.mcSpindleSetDirection(inst, 1);
    end
end

---------------------------------------------------------------
-- Spin CCW function.
---------------------------------------------------------------
function SpinCCW()
    local sigh = mc.mcSignalGetHandle(inst, mc.OSIG_SPINDLEON);
    local sigState = mc.mcSignalGetState(sigh);
    
    if (sigState == 1) then 
        mc.mcSpindleSetDirection(inst, 0);
    else 
        mc.mcSpindleSetDirection(inst, -1);
    end
end


-----------------------------------------------------
-- Toggle Relay 2 function.
---------------------------------------------------------------
function Relay2OnOff()
	local inst = mc.mcGetInstance('Relay2OnOff()')
	local outputSig = mc.OSIG_MISTON	-- output signal for spindle or plasma cutting tool
	local sigState = nil
	local valCuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "Spindle")
	local valConfigTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sConfigTool", "Spindle")
		
	-- get appropriate signal handle --
	if (valCuttingTool == 'Router') or (valConfigTool == "Router_Plasma") then
		outputSig = mc.OSIG_COOLANTON	-- output signal for router cutting tool
	end
	
	local sigh, rc = mc.mcSignalGetHandle(inst, outputSig)
	if (rc ~= mc.MERROR_NOERROR) then
		msg = 'Failure to aquire handle for ' .. outputSig
		mc.mcCntlLog(inst, msg, "", -1)
	else
		sigState, rc = mc.mcSignalGetState(sigh);  -- get current signal state
		if (rc ~= mc.MERROR_NOERROR) then
			msg = 'Failure to aquire signal state for ' .. outputSig
			mc.mcCntlLog(inst, msg, "", -1)
		else
			if (sigState == 0) then	-- toggle appropriate signal state
				rc = mc.mcSignalSetState(sigh, 1);
			else 
				rc = mc.mcSignalSetState(sigh, 0);
			end
		end
	end
end

-----------------------------------------------------
-- Toggle Coolant Relay function.
---------------------------------------------------------------
function CoolantOnOff()
	local inst = mc.mcGetInstance("CoolantOnOff()")
    local sigh, rc = mc.mcSignalGetHandle(inst, mc.OSIG_COOLANTON);
	if ( rc ~= mc.MERROR_NOERROR) then
		mc.mcCntlLog(inst, "Failure to aquire signal handle", "", -1)
	else
		local sigState = mc.mcSignalGetState(sigh);
    
		if (sigState == 1) then 
			rc = mc.mcSignalSetState(sigh, 0);
		else 
			rc = mc.mcSignalSetState(sigh, 1);
		end
	end
end

-----------------------------------------------------
-- Toggle Mist Relay function.
---------------------------------------------------------------
function MistOnOff()
	local inst = mc.mcGetInstance("MistOnOff()")
    local sigh = mc.mcSignalGetHandle(inst, mc.OSIG_MISTON);
	if ( rc ~= mc.MERROR_NOERROR) then
		mc.mcCntlLog(inst, "Failure to aquire signal handle", "", -1)
	else
		local sigState = mc.mcSignalGetState(sigh);
		
		if (sigState == 1) then 
			rc = mc.mcSignalSetState(sigh, 0);
		else 
			rc = mc.mcSignalSetState(sigh, 1);
		end
	end
end

-----------------------------------------------------
-- Set toolpath line widths
---------------------------------------------------------------
function SetToolpathLineWidth()
  local inst = mc.mcGetInstance("SetToolpathLineWidth()")

  scr.SetProperty("toolpath1", "Path Line Width", mc.mcProfileGetString(inst, "AvidCNC_Profile", "iToolpathPathLineWidth", "20"))
  scr.SetProperty("toolpath1", "Axis Line Width", mc.mcProfileGetString(inst, "AvidCNC_Profile", "iToolpathAxisLineWidth", "20"))
  scr.SetProperty("toolpath1", "Softlimit Width", mc.mcProfileGetString(inst, "AvidCNC_Profile", "iToolpathSoftlimitWidth", "20"))
end

---------------------------------------------------------------
-- Open Docs function.
---------------------------------------------------------------
function OpenDocs()
    local major, minor = wx.wxGetOsVersion()
    local dir = mc.mcCntlGetMachDir(inst);
    local cmd = "explorer.exe /open," .. dir .. "\\Docs\\"
    if(minor <= 5) then -- Xp we don't need the /open
        cmd = "explorer.exe ," .. dir .. "\\Docs\\"
    end
    wx.wxExecute(cmd);
end
---------------------------------------------------------------
-- Cycle Stop function.
---------------------------------------------------------------
function CycleStop()
	local inst = mc.mcGetInstance("CycleStop()")
	mc.mcCntlCycleStop(inst);
	mc.mcSpindleSetDirection(inst, 0);
	mc.mcCntlSetLastError(inst, "Cycle Stopped");
		
	local hEssHcZ_DRO_Force_Sync_With_Aux = mc.mcRegGetHandle(inst, "ESS/HC/Z_DRO_Force_Sync_With_Aux")
	if (hEssHcZ_DRO_Force_Sync_With_Aux == 0) then
		-- Failure to acquire a handle!
		mc.mcCntlLog(inst, 'TMC3in1 ESS/HC/Z_DRO_Force_Sync_With_Aux Handle Failure', "", -1) -- This will send a message to the log window
	else
		mc.mcRegSetValueLong(hEssHcZ_DRO_Force_Sync_With_Aux, 1)
		mc.mcCntlLog(inst, 'Cycle Stop forcing an ESS Z sync', "", -1) -- This will send a message to the log window
	end

end
---------------------------------------------------------------
-- Button Jog Mode Toggle() function.
---------------------------------------------------------------
function ButtonJogModeToggle()
    local cont = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_CONT);
    local jogcont = mc.mcSignalGetState(cont)
    local inc = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_INC);
    local joginc = mc.mcSignalGetState(inc)
    local mpg = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_MPG);
    local jogmpg = mc.mcSignalGetState(mpg)
    
    if (jogcont == 1) then
        mc.mcSignalSetState(cont, 0)
        mc.mcSignalSetState(inc, 1)
        mc.mcSignalSetState(mpg, 0)        
    else
        mc.mcSignalSetState(cont, 1)
        mc.mcSignalSetState(inc, 0)
        mc.mcSignalSetState(mpg, 0)
    end

end

---------------------------------------------------------------
-- Ref All Home() function.
---------------------------------------------------------------
function RefAllHome()
	local inst = mc.mcGetInstance("Screen load script, RefAllHome()")
	local valEnable = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigEnableSoftLimitsAfterHomed", 1)
	local valSimHome = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigHomeXYSimultaneously", 0)
  local valCustomHoming = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigCustHomingEnabled", 0)
  local msg = ""

	mc.mcAxisDerefAll(inst)  --Just to turn off all ref leds
	mc.mcAxisHomeAll(inst)
  coroutine.yield() --yield coroutine so we can do the following after motion stops
  
  if (valEnable == 1) then
    pf.EnableSoftLimits()
    msg = "Homing of machine is complete. Soft limits will now be enabled."
  else
    msg = "Homing of machine is complete."
  end

	wx.wxMessageBox(msg, "Homing")

end

---------------------------------------------------------------
-- Ref All Home() function.
---------------------------------------------------------------
function RefXYZHome()
	--Ref Z Axis
	mc.mcAxisDeref(inst, 2)
	mc.mcAxisHome(inst, 2)
	coroutine.yield()
	
	--Ref X Axis
	mc.mcAxisDeref(inst, 0)
	mc.mcAxisHome(inst, 0)
	coroutine.yield()
	
	--Ref Y Axis
	mc.mcAxisDeref(inst, 1)
	mc.mcAxisHome(inst, 1)
	coroutine.yield()
	
	local hHcCommand = mc.mcRegGetHandle(inst, string.format("ESS/HC/Command"))
	if (hHcCommand == 0) then
		mc.mcCntlLog(inst, "Failure to acquire handle", "" -1)
	else
		mc.mcRegSetValueString(hHcCommand, "(HC_WORK_Z_ZEROED=1)") 
		mc.mcCntlLog(inst, '....RefXYZHome() said that axes were homed', "", -1) -- This will send a message to the log window
	end
	
	wx.wxMessageBox('Referencing is complete')
end

---------------------------------------------------------------
-- Ref A Axis Home() function.
---------------------------------------------------------------
function RefAHome()
	mc.mcAxisDeref(inst, mc.A_AXIS)
	mc.mcAxisHome(inst, mc.A_AXIS)
	coroutine.yield()
	
	wx.wxMessageBox("Referencing is complete")
end
---------------------------------------------------------------
-- Go To Work Zero() function.
---------------------------------------------------------------
function GoToWorkZero()
	local inst = mc.mcGetInstance("GoToWorkZero()")
	local val = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local msg = "G0 G90 X0 Y0\nG" .. val
	mc.mcCntlMdiExecute(inst, msg)

	--mc.mcCntlMdiExecute(inst, "G00 X0 Y0")--Without A and Z moves
	--mc.mcCntlMdiExecute(inst, "G00 X0 Y0 A0")--Without Z moves
    --mc.mcCntlMdiExecute(inst, "G00 G53 Z0\nG00 X0 Y0 A0\nG00 Z0")--With Z moves
end


-- return true if we can start; false if we aren't on line 1 and the user doesn't want to start.
-- I kept starting the machine at a line I didn't want to after doing a manual Stop or eStop.
function VerifyCanStart()
	local inst = mc.mcGetInstance()

	lineNumber, rc = mc.mcCntlGetGcodeLineNbr(inst)
	if rc == mc.MERROR_NOERROR then
		mc.mcCntlSetLastError(inst, "line:"..lineNumber)
		if lineNumber > 1 then
			rc = wx.wxMessageBox("GCode Line is not at the start!\nAre you sure you want to start?", 
				"GCode not at line 1", wx.wxYES_NO)
			if (rc == wx.wxYES) then
				return true
			end
		else
			return true
		end
	else
		mc.mcCntlSetLastError(inst, "Failed to get current gcode line number.")
	end
	return false
end


---------------------------------------------------------------
-- Cycle Start() function.
---------------------------------------------------------------
function CycleStart()
    local rc;
    local tab, rc = scr.GetProperty("MainTabs", "Current Tab")
    local tabG_Mdione, rc = scr.GetProperty("nbGCodeMDI1", "Current Tab")
	local selectedTool = mc.mcToolGetSelected(inst)
		
	local hreg_mtcInProgress, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/ToolChange/MTC/In_Progress");
	if (rc ~= mc.MERROR_NOERROR) then
		mc.mcCntlLog(inst, "CycleStart(): Failed to get current gcode line number, rc="..rc, "", -1);
	else
		local mtcInProgress = mc.mcRegGetValue(hreg_mtcInProgress);
		if (mtcInProgress == 1) then
			-- manual tool change in progress
			mc.mcToolSetCurrent(inst, selectedTool);
			mc.mcRegSetValue(hreg_mtcInProgress, 0);
			local currentLine, rc = mc.mcCntlGetGcodeLineNbr(inst);
			if (rc ~= mc.MERROR_NOERROR) then
				mc.mcCntlLog(inst, "CycleStart(): Failed to get current gcode line number, rc="..rc, "", -1);
			else
				rc = mc.mcCntlSetGcodeLineNbr(inst, currentLine + 1);
				if (rc ~= mc.MERROR_NOERROR) then
					mc.mcCntlLog(inst, "CycleStart(): Failed to set current gcode line number, rc="..rc, "", -1);
				end
			end
		end
	end
    
    if (tonumber(tabG_Mdione) == 1) then
        local state = mc.mcCntlGetState(inst);
        if (state == mc.MC_STATE_MRUN_MACROH) then 
            mc.mcCntlCycleStart(inst);
            mc.mcCntlSetLastError(inst, "Do Cycle Start");
        else 
            scr.ExecMdi('mdi1');
            mc.mcCntlSetLastError(inst, "Do MDI 1");
        end
    else
		if VerifyCanStart() then		
			--Do CycleStart
			mc.mcCntlSetLastError(inst, "Do Cycle Start");
			mc.mcCntlCycleStart(inst);
		else
			mc.mcCntlSetLastError(inst, "Cycle start aborted by user.");
		end
    end
end

-------------------------------------------------------
--  Seconds to time Added 5-9-16
-------------------------------------------------------
--Converts decimal seconds to an HH:MM:SS.xx format
function SecondsToTime(seconds)
	if seconds == 0 then
		return "00:00:00.00"
	else
		local hours = string.format("%02.f", math.floor(seconds/3600))
		local mins = string.format("%02.f", math.floor((seconds/60) - (hours*60)))
		local secs = string.format("%04.2f",(seconds - (hours*3600) - (mins*60)))
		return hours .. ":" .. mins .. ":" .. secs
	end
end

-------------------------------------------------------
--  Decimal to Fractions
-------------------------------------------------------
function DecToFrac(axis)
	--Determine position to get and labels to set.
    local work = mc.mcAxisGetPos(inst, axis)
	local lab = string.format("lblFrac" .. tostring(axis))
	local labNum = string.format("lblFracNum" .. tostring(axis))
	local labDen = string.format("lblFracDen" .. tostring(axis))
    local sign = (" ")		--Use a blank space so we do not get any errors.
	
    if work < 0 then	--Change the sign to -
		sign = ("-")
	end
	
	work = math.abs (work)
	local remainder = math.fmod(work, .0625)

	if remainder >= .03125 then 	--Round up to the closest 1/16
		work = work + remainder
	else							--Round down to the closest 1/16
		work = work - remainder
	end

	local inches = math.floor(work / 1.000)
	local iremainder = work % 1.000
	local halves = math.floor(iremainder / .5000)
	local remainder = iremainder % .5000
	local quarters = math.floor(remainder / .2500)
	local remainder = remainder % .2500
	local eights = math.floor(remainder / .1250)
	local remainder = remainder % .1250
	local sixteens = math.floor(remainder / .0625)

	numar = 0	--Default to 0. The next if statement will change it if needed.
	denom = 0	--Default to 0. The next if statement will change it if needed.

	if sixteens > 0 then
		numar = math.floor(iremainder / .0625)
		denom = 16
	elseif eights > 0 then
		numar = math.floor(iremainder / .1250)
		denom = 8
	elseif quarters > 0 then
		numar = math.floor(iremainder / .2500)
		denom = 4
	elseif halves > 0 then
		numar = math.floor(iremainder / .5000)
		denom = 2
	end
	
    scr.SetProperty((lab), 'Label', (sign) .. tostring(inches))
	scr.SetProperty((labNum), 'Label', tostring(numar))
	scr.SetProperty((labDen), 'Label', "/" .. tostring(denom))
end

---------------------------------------------------------------
-- Set Button Jog Mode to Cont.
---------------------------------------------------------------
local cont = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_CONT);
local jogcont = mc.mcSignalGetState(cont)
mc.mcSignalSetState(cont, 1)

---------------------------------------------------------------
--Timer panel example
---------------------------------------------------------------
TimerPanel = wx.wxPanel (wx.NULL, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxSize( 0,0 ) )
timer = wx.wxTimer(TimerPanel)
TimerPanel:Connect(wx.wxEVT_TIMER,
function (event)
    wx.wxMessageBox("Hello")
    timer:Stop()
end)
     
---------------------------------------------------------------
-- Get fixtue offset pound variables function Updated 5-16-16
---------------------------------------------------------------
function GetFixOffsetVars()
    local FixOffset = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_14)
    local Pval = mc.mcCntlGetPoundVar(inst, mc.SV_BUFP)
    local FixNum, whole, frac

    if (FixOffset ~= 54.1) then --G54 through G59
        whole, frac = math.modf (FixOffset)
        FixNum = (whole - 53) 
        PoundVarX = ((mc.SV_FIXTURES_START - mc.SV_FIXTURES_INC) + (FixNum * mc.SV_FIXTURES_INC))
        CurrentFixture = string.format('G' .. tostring(FixOffset)) 
    else --G54.1 P1 through G54.1 P100
        FixNum = (Pval + 6)
        CurrentFixture = string.format('G54.1 P' .. tostring(Pval))
        if (Pval > 0) and (Pval < 51) then -- G54.1 P1 through G54.1 P50
            PoundVarX = ((mc.SV_FIXTURE_EXPAND - mc.SV_FIXTURES_INC) + (Pval * mc.SV_FIXTURES_INC))
        elseif (Pval > 50) and (Pval < 101) then -- G54.1 P51 through G54.1 P100
            PoundVarX = ((mc.SV_FIXTURE_EXPAND2 - mc.SV_FIXTURES_INC) + (Pval * mc.SV_FIXTURES_INC))	
        end
    end
PoundVarY = (PoundVarX + 1)
PoundVarZ = (PoundVarX + 2)
return PoundVarX, PoundVarY, PoundVarZ, FixNum, CurrentFixture
--PoundVar(Axis) returns the pound variable for the current fixture for that axis (not the pound variables value).
--CurretnFixture returned as a string (examples G54, G59, G54.1 P12).
--FixNum returns a simple number (1-106) for current fixture (examples G54 = 1, G59 = 6, G54.1 P1 = 7, etc).
end
    
---------------------------------------------------------------
-- Button Enable function
---------------------------------------------------------------
-- Edited 11-8-2015
function ButtonEnable() --This function enables or disables buttons associated with an axis if the axis is enabled or disabled.

    AxisTable = {
        [0] = 'X',
        [1] = 'Y',
        [2] = 'Z',
        [3] = 'A',
        [4] = 'B',
        [5] = 'C'}
        
    for Num, Axis in pairs (AxisTable) do -- for each paired Num (key) and Axis (value) in the Axis table
        local rc = mc.mcAxisIsEnabled(inst,(Num)) -- find out if the axis is enabled, returns a 1 or 0
        scr.SetProperty((string.format ('btnPos' .. Axis)), 'Enabled', tostring(rc)); --Turn the button on or off
        scr.SetProperty((string.format ('btnNeg' .. Axis)), 'Enabled', tostring(rc)); --Turn the button on or off
        scr.SetProperty((string.format ('btnZero' .. Axis)), 'Enabled', tostring(rc)); --Turn the button on or off
        scr.SetProperty((string.format ('btnRef' .. Axis)), 'Enabled', tostring(rc)); --Turn the button on or off
    end
    
end

ButtonEnable()

----------------------------------------
-- Retract		added 9/19/2016
----------------------------------------
function SetRetractCode()
    local inst = mc.mcGetInstance();
    local hReg = mc.mcRegGetHandle(inst, "/core/inst/RetractCode");
    mc.mcRegSetValueString(hReg, "G80G40G90G20\\nG53 G00 Z0\\nM5\\nG53 G00 X0Y0"); --This is the Gcode string that will be executed when retract is requested
end

SetRetractCode();

----------------------------------------
-- Enable KeyboardJog on startup
----------------------------------------
function StartupEnableKeyboardJog()
	DisableKeyboard()
end

----------------------------------------
-- Enable Keyboard
----------------------------------------
function EnableKeyboard()
	SetKeyboardInputsEnabled(1)
	scr.SetProperty('bmbKeyboardJog', 'Image', 'toggle_ON.png')
	
	--        mc.mcCntlSetLastError(inst, debug.traceback)

end

----------------------------------------
-- Disable Keyboard
----------------------------------------
function DisableKeyboard()
	SetKeyboardInputsEnabled(0)
	scr.SetProperty('bmbKeyboardJog', 'Image', 'toggle_OFF.png')
end

---------------------------------------------------------------
-- Go To X Zero() function.
---------------------------------------------------------------
function GoToXzero()
	mc.mcCntlMdiExecute(inst, "G00 X0")
end

---------------------------------------------------------------
-- Go To Y Zero() function.
---------------------------------------------------------------
function GoToYzero()
	mc.mcCntlMdiExecute(inst, "G00 Y0")
end

---------------------------------------------------------------
-- Go To Z Zero() function.
---------------------------------------------------------------
function GoToZzero()
	mc.mcCntlMdiExecute(inst, "G00 Z0")
end

---------------------------------------------------------------
-- Go To A Zero() function.
---------------------------------------------------------------
function GoToAzero()
	mc.mcCntlMdiExecute(inst, "G00 A0")
end



function GetRegister(regname)
	local inst = mc.mcGetInstance()
	local hreg = mc.mcRegGetHandle(inst, string.format("iRegs0/%s", regname))
	return mc.mcRegGetValueString(hreg)
end

function WriteRegister(regname, regvalue)
	local inst = mc.mcGetInstance()
	local hreg = mc.mcRegGetHandle(inst, string.format("iRegs0/%s", regname))
	mc.mcRegSetValueString(hreg, tostring(regvalue))
end

-- function (used in Sig Lib) to enable and disable Axis Limits Override for X-Axis --
function EnableLimitOverride(state)
	local inst = mc.mcGetInstance('EnableLimitOverride()')
		
	local hsig_LimitOver, rc = mc.mcSignalGetHandle(inst, mc.ISIG_LIMITOVER)
	local valConfigModel = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sConfigModel", "PRO CNC")

	if (rc ~= mc.MERROR_NOERROR) then
		mc.mcCntlLog(inst, 'Signal Lib: Failure to aquire handle for ISIG_LIMITOVER', "", -1)
	else
    if ( state == 1 ) then
      wx.wxMilliSleep(50)
      rc = mc.mcSignalSetState(hsig_LimitOver, 1)
      if (rc ~= mc.MERROR_NOERROR) then
        mc.mcCntlLog(inst, "Failure to set state of ISIG_LIMITOVER to 1", "", -1)
      end
    elseif ( state == 0 ) then
      rc = mc.mcSignalSetState(hsig_LimitOver, 0)
      if (rc ~= mc.MERROR_NOERROR) then
        mc.mcCntlLog(inst, 'Failure to set state of ISIG_LIMITOVER to 0', "", -1)
      end
    end
	end
end

------------------------------------------------
--Restore THC Default Settings
------------------------------------------------
function RestoreDefaultTHCSettings()
    local inst = mc.mcGetInstance('RestoreDefaultTHCSettings()');
    local val = nil;
    local msg = "";
    local hreg = 0;
    local rc = mc.MERROR_NOERROR;
    local isImage, isValue = nil, nil;
    local settingsSaved = true;
        
    local TMC3in1Params = {{'iAD1DelayAfterArcOkayEnabled', 'TMC3in1/TMC3IN1_AD1_DELAY_ENABLED', 'bmbTHCDelayAfterArcOk', 0},
        {'iAD3VelocityEnabled', 'TMC3in1/TMC3IN1_AD3_VELOCITY_ENABLED', 'bmbTHCVelocityBased', 0},
        {'iVoltageAD_Enabled', 'TMC3in1/TMC3IN1_VOLTAGE_AD_ENABLED', 'bmbTHCVoltageBased', 0},
        {'iVoltageAD_ATV_BufferSize', 'TMC3in1/TMC3IN1_VOLTAGE_AD_ATV_BUFFER_SIZE', 'droTHCVoltageBasedBuffer', 800},
        {'dAD1DelayValueAfterArcOkay', 'TMC3in1/TMC3IN1_AD1_DELAY_VALUE', 'droTHCDelayAfterArcOkValue', 2.0},
        {'dAD3VelocityPercentage', 'TMC3in1/TMC3IN1_AD3_VELOCITY_PERCENT', 'droTHCVelocityBasedValue', 97.0},
        {'dVoltageAD_PreconditionWindowPercent', 'TMC3in1/TMC3IN1_VOLTAGE_AD_PRECONDITION_WINDOW_PERCENT', 'droTHCVoltagePreconditionPercent', 4.0},
        {'dAD4VoltageThrottlingPercent', 'TMC3in1/TMC3IN1_VOLTAGE_AD_AD4_THC_THROTTLING_PERCENT', 'droTHCVoltageBasedThrottlePercent', 0.0},
        {'dVoltageAD5ATV_PercentAboveCurrentTipVolts', 'TMC3in1/TMC3IN1_VOLTAGE_AD_AD5_ATV_PERCENT_ABOVE_CURRENT_TIP_VOLTS', 'droTHCVoltageBasedAboveTargetTipVolts', 15.0},
        {'dVoltageAD6ATV_PercentBelowCurrentTipVolts', 'TMC3in1/TMC3IN1_VOLTAGE_AD_AD6_ATV_PERCENT_BELOW_CURRENT_TIP_VOLTS', 'droTHCVoltageBasedBelowTargetTipVolts', 15.0},
        };

    -- Set register and screen element values using ini vlaues.
    for _,setting in pairs(TMC3in1Params) do
        hreg, rc = mc.mcRegGetHandle(inst, settings[2]);
        isImage = scr.IsProperty(settings[3], "Image");
        isValue = scr.IsProperty(settings[3], "Value");
        if (rc ~= mc.MERROR_NOERROR) then
            msg = string.format("Failure to acquire register hanlde for %s, rc = %0.0f", settings[2], rc);
            settingsSaved = false;
        else
            -- Registers
            if (settings[1]:sub(1, 1) == "i") then
                val = mc.mcProfileGetInt(inst, "TMC3in1", settings[1], settings[4]);
                mc.mcRegSetValueLong(hreg, val);
            elseif (settings[1]:sub(1, 1) == "d") then
                val = mc.mcProfileGetDouble(inst, "TMC3in1", settings[1], settings[4]);
                mc.mcRegSetValue(hreg, val);
            else
                settingsSaved = false;
                msg = string.format("RestoreDefaultTHCSettings(): Failed to get ini val and set regsiter for %s", settings[1]);
                mc.mcCntlLog(inst, msg, "", -1);
            end

            -- Screen elements
            if isImage and (val == 1) then
                scr.SetProperty(settings[3], "Image", "toggle_ON.png");
            elseif isImage then
                scr.SetProperty(settings[3], "Image", "toggle_OFF.png");
            elseif isValue then
                scr.SetProperty(settings[3], "Value", tostring(val));
            else
                settingsSaved = false;
                msg = string.format("RestoreDefaultTHCSettings(): Failed to set screen element value or image for %s", settings[1]);
                mc.mcCntlLog(inst, msg, "", -1);
            end
        end
    end

    if settingsSaved then
        mc.mcCntlSetLastError(inst, "Restore default THC settings: Screen values updated");
    else
        mc.mcCntlSetLastError(inst, "Restore default THC settings: Failed to set all screen values, see log for details");
    end
end
--------------------------------------------------------

-- Units Mode Toggle Button
function UnitsModeToggle()
	local inst = mc.mcGetInstance("UnitsModeToggle()")
	local Units = math.floor(mc.mcCntlGetUnitsCurrent(inst))	-- get current units mode
	local NewUnitsModal = "G21"
	local NewUnits = 210
	local UnitsLabel = "MMPM"
	local ConvertFactor = 25.4
	
	if (Units == 210) then	-- if currently G21
		NewUnitsModal = "G20"
		NewUnits = 200
		UnitsLabel = "IPM"
		ConvertFactor = 1 / 25.4
	end

	-- rc = mc.mcProfileWriteString(inst, "DefaultMode", "UnitsMode", NewUnitsModal)	-- write new .ini value
	-- msg = "Units Mode changed to " .. NewUnitsModal .. " with a return code of " .. rc
	-- mc.mcCntlLog(inst, "", msg, -1)		-- send message to log

	mc.mcCntlMdiExecute(inst, NewUnitsModal)		-- change units mode
	
	scr.SetProperty("txtJogRateUnits", "Label", UnitsLabel)		-- update units label
	scr.SetProperty("txtFeedRateUnits", "Label", UnitsLabel)	-- update units label
	scr.SetProperty("txtRapidRateUnits", "Label", UnitsLabel)	-- update units label

	-- convert current value DROs as needed	
	local valDroJogRate = scr.GetProperty("droJogRateCur", "Value")		-- get current dro value
	local valDroRapidRate = scr.GetProperty("droRapidRateCur", "Value")		-- get current dro value
	
end
--------------------------------------------------------

-- Convert DRO values --
function droConvert()
	local inst = mc.mcGetInstance("droConvert()")
	local ConvertFactor = 1
	local UserUnits = mc.mcCntlGetUnitsCurrent(inst)
	local DefaultUnits = mc.mcCntlGetUnitsDefault(inst)
	
	if (math.floor(UserUnits) == 200) and (math.floor(DefaultUnits) == 210) then
		ConvertFactor = 1 / 25.4
	elseif (math.floor(UserUnits) == 210) and (math.floor(DefaultUnits) == 200) then
		ConvertFactor = 25.4
	end
	
	return ConvertFactor
	
end
--------------------------------------------------------

-- Resume GCode after manual tool change --
function ResumeGCode()
    local inst = mc.mcGetInstance("ResumeGCode")
    local unitsMode = mc.mcCntlGetUnitsCurrent(inst)	-- get current units mode
    local valConfigHomingSensors = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigHomingSensors", 0)
    local show = nil;

    if (valConfigHomingSensors == 0) and pf.IsHomed() then -- if machine has sensors on X, Y and Z axes
		show = avd.WarningDialog("Machine Movement Warning!", "Machine will move to a safe Z height and then continue with program operation.", "iShowWarningResumeGCode");
		if (show == 0) then
			local zOffset = (unitsMode == 210) and -6.35 or -0.25;
			local rc = mc.mcCntlMdiExecute(inst, "G00 G53 Z" .. zOffset)	-- move Z axis to max clearance height
			if (rc ~= mc.MERROR_NOERROR) then
				mc.mcCntlSetLastError(inst, "Failed to execute gcode, rc="..rc);
			end
			coroutine.yield();
		else
			return;
		end
    else
		show = avd.WarningDialog("Resume G-Code", "Manually move machine to a safe position to resume G-Code and press Cycle Start.", false, true);
		return;
    end

	CycleStart()
end
--------------------------------------------------------

-- End manual tool change
function StopManualToolChange(setTool)
	local inst = mc.mcGetInstance("Fn StopManualToolChange");
	
	-- set current tool number
	local selectedTool, rc = mc.mcToolGetSelected(inst);
	if (rc ~= mc.MERROR_NOERROR) then
		mc.mcCntlLog(inst, "Fn StopManualToolChange: Failure to get selected tool, rc="..rc, "", -1);
	elseif setTool then
		rc = mc.mcToolSetCurrent(inst, selectedTool);
		if (rc ~= mc.MERROR_NOERROR) then
			mc.mcCntlLog(inst, "Fn StopManualToolChange: Failure to set selected tool, rc="..rc, "", -1);
		end
	end
	
	-- reset register for manual tool change in progress
	local hreg_mtcInProgress, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/ToolChange/MTC/In_Progress");
	if (rc ~= mc.MERROR_NOERROR) then
		mc.mcCntlLog(inst, "Fn StopManualToolChange: Failure to get register handle, rc="..rc, "", -1);
	else
		mc.mcRegSetValue(hreg_mtcInProgress, 0);
	end
end
--------------------------------------------------------

-- Update spindle speed DROs.
function SetSpindleSpeedDROs()
  local curOverride
  local curSpindleSpeed, rc = mc.mcSpindleGetCommandRPM(inst);
	if (rc ~= mc.MERROR_NOERROR) then
		msg = "Failure to get spindle commanded RPM with rc of " .. rc;
    mc.mcCntlLog(inst, msg, "", -1);
  else
    curOverride, rc = mc.mcSpindleGetOverride(inst);
    if (rc ~= mc.MERROR_NOERROR) then
      msg = "Failure to get spindle override with rc of " .. rc;
      mc.mcCntlLog(inst, msg, "", -1);
      return;
    end
  end

  -- Calculate 100% spindle speed we can compare to min sindle speed.
  curSpindleSpeed = curSpindleSpeed / curOverride;

	if (curSpindleSpeed <= minSpindleRPM) then
		-- Spindle speed is now less than new minimum, reset speed to min.
		rc = mc.mcSpindleSetCommandRPM(inst, minSpindleRPM);
		if (rc ~= mc.MERROR_NOERROR) then
			msg = "Failure to set spindle commanded RPM with rc of " .. rc;
			mc.mcCntlLog(inst, msg, "", -1);
		end
	end
end
--------------------------------------------------------

-- Update Avid config vars
function GetAvidConfigVars()
	AvidConfigVars.model = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sConfigModel", "PRO CNC");
	AvidConfigVars.cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "Spindle");
	AvidConfigVars.electronics = mc.mcProfileGetString(inst, "AvidCNC_Profile" ,"iConfigElectronics", "CRP800");
	AvidConfigVars.useCustomMinSpindleRPM = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigUseCustomMinSpindleRPM", 0) == 1 and true or false;
	AvidConfigVars.spindleType = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigSpindleType", 0);
	AvidConfigVars.customMinSpindleRPM = mc.mcProfileGetDouble(inst, "AvidCNC_Profile", "dConfigCustomMinSpindleRPM", 1000);
	AvidConfigVars.defaultMinSpindleRPM = mc.mcProfileGetDouble(inst, "AvidCNC_Profile", "dDefaultMinSpindleRPM", AvidConfigVars.spindleType == 0 and 500 or 1000);
	AvidConfigVars.loggingEnabled = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iadvancedlogging", 0) == 1 and true or false;
end

function CheckNumberOfTools()
	local inst = mc.mcGetInstance("CheckNumberOfTools()")
	local fileName = mc.mcCntlGetGcodeFileName(inst)
	local toolCount, tools = pf.GetNumberOfToolsInFile(fileName);
	if (toolCount > 1) then
		avd.MultipleToolWarning(fileName, tools);
	end
end

function ResetSoftLimitEnabledStates(...)
	local inst = mc.mcGetInstance("ResetSoftLimitEnabledStates()");
	local hreg = 0;
	local rc = mc.MERROR_NOERROR;
	local msg = "ResetSoftLimitEnabledStates()";
	
	hreg, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/Config/Soft_Limits/Reset_Enabled_States");
	if (rc ~= mc.MERROR_NOERROR) then
		msg = string.format("%s Failure to acquire register handle, rc=%s", msg, tostring(rc));
		mc.mcCntlLog(inst, msg, "", -1);
	else
		local reset = mc.mcRegGetValue(hreg);
		if (reset == 1) then
			-- Reset soft limits
			pf.ResetSoftLimitEnabledStates(...);
		end
	end
end

--------------------------------------------------------

--------------------------------------------------------
function SetTHCSettingsToggleButtons()
	local inst = mc.mcGetInstance("SetTHCSettingsToggleButtons()")
	local msgBase = "Set THC Settings toggle buttons: "
	
	-- TCHConfigSettings will be nil if there was an error loading THCSettings.json
	if THCConfigSettings then
		for _,ADType in pairs(THCConfigSettings.THCConfig.AntiDiveTypes) do
			
			-- we only want to set states of toggle buttons
			if ADType.Settings.EnableDisable and ADType.Settings.EnableDisable.ScreenElement.IsUsed then
				
				local hreg, rc = mc.mcRegGetHandle(inst, ADType.Settings.EnableDisable.RegPath)
				if (rc ~= mc.MERROR_NOERROR) then
					local msg = msgBase .. 'Failure to aquire a handle for ' .. ADType.Settings.EnableDisable.RegPath
					mc.mcCntlLog(inst, msg, "", -1)
					mc.mcCntlSetLastError(inst, msg)
				else
					local regVal = mc.mcRegGetValueLong(hreg)
					local toggleImg = (regVal == 1) and "ToggleOn" or "ToggleOff"
					scr.SetProperty(ADType.Settings.EnableDisable.ScreenElement.Name, "Image", THCConfigSettings.THCConfig.ScreenImages[toggleImg])
				end
			end
		end
	else
		local msg = msgBase .. "Failure to set toggle buttons, error loading THCConfig.json"
		mc.mcCntlLog(inst, msg, "", -1)
		mc.mcCntlSetLastError(inst, msg)
	end	
end
--------------------------------------------------------

--------------------------------------------------------
function ToggleAntiDiveToggleButton(ADType)
	local inst = mc.mcGetInstance("ToggleAntiDiveToggleButton()")
	local msgBase = "Toggle enable/disable for THC anti-dive type: "
	
	-- TCHConfigSettings will be nil if there was an error loading THCSettings.json
	-- we also need to check if the ADType passed is a valid object in the config file
	if THCConfigSettings and THCConfigSettings.THCConfig.AntiDiveTypes[ADType] then
		ADType = THCConfigSettings.THCConfig.AntiDiveTypes[ADType]
		local hreg, rc = mc.mcRegGetHandle(inst, ADType.Settings.EnableDisable.RegPath)
		if (rc ~= mc.MERROR_NOERROR) then
			local msg = msgBase .. 'Failure to aquire a handle for ' .. ADType.Settings.EnableDisable.RegPath
			mc.mcCntlLog(inst, msg, "", -1)
			mc.mcCntlSetLastError(inst, msg)
		else
			local curRegVal = mc.mcRegGetValueLong(hreg)
			local newRegVal = (curRegVal == 1) and 0 or 1
			local newToggleImg = (curRegVal == 1) and "ToggleOff" or "ToggleOn" 
			mc.mcRegSetValueLong(hreg, newRegVal)
			if ADType.Settings.EnableDisable.ScreenElement.IsUsed then
				scr.SetProperty(ADType.Settings.EnableDisable.ScreenElement.Name, "Image", THCConfigSettings.THCConfig.ScreenImages[newToggleImg])
			end
		end
	else
		local msg = msgBase .. ADType .. ", error loading THCConfig.json or invalid AntiDiveType object"
	end
end
--------------------------------------------------------

--------------------------------------------------------
function RestoreDefaultTHCSettings()
	local inst = mc.mcGetInstance("RestoreDefaultTHCSettings")
	local msgBase = "Restore THC Settings from machine.ini: "
	local valueGroup = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sTHCValueGroup", "Avid-CNC-Default")
	
	-- set screen elements based on updated settings in machine.ini
	-- when registers are changed by TMC3in1 config window they don't
	-- automatically updated the screen DROs
	local function SetScreenElement(element, val)
		if not element.IsUsed then return end
		
		if (element.Type == "toggleButton") then
			local toggleImg = (val == 1) and THCConfigSettings.THCConfig.ScreenImages.ToggleOn or THCConfigSettings.THCConfig.ScreenImages.ToggleOff
			scr.SetProperty(element.Name, "Image", toggleImg)
		elseif (element.Type == "dro") then
			scr.SetProperty(element.Name, "Value", tostring(val))
		end
	end
	
	
	if THCConfigSettings then
		-- loop through each type of anti-dive
		for _,ADType in pairs(THCConfigSettings.THCConfig.AntiDiveTypes) do
			-- loop through all settings for each anti-dive type
			for _,setting in pairs(ADType.Settings) do
				local element = setting.ScreenElement
				local iniParam = "not found"
				local hreg, rc = mc.mcRegGetHandle(inst, setting.RegPath)
				
				if (rc ~= mc.MERROR_NOERROR) then
					local msg = msgBase .. 'Failure to aquire a handle for ' .. setting.RegPath
					mc.mcCntlLog(inst, msg, "", -1)
					mc.mcCntlSetLastError(inst, msg)
				else
					if (setting.DataType == "int") then
						iniParam = mc.mcProfileGetInt(inst, "TMC3in1", setting.IniParameter, math.tointeger(setting.Value[valueGroup]))
						mc.mcRegSetValueLong(hreg, iniParam)
						SetScreenElement(element, iniParam)
					elseif (setting.DataType == "double") then
						iniParam = mc.mcProfileGetDouble(inst, "TMC3in1", setting.IniParameter, tonumber(setting.Value[valueGroup]))
						mc.mcRegSetValue(hreg, iniParam)
						SetScreenElement(element, iniParam)
					else
						local msg = msgBase .. "Invalid data type for " .. setting.IniParameter
						mc.mcCntlLog(inst, msg, "", -1)
					end
				end
			end
		end
	else
		local msg = msgBase .. "Error loading THCConfig.json"
		mc.mcCntlLog(inst, msg, "", -1)
		mc.mcCntlSetLastError(inst, msg)
		
		return
	end
	
	local msg = msgBase .. "THC settings on screen updated"
	mc.mcCntlSetLastError(inst, msg)
end
--------------------------------------------------------

GetAvidConfigVars();
minSpindleRPM = AvidConfigVars.defaultMinSpindleRPM;

callSuccess = xpcall(pf.LoadRegisters,
					function(msg) 
						mc.mcCntlLog(inst, msg, "", -1);
					end,
					"iRegs0",
					"\\Modules\\AvidCNC\\Config\\Registers.json"
					);



-- PLC script
function Mach_PLC_Script()
    local inst = mc.mcGetInstance()
    local rc = 0;
    testcount = testcount + 1
    machState, rc = mc.mcCntlGetState(inst);
    local inCycle = mc.mcCntlIsInCycle(inst);
    
    if ATCTools ~= nil then
    	ATCTools.PLCScript() -- corbin, added to update the LED
    end
    
    -- corbin, fix the touch plate to work with tool offsets. Only runs when it is shown, which shouldn't slow anything down
    if TframeShown then
    	-- It was shown (the button clicked), make sure the dialog is still visible; if it isn't, restore state
    	-- it also might be set back to nil on close...so check for nil and restore state then too.
    	if Tframe == nil or not Tframe:IsShown() then		
    		TframeShown = false -- No longer visible..restore state
    		CWUtilities.RestoreToolHeightActiveState()						
    	end
    end
    
    
    ------------------------------------------
    -- Check for multiple tools in g-code if ignoring tool changes
    ------------------------------------------
    local hreg_checkToolNum, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/ToolChange/Check_Tool_Numbers");
    if (rc == mc.MERROR_NOERROR) then
    	local checkToolNum = mc.mcRegGetValue(hreg_checkToolNum);
      local toolPathPercent = mc.mcToolPathGeneratedPercent(inst);
    	if (checkToolNum == 1) and (toolPathPercent == 100) then
        mc.mcRegSetValue(hreg_checkToolNum, 0);
        scr.StartTimer(0, 250, 1);
    	end
    end
    			
    ------------------------------------------
    -- Check if G-Code file was loaded
    ------------------------------------------
    local hreg_loaded = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/GCode/File_Loaded");
    if (rc == mc.MERROR_NOERROR) then
    	local gcode_loaded = mc.mcRegGetValue(hreg_loaded);
    	if (gcode_loaded == 1) then
    		-- Ignore tool changes
    		local hreg_ignore, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/ToolChange/Ignore_Tool_Changes");
    		local ignore = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigIgnoreToolChanges", 0);
    		if (ignore == 1) then
    			local isInList = false;
    			local fileList = ignoreToolChangeFileList or {};
    			local fileName = mc.mcCntlGetGcodeFileName(inst);
    			for _,listFileName in pairs(fileList) do
    				-- check if loaded file is in list of files to respect tool changes
    				if (listFileName == fileName) then
    					mc.mcRegSetValue(hreg_ignore, 0)
    					isInList = true;
    					break;
    				end;
    			end
    			if (hreg_checkToolNum ~= 0) and (not isInList) then
    				mc.mcRegSetValue(hreg_checkToolNum, 1);
    			end
    		end
    		mc.mcRegSetValue(hreg_loaded, 0);
    	end
    end
    
    ------------------------------------------
    -- Add files for respecting tool changes when ignore tool change option selected
    ------------------------------------------
    local hreg_fileName, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/ToolChange/Respect_File_Name");
    if (rc == mc.MERROR_NOERROR) then
    	local fileName = mc.mcRegGetValueString(hreg_fileName);
    	if (fileName == "RESET") then
    		ignoreToolChangeFileList = {};
    	elseif (fileName ~= "") and (ignoreToolChangeFileList) then
    		table.insert(ignoreToolChangeFileList, fileName);
    	end
    	mc.mcRegSetValueString(hreg_fileName, "");
    end
    
    ------------------------------------------
    -- Manual tool change
    ------------------------------------------
    local hreg_mtc, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/ToolChange/MTC/In_Progress");
    if (rc == mc.MERROR_NOERROR) then
    	local mtcInProgress = mc.mcRegGetValue(hreg_mtc);
    	local selectedtool = mc.mcToolGetSelected(inst);
    	local cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "not found");
    	if (mtcInProgress == 1) and (LastStateMtcInProgress == 0) then
    		-- iReg0/AvidCNC/ToolChange/MTC/In_Progress rising edge
    		scr.SetProperty("lblToolChange", "Label", string.format("Tool change required to tool #%0.0f", selectedtool));
    		scr.SetProperty("OperationsTabs", "Current Tab", "1")
    		scr.SetProperty("btnResumeGCode", "Enabled", (cuttingTool ~= "Plasma") and "1" or "0");
    	elseif (mtcInProgress == 0) and (LastStateMtcInProgress == 1) then
    		-- iReg0/AvidCNC/ToolChange/MTC/In_Progress falling edge
    		scr.SetProperty("lblToolChange", "Label", "Tool change");
    		scr.SetProperty("btnResumeGCode", "Enabled", "0");
    	end
    	LastStateMtcInProgress = mtcInProgress;
    end
    
    ------------------------------------------
    -- Close Mach4 to apply configuration changes
    ------------------------------------------
    do
      local hreg_state, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/State")
      local hreg_restart, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/Restart")
    
      if (hreg_state ~= 0) and (hreg_restart ~= 0) then
        local val_state = mc.mcRegGetValueLong(hreg_state)
        local val_restart = mc.mcRegGetValueLong(hreg_restart)
    
        if (val_state == 0) and (val_restart == 99) then
          mc.mcRegSetValueLong(hreg_restart, 0)
          -- Close Mach4, but sleep is required so Avid config can finish closing.
          -- Otherwise Mach4 won't gracefully close.
          wx.wxMilliSleep(1000)
          mc.mcProfileFlush(inst)
          scr.Exit(false)
        end
      end
    end
    
    
    -------------------------------------------------------
    --  Coroutine resume
    -------------------------------------------------------
    if (wait ~= nil) and (machState == 0) then --wait exist and state == idle
    	local state = coroutine.status(wait)
        if state == "suspended" then --wait is suspended
            coroutine.resume(wait)
        end
    end
    
    -------------------------------------------------------
    --  Coroutine resume
    -------------------------------------------------------
    if (waitHome ~= nil) and (machState == 0) then --wait exist and state == idle
    	local state = coroutine.status(waitHome)
        if state == "suspended" then --wait is suspended
            coroutine.resume(waitHome)
        end
    end
    
    -------------------------------------------------------
    --  Coroutine resume for spindle warm-up
    -------------------------------------------------------
    if (co_swu ~= nil) and (machState == 0) then
    	do
    		local state = coroutine.status(co_swu)
    		if (state == "suspended") then
    			coroutine.resume(co_swu)
    		end
    	end
    end
    
    -------------------------------------------------------
    --  Coroutine resume for Resume G-Code
    -------------------------------------------------------
    if (coResumeGCode ~= nil) and (machState == 0) then
    	local coState = coroutine.status(coResumeGCode);
    	if (coState == "suspended") then
    		coroutine.resume(coResumeGCode);
    	end
    end
    
    -------------------------------------------------------
    --  Current cycle time label update
    -------------------------------------------------------
    --Requires a static text box named "CycleTime" on the screen
    if (machEnabled == 1) then
    	local cycletime = mc.mcCntlGetRunTime(inst, time)
    	scr.SetProperty("CycleTime", "Label", SecondsToTime(cycletime))
    end
    
    -------------------------------------------------------
    -- Last cycle time label update
    -------------------------------------------------------
    local hreg_cycle = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/GCode/Last_Cycle_Time");
    if (hreg_cycle == 0) then
    	-- failure to acquire register handle, do nothing
    else
    	local val_cycle = mc.mcRegGetValueString(hreg_cycle);
    	if (tonumber(val_cycle)) then
    		scr.SetProperty("CycleTimeLast", "Label", SecondsToTime(tonumber(val_cycle)))
    	end
    end
    
    -------------------------------------------------------
    -- Units Mode label updated
    -------------------------------------------------------
    local UnitsModeNew = mc.mcCntlGetUnitsCurrent(inst)
    if (UnitsModeNew ~= LastStateUnitsMode) then
    	LastStateUnitsMode = UnitsModeNew
    	if (UnitsModeNew == 200) then
    		scr.SetProperty("lblUnitsMode", "Label", "Units: G20 (in)")
    		scr.SetProperty("btnUnitsMode", "Label", "Change Units to\nG21 (mm)")
    		scr.SetProperty("lblUnitsModeOffsetsTab", "Label", "Units: G20 (in)")
    		scr.SetProperty("btnUnitsModeOffsetsTab", "Label", "Change Units to\nG21 (mm)")
    		scr.SetProperty("txtJogRateUnits", "Label", "IPM")
    		scr.SetProperty("txtFeedRateUnits", "Label", "IPM")
    		scr.SetProperty("txtRapidRateUnits", "Label", "IPM")
    		
    		-- convert current value DROs
    		local valJogRate = scr.GetProperty("droJogRateCur", "Value")
    		local valRapidRate = scr.GetProperty("droRapidRateCur", "Value")
    		scr.SetProperty("droJogRateCur", "Value", tostring(valJogRate / 25.4))
    		scr.SetProperty("droRapidRateCur", "Value", tostring(valRapidRate / 25.4))
    	elseif (UnitsModeNew == 210) then
    		scr.SetProperty("lblUnitsMode", "Label", "Units: G21 (mm)")
    		scr.SetProperty("btnUnitsMode", "Label", "Change Units to\nG20 (in)")
    		scr.SetProperty("lblUnitsModeOffsetsTab", "Label", "Units: G21 (mm)")
    		scr.SetProperty("btnUnitsModeOffsetsTab", "Label", "Change Units to\nG20 (in)")
    		scr.SetProperty("txtJogRateUnits", "Label", "MMPM")
    		scr.SetProperty("txtFeedRateUnits", "Label", "MMPM")
    		scr.SetProperty("txtRapidRateUnits", "Label", "MMPM")
    		
    		-- convert current value DROs
    		local valJogRate = scr.GetProperty("droJogRateCur", "Value")
    		local valRapidRate = scr.GetProperty("droRapidRateCur", "Value")
    		scr.SetProperty("droJogRateCur", "Value", tostring(valJogRate * 25.4))
    		scr.SetProperty("droRapidRateCur", "Value", tostring(valRapidRate * 25.4))
    	end
    end
    
    -------------------------------------------------------
    -- Stop button implements feed hold before cycle stop
    -------------------------------------------------------
    if (FeedHoldAndThenStop >= 3) then
    	mc.mcCntlLog(inst, "Avid: Stop button pressed 3 times, calling CycleStop()", "", -1)
    	CycleStop()
    	FeedHoldAndThenStop = 0
    	FeedHoldRequested = 0
    elseif (FeedHoldAndThenStop > 0) and (FeedHoldAndThenStop < 3) then
    
    	if (FeedHoldRequested < 1) then
    		-- Feed hold once before stopping
    		mc.mcCntlLog(inst, "FHBC: Stop button pressed, but calling Feed Hold before cycle stop", "", -1)
    		local hEssHcControlFeedHoldPressed = mc.mcRegGetHandle(inst, "ESS/HC/FeedHoldPressed")
    		if ( hEssHcControlFeedHoldPressed == 0) then
    			-- Failure to acquire a handle!
    			mc.mcCntlLog(inst, 'FHBC: Handle Failure', "", -1) -- This will send a message to the log window
    		else
    			mc.mcRegSetValueLong(hEssHcControlFeedHoldPressed, 1)
    			mc.mcCntlLog(inst, 'FHBC: Calling mc.mcCntlFeedHold() ', "", -1) -- This will send a message to the log window
    		end
    		mc.mcCntlFeedHold(inst)
    		FeedHoldRequested = 1
    	end
    	
    	-- Check if axes are still
    	local allStill = true
    	for i = 0, 5 do
    		local regName = string.format("ESS/FeedRate/M%sFeedRateActual", i)
    		local hreg, rc = mc.mcRegGetHandle(inst, regName)
    		if (rc == mc.MERROR_NOERROR) then
    			local rate = mc.mcRegGetValue(hreg)
    			if (rate ~= 0) then
    				allStill = false
    				mc.mcCntlLog(inst, "Avid: Motors not still after feed hold from stop button, motor #"..i, "", -1)
    				break
    			end
    		end
    	end
    	
    	if allStill then
    		FeedHoldAndThenStop = 0
    		FeedHoldRequested = 0
    		mc.mcCntlLog(inst, "Avid: Motors still after feed hold from stop button, calling CycleStop()", "", -1)
    		CycleStop()
    	end
    end
    
    -------------------------------------------------------
    -- Avid Config Values
    -------------------------------------------------------
    local valConfigSettingsSaved = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigSettingsSaved", 0)
    if (valConfigSettingsSaved == 1) then
    	pf.WriteIniParams(inst, "int", "AvidCNC_Profile", "iConfigSettingsSaved", 0, AvidConfigVars.loggingEnabled);
    	GetAvidConfigVars();
    	
    	-- after an update to config settings, we need to update minSpindleRPM before setting spindle speed DROs
    	minSpindleRPM = pf.GetMinSpindleSpeed();
    	SetSpindleSpeedDROs();
    end
    
    -------------------------------------------------------
    -- Minimum spindle speed
    -------------------------------------------------------
    local curSpindleRange = mc.mcSpindleGetCurrentRange(inst)
    minSpindleRPM = pf.GetMinSpindleSpeed(curSpindleRange);
    
    --------------------------------------------------------
    --This is the code that restarts us once Arc Okay is detected after a probe crash or the arc going out
    local valEss_HeightControl_ResumeCutting_DelayUntilArcOkay = mc.mcRegGetValueLong(hEss_HeightControl_ResumeCutting_DelayUntilArcOkay)
    
    if (valEss_HeightControl_ResumeCutting_DelayUntilArcOkay == 1) then	--Did the screen set button tell us to start cutting?  It started the Torchfor us
    	
    	--This will print out a message about once a second...
    	valEssResumeCuttingCounter = valEssResumeCuttingCounter + 1;
    	if (valEssResumeCuttingCounter > 20) then
    		mc.mcCntlLog(inst, '>>>>ESS: Resume cuting button started the torch, but we are waiting for Arc Okay', "", -1) 	
    		valEssResumeCuttingCounter = 0;
    	end
    	
    	
    	local valEssArcOkay = mc.mcRegGetValueLong(hEssArcOkay)
    	if(valEssArcOkay == 1)then	--If the Arc Okay is on...
    		mc.mcCntlLog(inst, 'Arc Okay detected.  Calling Cycle Start to resume motion.', "", -1) 
    		mc.mcRegSetValueLong(hEss_HeightControl_ResumeCutting_DelayUntilArcOkay,0)	--_Clear this flag out now
    		CycleStart()
    	end	
    end
    --------------------------------------------------------
    
    --------------------------------------------------------
    --Monitor the registers in the TMC3in1 so we can set the LEDs and status stings accordingly!
    --------------------------------------------------------
    
    --TMC3in1 Report Torch Relay On/Off
    local hLedTorchRelayEss = mc.mcRegGetHandle(inst, "ESS/HC/Torch_Relay_On");
    
    if ( hLedTorchRelayEss == 0) then
        -- Failure to acquire a handle!
    else
        local valLedTorchRelayEss = mc.mcRegGetValueLong(hLedTorchRelayEss)
        if ( valLedTorchRelayEss == LastStateOfTorchRelayRegister) then
    		-- no change occuered so don't change the bmp for the toggle switch
    	else
    		LastStateOfTorchRelayRegister = valLedTorchRelayEss		
    		if (valLedTorchRelayEss == 0) then
    			--Send the off image
    			scr.SetProperty("bmbTorchOnOff","Image","toggle_OFF.png")
    		else
    			--send the on image
    			scr.SetProperty("bmbTorchOnOff","Image","toggle_ON.png")
    		end
    	end
    end
    
    -------------------------------------------------------
    
    -- --TMC3in1 Report TMC3in1 THC Active (set THC Inhibited LED, changed for AvidCNC screen)
    -- local hLedThcActive = mc.mcRegGetHandle(inst, "TMC3in1/REPORT_TMC3IN1_THC_ALLOWED");
    
    -- if ( hLedThcActive == 0) then
    --     -- Failure to acquire a handle!
    --     scr.SetProperty("LedThcInhibited","Value","1")
    -- else
    --     local valLedThcActive = mc.mcRegGetValueLong(hLedThcActive)
    -- 	if ( valLedThcActive == LastStateOfThcAllowedRegister ) then
    -- 		-- no change occured so don't update the LED value
    -- 	else
    -- 		LastStateOfThcAllowedRegister = valLedThcActive
    -- 		--if ( valLedThcActive == 0 or valExpansionReady == 0) then
    -- 		if ( valLedThcActive == 0 ) then
    -- 			scr.SetProperty("LedThcInhibited","Value","1")
    -- 		else
    -- 			scr.SetProperty("LedThcInhibited","Value","0")
    -- 		end
    -- 	end
    -- end
    
    -------------------------------------------------------
    
    -------------------------------------------------------
    -- Reset screen THC values to default after THC Config window opened
    -------------------------------------------------------
    local hreg_ThcConfigWindowSaved = mc.mcRegGetHandle(inst, "TMC3in1/CONFIG_WINDOW_SAVED")
    
    if ( hreg_ThcConfigWindowSaved == 0 ) then
    	-- failure to aquire register handle, do nothing
    else
    	local valThcConfigWindowSaved = mc.mcRegGetValueLong(hreg_ThcConfigWindowSaved)
    	if (valThcConfigWindowSaved == 1) then
    		RestoreDefaultTHCSettings()
    		mc.mcRegSetValueLong(hreg_ThcConfigWindowSaved, 0)
    	end
    end
    -------------------------------------------------------
    
    -------------------------------------------------------
    -- Monitor ESS/State register for exiting config state
    local hreg_EssStateRegister, rc = mc.mcRegGetHandle(inst, "ESS/State")
    if (rc ~= mc.MERROR_NOERROR) then
    	-- failure to acquire reg handle, do nothing
    else
    	local valEssStateRegister = mc.mcRegGetValue(hreg_EssStateRegister)
    	if (LastStateEssStateRegister ~= valEssStateRegister) then
    		if (LastStateEssStateRegister == 1) and (valEssStateRegister == 0) then
    			-- ESS went from CONFIG to NORMAL state
    			pf.SetDiagLeds()
    			local msg = ">>>>>Avid: ESS change from CONFIG to NORMAL state, calling pf.SetDiagLeds()"
    			mc.mcCntlLog(inst, msg, "", -1)
    		end
    		LastStateEssStateRegister = valEssStateRegister
    	end
    end
    -------------------------------------------------------
    
    -------------------------------------------------------
    --  PLC First Run
    -------------------------------------------------------
    if (testcount == 1) then
    	ATCTools.SetMainScreenButtonTitles()	
    	DisableKeyboard()
    	
        -- prb.LoadSettings()
    
        DecToFrac(0)
        DecToFrac(1)
        DecToFrac(2)
    
    	---------------------------------------------------------------
    	-- Set Persistent DROs.
    	---------------------------------------------------------------
    
        DROTable = {
    	[1000] = "droJogRate", 
    	[1001] = "droSurfXPos", 
    	[1002] = "droSurfYPos", 
    	[1003] = "droSurfZPos",
        [1004] = "droInCornerX",
        [1005] = "droInCornerY",
        [1006] = "droInCornerSpaceX",
        [1007] = "droInCornerSpaceY",
        [1008] = "droOutCornerX",
        [1009] = "droOutCornerY",
        [1010] = "droOutCornerSpaceX",
        [1011] = "droOutCornerSpaceY",
        [1012] = "droInCenterWidth",
        [1013] = "droOutCenterWidth",
        [1014] = "droOutCenterAppr",
        [1015] = "droOutCenterZ",
        [1016] = "droBoreDiam",
        [1017] = "droBossDiam",
        [1018] = "droBossApproach",
        [1019] = "droBossZ",
        [1020] = "droAngleXpos",
        [1021] = "droAngleYInc",
        [1022] = "droAngleXCenterX",
        [1023] = "droAngleXCenterY",
        [1024] = "droAngleYpos",
        [1025] = "droAngleXInc",
        [1026] = "droAngleYCenterX",
        [1027] = "droAngleYCenterY",
        [1028] = "droCalZ",
        [1029] = "droGageX",
        [1030] = "droGageY",
        [1031] = "droGageZ",
        [1032] = "droGageSafeZ",
        [1033] = "droGageDiameter",
        [1034] = "droEdgeFinder",
        [1035] = "droGageBlock",
        [1036] = "droGageBlockT"
        }
    	
    	-- ******************************************************************************************* --
    	--  _   _   _  __          __             _____    _   _   _____   _   _    _____   _   _   _  --
    	-- | | | | | | \ \        / /     /\     |  __ \  | \ | | |_   _| | \ | |  / ____| | | | | | | --
    	-- | | | | | |  \ \  /\  / /     /  \    | |__) | |  \| |   | |   |  \| | | |  __  | | | | | | --
    	-- | | | | | |   \ \/  \/ /     / /\ \   |  _  /  | . ` |   | |   | . ` | | | |_ | | | | | | | --
    	-- |_| |_| |_|    \  /\  /     / ____ \  | | \ \  | |\  |  _| |_  | |\  | | |__| | |_| |_| |_| --
    	-- (_) (_) (_)     \/  \/     /_/    \_\ |_|  \_\ |_| \_| |_____| |_| \_|  \_____| (_) (_) (_) --
    	--                                                                                             --
    	-- The following is a loop. As a rule of thumb loops should be avoided in the PLC Script.      --
    	-- However, this loop only runs during the first run of the PLC script so it is acceptable.    --
    	-- ******************************************************************************************* --                                                          
    
        for name,number in pairs (DROTable) do -- for each paired name (key) and number (value) in the DRO table
            local droName = (DROTable[name]) -- make the variable named droName equal the name from the table above
            --wx.wxMessageBox (droName)
            local val = mc.mcProfileGetString(inst, "PersistentDROs", (droName), "NotFound") -- Get the Value from the profile ini
            if(val ~= "NotFound")then -- If the value is not equal to NotFound
                scr.SetProperty((droName), "Value", val) -- Set the dros value to the value from the profile ini
            end -- End the If statement
        end -- End the For loop
        ---------------------------------------------------
    
    	
    	
    	--SetStartupUnits()
    	-- Set Units Mode label and 4th Axis DRO units label --
    	local StartupUnitsMode = mc.mcCntlGetUnitsCurrent(inst)
    	local UnitsLabel = "IPM"
    	if (StartupUnitsMode == 200) then
    		scr.SetProperty("lblUnitsMode", "Label", "Units: G20 (in)")
    		scr.SetProperty("btnUnitsMode", "Label", "Change Units to\nG21 (mm)")
    		scr.SetProperty("lblUnitsModeOffsetsTab", "Label", "Units: G20 (in)")
    		scr.SetProperty("btnUnitsModeOffsetsTab", "Label", "Change Units to\nG21 (mm)")
    	elseif (StartupUnitsMode == 210) then
    		scr.SetProperty("lblUnitsMode", "Label", "Units: G21 (mm)")
    		scr.SetProperty("btnUnitsMode", "Label", "Change Units to\nG20 (in)")
    		scr.SetProperty("lblUnitsModeOffsetsTab", "Label", "Units: G21 (mm)")
    		scr.SetProperty("btnUnitsModeOffsetsTab", "Label", "Change Units to\nG20 (in)")
    		UnitsLabel = "MMPM"
    	end
    	scr.SetProperty("txtJogRateUnits", "Label", UnitsLabel)
    	scr.SetProperty("txtFeedRateUnits", "Label", UnitsLabel)
    	scr.SetProperty("txtRapidRateUnits", "Label", UnitsLabel)
    	
    	---------------------------------------------------
    	-- Set initial state of enable/disable THC Anti-Dive Mode buttons (THC Settings tab)
      ---------------------------------------------------
      SetTHCSettingsToggleButtons()
    
      --[[
    	local AntiDiveModesTable = {
    		['TMC3in1/TMC3IN1_AD1_DELAY_ENABLED'] = 'bmbTHCDelayAfterArcOk',
    		['TMC3in1/TMC3IN1_AD3_VELOCITY_ENABLED'] = 'bmbTHCVelocityBased',
    		['TMC3in1/TMC3IN1_AD4_VOLTAGE_ENABLED'] = 'bmbTHCVoltageBased',
    		['TMC3in1/LOGGING_ENABLED'] = 'bmbTMC3in1EnableLogging',
    	}
    	
    	for reg,element in pairs(AntiDiveModesTable) do
    		local hreg_THC_AntiDive, rc = mc.mcRegGetHandle(inst, reg)
    		local propTest = scr.IsProperty(AntiDiveModesTable[reg], 'Image')
    		if (rc ~= mc.MERROR_NOERROR) then
    			msg = 'Set THC AD Mode screen button states: Failure to aquire a handle for ' .. reg
    			mc.mcCntlLog(inst, msg, "", -1)
    			mc.mcCntlSetLastError(inst, msg)
    		else
    			local regVal = mc.mcRegGetValueLong(hreg_THC_AntiDive)
    			if (propTest == true) then
    				if (regVal == 1) then
    					scr.SetProperty(AntiDiveModesTable[reg], 'Image', 'toggle_ON.png')
    				else
    					scr.SetProperty(AntiDiveModesTable[reg], 'Image', 'toggle_OFF.png')
    				end
    			end
    		end
      end
    		
      --]]
    		
    	---------------------------------------------------
    	-- Set initial state of main Probe ACTIVE / INACTIVE led
    	---------------------------------------------------
    	local hsig_probe, rc = mc.mcSignalGetHandle(inst, mc.ISIG_PROBE)
    	if (rc ~= mc.MERROR_NOERROR) then
    		mc.mcCntlLog(inst, "Failure to aquire handle for Probe Signal", "", -1)
    	else
    		local ProbeSigState = mc.mcSignalGetState(hsig_probe)
    		if (ProbeSigState == 1) then
    			scr.SetProperty('lblProbeSigLED', 'Bg Color', '#0080FF');
    			scr.SetProperty('lblProbeSigLED', 'Fg Color', '#FFFFFF');
    			scr.SetProperty('lblProbeSigLED', 'Label', 'ACTIVE');
    		else
    			scr.SetProperty('lblProbeSigLED', 'Bg Color', '#002929');
    			scr.SetProperty('lblProbeSigLED', 'Fg Color', '#FFFFFF');
    			scr.SetProperty('lblProbeSigLED', 'Label', 'INACTIVE');
    		end
    	end
    	
    	---------------------------------------------------
    	-- Set initial state of TMC3in1 LEDs
    	---------------------------------------------------
    	scr.SetProperty("LedTMC3in1StatusGreen", "Value", "0")
    	scr.SetProperty("LedTMC3in1StatusYellow", "Value", "1")	-- No Communication (with TMC3in1) LED
    	scr.SetProperty("LedTMC3in1StatusRed", "Value", "0")
    	scr.SetProperty("LedDelayAfterArcOkInhibiting", "Value", "0")
    	scr.SetProperty("LedM62M63Inhibiting", "Value", "0")
    	scr.SetProperty("LedVelocityAntiDiveInhibiting", "Value", "0")
    	scr.SetProperty("LedVoltageAntiDiveInhibting", "Value", "0")
    	scr.SetProperty("LedThcInhibited", "Value", "0")
    	scr.SetProperty("LedThcCmdVelUp", "Value", "0")
    	scr.SetProperty("LedThcCmdVelDn", "Value", "0")
    	scr.SetProperty("LedVoltageThrottlingAbove", "Value","0")
    	scr.SetProperty("LedVoltageThrottlingBelow", "Value", "0")
    	
    	---------------------------------------------------
    	--Set initial toggle button images
    	---------------------------------------------------
    	-- Relay 1 and 2 buttons
    	local hsig_Coolant = mc.mcSignalGetHandle(inst, mc.OSIG_COOLANTON)
    	local hsig_Mist = mc.mcSignalGetHandle(inst, mc.OSIG_MISTON)
    	local Relay1Image, Relay2Image = "toggle_OFF.png", "toggle_OFF.png"
    	
    	if (hsig_Coolant == 0) or (hsig_Mist == 0) then
    		mc.mcCntlLog(inst, "Failure to acquire handle, initial button images", "", -1)
    	else
    		local valCoolant = mc.mcSignalGetState(hsig_Coolant)
    		local valMist = mc.mcSignalGetState(hsig_Mist)
    		local valCuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "Spindle")
    		if (valCoolant == 1) then
    			Relay1Image = "toggle_ON.png"
    			if (valCuttingTool == "Router") then
    				Relay2Image = "toggle_ON.png"
    			end
    		end
    		if (valMist == 1) and (valCuttingTool ~= "Router") then
    			Relay2Image = "toggle_ON.png"
    		end
    	end
    	scr.SetProperty("bmbRelay1", "Image", Relay1Image)
    	scr.SetProperty("bmbRelay2", "Image", Relay2Image)
    			
    	-- Spindle and Router buttons
    	local hsig_SpindleOn = mc.mcSignalGetHandle(inst, mc.OSIG_SPINDLEON)
    	if (hsig_SpindleOn == 0) then
    		mc.mcCntlLog(inst, "Failure to acquire handle, initial button images", "", -1)
    	else
    		local valSpindleOn = mc.mcSignalGetState(hsig_SpindleOn)
    		if (valSpindleOn == 1) then
    			scr.SetProperty("bmbSpindleOnOff", "Image", "toggle_ON.png")
    			scr.SetProperty("bmbRouterOnOff", "Image", "toggle_ON.png")
    		else
    			scr.SetProperty("bmbSpindleOnOff", "Image", "toggle_OFF.png")
    			scr.SetProperty("bmbRouterOnOff", "Image", "toggle_OFF.png")
    		end
    	end
    	
    	-- THC button
    	local hreg_THCOnOff = mc.mcRegGetHandle(inst, "ESS/HC/Control_Mode_Enable")
    	if (hreg_THCOnOff == 0) then
    		mc.mcCntlLog(inst, "Failure to acquire handle, initial button images", "", -1)
    	else
    		valTHCOnOff = mc.mcRegGetValueLong(hreg_THCOnOff)
    		if (valTHCOnOff == 1) then
    			scr.SetProperty("bmbTHCOnOff", "Image", "toggle_ON.png")
    		else
    			scr.SetProperty("bmbTHCOnOff", "Image", "toggle_OFF.png")
    		end
    	end
    		
    	-- Torch button
    	local hreg_TorchOnOff = mc.mcRegGetHandle(inst, "ESS/HC/Torch_Relay_On")
    	if (hreg_TorchOnOff == 0) then
    		mc.mcCntlLog(inst, "Failure to acquire handle, initial button images", "", -1)
    	else
    		valTorchOnOff = mc.mcRegGetValueLong(hreg_TorchOnOff)
    		if (valTorchOnOff == 1) then
    			scr.SetProperty("bmbTorchOnOff", "Image", "toggle_ON.png")
    		else
    			scr.SetProperty("bmbTorchOnOff", "Image", "toggle_OFF.png")
    		end
    	end
    	---------------------------------------------------
    	
    	---------------------------------------------------
    	-- Set GUI based on Machine Configuration
    	---------------------------------------------------
      pf.SplitSwitchGUI() -- set screen elements
      pf.SetDRO()	-- set current jog and rapid speed DRO's (due to possible motor tuning changes)
    	
    	---------------------------------------------------
    	-- Set Current Jog Rate and Rapid Rate Velocity DRO
    	---------------------------------------------------
    	local JogRatePerc = mc.mcProfileGetDouble(inst, "Preferences", "JogRate", 100)
    	local RapidRatePerc = scr.GetProperty("droRapidRate", "Value")
    	local ConvertFactor = droConvert()
    	local curJogRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * JogRatePerc / 100) * ConvertFactor
    	local curRapidRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * RapidRatePerc / 100) * ConvertFactor
    	scr.SetProperty("droJogRateCur", "Value", tostring(curJogRate))
    	scr.SetProperty("droRapidRateCur", "Value", tostring(curRapidRate))
    	
    	---------------------------------------------------
    	-- Set DRO Code for current feed rate (only used during program run)
    	---------------------------------------------------
    	scr.SetProperty("droFeedRateCur", "DRO Code", "-1")
      scr.SetProperty("droFeedRateCur", "Value", "0")
      
      SetToolpathLineWidth()
    
      ---------------------------------------------------
    	--Load Machine Configuration dialog if first time opening AvidCNC Profile
    	---------------------------------------------------
      local valInitialMachineConfig = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iInitialMachineConfig", -1)
      local valShowWelcomeMessage = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iShowWelcomeMessage", 0)
      local forcingUpdate = pf.ForceAvidConfig()
      if (valInitialMachineConfig == 0) or forcingUpdate then
        if (valShowWelcomeMessage == 1) then avd.Welcome("New") end
    		package.loaded.AvidMachineConfig = nil
        MachineConfiguration = require "AvidMachineConfig"
      elseif (valShowWelcomeMessage == 1) then
    		avd.Welcome("Update")
      end
    
      ---------------------------------------------------
      -- Write profile version to ini
    	---------------------------------------------------
      if (AvidConfigJson ~= nil) then
        mc.mcProfileWriteString(inst, "AvidCNC_Profile", "sProfileVersion", AvidConfigJson.AvidCNC_Profile_Version)
      end
    
    	---------------------------------------------------
    	-- Set initial states of outputs
    	---------------------------------------------------
    	-- Parts finished
    	local hsig_prtsf = mc.mcSignalGetHandle(inst, mc.OSIG_PRTSF);
    	if (hsig_prtsf == 0) then
    		mc.mcCntlLog(inst, "PLC 1st loop: Failure to acquire signal handle, rc="..rc, "", -1);
    	else
    		mc.mcSignalSetState(hsig_prtsf, 0);
    	end
    
      DisableKeyboard()
    
    end
    
    
    --This is the last thing we do.  So keep it at the end of the script!
    machStateOld = machState;
    machWasEnabled = machEnabled;
    
end

-- Signal script
function Mach_Signal_Script(sig, state)
    if SigLib[sig] ~= nil then
        SigLib[sig](state);
    end
end

-- Message script
function Mach_Message_Script(msg, param1, param2)
    
end

-- Timer script
-- 'timer' contains the timer number that fired the															 script.
function Mach_Timer_Script(timer)
    if timer == 0 then
    	CheckNumberOfTools();
    end
    
end

-- Screen unload script
function Mach_Screen_Unload_Script()
    --Screen unload
    inst = mc.mcGetInstance()
    
    if (Tframe ~= nil) then	-- touch plate frame
    	Tframe:Close()
    	-- Tframe:Destroy()
    end
    
    if (ASframe ~= nil) then	-- touch plate advanced settings frame
    	ASframe:Close()
    	-- ASframe:Destroy()
    end
    
    --Save Jog Rate % to .ini
    local valJogRate = scr.GetProperty("droJogRate", "Value")
    mc.mcProfileWriteString(inst, "Preferences", "JogRate", valJogRate)
    
    -- check modified state of config files
    pf.CheckAllConfigFiles()
    
    
end

-- Default-GlobalScript
-- by Corbin Dunn
-- corbin@corbinstreehouse.com
-- https://www.corbinsworkshop.com
-- ControlGroup-GlobalScript
function btnCycleStart_Left_Up_Script(...)
    local inst = mc.mcGetInstance("Cycle Start Btn");
    local cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "not found");
    local msg = "Cycle Start Btn:";
    
    -- Pre-cycle start checks for spindle cutting tool
    if (cuttingTool == "Spindle") then
      local hsig_Ptc, rc = mc.mcSignalGetHandle(inst, mc.ISIG_INPUT10);
      
    	if (rc ~= mc.MERROR_NOERROR) then
    		msg = string.format("%s Failure to acquire signal handle, rc=%s", msg, rc);
    		mc.mcCntlLog(inst, msg, "", -1);
    	else
        local statePtc = mc.mcSignalGetState(hsig_Ptc);
        
    		if (statePtc == 1) then
          wx.wxMessageBox("Spindle PTC fault signal active!\nCorrect before running G-Code or MDI", "Cycle Start");
          
    			return;
    		end
    	end
    -- Pre-cycle start checks for plasma cutting tool
    elseif (cuttingTool == "Plasma") then
      -- Check for active communications with TMC3in1
    	local hreg_GREEN, rc = mc.mcRegGetHandle(inst, "TMC3in1/REPORT_TMC3IN1_STATUS_GREEN");
      local hreg_RED, rc = mc.mcRegGetHandle(inst, "TMC3in1/REPORT_TMC3IN1_STATUS_RED");
      
    	if (hreg_GREEN == 0) or (hreg_RED == 0) then
    		msg = string.format("%s Failure to acquire register handle for TMC3in1 status", msg);
    		mc.mcCntlLog(inst, msg, "", -1);
    	else
    		local green = mc.mcRegGetValueLong(hreg_GREEN);
        local red = mc.mcRegGetValueLong(hreg_RED);
        
        if (green ~= 1) then
          -- TMC3in1 does not have active communications, don't allow cycle start
          local msg = "TMC3in1 did not have active communications\nwhile trying to Cycle Start G-Code"
          
          if (red == 1) then
            msg = "TMC3in1 is updating firmware!!\nPlease wait for this process to finish before starting G-Code."
          end
    
    			-- Swtich to diagnostics tab for user to see comms status
    			scr.SetProperty("OperationsTabs", "Current Tab", "3");
          wx.wxMessageBox(msg);
          
    			return;
    		end
    	end
    	
    	-- Check if we need to disable soft limits to allow probing during G-Code
      local hreg_reset, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/Config/Soft_Limits/Reset_Enabled_States");
      
    	if (rc ~= mc.MERROR_NOERROR) then
    		msg = string.format("%s Failure to acquire register handle, rc=%s", msg, rc);
    		mc.mcCntlLog(inst, msg, "", -1);
    	else
    		local reset = mc.mcRegGetValue(hreg_reset);
        
        if (reset ~= 1) then
    			pf.DisableSoftLimit(2);
    		end
    	end
    end
    
    CycleStart();
    			
    			
    			
    			
    			
    			
    			
    			
end
function btnFeedHold_Left_Up_Script(...)
    local inst = mc.mcGetInstance('Screen set Feed Hold button') -- Pass in the script number, so we can see the commands called by this script in the log
    
    local hEssHcControlFeedHoldPressed = mc.mcRegGetHandle(inst, "ESS/HC/FeedHoldPressed")
    if ( hEssHcControlFeedHoldPressed == 0) then
        -- Failure to acquire a handle!
        mc.mcCntlLog(inst, 'Screen set Feed Hold Pressed button() Handle Failure', "", -1) -- This will send a message to the log window
    else
    	mc.mcRegSetValueLong(hEssHcControlFeedHoldPressed, 1)
    	mc.mcCntlLog(inst, 'Screenset Feed Hold button() Pressed ', "", -1) -- This will send a message to the log window
    end
    
    mc.mcCntlFeedHold(inst)	--Activate the Mach4 Feedhold
    		
    		
    		
    		
end
function btnStop_Left_Up_Script(...)
    local inst = mc.mcGetInstance("Cycle Stop Btn");
    local cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "not found");
    local msg = "Cycle Stop requesting Feed Hold #"
    
    if (cuttingTool == "Plasma") then
    	-- Attempt to feed hold before issuing cycle stop
    	FeedHoldAndThenStop = FeedHoldAndThenStop + 1
    	mc.mcCntlLog(inst, msg .. FeedHoldAndThenStop, "", -1)
    	
    	ResetSoftLimitEnabledStates()
    else
    	-- Stop cycle
    	CycleStop();
    
    	-- reset manual tool change
    	StopManualToolChange(false);
    	
    	-- Kill spindle warm-up coroutine
    	warmUpRunning = false
    end
    
end
function btnReset_Left_Up_Script(...)
    local inst = mc.mcGetInstance("Reset Btn")
    local cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "not found")
    local hEssHcZ_DRO_Force_Sync_With_Aux = mc.mcRegGetHandle(inst, "ESS/HC/Z_DRO_Force_Sync_With_Aux")
    
    mc.mcCntlReset(inst)
    mc.mcSpindleSetDirection(inst, 0)
    mc.mcCntlSetLastError(inst, '')
    
    -- Sync Z-axis DRO with Z-axis AUX DRO
    if (hEssHcZ_DRO_Force_Sync_With_Aux == 0) then
    	-- Failure to acquire a handle!
    	mc.mcCntlLog(inst, 'TMC3in1 ESS/HC/Z_DRO_Force_Sync_With_Aux Handle Failure', "", -1) -- This will send a message to the log window
    else
    	mc.mcRegSetValueLong(hEssHcZ_DRO_Force_Sync_With_Aux, 1)
    	mc.mcCntlLog(inst, 'Reset forcing an ESS Z sync', "", -1) -- This will send a message to the log window
    end
    
    -- reset manual tool change
    StopManualToolChange(false)
    
    -- Reset soft limit enabled states
    if (cuttingTool == "Plasma") then ResetSoftLimitEnabledStates() end;
    
    -- Kill spindle warm-up coroutine
    warmUpRunning = false
end
-- tabPositionsExtens-GlobalScript
function tabPositionsExtens_On_Enter_Script(...)
    local rc;
    local tabG_Mdi, rc = scr.GetProperty("nbGCodeMDI1", "Current Tab")
    
    --See if we have to do an MDI command
    if (tonumber(tabG_Mdi) == 1 ) then
        scr.SetProperty('btnCycleStart', 'Label', 'Cycle Start\nMDI');
    else
        scr.SetProperty('btnCycleStart', 'Label', 'Cycle Start\nGcode');
    end
    
    ATCTools.SetMainScreenButtonTitles()
end
-- grpToolPath-GlobalScript
function btnDispRight_Left_Up_Script(...)
    -- Right
    local inst = mc.mcGetInstance();
    local rc = scr.SetProperty("toolpath1", "View", "3")
    local rc = scr.SetProperty("toolpath2", "View", "3")
    local rc = scr.SetProperty("toolpath3", "View", "3")
    local rc = scr.SetProperty("toolpath4", "View", "3")
    local rc = scr.SetProperty("toolpath5", "View", "3")
end
function btnDispBottom_Left_Up_Script(...)
    -- Bottom
    local inst = mc.mcGetInstance();
    local rc = scr.SetProperty("toolpath1", "View", "1")
    local rc = scr.SetProperty("toolpath2", "View", "1")
    local rc = scr.SetProperty("toolpath3", "View", "1")
    local rc = scr.SetProperty("toolpath4", "View", "1")
    local rc = scr.SetProperty("toolpath5", "View", "1")
end
function btnDispTop_Left_Up_Script(...)
    --Top
    local inst = mc.mcGetInstance();
    local rc = scr.SetProperty("toolpath1", "View", "0")
    local rc = scr.SetProperty("toolpath2", "View", "0")
    local rc = scr.SetProperty("toolpath3", "View", "0")
    local rc = scr.SetProperty("toolpath4", "View", "0")
    local rc = scr.SetProperty("toolpath5", "View", "0")
end
function btnDispISO_Left_Up_Script(...)
    -- ISO
    local inst = mc.mcGetInstance();
    local rc = scr.SetProperty("toolpath1", "View", "4")
    local rc = scr.SetProperty("toolpath2", "View", "4")
    local rc = scr.SetProperty("toolpath3", "View", "4")
    local rc = scr.SetProperty("toolpath4", "View", "4")
    local rc = scr.SetProperty("toolpath5", "View", "4")
end
function btnDispLeft_Left_Up_Script(...)
    -- Left
    local inst = mc.mcGetInstance();
    local rc = scr.SetProperty("toolpath1", "View", "2")
    local rc = scr.SetProperty("toolpath2", "View", "2")
    local rc = scr.SetProperty("toolpath3", "View", "2")
    local rc = scr.SetProperty("toolpath4", "View", "2")
    local rc = scr.SetProperty("toolpath5", "View", "2")
    
end
function btnToolPathDisplaySettings_Left_Up_Script(...)
    package.loaded.ToolpathDisplay = nil
    tp = require "ToolpathDisplay"
    tp.Dialog()
end
-- nbGCodeInput1-GlobalScript
function nbGCodeInput1_On_Enter_Script(...)
    scr.SetProperty('btnCycleStart', 'Label', 'Cycle Start\nGcode');
    --DisableKeyboard()
end
-- nbMDIInput-GlobalScript
function nbMDIInput_On_Enter_Script(...)
    scr.SetProperty('btnCycleStart', 'Label', 'Cycle Start\nMDI');
    DisableKeyboard()
end
function nbMDIInput_On_Exit_Script(...)
    EnableKeyboard();
end
function btnRunFromHere_Left_Up_Script(...)
    -- Check if file is loaded before showing warning dialog
    local inst = mc.mcGetInstance("Run From Here button");
    local fineName = mc.mcCntlGetGcodeFileName(inst);
    if (fileName == "") then return end;
    
    -- Warning dialog
    local cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "scuttingtool", "cutting tool");
    if (cuttingTool ~= "Plasma") then
    	local msg = "If using \"Run From Here\" to start mid-program, you must manually start your "..string.lower(cuttingTool).." before pressing \"Cycle Start\".";
      avd.WarningDialog("Machine Operation Warning!", msg, "iShowWarningRunFromHere", true);
      scr.DoFunctionCode(21)
    else
      scr.DoFunctionCode(21)
    end
    
end
function btnEditGcode_Left_Up_Script(...)
    DisableKeyboard();
end
function btnCloseGcode_Left_Up_Script(...)
    local inst = mc.mcGetInstance("Close GCode Button");
    local hreg, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/ToolChange/Ignore_Tool_Changes");
    local ignore = mc.mcProfileGetInt(inst, "AvidCNC_Profile", "iConfigIgnoreToolChanges", 0);
    
    if (rc ~= mc.MERROR_NOERROR) then
    	mc.mcCntlLog(inst, "Close GCode Button: Failure to acquire register handle, rc="..rc, "", -1);
    else
    	mc.mcRegSetValue(hreg, ignore);
    end
    
end
function lblCurrentFileDisplay_On_Update_Script(...)
    local fileName = select(1, ...);
    local inst = mc.mcGetInstance("Screen lblCurrentFileDisplay");
    local rc = mc.MERROR_NOERROR;
    local hreg_cycle = 0;
    local hreg_loaded = 0;
    
    -------------------------------------------------
    -- Reset last cycle time DRO
    -------------------------------------------------
    hreg_cycle, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/GCode/Last_Cycle_Time");
    if (rc ~= mc.MERROR_NOERROR) then
    	mc.mcCntlLog(inst, "File Name Text Box: Failure to acquire register handle, rc="..rc, "", -1);
    else
    	mc.mcRegSetValue(hreg_cycle, 0);
    end
    
    -------------------------------------------------
    -- Stop manual tool change with any onUpdate event
    -------------------------------------------------
    StopManualToolChange();
    
    -------------------------------------------------
    -- Set registers so we can see a G-Code file was loaded
    -------------------------------------------------
    if (fileName == "") then return fileName end;
    	
    hreg_loaded, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/GCode/File_Loaded");
    if (rc ~= mc.MERROR_NOERROR) then
    	mc.mcCntlLog(inst, "File Name Text Box: Failure to acquire register handle, rc="..rc, "", -1);
    	return fileName;
    else
    	mc.mcRegSetValue(hreg_loaded, 1);
    end
    
    
    return fileName;
end
function btnRewindGcode_Left_Up_Script(...)
    local inst = mc.mcGetInstance('Screenset Rewind button') -- Pass in the script number, so we can see the commands called by this script in the log
    local hEssHcZ_DRO_Force_Sync_With_Aux = mc.mcRegGetHandle(inst, "ESS/HC/Z_DRO_Force_Sync_With_Aux")
    
    mc.mcCntlRewindFile(inst)
    
    if (hEssHcZ_DRO_Force_Sync_With_Aux == 0) then
    	-- Failure to acquire a handle!
    	mc.mcCntlLog(inst, 'TMC3in1 ESS/HC/Z_DRO_Force_Sync_With_Aux Handle Failure', "", -1) -- This will send a message to the log window
    else
    	mc.mcRegSetValueLong(hEssHcZ_DRO_Force_Sync_With_Aux, 1)
    	mc.mcCntlLog(inst, 'Rewind forcing an ESS Z sync', "", -1) -- This will send a message to the log window
    end
end
function btnResumeCut_Left_Up_Script(...)
    -- Disable soft limts for Z axis when using a plasma cutting tool
    local cuttingTool = mc.mcProfileGetString(inst, "AvidCNC_Profile", "sCuttingTool", "not found");
    local hreg, rc = mc.mcRegGetHandle(inst, "iRegs0/AvidCNC/Config/Soft_Limits/Reset_Enabled_States");
    if (rc ~= mc.MERROR_NOERROR) then
    	local msg = string.format("Resume Cutting Button: Failure to acquire register handle, rc=%s", rc);
    	mc.mcCntlLog(inst, msg, "", -1);
    else
    	local reset, rc = mc.mcRegGetValue(hreg);
    	if (reset ~= 1) and (cuttingTool == "Plasma") then
    		-- Don't disable soft limits again if we're already in a reset soft limit state
    		pf.DisableSoftLimit(2)
    	end
    end
    
    -- Resume Cutting button script
    local inst = mc.mcGetInstance('Screen set H.C. Cut Resume button') 
    local hHcCommand = mc.mcRegGetHandle(inst, string.format("ESS/HC/Command"))  
    mc.mcRegSetValueString(hHcCommand, "(ESS_TORCH_RESUME_WAIT_FOR_ARC_OKAY=1)") 
    
    local hEss_HeightControl_ResumeCutting_DelayUntilArcOkay = mc.mcRegGetHandle(inst, string.format("ESS/HC/Resume_Cutting__Delay_Until_Arc_Okay"))  
    mc.mcRegSetValueLong(hEss_HeightControl_ResumeCutting_DelayUntilArcOkay, 1) 
    
    mc.mcCntlLog(inst, 'ESS Cut Resume button pressed. Starting torch and resuming the cut!', "", -1) -- This will send a message to the log window
end
-- grpMTC-GlobalScript
function btnGoToMTCLoc_Left_Up_Script(...)
    -- Return To Position
    ReturnToPosition() -- This runs the Return to Position Function that is in the screenload script.
    
end
function btnResumeGCode_Left_Up_Script(...)
    coResumeGCode = coroutine.create(ResumeGCode);
end
-- grpProgramTools-GlobalScript
function btnFetchToolPocket1_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket2_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket3_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket4_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket5_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket6_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket7_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket8_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket9_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket10_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnATCPutBack_2__Left_Up_Script(...)
    ATCTools.PutBackCurrentTool()
end
function btnFetchToolPocket11_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnFetchToolPocket12_Left_Up_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
-- tabOffsets-GlobalScript
function tabOffsets_On_Enter_Script(...)
    mc.mcProfileWriteInt(inst, "AvidCNC_Profile", "iUpdateOffsetsCounter", 1)
end
function btnUnitsModeOffsetsTab_Left_Up_Script(...)
    UnitsModeToggle()
end
-- grpFixtureTable-GlobalScript
function luaFixtureTable_Script(...)
    local inst = mc.mcGetInstance("panelFixtureTable")
    
    -- local profile = mc.mcProfileGetName(inst)
    local path = mc.mcCntlGetMachDir(inst)
    
    package.path = package.path .. ";" .. path .. "\\Modules\\AvidCNC\\?.luac;" 
    
    package.loaded.FixtureTable = nil
    touFT = require "FixtureTable"
    
    touFT.FixtureOffsets()
end
-- nbpMachineConfig-GlobalScript
function luaSelectTool_Script(...)
    --Load Select Tool module into parent panel
    local inst = mc.mcGetInstance()
    
    -- local profile = mc.mcProfileGetName(inst)
    local path = mc.mcCntlGetMachDir(inst)
    package.path = package.path .. ";" .. path .. "\\Modules\\AvidCNC\\?.luac"
    -- package.path = path .. "\\AvidCNC\\?.luac;" 
    
    package.loaded.SelectTool = nil
    touST = require "SelectTool"
    
    STframe = touST.MachineSetup()
end
-- tabATCTools-GlobalScript
-- by corbin dunn
-- corbin@corbinstreehouse.com

package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
local ATCTools = require 'ATCTools'
function tabATCTools_On_Enter_Script(...)
    ATCTools.OnTabShow()
end
function tabATCTools_On_Exit_Script(...)
    ATCTools.OnTabHide()
end
function droATCCurrentTool_On_Update_Script(...)
    val = select(1, ...)
    ATCTools.CurrentToolChanged()
    return val
end
function droATCCurrentTool_On_Modify_Script(...)
    val = select(1, ...)
    ATCTools.DoM6G43(val)
    return val
    
end
-- grpToolFork1-GlobalScript
function droToolForToolFork1_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork1_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork1_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork1_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork1_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork2-GlobalScript
function droToolForToolFork2_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork2_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork2_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork2_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork2_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork3-GlobalScript
function droToolForToolFork3_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork3_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork3_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork3_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork3_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork4-GlobalScript
function droToolForToolFork4_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork4_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork4_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork4_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork4_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork5-GlobalScript
function droToolForToolFork5_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork5_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork5_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork5_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork5_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork7-GlobalScript
function droToolForToolFork7_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork7_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork7_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork7_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork7_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork6-GlobalScript
function droToolForToolFork6_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork6_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork6_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork6_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork6_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork8-GlobalScript
function droToolForToolFork8_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork8_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork8_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork8_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork8_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork9-GlobalScript
function droToolForToolFork9_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork9_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork9_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork9_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork9_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
-- grpToolFork10-GlobalScript
function droToolForToolFork10_On_Modify_Script(...)
    ATCTools.OnModifyToolForkForTool(...)
end
function btnFetchFork10_Clicked_Script(...)
    ATCTools.OnFetchButtonClicked(...)
end
function btnRemoveFork10_Clicked_Script(...)
    ATCTools.OnRemoveButtonClicked(...)
end
function btnTouchOffFork10_Clicked_Script(...)
    ATCTools.OnTouchOffClicked(...)
end
function txtToolDescForToolFork10_On_Modify_Script(...)
    ATCTools.OnModifyToolDescription(...)
end
function btnM6G43_Left_Up_Script(...)
    local val = scr.GetProperty("droATCCurrentTool", "Value")
    ATCTools.DoM6G43(val)
end
-- grpToolOffset(1)-GlobalScript
function btnSetTool_Clicked_Script(...)
    --Set Tool button
    local inst = mc.mcGetInstance()			  
    local GageBlock = scr.GetProperty("droGageBlockT", "Value")
    local CurTool = mc.mcToolGetCurrent(inst) --Current Tool Num
    local OffsetState = mc.mcCntlGetPoundVar(inst, 4008) --Current Height Offset State
    mc.mcCntlGcodeExecuteWait(inst, "G49")
    GageBlock = tonumber(GageBlock)
    local ZPos = mc.mcAxisGetPos(inst, mc.Z_AXIS)
    local OffsetVal = ZPos - GageBlock
    mc.mcToolSetData(inst, mc.MTOOL_MILL_HEIGHT, CurTool, OffsetVal)
    mc.mcCntlSetLastError(inst, string.format("Tool %.0f Height Offset Set: %.4f", CurTool, OffsetVal))
    if (OffsetState ~= 49) then
        mc.mcCntlMdiExecute(inst, string.format("G%.1f", OffsetState))
    end
    ATCTools.UpdateUI()
end
function droGageBlockT_On_Modify_Script(...)
    local inst = mc.mcGetInstance()
    local val = scr.GetProperty("droGageBlockT", "Value")
    mc.mcProfileWriteString(inst, "PersistentDROs", "droGageBlockT", string.format (val)) --Create a register and write to it
end
-- grpZOffset(1)-GlobalScript
function droGageBlock_On_Modify_Script(...)
    local inst = mc.mcGetInstance()
    local val = scr.GetProperty("droGageBlock", "Value")
    mc.mcProfileWriteString(inst, "PersistentDROs", "droGageBlock", string.format (val)) --Create a register and write to it
end
function btnSetZ_Clicked_Script(...)
    -- Set Z button
    local inst = mc.mcGetInstance()			  
    local GageBlock = scr.GetProperty("droGageBlock", "Value")
    local CurTool = mc.mcToolGetCurrent(inst) --Current Tool Num
    local CurH = mc.mcCntlGetPoundVar(inst, 2032) --Current Selected H Offset
    local CurHVal = mc.mcCntlGetPoundVar(inst, 2035) --Value of Current H Offset
    local OffsetState = mc.mcCntlGetPoundVar(inst, 4008) --Current Height Offset State
    if (OffsetState == 49) then
        CurHVal = 0
    end
    GageBlock = tonumber(GageBlock)
    local ZPos = mc.mcAxisGetMachinePos(inst, mc.Z_AXIS)
    XVar, YVar, ZVar = GetFixOffsetVars()
    local OffsetVal = ZPos - GageBlock - CurHVal
    mc.mcCntlSetPoundVar(inst, ZVar, OffsetVal)
    mc.mcCntlSetLastError(inst, string.format("Z Offset Set: %.4f", OffsetVal))
end
function btnATCPutBack_Left_Up_Script(...)
    ATCTools.PutBackCurrentTool()
end
function btnSetMTCLoc_1__Clicked_Script(...)
    -- Remember Position
    if (pf.IsHomed()) then
      XPos, YPos, ZPos = RememberPosition() -- This runs the Remember Position function that is in the screenload script
    
      XPos = string.format("%0.4f", XPos)
      YPos = string.format("%0.4f", YPos)
      ZPos = string.format("%0.4f", ZPos)
    
      msg = 'MTC location set to:\n\nMACHINE COORDINATES:\nX Position: ' .. XPos .. '\nY Postion: ' .. YPos .. '\nZ Postion: ' .. ZPos
      wx.wxMessageBox(msg, "Manual Tool Change")
    else
      wx.wxMessageBox("Your machine must be homed\nbefore setting MTC location", "Manual Tool Change")
    end
end
function btnGoToMTCLoc_1__Left_Up_Script(...)
    -- Return To Position
    ReturnToPosition() -- This runs the Return to Position Function that is in the screenload script.
    
end
function btnViewMTCLocation_1__Clicked_Script(...)
    -- View MTC Location
    local inst = mc.mcGetInstance("View MTC Location btn")
    local axes = {"X", "Y", "Z"}
    local msg = "MTC Location\n\nMACHINE COORDINATES:\n"
    
    for axis = 1,3,1 do
    	local pos = mc.mcProfileGetString(inst, "RememberPos", axes[axis], "Not Found")
    	if (pos == "Not Found") then
    		msg = "MTC position not found.\nYou must set MTC location first."
    	else
    		msg = msg .. axes[axis] .. " Position: " .. string.format("%0.4f", tonumber(pos)) .. "\n"
    	end
    end
    
    wx.wxMessageBox(msg, "Manual Tool Change")
end
function btnNext10_Left_Up_Script(...)
    ATCTools.NextTenButtonClicked()
end
function btnPrevious10_Left_Up_Script(...)
    ATCTools.PreviousTenButtonClicked()
end
-- tabATCToolForkSetup-GlobalScript
-- Created by Corbin Dunn, corbin@corbinstreehouse.com, Feb 2023
package.loaded.ATCToolForkSetup = nil
ATCToolForkSetup = require "ATCToolForkSetup"
function tabATCToolForkSetup_On_Enter_Script(...)
    -- ATC Tool Fork Setup Tab - On Enter Script
    -- by Corbin Dunn, Feb 22, 2023
    ATCToolForkSetup.HandleOnEnterToolForkTab()
    
    
end
function txtSlideDistance_On_Modify_Script(...)
    val = select(1,...)
    val = ATCToolForkSetup.HandleSlideDistanceChanged(val)
    return val
end
-- grpToolForkEditor-GlobalScript
function btnOrientationYNeg3_Clicked_Script(...)
    ATCToolForkSetup.OrientationClicked(...)
end
function btnOrientationXNeg1_Clicked_Script(...)
    ATCToolForkSetup.OrientationClicked(...)
end
function btnOrientationYPos2_Clicked_Script(...)
    ATCToolForkSetup.OrientationClicked(...)
end
function btnOrientationXPos0_Clicked_Script(...)
    ATCToolForkSetup.OrientationClicked(...)
end
function btnRemoveLastToolFork_Clicked_Script(...)
    ATCToolForkSetup.RemoveLastToolForkClicked()
end
function btnAssignX_Clicked_Script(...)
    local val = scr.GetProperty("droMachineX", "Value")
    val = HandlePositionSet(val, "X")
    HandleSelectedToolForkChanged()
end
function btnAssignY_Clicked_Script(...)
    local val = scr.GetProperty("droMachineY", "Value")
    val = HandlePositionSet(val, "Y")
    HandleSelectedToolForkChanged()
end
function btnAssignZ_Clicked_Script(...)
    local val = scr.GetProperty("droMachineZ", "Value")
    val = HandlePositionSet(val, "Z")
    HandleSelectedToolForkChanged()
end
function lstToolForks_On_Modify_Script(...)
    HandleToolForkListBoxSelectionChanged()
    
end
function btnAddToolFork_Clicked_Script(...)
     ATCToolForkSetup.HandleAddToolForkClicked()
end
function txtToolForkX_On_Modify_Script(...)
    val = select(1,...)
    val = HandlePositionSet(val, "X")
    return val
end
function txtToolForkY_On_Modify_Script(...)
    val = select(1,...)
    val = HandlePositionSet(val, "Y")
    return val
end
function txtToolForkZ_On_Modify_Script(...)
    val = select(1,...)
    val = HandlePositionSet(val, "Z")
    return val
end
function txtZBump_On_Modify_Script(...)
    return ATCToolForkSetup.HandleZBumpChanged(...)
end
function txtWaitTime_On_Modify_Script(...)
    val = select(1,...)
    val = ATCToolForkSetup.HandleWaitTimeChanged(val)
    return val
end
function txtZClearance_On_Modify_Script(...)
    return ATCToolForkSetup.HandleZClearanceChanged(...)
end
function btnAssignX_1__Clicked_Script(...)
    ATCToolForkSetup.HandleZClearanceAssignButtonClick(...)
end
function btnCasePressurization_Clicked_Script(...)
    ATCToolForkSetup.ToggleCasePressButton()
end
-- tabDiagnosticsSmall-GlobalScript
-- grpTHCLogging-GlobalScript
function btnTMC3in1MarkLogFile_Clicked_Script(...)
    local inst = mc.mcGetInstance('Screenset Mark Log File button') -- Pass in the script number, so we can see the commands called by this script in the log
    
    local hMarkLogFile = mc.mcRegGetHandle(inst, "TMC3in1/MARK_LOG_FILE")
    
    if ( hMarkLogFile == 0) then
        -- Failure to acquire a handle!
        mc.mcCntlLog(inst, 'Screenset Mark Log File button HANDLE FAILURE', "", -1) -- This will send a message to the log window
    else
        local valhMarkLogFile = mc.mcRegGetValue(hMarkLogFile)
    
        mc.mcRegSetValue(hMarkLogFile, valhMarkLogFile + 1)
        mc.mcCntlLog(inst, 'Screenset Mark Log File button incremented', "", -1) -- This will send a message to the log window
    
    end
end
function bmbTMC3in1EnableLogging_Clicked_Script(...)
    --Enable / Disable TMC3in1 THC Logging
    local inst = mc.mcGetInstance('bmbTMC3in1EnableLogging')
    
    local CurReg = 'TMC3in1/LOGGING_ENABLED'
    local hreg_LOGGING_ENABLED, rc = mc.mcRegGetHandle(inst, CurReg)
    
    if (rc ~= mc.MERROR_NOERROR) then
    	msg = 'Failed to aquire a handle for ' .. CurReg
    	mc.mcCntlLog(inst, msg, '', -1)
    else
    	local RegVal = mc.mcRegGetValueLong(hreg_LOGGING_ENABLED)
    	if (RegVal == 1) then
    		mc.mcRegSetValueLong(hreg_LOGGING_ENABLED, 0)
    		scr.SetProperty('bmbTMC3in1EnableLogging', 'Image', 'toggle_OFF.png')
    		msg = 'Screen button set ' .. CurReg .. ' to 0'
    	else
    		mc.mcRegSetValueLong(hreg_LOGGING_ENABLED, 1)
    		scr.SetProperty('bmbTMC3in1EnableLogging', 'Image', 'toggle_ON.png')
    		msg = 'Screen button set ' .. CurReg .. ' to 1'
    	end
    	mc.mcCntlLog(inst, msg, "", -1)
    end
end
-- grpTMC3in1Status-GlobalScript
-- grpHomingSensors-GlobalScript
-- grpLimitSwitches-GlobalScript
-- grpInputSignals-GlobalScript
-- grpSpindle-GlobalScript
function droSpindleOverride_On_Update_Script(...)
    local inst = mc.mcGetInstance()
    local val = select(1,...)
    local commandRPM = mc.mcSpindleGetCommandRPM(inst)
    local valSRO = mc.mcSpindleGetOverride(inst)
    local spindleSpeed100 = commandRPM / valSRO
    local spindleOverrideSpeed = (val / 100) * spindleSpeed100
    
    -- update DRO
    scr.SetProperty("droSpindleOverrideSpeed", "Value", tostring(spindleOverrideSpeed))
    
    return val
end
function droSpindleOverride_On_Modify_Script(...)
    local inst = mc.mcGetInstance()
    local val = select(1,...)
    local curRange = mc.mcSpindleGetCurrentRange(inst)
    local maxRPM = mc.mcSpindleGetMaxRPM(inst, curRange)
    local minRPM = minSpindleRPM
    local commandRPM = mc.mcSpindleGetCommandRPM(inst)
    local valSRO = mc.mcSpindleGetOverride(inst)
    local spindleSpeed100 = commandRPM / valSRO
    local spindleOverrideSpeed = (val / 100) * spindleSpeed100
    
    -- spindle speed limits
    if (spindleOverrideSpeed > maxRPM) then
    	spindleOverrideSpeed = maxRPM
    	val = (spindleOverrideSpeed / spindleSpeed100) * 100
    elseif (spindleOverrideSpeed < minRPM) then
    	spindleOverrideSpeed = minRPM
    	val = (spindleOverrideSpeed / spindleSpeed100) * 100
    end
    		
    return val
    
end
function btnSpindleRateMax_Left_Up_Script(...)
    --Spindle Rate Max
    local inst = mc.mcGetInstance()
    local rc = mc.mcSpindleSetOverride(inst, 1)
    if (rc ~= mc.MERROR_NOERROR) then
    	-- failure to set spindle override
    	msg = "Failure to set spindle override, return code " .. rc
    	mc.mcCntlLog(inst, msg, "", -1)
    end
    
end
function droSpindleOverrideSpeed_On_Modify_Script(...)
    local inst = mc.mcGetInstance("Screen Button droSpindleOverrideSpeed")
    local val = select(1,...)
    local valSRO = mc.mcSpindleGetOverride(inst)
    local curRange = mc.mcSpindleGetCurrentRange(inst)
    local maxRPM = mc.mcSpindleGetMaxRPM(inst, curRange)
    local minRPM = minSpindleRPM
    local commandRPM = mc.mcSpindleGetCommandRPM(inst)
    local spindleSpeed100 = commandRPM / valSRO
    
    -- spindle speed limits
    if (val > maxRPM) then
    	val = maxRPM
    elseif (val < minRPM) then
    	val = minRPM
    end
    
    -- update spindle override percentage
    valSRO = val / spindleSpeed100
    
    -- set new override percentage and update DRO
    mc.mcSpindleSetOverride(inst, valSRO)
    scr.SetProperty("droSpindleOverrideSpeed", "Value", tostring(val))
end
function bmbSpindleOnOff_Clicked_Script(...)
    SpinCW()
end
function bmbSpindleRateUp_Left_Up_Script(...)
    -- Increase Spindle Rate by 25%
    local inst = mc.mcGetInstance()
    local commandRPM = mc.mcSpindleGetCommandRPM(inst)
    local valSRO = mc.mcSpindleGetOverride(inst)
    local curRange = mc.mcSpindleGetCurrentRange(inst)
    local maxRPM = mc.mcSpindleGetMaxRPM(inst, curRange)
    local newSRO = valSRO + 0.25	-- decimal form
    local spindleSpeed100 = commandRPM / valSRO
    local spindleOverrideSpeed = (newSRO) * spindleSpeed100	-- new spindle override speed
    
    -- check spindle max speed
    if (spindleOverrideSpeed > maxRPM) then
    	spindleOverrideSpeed = maxRPM
    	newSRO = spindleOverrideSpeed / spindleSpeed100
    end
    
    -- set new spindle override percentage
    rc = mc.mcSpindleSetOverride(inst, newSRO)
    if (rc ~= mc.MERROR_NOERROR) then
    	-- failure to set spindle override
    	msg = "Failure to set spindle override, return code " .. rc
    	mc.mcCntlLog(inst, msg, "", -1)
    end
end
function bmbSpindleRateDown_Left_Up_Script(...)
    -- Decrease Spindle Rate by 25%
    local inst = mc.mcGetInstance()
    local valSRO = mc.mcSpindleGetOverride(inst)
    local commandRPM = mc.mcSpindleGetCommandRPM(inst)
    local minRPM = minSpindleRPM
    local newSRO = valSRO - 0.25	-- decimal form
    local spindleSpeed100 = commandRPM / valSRO
    local spindleOverrideSpeed = (newSRO) * spindleSpeed100	-- new spindle override speed
    
    -- check spindle min rpm
    if (spindleOverrideSpeed < minRPM) then
    	spindleOverrideSpeed = minRPM
    	newSRO = spindleOverrideSpeed / spindleSpeed100
    end
    
    -- set new spindle override percentage
    rc = mc.mcSpindleSetOverride(inst, newSRO)
    if (rc ~= mc.MERROR_NOERROR) then
    	-- failure to set spindle override
    	msg = "Failure to set spindle override, return code " .. rc
    	mc.mcCntlLog(inst, msg, "", -1)
    end
    
end
function droSpindleSpeed_On_Update_Script(...)
    local inst = mc.mcGetInstance()
    local val = select(1,...)
    local curRange = mc.mcSpindleGetCurrentRange(inst)
    local maxRPM = mc.mcSpindleGetMaxRPM(inst, curRange)
    local minRPM = minSpindleRPM
    local valSRO = mc.mcSpindleGetOverride(inst)	-- output in decimal form
    
    -- spindle speed limits
    if (val > maxRPM) then
    	val = maxRPM
    elseif (val < minRPM) then
    	val = minRPM
    end
    
    -- determine new override percentage
    local OverrideSpeed = val * valSRO
    if (OverrideSpeed > maxRPM) then
    	OverrideSpeed = maxRPM
    	valSRO = OverrideSpeed / val
    elseif (OverrideSpeed < minRPM) then
    	OverrideSpeed = minRPM
    	valSRO = OverrideSpeed / val
    end
    
    -- set override percentage, spindle speed, and DRO
    rc = mc.mcSpindleSetOverride(inst, valSRO)
    rc = mc.mcSpindleSetCommandRPM(inst, val)
    scr.SetProperty("droSpindleOverrideSpeed", "Value", tostring(OverrideSpeed))
    
    return val
end
function droSpindleSpeed_On_Modify_Script(...)
    local inst = mc.mcGetInstance()
    local val = select(1,...)
    local curRange = mc.mcSpindleGetCurrentRange(inst)
    local maxRPM = mc.mcSpindleGetMaxRPM(inst, curRange)
    local minRPM = minSpindleRPM
    local valSRO = mc.mcSpindleGetOverride(inst)	-- output in decimal form
    
    -- spindle rpm limits
    if (val > maxRPM) then
    	val = maxRPM
    elseif (val < minRPM) then
    	val = minRPM
    end
    
    -- set spindle override speed DRO
    local OverrideSpeed = val * valSRO
    if (OverrideSpeed > maxRPM) then
    	OverrideSpeed = maxRPM
    	valSRO = OverrideSpeed / val
    elseif (OverrideSpeed < minRPM) then
    	OverrideSpeed = minRPM
    	valSRO = OverrideSpeed / val
    end
    rc = mc.mcSpindleSetOverride(inst, valSRO)
    scr.SetProperty("droSpindleOverrideSpeed", "Value", tostring(OverrideSpeed))
    
    return val
end
function btnSpindleWarmUp_1__Left_Up_Script(...)
    package.loaded.SpindleWarmUp = nil;
    swu = require "SpindleWarmUp"
    co_swu = coroutine.create(swu.Dialog)
end
-- grpPlasma-GlobalScript
function bmbTorchOnOff_Clicked_Script(...)
    local inst = mc.mcGetInstance('TorchOnOff Button') -- Pass in the script number, so we can see the commands called by this script in the log
    
    local hThcCommand = mc.mcRegGetHandle(inst, string.format("ESS/HC/Command")) 
    local CurrentStr = "(ESS_TORCH_TOGGLE=1)"
    mc.mcRegSetValueString(hThcCommand, CurrentStr)   -- This will populate the GCode line data into the register
    
    mc.mcCntlLog(inst, '~~~~() Toggled Torch On/Off button.', "", -1) -- This will send a message to the log window
end
function bmbTHCOnOff_Clicked_Script(...)
    local inst = mc.mcGetInstance('Screenset H.C. ON OFF button') -- Pass in the script number, so we can see the commands called by this script in the log
    
    local hEssHcControlModeEnableOnOff = mc.mcRegGetHandle(inst, "ESS/HC/Control_Mode_Enable")
    
    if ( hEssHcControlModeEnableOnOff == 0) then
        -- Failure to acquire a handle!
        mc.mcCntlLog(inst, 'Screenset H.C. ON OFF button() Handle Failure', "", -1) -- This will send a message to the log window
    else
        local valEssThcControlOnOff = mc.mcRegGetValueLong(hEssHcControlModeEnableOnOff)
        if ( valEssThcControlOnOff == 0) then
            mc.mcRegSetValueLong(hEssHcControlModeEnableOnOff, 1)
            mc.mcCntlLog(inst, 'Screenset H.C. ON OFF button() turning ON', "", -1) -- This will send a message to the log window
    		scr.SetProperty("bmbTHCOnOff", "Image", "toggle_ON.png")
        else
            mc.mcRegSetValueLong(hEssHcControlModeEnableOnOff, 0)
            mc.mcCntlLog(inst, 'Screenset H.C. ON OFF button() turning OFF', "", -1) -- This will send a message to the log window
    		scr.SetProperty("bmbTHCOnOff", "Image", "toggle_OFF.png")
        end
    end
    
end
function btnResetPierces_Clicked_Script(...)
    local inst = mc.mcGetInstance('Screenset Reset Pierce Counter button') -- Pass in the script number, so we can see the commands called by this script in the log
    
    local hResetPierceCounter = mc.mcRegGetHandle(inst, "ESS/HC/Pierce_Count_Reset")
    
    if ( hResetPierceCounter == 0) then
        -- Failure to acquire a handle!
        mc.mcCntlLog(inst, 'Screenset Reset Pierce Counter button HANDLE FAILURE', "", -1) -- This will send a message to the log window
    else
        mc.mcRegSetValue(hResetPierceCounter, 1)
        mc.mcCntlLog(inst, 'Screenset Reset Pierce Counter button Activated', "", -1) -- This will send a message to the log window
    
    end
end
function bmbTipVoltUp_Clicked_Script(...)
    local inst = mc.mcGetInstance('Screenset Target Tip Volts +1 button') -- Pass in the script number, so we can see the commands called by this script in the log
    
    local hTargetTipVoltage = mc.mcRegGetHandle(inst, "TMC3in1/TMC3IN1_TARGET_TIP_VOLTS")
    
    if ( hTargetTipVoltage == 0) then
    	-- Failure to acquire a handle!
    	mc.mcCntlLog(inst, 'Screenset Target Tip Volts +1 button HANDLE FAILURE', "", -1) -- This will send a message to the log window
    else
    	local valhTargetTipVoltage = mc.mcRegGetValue(hTargetTipVoltage)
    
    	mc.mcRegSetValue(hTargetTipVoltage, valhTargetTipVoltage + 1)
    	mc.mcCntlLog(inst, 'Screenset Target Tip Volts +1 button incremented', "", -1) -- This will send a message to the log window
    
    end
    
end
function bmbTipVoltDn_Clicked_Script(...)
    local inst = mc.mcGetInstance('Screenset Target Tip Volts -1 button') -- Pass in the script number, so we can see the commands called by this script in the log
    
    local hTargetTipVoltage = mc.mcRegGetHandle(inst, "TMC3in1/TMC3IN1_TARGET_TIP_VOLTS")
    
    if ( hTargetTipVoltage == 0) then
    	-- Failure to acquire a handle!
    	mc.mcCntlLog(inst, 'Screenset Target Tip Volts -1 button HANDLE FAILURE', "", -1) -- This will send a message to the log window
    else
    	local valhTargetTipVoltage = mc.mcRegGetValue(hTargetTipVoltage)
    
    	mc.mcRegSetValue(hTargetTipVoltage, valhTargetTipVoltage - 1)
    	mc.mcCntlLog(inst, 'Screenset Target Tip Volts -1 button incremented', "", -1) -- This will send a message to the log window
    
    end
    
end
-- grpRouter-GlobalScript
function bmbRouterOnOff_Clicked_Script(...)
    SpinCW()
end
-- grpRelays-GlobalScript
function bmbRelay1_Clicked_Script(...)
    CoolantOnOff()
end
function bmbRelay2_Clicked_Script(...)
    Relay2OnOff()
end
function bmbKeyboardJog_Clicked_Script(...)
    KeyboardInputsToggle()
end
function btnTouchPlate_Left_Up_Script(...)
    CWUtilities.SaveToolHeightActiveStateAndDisable()
    
    --Touch Plate script
    if (Tframe == nil) then
    	package.loaded.TouchPlate = nil
    	tou = require "TouchPlate"
    	Tframe = tou.Dialog()
    	assert(Tframe ~= nil)
    else
    	Tframe:Show()
    	Tframe:Raise()
    end
    
    TframeShown = true -- set to true after the Tframe var is set
end
-- grpJogRate-GlobalScript
function btnJogRateMax_Left_Up_Script(...)
    local inst = mc.mcGetInstance()
    local ConvertFactor = droConvert()
    
    for i=0,5,1 do
    	rc = mc.mcJogSetRate(inst, i, 100)
    end
    
    local curJogRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0))) * ConvertFactor
    scr.SetProperty("droJogRateCur", "Value", tostring(curJogRate))
end
function droJogRate_On_Modify_Script(...)
    local droVal = scr.GetProperty("droJogRate", "Value")
    local ConvertFactor = droConvert()
    
    local val = tonumber(droVal)
    if (val > 100) then
    	val = 100
    elseif (val < 0) then
    	val = 0
    end
    scr.SetProperty("droJogRate", "Value", tostring(val))
    
    local curJogRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * val / 100) * ConvertFactor
    scr.SetProperty("droJogRateCur", "Value", tostring(curJogRate))
    
    return val
end
function btnFeedRateMax_Left_Up_Script(...)
    --scr.SetProperty('droFeedRate', 'Value', '100');
    local inst = mc.mcGetInstance()
    rc = mc.mcCntlSetFRO(inst, 100)
end
function droRapidRate_On_Modify_Script(...)
    --local droRapidRateVal = scr.GetProperty("droRapidRate", "Value")
    local inst = mc.mcGetInstance()
    local droRapidRateVal = select(1,...)
    local val = tonumber(droRapidRateVal)
    local ConvertFactor = droConvert()
    
    if (val > 100) then
    	val = 100
    elseif (val < 0) then
    	val = 0
    end
    scr.SetProperty("droRapidRate", "Value", tostring(val))
    
    local curRapidRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * val / 100) * ConvertFactor
    scr.SetProperty("droRapidRateCur", "Value", tostring(curRapidRate))
    
    return val
    
end
function bmbJogRateUp_Left_Up_Script(...)
    local inst = mc.mcGetInstance()
    local ConvertFactor = droConvert()
    local CurJogRate = scr.GetProperty("droJogRate", "Value")
    local NewJogRate = tonumber(CurJogRate) + 25
    
    if (NewJogRate > 100) then
    	NewJogRate = 100
    end
    
    for i=0,5,1 do
    	rc = mc.mcJogSetRate(inst, i, NewJogRate)
    end
    
    local curJogRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * NewJogRate / 100) * ConvertFactor
    scr.SetProperty("droJogRateCur", "Value", tostring(curJogRate))
end
function bmbJogRateDown_Left_Up_Script(...)
    local inst = mc.mcGetInstance()
    local ConvertFactor = droConvert()
    local CurJogRate = scr.GetProperty("droJogRate", "Value")
    local NewJogRate = tonumber(CurJogRate) - 25
    
    if (NewJogRate < 0) then
    	NewJogRate = 0
    end
    
    for i=0,5,1 do
    	rc = mc.mcJogSetRate(inst, i, NewJogRate)
    end
    
    local curJogRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * NewJogRate / 100) * ConvertFactor
    scr.SetProperty("droJogRateCur", "Value", tostring(curJogRate))
    
end
function bmbFeedRateUp_Left_Up_Script(...)
    -- Increase Feed Rate by 25%
    local inst = mc.mcGetInstance()
    
    local CurFRO = scr.GetProperty("droFeedRate", "Value")
    local NewFRO = tonumber(CurFRO) + 25
    local rc = mc.mcCntlSetFRO(inst, NewFRO)
    --scr.SetProperty("droFeedRate", "Value", tostring(NewJogRate))
    
end
function bmbFeedRateDown_Left_Up_Script(...)
    -- Decrease Feed Rate by 25%, min of 0%
    local inst = mc.mcGetInstance()
    
    local CurFeedRate = scr.GetProperty("droFeedRate", "Value")
    local NewFeedRate = tonumber(CurFeedRate) - 25
    if (NewFeedRate < 0) then
    	NewFeedRate = 0
    end
    local rc = mc.mcCntlSetFRO(inst, NewFeedRate)
end
function bmbRapidRateUp_Left_Up_Script(...)
    -- Increase Rapid Rate by 25%, max of 100%
    local inst = mc.mcGetInstance()
    local ConvertFactor = droConvert()
    
    local CurRapidRate = scr.GetProperty("droRapidRate", "Value")
    local NewRapidRate = tonumber(CurRapidRate) + 25
    if (NewRapidRate > 100) then
    	NewRapidRate = 100
    end
    
    local rc = mc.mcCntlSetRRO(inst, NewRapidRate)
    
    local curRapidRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * NewRapidRate / 100) * ConvertFactor
    scr.SetProperty("droRapidRateCur", "Value", tostring(curRapidRate))
end
function bmbRapidRateDown_Left_Up_Script(...)
    -- Decrease Rapid Rate by 25%, min of 0%
    local inst = mc.mcGetInstance()
    local ConvertFactor = droConvert()
    
    local CurRapidRate = scr.GetProperty("droRapidRate", "Value")
    local NewRapidRate = tonumber(CurRapidRate) - 25
    if (NewRapidRate < 0) then
    	NewRapidRate = 0
    end
    
    local rc = mc.mcCntlSetRRO(inst, NewRapidRate)
    
    local curRapidRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * NewRapidRate / 100) * ConvertFactor
    scr.SetProperty("droRapidRateCur", "Value", tostring(curRapidRate))
end
function btnRapidRateMax_Left_Up_Script(...)
    local inst = mc.mcGetInstance()
    local ConvertFactor = droConvert()
    
    local rc = mc.mcCntlSetRRO(inst, 100)
    
    local curRapidRate = ((mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0))) * ConvertFactor
    scr.SetProperty("droRapidRateCur", "Value", tostring(curRapidRate))
end
function droRapidRateCur_On_Modify_Script(...)
    local inst = mc.mcGetInstance()
    local val = select(1,...)
    local ConvertFactor = droConvert()
    local RRO = mc.mcCntlGetRRO(inst)
    
    -- max jog rate in user units (conversion necessary if user units differ from machine setup units)
        local MaxRapidRate = (mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * ConvertFactor
    	
    -- upper and lower limits
    if (val > MaxRapidRate) then
    	val = MaxRapidRate
    elseif (val < 0) then
    	val = 0
    end
    
    -- set new rapid rate override
    rc = mc.mcCntlSetRRO(inst, val * 100 / MaxRapidRate)
    
    -- set value of rapid rate
    scr.SetProperty("droRapidRateCur", "Value", tostring(val))
end
function droJogRateCur_On_Modify_Script(...)
    local inst = mc.mcGetInstance()
    local val = select(1,...)
    local ConvertFactor = droConvert()
    local JogPercent = mc.mcJogGetRate(inst, 0)
    
    -- max jog rate in user units (conversion necessary if user units differ from machine setup units)
    local MaxRapidRate = (mc.mcMotorGetMaxVel(inst, 0) * 60 / mc.mcMotorGetCountsPerUnit(inst, 0)) * ConvertFactor
    
    -- upper and lower limits
    if (val > MaxRapidRate) then
    	val = MaxRapidRate
    elseif (val < 0) then
    	val = 0
    end
    
    -- set new jog rate %
    for i = 0,5,1 do
    	mc.mcJogSetRate(inst, i, val * 100/MaxRapidRate)
    end
    
    -- set value of jog rate
    scr.SetProperty("droJogRateCur", "Value", tostring(val))
    
end
function bmbAvidLogo_Clicked_Script(...)
    pf.SplitSwitchGUI()
end
-- grpJogging-GlobalScript
function btnToggleJogMode_Left_Up_Script(...)
    ButtonJogModeToggle()
end
-- grpTools-GlobalScript
function droCurrentTool2_On_Modify_Script(...)
    -- this is when the user changes it..not somewhere else. Also do a G43 on the height
    if ATCTools == nil then
    	package.path = package.path .. ";./Modules/CorbinsWorkshop/?.lua"
    	ATCTools = require 'ATCTools'
    end
    
    val = select(1, ...)
    ATCTools.DoM6G43(val)
    return val
end
function btnATCPutBack_1__Left_Up_Script(...)
    ATCTools.PutBackCurrentTool()
end
-- grpDROsEtc-GlobalScript
function btnRefAll_Left_Up_Script(...)
    -- make sure we aren't already homed..
    
    local isHomed = CWUtilities.IsHomed()
    if isHomed then
    	-- ask the user if they really want to home again
    	local rc = wx.wxMessageBox("Already Homed....want to do it again?", "Tool Setup Error", wx.wxYES_NO)	
    	if rc ~= wx.wxYES then
    		do return end
    	end	
    end
    
    wait = coroutine.create (RefAllHome)
end
function droCurrentX_On_Update_Script(...)
    local val = select(1,...) -- Get the system value.
    val = tonumber(val) -- The value may be a number or a string. Convert as needed.
    DecToFrac(0)
    return val -- the script MUST return a value, otherwise, the control will not be updated.
end
function droCurrentY_On_Update_Script(...)
    local val = select(1,...) -- Get the system value.
    val = tonumber(val) -- The value may be a number or a string. Convert as needed.
    DecToFrac(1)
    return val -- the script MUST return a value, otherwise, the control will not be updated.
end
function btnZeroZ_Left_Down_Script(...)
    local inst = mc.mcGetInstance("Zero Z Btn, left down script")
    local hreg, rc = mc.mcRegGetHandle(inst, "ESS/HC/Z_DRO_Force_Sync_With_Aux")
    if (rc ~= mc.MERROR_NOERROR) then
      mc.mcCntlLog(
        inst,
        string.format("Failure to acquire register handle for ESS/HC/Z_DRO_Force_Sync_With_Aux, rc=%s", rc)
        "",
        -1)
    else
      mc.mcRegSetValueLong(hreg, 1)
      mc.mcCntlLog(inst, "Zero Z button forcing an ESS Z sync", "", -1)
    end
end
function btnZeroZ_Left_Up_Script(...)
    local inst = mc.mcGetInstance('Zero Z Button')
    local hHcCommand = mc.mcRegGetHandle(inst, string.format("ESS/HC/Command"))  
    if (hHcCommand == 0) then
    	mc.mcCntlLog(inst, "Failure to acquire handle", "", -1)
    else
    	mc.mcRegSetValueString(hHcCommand, "(HC_WORK_Z_ZEROED=1)") 
    	mc.mcCntlLog(inst, '....ZeroZButton() said that Z was zeroed', "", -1) -- This will send a message to the log window
    end
end
function droCurrentZ_On_Update_Script(...)
    local val = select(1,...) -- Get the system value.
    val = tonumber(val) -- The value may be a number or a string. Convert as needed.
    DecToFrac(2)
    return val -- the script MUST return a value, otherwise, the control will not be updated.
end
function droCurrentA_On_Update_Script(...)
    local val = select(1,...) -- Get the system value.
    val = tonumber(val) -- The value may be a number or a string. Convert as needed.
    DecToFrac(3)
    return val -- the script MUST return a value, otherwise, the control will not be updated.
end
function btnRefAOnly_Left_Up_Script(...)
    waitHome = coroutine.create(RefAHome)
    
    --local inst = mc.mcGetInstance()
    --rc = mc.mcAxisHome(inst, mc.A_AXIS)
end
function btnGotoMachineHome_Left_Up_Script(...)
    CWUtilities.GotoMachineHome()
end
function btnGotoZero_Left_Up_Script(...)
    local show = avd.WarningDialog("Machine Movement Warning!", "Machine will move at the rapid rate and current Z height to the X and Y zero positions of the current work coordinates.", "iShowWarningMoveToWorkZero");
    if (show == 0) then
    	GoToWorkZero()
    end
end
