local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Config)
local Forbidden = ReplicatedStorage:WaitForChild("Forbidden")
local forbiddenMathFolder = Forbidden:WaitForChild("Math")
local ForbiddenMath = require(forbiddenMathFolder)
local CommonMathCollection = require(forbiddenMathFolder:WaitForChild("CommonMathCollection"))

local NPC = script.Parent.Parent.Parent

local raycastSettings = {} :: ForbiddenMath.RaycastSettings
raycastSettings.Range = Config.VisionRange or 100
raycastSettings.SeeThroughTransparentParts = false
raycastSettings.SeeThroughNonCollidable = false
raycastSettings.MinimumTransparency = 0.001
raycastSettings.FilterAttempts = 10
raycastSettings.OutputCollision = false
raycastSettings.FilterFunction = function()
	return false
end

local function isInsideFieldOfView(npcRoot: BasePart, targetPosition: Vector3): boolean
	local offset = targetPosition - npcRoot.Position
	local direction = Vector3.new(offset.X, 0, offset.Z)
	if direction.Magnitude <= 0.001 then
		return true
	end

	local look = npcRoot.CFrame.LookVector
	local horizontalLook = Vector3.new(look.X, 0, look.Z)
	if horizontalLook.Magnitude <= 0.001 then
		return true
	end

	local fieldOfView = math.clamp(tonumber(Config.FieldOfView) or 120, 0, 360)
	local dot = horizontalLook.Unit:Dot(direction.Unit)
	return dot >= math.cos(math.rad(fieldOfView / 2))
end

return function(_npc: Instance, target: Player): boolean
	local targetCharacter = target and target.Character
	if not targetCharacter then
		return false
	end

	local npcRoot = NPC:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not npcRoot or not npcRoot:IsA("BasePart") or not targetRoot or not targetRoot:IsA("BasePart") then
		return false
	end

	local distance = (npcRoot.Position - targetRoot.Position).Magnitude
	if distance > (Config.VisionRange or 70) then
		return false
	end

	if not isInsideFieldOfView(npcRoot, targetRoot.Position) then
		return false
	end

	return CommonMathCollection.CheckLoSByAutomaticLimits(NPC, targetCharacter, raycastSettings)
end
