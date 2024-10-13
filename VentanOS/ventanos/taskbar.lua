local gpu = require("component").gpu
local program_menu = require("/usr/ventanos/program_menu")

local function draw_taskbar()
	local max_x, start_y = gpu.getViewport()
	start_y = start_y - 1

	gpu.setBackground(13712666) -- red
	gpu.set(1, start_y, " ")
	gpu.setBackground(9221934) -- green
	gpu.set(2, start_y, " ")
	gpu.setBackground(4094900) -- blue
	gpu.set(1, start_y + 1, " ")
	gpu.setBackground(2841503) -- yellow
	gpu.set(2, start_y + 1, " ")

	gpu.setBackground(2316495) -- task bar blue
	gpu.fill(3, start_y, max_x - 2, 2)
end

---@diagnostic disable-next-line: unused-local
local function mouse_handler(event, x, y)
	if event == "touch" then
		if x < 3 then
			program_menu()
		end
	end
end

return {
	draw_taskbar = draw_taskbar,
	mouse_handler = mouse_handler,
}
