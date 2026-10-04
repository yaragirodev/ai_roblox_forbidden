-- return true to resume normal operation
-- fires this function when a PathfindingLink with no "Label" property is reached.
-- seperate from the Default function by request from a lot of people.
return function(NPC: Model, WP: PathWaypoint)

	-- TP example
	local root = NPC.PrimaryPart or NPC:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		warn("[PATH LINK] NPC " .. NPC.Name .. " has no root part.")
		return false
	end
	root.CFrame = CFrame.new(WP.Position + Vector3.new(0, 2, 0))
	--root.AssemblyLinearVelocity = Vector3.zero -- idk if you can do this

	-- resume pathfind
	return true
end