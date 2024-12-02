local event = require("event")
local gpu = require("component").gpu
local thread = require("thread")

local wm = require("ventanos/window_manager")

local drag_min_time_ms = 1

local function wrap(func, ...)
	local function wrapper(f, ...)
		local completed, error = pcall(f, ...)

		if not completed then
			gpu.setBackground(16777215)
			gpu.setForeground(16711680)
			print("VentanOS error:" .. error)
		end
	end

	thread.create(wrapper, func, ...)
end

local last_drag = 0
local registered = {}
local function start()
	event.onError = function(...)
		gpu.setBackground(16711680)
		gpu.setForeground(16777215)
		print(...)
	end
	registered.touch = event.listen("touch", function(_event, _, x, y, button)
		wrap(wm.mouse_handler, _event, x, y, button)
	end)

	registered.drag = event.listen("drag", function(_event, _, x, y, button)
		local current_time = os.time()
		if current_time - last_drag < drag_min_time_ms then
			return
		end

		last_drag = current_time
		wrap(wm.mouse_handler, _event, x, y, button)
	end)
	registered.drop = event.listen("drop", function(_event, _, x, y, button)
		last_drag = 0
		wrap(wm.mouse_handler, _event, x, y, button)
	end)
	registered.listen = event.listen("scroll", function(_event, _, x, y, direction)
		wrap(wm.mouse_handler, _event, x, y, 0, direction)
	end)
end

local function stop()
	for _, id in pairs(registered) do
		event.cancel(id)
	end
end

return {
	start = start,
	stop = stop,
}
