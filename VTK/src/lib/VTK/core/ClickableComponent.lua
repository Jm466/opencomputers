local Component = require("VTK/core/Component")

---@return boolean success
local function array_remove(array, value)
	for i = 1, #array do
		if array[i] == value then
			for j = i, #array do
				array[j] = array[j + 1]
			end
			return true
		end
	end
	return false
end

---@class ClickableComponent
local Clickable = Component.new()

function Clickable:init(clickable)
	clickable.click_listeners = {}
end

function Clickable:add_click_listener(func)
	self.click_listeners[#self.click_listeners + 1] = func
end

function Clickable:remove_click_listener(func)
	return array_remove(self.click_listeners, func)
end

function Clickable:click()
	if self.click_listeners then
		for _, listener in pairs(self.click_listeners) do
			listener()
		end
	end
end

return {
	new = function() ---@return ClickableComponent
		return Clickable:new() ---@type ClickableComponent
	end,
}
