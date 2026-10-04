-- == Common functions you may need == --

-- == Services == --
local rs = game:GetService("ReplicatedStorage")


-- == References == --
local NPC       = script.Parent.Parent
local Root      = NPC.PrimaryPart


-- == Forbidden Architecture == --
local AI = require(rs:WaitForChild("Forbidden"):WaitForChild("AI"))


-- == Initialization == --
local Common = {}


-- == Hooks == --
-- == Other Hooks == --
local hooksFolder			= script.Parent.Hooks
local PathfindingLinksHandler 	= require(hooksFolder.PathfindingLinks.PathfindingLinkController)
local otherHooksFolder		= hooksFolder.Other
local PathingStarted			= require(otherHooksFolder.PathingStarted)
local PathingFailed				= require(otherHooksFolder.PathingFailed)
local MovingToWaypoint			= require(otherHooksFolder.MovingToWaypoint)
local GoalReached				= require(otherHooksFolder.GoalReached)



-- == API Functions == --

--[=[
Measures the distance from the NPC root to the Target root.
Returns math.huge if invalid

@param Target <strong>Instance</strong> The target to measure the distance to

@return <strong>number</strong> The distance to the target

]=]--
Common.GetDistanceFromNPC = function(Target: Instance): number
	local TargetRoot: BasePart = nil

	if Target:IsA("Player") then
		local char = Target.Character
		TargetRoot = char.PrimaryPart :: any
	end

	if Target:IsA("Model") then
		TargetRoot = Target.PrimaryPart :: any
		if not TargetRoot then
			TargetRoot = Target:FindFirstChildOfClass("BasePart") :: any
		end
	end

	if Target:IsA("BasePart") then
		TargetRoot = Target
	end

	if not TargetRoot then warn("Issue getting the Target's root: " .. Target:GetFullName()); return math.huge end

	return (Root.CFrame.Position - TargetRoot.CFrame.Position).Magnitude
end

Common.SetHooksForConfig = function()
	local config = AI.GetConfig(NPC)
	config.Hooks.PathfindingLinkReached = PathfindingLinksHandler
	config.Hooks.PathingFailed 			= PathingFailed
	config.Hooks.MovingToWaypoint 		= MovingToWaypoint
	config.Hooks.PathingStarted			= PathingStarted
	config.Hooks.GoalReached			= GoalReached
end

return Common
-- == End of API Functions == --