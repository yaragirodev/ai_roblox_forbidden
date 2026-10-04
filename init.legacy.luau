-- TCP V2 (SimpleTRACK)
-- Forbidden V2 Implementation of a TrackClosestPlayer script.
-- by @CritDEV, modified for Hear/Vision system

-- == Services == --
local rs			= game:GetService("ReplicatedStorage")
local run			= game:GetService("RunService")
local players		= game:GetService("Players")

-- == Libraries == --
local Forbidden		= rs:WaitForChild("Forbidden")
local AI			= require(Forbidden:WaitForChild("AI"))
local Common		= require(script.Common)

-- == References == --
local NPC			= script.Parent
assert(NPC:IsA("Model"), "[AI] The tracking script must be parented to an NPC Model")

local Root			= NPC:WaitForChild("HumanoidRootPart", 10)
if not Root or not Root:IsA("BasePart") then
	error("[AI] NPC " .. NPC.Name .. " is missing a BasePart named HumanoidRootPart")
end

local Human			= NPC:FindFirstChildOfClass("Humanoid") or NPC:WaitForChild("Humanoid", 10)
if not Human or not Human:IsA("Humanoid") then
	error("[AI] NPC " .. NPC.Name .. " is missing a Humanoid")
end

-- == Configuration == --
local Config		= require(script.Config)

-- == External Hooks == --
local hooksFolder		= script.Hooks
local ContinueChasing	= require(hooksFolder.ContinueChasing)
local Interrupt			= require(hooksFolder.Interrupt)
local IsTargetValid		= require(hooksFolder.IsTargetValid)
local PreInit			= require(hooksFolder.PreInitialization)
local PostInit			= require(hooksFolder.PostInitialization)
local Heartbeat			= require(hooksFolder.Heartbeat)
local DoingNothing		= require(hooksFolder.DoingNothing)
local PatrolStateManager	= require(hooksFolder.PatrolStateManager)

-- == Animation System == --
-- Стандартный Animate (LocalScript) не работает для NPC на сервере,
-- поэтому играем анимации сами через Animator хуманоида (реплицируется всем клиентам).

local animator = Human:FindFirstChildOfClass("Animator")
if animator == nil then
	animator = Instance.new("Animator")
	animator.Parent = Human
end

local animConfig = Config.Animations or {}
local loadedAnims = {}
local currentAnimTrack = nil
local currentAnimName = nil

