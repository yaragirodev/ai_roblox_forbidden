local Common = require(script.Parent.Parent.Common)

return function(NPC: Instance)
    return false -- does not block the loop
end

--[[
If true is returned:

Blocks the script from doing anything, though will continue the current pathfind and targeting if applicable.


Example use case,
return false in ContinueChasing
return true here.

now you can control the NPC without the script messing around.

]]--