local Debris = game:GetService("Debris")
local rs = game:GetService("ReplicatedStorage")
local AI = require(rs:WaitForChild("Forbidden"):WaitForChild("AI"))

local Common = require(script.Parent.Parent.Common)
local Config = require(script.Parent.Parent.Config)
local PatrolStateManager = require(script.Parent.PatrolStateManager)
local IsTargetValid = require(script.Parent.IsTargetValid)

local function CreateDebugPart(name: string, pos: Vector3)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1,1,1)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 0.5
	part.Color = Color3.fromRGB(255, 0, 0)
	part.Position = pos
	part.Parent = workspace
	part.Name = "Prediction"
	Debris:AddItem(part, 3)
end

-- Функция проверки бега
local function isTargetSprinting(targetChar)
	local root = targetChar:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	
	-- Проверка твоего атрибута
	if root:GetAttribute("IsRunning") == true then return true end
	
	-- Бэкап: физическая скорость (если атрибут лагает)
	local vel = root.AssemblyLinearVelocity
	local speed = Vector2.new(vel.X, vel.Z).Magnitude
	return speed > 18
end

return function(NPC: Instance, Target: Player)
	local Human = NPC:FindFirstChildOfClass("Humanoid")
	local PrevPoint = PatrolStateManager.RetrieveInformation()
	
	local targetChar = Target.Character
	local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
	
	if targetRoot then
		PatrolStateManager.SetTargetInfo(Target, targetRoot.Position)
	end
	
	if targetChar == nil or targetRoot == nil then
		return false
	end
	
	local targetHuman = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHuman or targetHuman.Health <= 0 then
		return false
	end
	
	-- 1. ЕСЛИ ВИДИТ (ЗРЕНИЕ)
	if IsTargetValid(NPC, Target) then
		Human.WalkSpeed = Config.ChaseWalkSpeed
		return true -- Всё ок, продолжаем погоню
	end
	
	-- 2. ЕСЛИ НЕ ВИДИТ, НО СЛЫШИТ (СЛУХ)
	if isTargetSprinting(targetChar) then
		local npcRoot = NPC:FindFirstChild("HumanoidRootPart")
		local dist = (npcRoot.Position - targetRoot.Position).Magnitude
		
		if dist <= (Config.HearRange or 110) then
			if Config.Debugging then
				warn("👂 [СЛУХ]: Слышу бег " .. Target.Name .. " через стену!")
			end
			Human.WalkSpeed = Config.ChaseWalkSpeed
			-- Форсируем путь к позиции (а не к игроку), чтобы обойти LoS проверку Forbidden
			AI.SmartPathfind(NPC, targetRoot.Position)
			return true 
		end
	end
	
	-- 3. ПОТЕРЯ ЦЕЛИ (Идем в последнюю точку - Corner Chase)
	if Config.Debugging then
		print("👣 [ПОТЕРЯ]: Не вижу и не слышу, иду к последней точке.")
	end
	
	Human.WalkSpeed = Config.ChaseWalkSpeed -- Не замедляемся, пока не дойдем до угла!
	
	if PrevPoint ~= nil then
		local NewPoint = targetRoot.Position
		local diff = NewPoint - PrevPoint
		
		if diff.Magnitude < 0.1 then return false end
		if diff.Magnitude > Config.IgnoreCornerChaseDistance then 
			PatrolStateManager.Clear()
			return false 
		end
		
		local direction = diff.Unit
		local Prediction = NewPoint + direction * Config.ReasonablePredictionDistance
		
		if Config.Debugging then
			CreateDebugPart("Predict", Prediction)
		end

		PatrolStateManager.SetTargetInfo(Target, Prediction)
	end
	
	return false -- Возвращаемся к патрулю
end