local function loadAnim(id: string?)
	if not id or id == "" then
		return nil
	end

	local anim = Instance.new("Animation")
	local ok, track = pcall(function()
		anim.AnimationId = id
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()

	if ok and track then
		track.Looped = true
		return track
	end
	if Config.Debugging then
		warn("[АНИМАЦИИ] Не удалось загрузить анимацию: " .. tostring(id) .. " (проверьте ID и права доступа)")
	end
	return nil
end

if animConfig.Enabled ~= false then
	loadedAnims.Idle = loadAnim(animConfig.Idle)
	loadedAnims.Walk = loadAnim(animConfig.Walk)
	loadedAnims.Run = loadAnim(animConfig.Run)
end

local function playAnimation(animName: string, fadeTime: number?, speed: number?)
	local track = loadedAnims[animName]
	local selectedName = animName

	-- Missing custom run/walk assets should not prevent the other animations from playing.
	if not track and animName == "Run" then
		track = loadedAnims.Walk or loadedAnims.Idle
		selectedName = loadedAnims.Walk and "Walk" or "Idle"
		speed = nil
	elseif not track and animName == "Walk" then
		track = loadedAnims.Run or loadedAnims.Idle
		selectedName = loadedAnims.Run and "Run" or "Idle"
		speed = nil
	end
	if not track then
		if currentAnimTrack then
			currentAnimTrack:Stop(fadeTime or 0.2)
			currentAnimTrack = nil
			currentAnimName = nil
		end
		return
	end

	if currentAnimName == selectedName and currentAnimTrack == track and track.IsPlaying then
		if speed and math.abs(track.Speed - speed) > 0.01 then
			track:AdjustSpeed(speed)
		end
		return
	end

	if currentAnimTrack then
		currentAnimTrack:Stop(fadeTime or 0.2)
	end
	track.Priority = selectedName == "Idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
	track:Play(fadeTime or 0.2, 1, speed or 1)
	currentAnimTrack = track
	currentAnimName = selectedName

	if Config.Debugging then
		print(string.format("🎬 [АНИМАЦИЯ] -> %s", selectedName))
	end
end

-- Автоматический выбор анимации по фактической скорости движения NPC:
-- стоит на месте -> Idle | патруль -> Walk | погоня/расследование -> Run
local function updateAnimation()
	local vel = Root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	if speed < 0.5 then
		playAnimation("Idle")
	elseif speed <= (Config.PatrolWalkSpeed or Config.WalkSpeed or 8) + 1 then
		playAnimation("Walk")
	else
		playAnimation("Run", 0.2, animConfig.RunSpeedMultiplier or 1.25)
	end
end

-- == Start of Code == --

task.wait(Config.InitializationTimer)
task.spawn(PreInit, NPC)

if Config.WalkSpeed then
	Human.WalkSpeed = Config.WalkSpeed
end

if Config.InsertAntiLag then
	AI.InsertAntiLag(NPC)
end

-- =============================================
-- БАЗОВЫЕ ПРОВЕРКИ ИГРОКА
-- =============================================

local function isPlayerAlive(player: Player): boolean
	if not player or player.Parent ~= players then
		return false
	end

	local char = player.Character
	if not char then
		return false
	end

	local root = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	return root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0
end

local function canSeePlayer(player: Player): boolean
	if not isPlayerAlive(player) then
		return false
	end

	-- The shared hook checks range, field of view and line of sight so the
	-- acquisition and chase-continuation checks use identical vision rules.
	local canSee = IsTargetValid(NPC, player)
	if canSee and Config.Debugging then
		print(string.format("👁️✅ [ЗРЕНИЕ] Вижу %s", player.Name))
	end
	return canSee
end

local function canHearPlayer(player: Player): boolean
	if not isPlayerAlive(player) then 
		return false 
	end

	local char = player.Character
	local targetRoot = char:FindFirstChild("HumanoidRootPart")
	local targetHuman = char:FindFirstChildOfClass("Humanoid")
	if not targetRoot then return false end

	-- ГЛУБОКИЙ ПОИСК АТРИБУТОВ (Root -> Character -> Humanoid)
	local function getAttr(name)
		local v = targetRoot:GetAttribute(name)
		if v ~= nil then return v end
		v = char:GetAttribute(name)
		if v ~= nil then return v end
		if targetHuman then
			v = targetHuman:GetAttribute(name)
			if v ~= nil then return v end
		end
		return nil
	end

	local isCrouching = getAttr("IsCrouching") == true
	local isRunningAttr = getAttr("IsRunning") == true

	if Config.Debugging then
		-- print(string.format("👂 [СЛУХ НАЧАЛО] %s | IsCrouching: %s | IsRunning: %s", player.Name, tostring(isCrouching), tostring(isRunningAttr)))
	end

	-- АБСОЛЮТНАЯ ПРОВЕРКА: если в приседе - тишина!
	if isCrouching then
		if Config.Debugging then
			warn(string.format("🤫 [ПРИСЕД БЛОК] %s В ПРИСЕДЕ - НЕ СЛЫШУ НИЧЕГО!", player.Name))
		end
		return false
	end

	local dist = (Root.Position - targetRoot.Position).Magnitude
	local vel = targetRoot.AssemblyLinearVelocity
	local speed = Vector2.new(vel.X, vel.Z).Magnitude

	-- Проверка на бег
	local isRunning = isRunningAttr or speed > 18

	-- Минимальная скорость
	if speed < 1 then
		if Config.Debugging then
			print(string.format("   └─ 🧍 [СТОИТ] %s скорость < 1, не слышу", player.Name))
		end
		return false
	end

	-- БЕГ
	if isRunning then
		local canHear = dist <= (Config.HearRange or 110)
		if Config.Debugging then
			if canHear then
				print(string.format("   └─ 🏃 [БЕГ СЛЫШУ] %s на %.1f studs ✅", player.Name, dist))
			else
				print(string.format("   └─ 🏃 [БЕГ ДАЛЕКО] %s на %.1f > %d ❌", player.Name, dist, Config.HearRange or 110))
			end
		end
		return canHear
	end

	-- ХОДЬБА
	if speed > 1 and speed <= 18 then
		local canHear = dist <= (Config.WalkHearRange or 16)
		if Config.Debugging then
			if canHear then
				print(string.format("   └─ 🚶 [ХОДЬБА СЛЫШУ] %s на %.1f studs ✅", player.Name, dist))
			else
				print(string.format("   └─ 🚶 [ХОДЬБА ДАЛЕКО] %s на %.1f > %d ❌", player.Name, dist, Config.WalkHearRange or 16))
			end
		end
		return canHear
	end

	return false
end

local cachedPlayerSenses = {}

local function getPlayerSenses(player: Player): (boolean, boolean)
	local cached = cachedPlayerSenses[player]
	if cached then
		return cached.canSee, cached.canHear
	end

	local canSee = canSeePlayer(player)
	local canHear = not canSee and canHearPlayer(player)
	cachedPlayerSenses[player] = {
		canSee = canSee,
		canHear = canHear,
	}
	return canSee, canHear
end

local function isValidTarget(player: Player): boolean
	local canSee, canHear = getPlayerSenses(player)

	if Config.Debugging and (canSee or canHear) then
		print(string.format("✅ [ВАЛИДНАЯ ЦЕЛЬ] %s | Вижу: %s | Слышу: %s", 
			player.Name, 
			tostring(canSee), 
			tostring(canHear)
			))
	end

	return canSee or canHear
end

-- =============================================
-- ПОИСК БЛИЖАЙШЕЙ ЦЕЛИ С ПРИОРИТЕТОМ
-- =============================================

local lastDetectMethod = ""
local lastTarget = nil

local function getClosestPlayer()
	cachedPlayerSenses = {}
	local closestPlayer = nil
	local closestDistance = math.huge
	local detectMethod = ""

	for _, player in pairs(players:GetPlayers()) do
		if not isPlayerAlive(player) then continue end

		local char = player.Character
		local targetRoot = char:FindFirstChild("HumanoidRootPart")
		if not targetRoot then continue end

		local distance = (Root.Position - targetRoot.Position).Magnitude

		local canSee, canHear = getPlayerSenses(player)
		if canSee then
			if distance < closestDistance then
				closestDistance = distance
				closestPlayer = player
				detectMethod = "👁️ ЗРЕНИЕ"
			end
		elseif canHear then
			if distance < closestDistance then
				closestDistance = distance
				closestPlayer = player

				local speed = Vector2.new(targetRoot.AssemblyLinearVelocity.X, targetRoot.AssemblyLinearVelocity.Z).Magnitude
				local isRunning = targetRoot:GetAttribute("IsRunning") == true or char:GetAttribute("IsRunning") == true or speed > 18

				if isRunning then
					detectMethod = "👂 СЛУХ (БЕГ)"
				else
					detectMethod = "👂 СЛУХ (ХОДЬБА)"
				end
			end
		end
	end

	if closestPlayer and closestPlayer ~= lastTarget then
		if Config.Debugging then
			print(string.format("\n🎯 [НОВАЯ ЦЕЛЬ]: %s | Способ: %s | Дистанция: %.1f studs\n", 
				closestPlayer.Name, 
				detectMethod, 
				closestDistance
				))
		end
	end

	lastTarget = closestPlayer
	lastDetectMethod = detectMethod
	return closestPlayer
end

-- =============================================
-- СМЕНА ЦЕЛИ С УМНЫМ АЛГОРИТМОМ
-- =============================================

local chasingPlayer = nil
local pendingDetectionTarget: Player? = nil
local pendingDetectionSince = 0
local DETECTION_DELAY = math.max(tonumber(Config.DetectionDelay) or 0, 0)
local lastTargetSwitchTime = 0

local function shouldSwitchTarget(newTarget: Player): boolean
	if newTarget == nil then return false end
	if chasingPlayer == nil then return true end
	if newTarget == chasingPlayer then return false end

	-- Never keep chasing a dead, departed or respawning target just to honor the cooldown.
	if not isPlayerAlive(chasingPlayer) then
		return true
	end

	-- Защита от постоянного переключения. A negative value disables the cooldown.
	local switchCooldown = tonumber(Config.MinTargetSwitchInterval or Config.SwapTargetsTimer) or 2
	if switchCooldown >= 0 and os.clock() - lastTargetSwitchTime < switchCooldown then
		if Config.Debugging then
			print("⏱️ [СМЕНА ЦЕЛИ] Слишком рано переключаться (защита от спама)")
		end
		return false
	end

	local currentChar = chasingPlayer.Character
	local newChar = newTarget.Character

	if not currentChar then return true end
	if not newChar then return false end

	local currentRoot = currentChar:FindFirstChild("HumanoidRootPart")
	local newRoot = newChar:FindFirstChild("HumanoidRootPart")

	if not currentRoot then return true end
	if not newRoot then return false end

	local distToCurrent = (Root.Position - currentRoot.Position).Magnitude
	local distToNew = (Root.Position - newRoot.Position).Magnitude

	-- Новая цель должна быть ЗНАЧИТЕЛЬНО ближе (минимум на 30%)
	local advantageThreshold = Config.TargetSwitchAdvantage or 0.7

	if distToNew < distToCurrent * advantageThreshold then
		if Config.Debugging then
			print(string.format("🔄 [ВЫГОДНАЯ СМЕНА] %s (%.1f) -> %s (%.1f) | Выгода: %.1f%%", 
				chasingPlayer.Name, distToCurrent,
				newTarget.Name, distToNew,
				(1 - distToNew/distToCurrent) * 100
				))
		end
		return true
	end

	-- Или если текущую цель больше не видим/слышим, а новую видим
	local canDetectCurrent = isValidTarget(chasingPlayer)
	local canDetectNew = isValidTarget(newTarget)

	if not canDetectCurrent and canDetectNew then
		if Config.Debugging then
			print(string.format("🔄 [СМЕНА: ПОТЕРЯ] %s потерян, переключаюсь на %s", 
				chasingPlayer.Name, newTarget.Name))
		end
		return true
	end

	return false
end

-- =============================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ПАТРУЛЯ
-- =============================================

local function getNodePosition(node)
	if not node then return nil end
	if typeof(node) == "Vector3" then
		return node
	elseif typeof(node) == "Instance" then
		if node:IsA("BasePart") then
			return node.Position
		elseif node:IsA("Model") then
			return node:GetPivot().Position
		end
	end
	return nil
end

local function isNodeValid(node)
	if not node then return false end
	if typeof(node) == "Vector3" then return true end
	if typeof(node) == "Instance" and node.Parent ~= nil then return true end
	return false
end

-- =============================================
-- СОСТОЯНИЕ РАССЛЕДОВАНИЯ И ПАТРУЛЯ
-- =============================================

local investigating = false
local investigateUntil = 0

local isPatrolling = false
local currentPatrolNode = nil
local patrolNodeReachedTime = 0
local patrolStartTime = 0
local nextPatrolRetryTime = 0

local INVESTIGATE_TIME = math.max(tonumber(Config.InvestigateTime) or 4, 0)
local PATROL_RETRY_INTERVAL = math.max(tonumber(Config.PatrolRetryInterval) or 2, 0.1)

local function requestNextPatrolNode()
	currentPatrolNode = DoingNothing()
	patrolNodeReachedTime = 0
	patrolStartTime = os.clock()

	if isNodeValid(currentPatrolNode) then
		nextPatrolRetryTime = 0
	else
		-- Avoid calling the patrol hook every 0.1 seconds when there are no nodes.
		nextPatrolRetryTime = os.clock() + PATROL_RETRY_INTERVAL
	end
end

local function startPatrol()
	if isPatrolling then return end
	isPatrolling = true
	investigating = false
	chasingPlayer = nil
	patrolNodeReachedTime = 0
	patrolStartTime = os.clock()
	NPC:SetAttribute("IsChasing", false)
	NPC:SetAttribute("ChaseTargetUserId", nil)

	if Config.Debugging then
		print("🚶‍♂️ [ПАТРУЛЬ АКТИВИРОВАН] Монстр начал патрулирование")
	end

	AI.Stop(NPC)
	Human.WalkSpeed = Config.PatrolWalkSpeed or Config.WalkSpeed or 8
	requestNextPatrolNode()
end

local function updatePatrol()
	if not isPatrolling then return end

	if not isNodeValid(currentPatrolNode) then
		if os.clock() >= nextPatrolRetryTime then
			requestNextPatrolNode()
		end
		return
	end

	local nodePos = getNodePosition(currentPatrolNode)
	if not nodePos then
		currentPatrolNode = nil
		nextPatrolRetryTime = os.clock() + PATROL_RETRY_INTERVAL
		return
	end

	local dist = (Root.Position - nodePos).Magnitude
	local timeWalking = os.clock() - patrolStartTime

	-- Reached the node, or give up on a path that has taken too long.
	if dist <= 5 or timeWalking > 15 then
		if patrolNodeReachedTime == 0 then
			patrolNodeReachedTime = os.clock()
			if Config.Debugging then
				local name = (typeof(currentPatrolNode) == "Instance") and currentPatrolNode.Name or "Точка"
				print(string.format("📍 [ПАТРУЛЬ] Дошел до точки '%s', осматриваюсь...", name))
			end
		elseif os.clock() - patrolNodeReachedTime >= 2 then
			if Config.Debugging then
				print("🚶‍♂️ [ПАТРУЛЬ] Иду к следующей точке...")
			end
			requestNextPatrolNode()
		end
	end
end

local function startInvestigation(lastKnownPos: Vector3, target: Player?)
	if typeof(lastKnownPos) ~= "Vector3" then
		startPatrol()
		return
	end

	isPatrolling = false
	investigating = true
	investigateUntil = os.clock() + INVESTIGATE_TIME
	Human.WalkSpeed = Config.ChaseWalkSpeed or Config.WalkSpeed or 16
	if target then
		PatrolStateManager.SetTargetInfo(target, lastKnownPos)
	end

	if Config.Debugging then
		warn(string.format("🔍 [РАССЛЕДОВАНИЕ НАЧАТО] Иду к последней известной точке (%.1f, %.1f, %.1f) | Время: %.1f сек",
			lastKnownPos.X, lastKnownPos.Y, lastKnownPos.Z, INVESTIGATE_TIME))
	end

	AI.SmartPathfind(NPC, lastKnownPos)
end

local function stopInvestigation()
	if not investigating then return end
	investigating = false
	Human.WalkSpeed = Config.PatrolWalkSpeed or Config.WalkSpeed or 8

	if Config.Debugging then
		warn("🔍 [РАССЛЕДОВАНИЕ ОКОНЧЕНО] Никого не нашёл, возвращаюсь к патрулю")
	end

	startPatrol()
end

-- =============================================
-- НАЧАЛО ПОГОНИ
-- =============================================

local function startChasing(target: Player)
	-- Stop an old patrol/investigation path before starting the new chase.
	AI.Stop(NPC)
	pendingDetectionTarget = nil
	pendingDetectionSince = 0

	isPatrolling = false
	investigating = false

	if Config.Debugging then
		warn(string.format("🚨 [ПОГОНЯ НАЧАТА] Цель: %s | Метод: %s", target.Name, lastDetectMethod))
	end

	chasingPlayer = target
	lastTargetSwitchTime = os.clock()
	NPC:SetAttribute("IsChasing", true)
	NPC:SetAttribute("ChaseTargetUserId", target.UserId)
	Human.WalkSpeed = Config.ChaseWalkSpeed or Config.WalkSpeed or 16

	local targetCharacter = target.Character
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if targetRoot and targetRoot:IsA("BasePart") then
		PatrolStateManager.SetTargetInfo(target, targetRoot.Position)
	end

	local config = AI.GetConfig(NPC)
	config:RestoreDefaults()
	config.Tracking.Enabled = true
	config.Visualization.Enabled = Config.Visualize
	config.Debugging.Enabled = Config.ForbiddenDebugging
	config.AgentInfo = Config.GetAgentInfo()
	Common.SetHooksForConfig()

	AI.SmartPathfind(NPC, target)
end

local function stopChasing()
	if Config.Debugging then
		warn("🛑 [ПОГОНЯ ОСТАНОВЛЕНА] Сброс состояния")
	end

	chasingPlayer = nil
	NPC:SetAttribute("IsChasing", false)
	NPC:SetAttribute("ChaseTargetUserId", nil)
	AI.Stop(NPC)
end

-- =============================================
-- ОСНОВНОЙ ЦИКЛ
-- =============================================

local function coreLoop()
	local targetCheckInterval = math.max(tonumber(Config.CheckTargetsInterval) or 0.1, 0.05)
	while NPC and NPC.Parent do
		task.wait(targetCheckInterval)

		if Interrupt(NPC) then continue end

		local closestPlayer = getClosestPlayer()

		-- =======================================
		-- ФАЗА 1: РАССЛЕДОВАНИЕ
		-- =======================================
		if investigating then
			if closestPlayer then
				if Config.Debugging then
					warn(string.format("🔍➡️🚨 [РАССЛЕДОВАНИЕ→ПОГОНЯ] Обнаружен %s!", closestPlayer.Name))
				end
				startChasing(closestPlayer)
				continue
			end

			if os.clock() > investigateUntil then
				if Config.Debugging then
					warn("⏰ [РАССЛЕДОВАНИЕ] Время вышло, завершаю")
				end
				stopInvestigation()
			else
				continue
			end
		end

		-- =======================================
		-- ФАЗА 2: АКТИВНАЯ ПОГОНЯ
		-- =======================================
		if chasingPlayer ~= nil then
			-- Проверяем смену цели ДАЖЕ во время погони
			if closestPlayer and shouldSwitchTarget(closestPlayer) then
				if Config.Debugging then
					warn(string.format("🔄 [СМЕНА ЦЕЛИ] %s → %s", chasingPlayer.Name, closestPlayer.Name))
				end
				startChasing(closestPlayer)
				continue
			end

			local target = chasingPlayer
			local canSee, canHear = getPlayerSenses(target)
			local stillValid = canSee or canHear
			local continueResult = ContinueChasing(NPC, target, canSee, canHear)

			if not stillValid and not continueResult then
				if Config.Debugging then
					warn(string.format("❌ [ЦЕЛЬ ПОТЕРЯНА] %s пропал → расследую последнюю точку", target.Name))
				end

				-- Do not read the player's live position after losing sight/hearing.
				-- ContinueChasing stores the last sensed (or predicted corner) position.
				local lastKnownPosition = PatrolStateManager.RetrieveInformation()
				stopChasing()

				if lastKnownPosition then
					startInvestigation(lastKnownPosition, target)
				else
					PatrolStateManager.Clear()
					startPatrol()
				end
			end

			continue
		end

		-- =======================================
		-- ФАЗА 3: ПОИСК НОВОЙ ЦЕЛИ
		-- =======================================
		if chasingPlayer == nil and not investigating then
			if closestPlayer ~= nil then
				if pendingDetectionTarget ~= closestPlayer then
					pendingDetectionTarget = closestPlayer
					pendingDetectionSince = os.clock()
				end

				if os.clock() - pendingDetectionSince >= DETECTION_DELAY then
					if Config.Debugging then
						warn(string.format("⏱️ [ОБНАРУЖЕНИЕ] Цель %s найдена!", closestPlayer.Name))
					end
					startChasing(closestPlayer)
				end
			else
				pendingDetectionTarget = nil
				pendingDetectionSince = 0
				-- НЕТ ЦЕЛЕЙ - ПАТРУЛЬ!
				if not isPatrolling then
					startPatrol()
				else
					updatePatrol()
				end
			end
		end
	end
end

task.spawn(PostInit, NPC)

local heartbeatHookWarned = false
local heartbeatConnection
heartbeatConnection = run.Heartbeat:Connect(function()
	if not NPC.Parent then
		heartbeatConnection:Disconnect()
		if currentAnimTrack then
			currentAnimTrack:Stop(0.1)
		end
		return
	end

	local ok, err = pcall(Heartbeat, NPC, chasingPlayer)
	if not ok and not heartbeatHookWarned then
		heartbeatHookWarned = true
		warn("[AI] Ошибка в Hooks.Heartbeat: " .. tostring(err))
	end
	updateAnimation()
end)

coreLoop()