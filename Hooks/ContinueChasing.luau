local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AI = require(ReplicatedStorage:WaitForChild("Forbidden"):WaitForChild("AI"))

local Config = require(script.Parent.Parent.Config)
local PatrolStateManager = require(script.Parent.PatrolStateManager)
local IsTargetValid = require(script.Parent.IsTargetValid)

local currentTarget: Player? = nil
local lastSoundPathPosition: Vector3? = nil
local lastSoundPathTime = 0
local wasFollowingSound = false
local lastKnownDirection: Vector3? = nil
local lastKnownSpeed = 0
local lastSensedTime = 0

local function getAttribute(root: Instance, character: Model, humanoid: Humanoid?, name: string)
	local value = root:GetAttribute(name)
	if value ~= nil then
		return value
	end

	value = character:GetAttribute(name)
	if value ~= nil then
		return value
	end

	return humanoid and humanoid:GetAttribute(name) or nil
end

local function createDebugPart(position: Vector3)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 0.5
	part.Color = Color3.fromRGB(255, 0, 0)
	part.Position = position
	part.Name = "Prediction"
	part.Parent = workspace
	Debris:AddItem(part, 3)
end

local function rememberSensedPosition(target: Player, targetRoot: BasePart)
	local velocity = targetRoot.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	lastKnownSpeed = horizontalVelocity.Magnitude
	lastKnownDirection = lastKnownSpeed > 0.5 and horizontalVelocity.Unit or nil
	lastSensedTime = os.clock()
	PatrolStateManager.SetTargetInfo(target, targetRoot.Position)
end

local function pathToSoundPosition(NPC: Model, position: Vector3)
	local now = os.clock()
	local minInterval = math.max(tonumber(Config.SoundPathUpdateInterval) or 0.5, 0)
	local minDistance = math.max(tonumber(Config.SoundPathUpdateDistance) or 3, 0)
	local movedEnough = lastSoundPathPosition == nil
		or (position - lastSoundPathPosition).Magnitude >= minDistance

	if not movedEnough and now - lastSoundPathTime < minInterval then
		return
	end

	local ok, err = pcall(AI.SmartPathfind, NPC, position)
	if not ok then
		if Config.Debugging then
			warn("[СЛУХ] Не удалось построить путь к источнику звука: " .. tostring(err))
		end
		return
	end

	lastSoundPathPosition = position
	lastSoundPathTime = now
	wasFollowingSound = true
end

return function(NPC: Model, Target: Player, sensedCanSee: boolean?, sensedCanHear: boolean?): boolean
	if Target ~= currentTarget then
		currentTarget = Target
		lastSoundPathPosition = nil
		lastSoundPathTime = 0
		wasFollowingSound = false
		lastKnownDirection = nil
		lastKnownSpeed = 0
		lastSensedTime = 0
	end

	local character = Target and Target.Character
	local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local npcRoot = NPC:FindFirstChild("HumanoidRootPart")
	local npcHumanoid = NPC:FindFirstChildOfClass("Humanoid")

	if not character
		or not targetRoot
		or not targetRoot:IsA("BasePart")
		or not targetHumanoid
		or targetHumanoid.Health <= 0
		or not npcRoot
		or not npcRoot:IsA("BasePart")
	then
		return false
	end

	local previousPoint = PatrolStateManager.RetrieveInformation()
	local distance = (npcRoot.Position - targetRoot.Position).Magnitude

	-- Reuse the main loop's sensor results when provided; the hook can still
	-- calculate them itself if called independently.
	local canSee = sensedCanSee
	if canSee == nil then
		canSee = IsTargetValid(NPC, Target)
	end

	if canSee then
		rememberSensedPosition(Target, targetRoot)
		if npcHumanoid then
			npcHumanoid.WalkSpeed = Config.ChaseWalkSpeed or npcHumanoid.WalkSpeed
		end

		-- Sound paths use a fixed point. Resume tracking the moving Player after
		-- the NPC sees them again instead of getting stuck at the old sound point.
		if wasFollowingSound then
			AI.SmartPathfind(NPC, Target)
			wasFollowingSound = false
			lastSoundPathPosition = nil
			lastSoundPathTime = 0
		end
		return true
	end

	local canHear = sensedCanHear
	if canHear == nil then
		local velocity = targetRoot.AssemblyLinearVelocity
		local speed = Vector2.new(velocity.X, velocity.Z).Magnitude
		local isCrouching = getAttribute(targetRoot, character, targetHumanoid, "IsCrouching") == true
		local isRunning = getAttribute(targetRoot, character, targetHumanoid, "IsRunning") == true or speed > 18
		local hearRange = isRunning and (Config.HearRange or 110) or (Config.WalkHearRange or 16)
		canHear = not isCrouching and speed >= 1 and distance <= hearRange
	end

	if canHear then
		rememberSensedPosition(Target, targetRoot)
		if npcHumanoid then
			npcHumanoid.WalkSpeed = Config.ChaseWalkSpeed or npcHumanoid.WalkSpeed
		end

		if Config.Debugging then
			warn(string.format("[СЛУХ] Слышу %s на %.1f studs", Target.Name, distance))
		end
		pathToSoundPosition(NPC, targetRoot.Position)
		return true
	end

	-- The target was neither seen nor heard. Investigate the last sensed point,
	-- optionally nudged along its last observed movement direction. This avoids
	-- using the player's hidden, current position as a destination.
	if Config.DoCornerChase and previousPoint and lastKnownDirection then
		local timeSinceSensed = math.max(os.clock() - lastSensedTime, 0)
		local estimatedTravel = lastKnownSpeed * timeSinceSensed
		local maxCornerDistance = math.max(tonumber(Config.IgnoreCornerChaseDistance) or 20, 0)
		if estimatedTravel > maxCornerDistance then
			PatrolStateManager.Clear()
			return false
		end

		local predictionDistance = math.min(
			math.max(tonumber(Config.ReasonablePredictionDistance) or 2, 0),
			estimatedTravel
		)
		if predictionDistance > 0.1 then
			local prediction = previousPoint + lastKnownDirection * predictionDistance
			PatrolStateManager.SetTargetInfo(Target, prediction)
			if Config.Debugging then
				createDebugPart(prediction)
			end
		end
	end

	return false
end
