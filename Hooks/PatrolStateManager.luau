--[[

THIS ACTUALLY ISN'T A HOOK! But it's to show how to implement a 
shared state ( or singleton for my Java devs :) ) between multiple 
hooks.
	- rman501

]]--


local Common = require(script.Parent.Parent.Common)

-- return false to stop chasing the target
local PatrolStateManager = {}

local StoredTarget = nil
local StoredPoint = nil

PatrolStateManager.SetTargetInfo = function(Target: Instance, Point: Vector3)
	if Target then
		StoredTarget = Target
		StoredPoint = Point
	end
end

PatrolStateManager.GetTarget = function()
	return StoredTarget
end

PatrolStateManager.RetrieveInformation = function()
	
	if not StoredTarget then return nil, nil end
	
	local char = StoredTarget.Character
	if char == nil then return nil, nil end
	
	local human = char:FindFirstChildOfClass("Humanoid")
	if human == nil then return nil, nil end
	if human.Health == 0 then return nil, nil end
	
	return StoredPoint
end

PatrolStateManager.Clear = function()
	StoredTarget = nil
	StoredPoint = nil
end

return PatrolStateManager