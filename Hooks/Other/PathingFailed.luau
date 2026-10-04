local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local AI = require(rs:WaitForChild("Forbidden"):WaitForChild("AI"))

local Config = require(script.Parent.Parent.Parent.Config)

-- Восстановление после потери пути во время погони.
-- Без этого хука Forbidden просто останавливается: Tracking не пересчитает путь,
-- если цель сдвинулась меньше, чем на Tracking.DistanceMovedThreshold (1 стад).
-- Цель берём из атрибута NPC (не через PatrolStateManager — циклический require).

local lastRecovery = 0
local RECOVERY_COOLDOWN = 1 -- секунд между попытками восстановления

return function(NPC: Instance, Reason: "Path Not Found" | "Stuck Limit Reached" | string)
	-- Восстанавливаем только активную погоню (не патруль и не расследование)
	if NPC:GetAttribute("IsChasing") ~= true then return end
	if os.clock() - lastRecovery < RECOVERY_COOLDOWN then return end

	local target = Players:GetPlayerByUserId(NPC:GetAttribute("ChaseTargetUserId") or -1)
	if not target then return end

	local char = target.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local human = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not human or human.Health <= 0 then return end

	lastRecovery = os.clock()

	if Config.Debugging then
		warn("[ВОССТАНОВЛЕНИЕ]: путь потерян (" .. tostring(Reason) .. "), перезапускаю погоню за " .. target.Name)
	end

	-- Перезапускаем Tracking на живую цель — Forbidden сразу построит свежий путь
	AI.SmartPathfind(NPC, target)
end