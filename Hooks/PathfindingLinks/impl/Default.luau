-- return true to resume normal operation
-- fires this function when a PathfindingLink with no other preset ModuleScript exists.
return function(NPC: Model, WP: PathWaypoint)

	-- MoveTo example
	local human = NPC:FindFirstChildOfClass("Humanoid")
	human:MoveTo(WP.Position)
	human.MoveToFinished:Wait()

	-- resume pathfind when MoveTo complete
	return true
end