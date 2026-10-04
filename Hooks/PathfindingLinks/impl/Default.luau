-- return true to resume normal operation
-- fires this function when a PathfindingLink with no other preset ModuleScript exists.
return function(NPC: Model, WP: PathWaypoint)

	-- MoveTo example
	local human = NPC:FindFirstChildOfClass("Humanoid")
	if not human then
		warn("[PATH LINK] NPC " .. NPC.Name .. " has no Humanoid.")
		return false
	end

	human:MoveTo(WP.Position)
	local reached = human.MoveToFinished:Wait()
	if not reached then
		return false
	end

	-- resume pathfind when MoveTo complete
	return true
end