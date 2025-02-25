local Component = require("VTK/core/Component")

---@class Spacer
local Spacer = Component.new()

---@return Spacer
function Spacer:init(new_spacer)
	new_spacer.pref_width = 1
	new_spacer.pref_height = 1

	new_spacer.min_width = 0
	new_spacer.min_height = 0

	new_spacer.max_width = new_spacer.pref_width
	new_spacer.min_width = new_spacer.pref_height

	return new_spacer
end

return {
	new = function() ---@return Spacer
		return Spacer:new() ---@type Spacer
	end,
	new_configured = function(horizontal_pad, vertical_pad) ---@return Spacer
		local new_spacer = Spacer:new() ---@cast new_spacer Spacer

		new_spacer.pref_width = horizontal_pad
		new_spacer.pref_height = vertical_pad
		new_spacer.max_width = horizontal_pad
		new_spacer.max_height = vertical_pad

		return new_spacer
	end,
}
