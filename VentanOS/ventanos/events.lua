local event = require("event")

local wm = require("/usr/ventanos/window_manager")

local drag_min_time_mn = 100

local last_drag = 0
local function start()
	event.listen("touch", function(_event, _, x, y, button)
		wm.mouse_handler(_event, x, y, button)
	end)
	event.listen("drag", function(_event, _, x, y, button)
		local current_time = os.time()
		if current_time - last_drag < drag_min_time_mn then
			return
		end

		last_drag = current_time
		wm.mouse_handler(_event, x, y, button)
	end)
	event.listen("drop", function(_event, _, x, y, button)
		wm.mouse_handler(_event, x, y, button)
	end)
	event.listen("scroll", function(_event, screenAdress, x, y, direction, playerName) end)
	event.listen("component_available", function(_event, componentType) end)
	event.listen("component_unavailable", function(_event, componentType) end)
end

return {
	start = start,
}
