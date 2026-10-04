local rs = game:GetService("ReplicatedStorage")
local Common = require(script.Parent.Parent.Common)
local Config = require(script.Parent.Parent.Config)
local ForbiddenMath = require(rs.Forbidden.Math)
local CommonMathCollection = require(rs.Forbidden.Math.CommonMathCollection)

local char = script.Parent.Parent.Parent

local raycastSettings = {} :: ForbiddenMath.RaycastSettings
raycastSettings.Range = Config.VisionRange or 100
raycastSettings.SeeThroughTransparentParts = false
raycastSettings.SeeThroughNonCollidable = false
raycastSettings.MinimumTransparency = 0.001
raycastSettings.FilterAttempts = 10
raycastSettings.OutputCollision = false
raycastSettings.FilterFunction = function() return false end

return function(NPC: Instance, Target: Player)
	local targetChar = Target.Character
	if not targetChar then return false end

	local npcRoot = NPC:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not npcRoot or not targetRoot then return false end

	local dist = (npcRoot.Position - targetRoot.Position).Magnitude
	if dist > (Config.VisionRange or 70) then return false end

	local hasLoS = CommonMathCollection.CheckLoSByAutomaticLimits(char, targetChar, raycastSettings)

	if hasLoS then
		if Config.Debugging then
			print("👁️ [ЗРЕНИЕ]: Вижу " .. Target.Name .. " (Дист: " .. math.floor(dist) .. ")")
		end
		return true
	end

	return false
end