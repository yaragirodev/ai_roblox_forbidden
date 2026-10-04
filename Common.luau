-- == Common functions you may need == --

-- == Services == --
local rs = game:GetService("ReplicatedStorage")


-- == References == --
local NPC       = script.Parent.Parent
local Root      = NPC:FindFirstChild("HumanoidRootPart") or NPC.PrimaryPart


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
	if not Target then
		return math.huge
	end

	local TargetRoot: BasePart? = nil
	if Target:IsA("Player") then
		local character = Target.Character
		if character then
			TargetRoot = character.PrimaryPart
			if not TargetRoot then
				local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
				if humanoidRoot and humanoidRoot:IsA("BasePart") then
					TargetRoot = humanoidRoot
				end
			end
		end
	elseif Target:IsA("Model") then
		TargetRoot = Target.PrimaryPart
		if not TargetRoot then
			local humanoidRoot = Target:FindFirstChild("HumanoidRootPart")
			if humanoidRoot and humanoidRoot:IsA("BasePart") then
				TargetRoot = humanoidRoot
			else
				TargetRoot = Target:FindFirstChildWhichIsA("BasePart")
			end
		end
	elseif Target:IsA("BasePart") then
		TargetRoot = Target
	end

	local npcRoot = Root or NPC.PrimaryPart or NPC:FindFirstChild("HumanoidRootPart")
	if not npcRoot or not npcRoot:IsA("BasePart") or not TargetRoot then
		warn("Issue getting a root part for distance measurement")
		return math.huge
	end

	return (npcRoot.Position - TargetRoot.Position).Magnitude
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