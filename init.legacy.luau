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
local Root			= NPC:WaitForChild("HumanoidRootPart")
local Human			= NPC:FindFirstChildOfClass("Humanoid")

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
	if not id or id == "" then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		return track
	end
	if Config.Debugging then
		warn("[АНИМАЦИИ] Не удалось загрузить анимацию: " .. tostring(id))
	end
	return nil
end

if animConfig.Enabled ~= false then
	loadedAnims.Idle = loadAnim(animConfig.Idle)
	loadedAnims.Walk = loadAnim(animConfig.Walk)
	loadedAnims.Run = loadAnim(animConfig.Run)
end

local function playAnimation(animName: string, fadeTime: number?, speed: number?)
	if loadedAnims.Idle == nil then return end -- анимации отключены или не загрузились

	-- Уже играем эту анимацию — только подстраиваем скорость при необходимости
	if currentAnimName == animName then
		if currentAnimTrack and speed and currentAnimTrack.Speed ~= speed then
			currentAnimTrack:AdjustSpeed(speed)
		end
		return
	end

	local track = loadedAnims[animName]
	if not track then return end

	if currentAnimTrack then
		currentAnimTrack:Stop(fadeTime or 0.2)
	end
	track:Play(fadeTime or 0.2, 1, speed or 1)
	currentAnimTrack = track
	currentAnimName = animName

	if Config.Debugging then
		print(string.format("🎬 [АНИМАЦИЯ] -> %s", animName))
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

local function debugPrint(...)
	if Config.Debugging then
		local varArgs = {...}
		local message = ""
		for _, v in ipairs(varArgs) do
			message = message .. tostring(v)
		end
		print("[@DEBUG TrackClosestPlayer] " .. message)
	end
end

-- =============================================
-- ПРОВЕРКА УГЛА ОБЗОРА (FOV)
-- =============================================

local function isInFieldOfView(targetPosition: Vector3): boolean
	local npcLookVector = Root.CFrame.LookVector
	local directionToTarget = (targetPosition - Root.Position).Unit

	-- Вычисляем угол между взглядом NPC и направлением к цели
	local dotProduct = npcLookVector:Dot(directionToTarget)
	local angle = math.deg(math.acos(dotProduct))

	local maxAngle = Config.FieldOfView or 120 -- градусов (по умолчанию 120°)
	local halfFOV = maxAngle / 2

	if Config.Debugging then
		-- print(string.format("   └─ 👁️ [УГОЛ ОБЗОРА] Угол: %.1f° | Макс: %.1f° | В поле зрения: %s", angle, halfFOV, tostring(angle <= halfFOV)))
	end

	return angle <= halfFOV
end

-- =============================================
-- БАЗОВЫЕ ПРОВЕРКИ ИГРОКА
-- =============================================

local invalidPlayers = {}

local function isPlayerAlive(player: Player): boolean
	if player == nil then return false end
	local char = player.Character
	if char == nil then return false end
	local hrt = char:FindFirstChild("HumanoidRootPart")
	if hrt == nil then return false end
	local human = char:FindFirstChild("Humanoid")
	if human == nil then return false end
	if human.Health <= 0 then return false end
	if invalidPlayers[player] ~= nil then
		if os.clock() - invalidPlayers[player] < Config.InvalidatePlayersFor then
			return false
		end
	end
	return true
end

local function canSeePlayer(player: Player): boolean
	if not isPlayerAlive(player) then return false end

	local char = player.Character
	local targetRoot = char:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return false end

	-- ПРОВЕРКА 1: Угол обзора (FOV)
	if not isInFieldOfView(targetRoot.Position) then
		if Config.Debugging then
			-- print(string.format("👁️❌ [ЗРЕНИЕ] %s вне поля зрения (за спиной)", player.Name))
		end
		return false
	end

	-- ПРОВЕРКА 2: Raycast видимость (стены, препятствия)
	local canSee = IsTargetValid(NPC, player)

	if Config.Debugging then
		if canSee then
			print(string.format("👁️✅ [ЗРЕНИЕ] Вижу %s", player.Name))
		end
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

