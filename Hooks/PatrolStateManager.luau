-- Shared last-known target information for the chase and patrol hooks.
local PatrolStateManager = {}

local storedTarget: Instance? = nil
local storedPoint: Vector3? = nil

function PatrolStateManager.SetTargetInfo(target: Instance?, point: Vector3?)
	if target ~= nil and typeof(point) == "Vector3" then
		storedTarget = target
		storedPoint = point
	end
end

function PatrolStateManager.GetTarget(): Instance?
	return storedTarget
end

function PatrolStateManager.RetrieveInformation(): Vector3?
	-- Keep the last known point even if the player respawns or leaves. The state is
	-- cleared when the patrol consumes it or when the caller decides to abandon it.
	return storedPoint
end

function PatrolStateManager.Clear()
	storedTarget = nil
	storedPoint = nil
end

return PatrolStateManager
