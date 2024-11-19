local core = require("VTK/core")

---@class Spacer: Component
local spacer = {}

spacer.new_spacer = function(horizontal_pad, vertical_pad)
	local new_spacer = core.new_component() ---@class Spacer
	new_spacer.pref_width = horizontal_pad and horizontal_pad or 1
	new_spacer.pref_height = vertical_pad and vertical_pad or 1

	new_spacer.min_width = 0
	new_spacer.min_height = 0

	new_spacer.max_width = new_spacer.pref_width
	new_spacer.min_width = new_spacer.pref_height

	return new_spacer
end

return spacer
