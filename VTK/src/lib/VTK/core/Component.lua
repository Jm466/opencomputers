---@class Component
local Component = {
	x = 1,
	y = 1,
	width = 0,
	height = 0,
	pref_width = 5,
	pref_height = 5,
	min_width = 0,
	min_height = 0,
	max_width = math.huge,
	max_height = math.huge,
}

---@param class Component
---@param comp Component
local function initialize_component(class, comp)
	if class.parent and class ~= class.parent then
		initialize_component(class.parent, comp)
	end
	if class.init then
		class:init(comp)
	end
end

function Component:new()
	local new_component = setmetatable({}, { __index = self })
	new_component.parent = self
	initialize_component(self, new_component)
	return new_component
end

return {
	new = function() ---@return Component
		return Component:new()
	end,
}
