-- Called when the NPC has no active target; selects the next patrol destination.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AI = require(ReplicatedStorage:WaitForChild("Forbidden"):WaitForChild("AI"))

local NPC = script.Parent.Parent.Parent
local Config = require(script.Parent.Parent.Config)
local Common = require(script.Parent.Parent.Common)
local PatrolStateManager = require(script.Parent.PatrolStateManager)

local lastNode: Instance? = nil
local warnedNoNodes = false
local busy = false

local function getNodeFolder(): Instance?
	local configuredFolder = Config.PatrollingNodes
	if typeof(configuredFolder) == "Instance" and configuredFolder.Parent then
		return configuredFolder
	end

	local workspaceFolder = workspace:FindFirstChild("nodes")
	if workspaceFolder then
		Config.PatrollingNodes = workspaceFolder
	end
	return workspaceFolder
end

local function getRandomNode(): Instance?
	local nodeFolder = getNodeFolder()
	local children = {}

	if nodeFolder then
		for _, child in ipairs(nodeFolder:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Model") then
				table.insert(children, child)
			end
		end
	end

	if #children == 0 then
		if not warnedNoNodes then
			warn("[PATROL] Не найдены точки патруля в workspace.nodes (добавьте Part или Model).")
			warnedNoNodes = true
		end
		return nil
	end
	warnedNoNodes = false

	if lastNode and #children > 1 then
		local lastIndex = table.find(children, lastNode)
		if lastIndex then
			table.remove(children, lastIndex)
		end
	end

	local chosenNode = children[math.random(1, #children)]
	lastNode = chosenNode
	return chosenNode
end

local function wander()
	if busy then
		return nil
	end
	busy = true

	local ok, result = pcall(function()
		local humanoid = NPC:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Config.PatrolWalkSpeed or Config.WalkSpeed or 8
		end

		local aiConfig = AI.GetConfig(NPC)
		aiConfig:RestoreDefaults()
		aiConfig.Visualization.Enabled = Config.Visualize
		aiConfig.Debugging.Enabled = Config.ForbiddenDebugging
		aiConfig.AgentInfo = Config.GetAgentInfo()
		Common.SetHooksForConfig()

		local node = nil
		if Config.DoCornerChase then
			node = PatrolStateManager.RetrieveInformation()
		end
		-- Always consume the old memory so a later patrol cannot follow a stale target.
		PatrolStateManager.Clear()

		if node == nil and Config.DoPatrolling then
			node = getRandomNode()
		end
		if node == nil then
			return nil
		end

		AI.SmartPathfind(NPC, node, true)
		return node
	end)

	busy = false
	if not ok then
		warn("[PATROL] Не удалось запустить патруль: " .. tostring(result))
		return nil
	end
	return result
end

return function()
	return wander()
end
