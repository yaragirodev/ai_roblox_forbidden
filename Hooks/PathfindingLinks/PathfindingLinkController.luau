-- == References == --
local LocalRoot     = script.Parent
local MainScript    = LocalRoot.Parent.Parent
local implFolder    = LocalRoot.impl

-- == Config == --
local Config        = require(MainScript.Config)

-- == Initialization == --
local LoadedLinks: {[string]: {(NPC: Model, WP: PathWaypoint) -> (boolean)}} = {}

for _, mod in pairs(implFolder:GetChildren()) do
	if LoadedLinks[mod.Name] then warn("A pathfinding link implementation by the same name: [" .. mod.Name .. "] was already loaded! Skipping this!"); continue end
	if not mod:IsA("ModuleScript") then warn("[" .. mod:GetFullName() .. "] is not a ModuleScript. Please see [Default] and [NoLabel] for an example in the impl folder."); end
	LoadedLinks[mod.Name] = require(mod)
end


-- == Main Code == --
return function(NPC: Model, WP: PathWaypoint)
	local linkType = WP.Label

	if linkType == "" or linkType == nil then
		linkType = "NoLabel"
		if Config.DebugLinks and not Config.IgnoreDefaultLinkMessage then
			warn("No Label pathfinding link from NPC [" .. NPC.Name .. "]" .. "silence with `IgnoreNoLabelLinkMessage`")
		end
	end

	local function FireFunc(func)
		local success, result = pcall(func, NPC, WP)
		if not success then
			warn("An error occurred while executing a pathfinding link of type [" .. linkType .. "] for NPC [" .. NPC.Name .. "]: " .. tostring(result))
			return false
		end

		if not result then
			warn("Pathfinding Link did not return true, interrupting!")
			return false
		end

		return true
	end

	-- No label / func found
	if LoadedLinks[linkType] then
		return FireFunc(LoadedLinks[linkType])
	end


	-- Defaulting
	if not LoadedLinks[linkType] then    
		if Config.DebugLinks and not Config.IgnoreDefaultLinkMessage then
			warn("No pathfinding link implementation found for type [" .. linkType .. "] for NPC [" .. NPC.Name .. "]" .. "silence with `IgnoreDefaultLinkMessage")
		end

		return FireFunc(LoadedLinks[linkType])
	end

	warn("Now this is a real shocker. How you managed to see this message is impressive.")
	return true -- never reaches here. just shutting my IDE up.
end