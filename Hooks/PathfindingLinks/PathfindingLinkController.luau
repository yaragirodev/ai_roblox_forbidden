local LocalRoot = script.Parent
local MainScript = LocalRoot.Parent.Parent
local Config = require(MainScript.Config)

local LoadedLinks: {[string]: (NPC: Model, WP: PathWaypoint) -> boolean} = {}
local implementationFolder = LocalRoot:FindFirstChild("impl")

if implementationFolder then
	for _, module in ipairs(implementationFolder:GetChildren()) do
		if not module:IsA("ModuleScript") then
			warn("[PATH LINK] " .. module:GetFullName() .. " is not a ModuleScript; skipping it.")
			continue
		end
		if LoadedLinks[module.Name] then
			warn("[PATH LINK] Duplicate implementation name '" .. module.Name .. "'; skipping " .. module:GetFullName())
			continue
		end

		local ok, implementation = pcall(require, module)
		if not ok then
			warn("[PATH LINK] Failed to load " .. module:GetFullName() .. ": " .. tostring(implementation))
		elseif type(implementation) ~= "function" then
			warn("[PATH LINK] " .. module:GetFullName() .. " must return a function.")
		else
			LoadedLinks[module.Name] = implementation
		end
	end
elseif Config.DebugLinks then
	warn("[PATH LINK] No implementation folder found at " .. LocalRoot:GetFullName() .. ".impl")
end

local function fireFunction(linkType: string, NPC: Model, WP: PathWaypoint, implementation): boolean
	if type(implementation) ~= "function" then
		return false
	end

	local success, result = pcall(implementation, NPC, WP)
	if not success then
		warn("[PATH LINK] Error in '" .. linkType .. "' for NPC " .. NPC.Name .. ": " .. tostring(result))
		return false
	end
	if result ~= true then
		warn("[PATH LINK] Link '" .. linkType .. "' returned false; interrupting this path.")
		return false
	end

	return true
end

return function(NPC: Model, WP: PathWaypoint): boolean
	local linkType = WP.Label
	if linkType == nil or linkType == "" then
		linkType = "NoLabel"
		if Config.DebugLinks and not Config.IgnoreNoLabelLinkMessage then
			warn("[PATH LINK] No label on a pathfinding link for NPC " .. NPC.Name)
		end
	end

	local implementation = LoadedLinks[linkType]
	if implementation then
		return fireFunction(linkType, NPC, WP, implementation)
	end

	if Config.DebugLinks and not Config.IgnoreDefaultLinkMessage then
		warn("[PATH LINK] No implementation for '" .. linkType .. "' on NPC " .. NPC.Name .. "; trying Default.")
	end

	-- Previously this attempted to call LoadedLinks[linkType] (nil), aborting every
	-- unknown labelled link even though a Default implementation is provided.
	local defaultImplementation = LoadedLinks.Default
	if defaultImplementation then
		return fireFunction("Default", NPC, WP, defaultImplementation)
	end

	warn("[PATH LINK] No implementation for '" .. linkType .. "' and no Default implementation.")
	return false
end
