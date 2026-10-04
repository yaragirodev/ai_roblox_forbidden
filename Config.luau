--[[ Config for SimpleTRACK

By @CritDEV, please feel free to modify/use this code

This file is part of the SimpleTRACK project, which is a simple implementation of a tracking NPC for Roblox.

Understand, SimpleTRACK is a basic framework and may not cover all edge cases or complex behaviors. 

It is meant to be a starting point for developers to build upon, and learn the Forbidden pathfinding library.

Do not use this code for malicious purposes or to exploit other developers in any way.
]]--

local Config = {}

-- == Initialization == --
Config.InsertAntiLag            = true -- yes, do this, please. (and you have to do AI.InsertAntiLag(NPC) everytime you anchor it)
Config.InitializationTimer      = 1 -- could set this to 0, just keep in mind, may cause random issues if you do not initialize your models properly.


-- == General Configuration == --
Config.SwapTargetsTimer         = 2 -- Time in seconds before the target is swapped, if a new target is closer. (set to -1 to disable)
Config.CheckTargetsInterval     = 1 -- Check for new targets, or target validity, every "x" seconds
Config.InvalidatePlayersFor     = 1 -- ignores a player for "x" seconds
Config.DetectionDelay          = 1.5 -- delay in seconds before the monster starts chasing after detecting a player
Config.InvestigateTime = 4 -- Сколько секунд монстр ищет на последней точке
Config.WalkHearRange = 16 -- Расстояние слышимости ходьбы (очень маленькое)
Config.FieldOfView = 120
Config.MinTargetSwitchInterval = 2
Config.TargetSwitchAdvantage = 0.7

-- == Additional Features Configuration == --
Config.DoCornerChase			= true -- Chase to the last seen position of a target.
Config.ReasonablePredictionDistance = 2 -- go x studs in the direction the player ran. 
Config.IgnoreCornerChaseDistance = 20 -- Last spot the player was seen is ignored if the distance to next point is more than this value. (TP to base) 
Config.DoPatrolling				= true -- Enable patrolling to random nodes.
Config.PatrollingNodes			= workspace:WaitForChild("nodes")

-- == Debugging == --
Config.Visualize                = true  -- Visualizes the path
Config.Debugging                = true -- Prints important info from the script.
Config.ForbiddenDebugging       = false -- really not recommended to enable this, even when debugging, serves mainly as a debugger for myself.
Config.DebugLinks               = true -- Debugs pathfinding links, useful for development of new link types.
Config.IgnoreDefaultLinkMessage = false -- ignore the default message when a pathfinding link is not found.
Config.IgnoreNoLabelLinkMessage = false -- ignore the default message when a pathfinding link with NoLabel is found


-- == Pathfinding Configuration == --
Config.WalkSpeed                = 16 -- if nil, no effect
Config.PatrolWalkSpeed          = 8  -- speed when patrolling (slower)
Config.ChaseWalkSpeed           = 18 -- speed when chasing a player (faster)

-- == Detection Configuration == --
Config.VisionRange              = 70 -- Дальность зрения (нужен LoS)
Config.HearRange                = 110 -- Дальность слуха (через стены, если бежит)

-- == Animations == --
-- Анимации играются на сервере через Animator хуманоида (реплицируются всем клиентам).
-- Idle  - стоит на месте (например, осматривается на точке патруля)
-- Walk  - идёт (патруль)
-- Run   - бежит (погоня / расследование)
Config.Animations = {
	Enabled             = true,
	Idle                = "rbxassetid://180435571", -- стандартный R6 idle
	Walk                = "rbxassetid://96099501193406", -- кастомная анимация ходьбы
	Run                 = "rbxassetid://96099501193406", -- та же анимация, но быстрее (см. множитель ниже)
	RunSpeedMultiplier  = 1.25, -- во сколько раз ускорять анимацию бега
}

-- Returns a FRESH copy of AgentInfo each call.
-- This prevents RestoreDefaults() from mutating the shared Config table.
Config.GetAgentInfo = function()
	return {
		AgentRadius    = 2.25,
		AgentHeight    = 5,
		AgentCanJump   = true,
		AgentCanClimb  = false,
		WaypointSpacing = 4,
		Cost           = {["Obstacle"] = math.huge},
	}
end
    -- modify other Forbidden settings in the script!



return Config