local function isValidTarget(player: Player): boolean
	local canSee = canSeePlayer(player)
	local canHear = canHearPlayer(player)

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
	local closestPlayer = nil
	local closestDistance = math.huge
	local detectMethod = ""

	for _, player in pairs(players:GetPlayers()) do
		if not isPlayerAlive(player) then continue end

		local char = player.Character
		local targetRoot = char:FindFirstChild("HumanoidRootPart")
		if not targetRoot then continue end

		local distance = (Root.Position - targetRoot.Position).Magnitude

		if canSeePlayer(player) then
			if distance < closestDistance then
				closestDistance = distance
				closestPlayer = player
				detectMethod = "👁️ ЗРЕНИЕ"
			end
		elseif canHearPlayer(player) then
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
local lastTargetSwitchTime = 0

local function shouldSwitchTarget(newTarget: Player): boolean
	if newTarget == nil then return false end
	if chasingPlayer == nil then return true end
	if newTarget == chasingPlayer then return false end

	-- Защита от постоянного переключения
	if os.clock() - lastTargetSwitchTime < (Config.MinTargetSwitchInterval or 2) then
		if Config.Debugging then
			print("⏱️ [СМЕНА ЦЕЛИ] Слишком рано переключаться (защита от спама)")
		end
		return false
	end

	local currentChar = chasingPlayer.Character
	local newChar = newTarget.Character

	if not currentChar or not newChar then return false end

	local currentRoot = currentChar:FindFirstChild("HumanoidRootPart")
	local newRoot = newChar:FindFirstChild("HumanoidRootPart")

	if not currentRoot or not newRoot then return false end

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
local investigatePosition = nil

local isPatrolling = false
local currentPatrolNode = nil
local patrolNodeReachedTime = 0
local patrolStartTime = 0

local INVESTIGATE_TIME = Config.InvestigateTime or 4

local function startPatrol()
	if isPatrolling then return end
	isPatrolling = true
	investigating = false
	chasingPlayer = nil
	patrolNodeReachedTime = 0
	patrolStartTime = os.clock()

	if Config.Debugging then
		print("🚶‍♂️ [ПАТРУЛЬ АКТИВИРОВАН] Монстр начал патрулирование")
	end

	AI.Stop(NPC)
	Human.WalkSpeed = Config.PatrolWalkSpeed or Config.WalkSpeed or 8
	currentPatrolNode = DoingNothing()
end

local function updatePatrol()
	if not isPatrolling then return end

	-- Если нода не выбрана или невалидна
	if not isNodeValid(currentPatrolNode) then
		currentPatrolNode = DoingNothing()
		patrolNodeReachedTime = 0
		patrolStartTime = os.clock()
		return
	end

	local nodePos = getNodePosition(currentPatrolNode)
	if not nodePos then
		currentPatrolNode = DoingNothing()
		patrolNodeReachedTime = 0
		patrolStartTime = os.clock()
		return
	end

	local dist = (Root.Position - nodePos).Magnitude
	local timeWalking = os.clock() - patrolStartTime

	-- Дошел до точки ИЛИ идем к ней слишком долго (> 15 сек)
	if dist <= 5 or timeWalking > 15 then
		if patrolNodeReachedTime == 0 then
			patrolNodeReachedTime = os.clock()
			if Config.Debugging then
				local name = (typeof(currentPatrolNode) == "Instance") and currentPatrolNode.Name or "Точка"
				print(string.format("📍 [ПАТРУЛЬ] Дошел до точки '%s', осмотр местности...", name))
			end
		elseif os.clock() - patrolNodeReachedTime >= 2 then -- Ждет 2 секунды на точке
			patrolNodeReachedTime = 0
			patrolStartTime = os.clock()
			if Config.Debugging then
				print("🚶‍♂️ [ПАТРУЛЬ] Иду к следующей точке...")
			end
			currentPatrolNode = DoingNothing() -- Выбираем следующую ноду!
		end
	end
end

