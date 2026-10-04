--[[
Called whenever the NPC is doing nothing, normally used for patrol logic.
]]--

-- == Services == --
local rs = game:GetService("ReplicatedStorage")

-- == Forbidden Architecture == --
local AI = require(rs.Forbidden.AI)

-- == References == --
local NPC     = script.Parent.Parent.Parent
local CFG     = require(script.Parent.Parent.Config)
local nodes    = CFG.PatrollingNodes

-- == Assist == --
local Common = require(script.Parent.Parent.Common)
local PatrolStateManager = require(script.Parent.PatrolStateManager)

-- == Initialization == --
local lastNode = nil

-- == Core == --
local function getRandomNode()
    local children = nodes:GetChildren()
    if #children == 0 then return nil end

    if lastNode ~= nil and #children > 1 then 
        local idx = table.find(children, lastNode)
        if idx then
            table.remove(children, idx)
        end
    end

    local chosenNode = children[math.random(1, #children)]
    lastNode = chosenNode
    return chosenNode
end

local db = false

local function WanderLogic()
    if db then return nil end
    db = true

    local human = NPC:FindFirstChildOfClass("Humanoid")
    if human then
        human.WalkSpeed = CFG.PatrolWalkSpeed or 8
    end

    local config = AI.GetConfig(NPC)
    config:RestoreDefaults()
    config.Visualization.Enabled     = CFG.Visualize
    config.Debugging.Enabled        = CFG.ForbiddenDebugging
    config.AgentInfo                 = CFG.GetAgentInfo()
    Common.SetHooksForConfig()

    local node = nil

    if CFG.DoCornerChase then
        node = PatrolStateManager.RetrieveInformation()
        PatrolStateManager.Clear()
    end

    if node == nil and CFG.DoPatrolling then
        node = getRandomNode()
    end

    if node == nil then
        warn(":warning: [PATROL] Нет точек патруля в workspace.nodes!")
        db = false
        return nil
    end

    AI.SmartPathfind(NPC, node, true)
    db = false
    return node -- Возвращаем точку обратно в скрипт!
end

return function()
    return WanderLogic()
end