local function startInvestigation(lastKnownPos)
	isPatrolling = false
	investigating = true
	investigateUntil = os.clock() + INVESTIGATE_TIME
	investigatePosition = lastKnownPos
	Human.WalkSpeed = Config.ChaseWalkSpeed

	if Config.Debugging then
		warn(string.format("🔍 [РАССЛЕДОВАНИЕ НАЧАТО] Бегу к точке (%.1f, %.1f, %.1f) | Время: %d сек", 
			lastKnownPos.X, lastKnownPos.Y, lastKnownPos.Z, INVESTIGATE_TIME))
	end

	AI.SmartPathfind(NPC, lastKnownPos)
end

local function stopInvestigation()
	if not investigating then return end
	investigating = false
	investigatePosition = nil
	Human.WalkSpeed = Config.PatrolWalkSpeed or Config.WalkSpeed

	if Config.Debugging then
		warn("🔍 [РАССЛЕДОВАНИЕ ОКОНЧЕНО] Никого не нашёл, возвращаюсь к патрулю")
	end

	startPatrol()
end

-- =============================================
-- НАЧАЛО ПОГОНИ
-- =============================================

local function startChasing(target: Player)
	-- КРИТИЧЕСКИЙ ФИКС: СРАЗУ МГНОВЕННО ОСТАНАВЛИВАЕМ ПАТРУЛЬ В AI!
	AI.Stop(NPC)

	isPatrolling = false
	investigating = false
	investigatePosition = nil

	if Config.Debugging then
		warn(string.format("🚨 [ПОГОНЯ НАЧАТА] Цель: %s | Метод: %s", target.Name, lastDetectMethod))
	end

	chasingPlayer = target
	lastTargetSwitchTime = os.clock()
	NPC:SetAttribute("IsChasing", true)
	NPC:SetAttribute("ChaseTargetUserId", target.UserId)
	Human.WalkSpeed = Config.ChaseWalkSpeed

	local config = AI.GetConfig(NPC)
	config:RestoreDefaults()
	config.Tracking.Enabled			= true
	config.Visualization.Enabled	= Config.Visualize
	config.Debugging.Enabled		= Config.ForbiddenDebugging
	config.AgentInfo				= Config.GetAgentInfo()
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
	while NPC and NPC.Parent do
		-- ЧАСТАЯ ПРОВЕРКА (0.1 сек вместо 1.0 сек), чтобы реакция на ходу была МГНОВЕННОЙ!
		task.wait(0.1)

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

			local stillValid = isValidTarget(chasingPlayer)
			local continueResult = ContinueChasing(NPC, chasingPlayer)

			if stillValid then
				continue
			elseif not continueResult then
				if canHearPlayer(chasingPlayer) then
					if Config.Debugging then
						print(string.format("👁️❌👂✅ [ПОТЕРЯН ИЗ ВИДУ] Но слышу %s!", chasingPlayer.Name))
					end
					local targetRoot = chasingPlayer.Character and chasingPlayer.Character:FindFirstChild("HumanoidRootPart")
					if targetRoot then
						AI.SmartPathfind(NPC, targetRoot.Position)
					end
				else
					if Config.Debugging then
						warn(string.format("❌ [ЦЕЛЬ ПОТЕРЯНА] %s пропал → расследование", chasingPlayer.Name))
					end

					local lastPos = nil
					local targetChar = chasingPlayer.Character
					if targetChar then
						local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
						if targetRoot then
							lastPos = targetRoot.Position
						end
					end

					stopChasing()

					if lastPos then
						startInvestigation(lastPos)
					else
						startPatrol()
					end
				end
			end

			continue
		end

		-- =======================================
		-- ФАЗА 3: ПОИСК НОВОЙ ЦЕЛИ
		-- =======================================
		if chasingPlayer == nil and not investigating then
			if closestPlayer ~= nil then
				if Config.Debugging then
					warn(string.format("⏱️ [ОБНАРУЖЕНИЕ] Цель %s найдена!", closestPlayer.Name))
				end

				-- КРИТИЧЕСКИЙ ФИКС: Убрали task.wait(Config.DetectionDelay), чтобы монстр реагировал МОМЕНТАЛЬНО!
				startChasing(closestPlayer)
			else
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

run.Heartbeat:Connect(function()
	Heartbeat(NPC, chasingPlayer)
	updateAnimation()
end)

coreLoop()