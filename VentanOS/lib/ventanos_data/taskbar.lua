local gpu = require("component").gpu

local program_menu = require("ventanos_data/program_launcher")

local function draw_taskbar()
	local max_x, start_y = gpu.getViewport()
	start_y = start_y - 1

	gpu.setBackground(0xFF0000) -- red
	gpu.fill(1, start_y, 2, 1, " ")
	gpu.setBackground(0x00FF00) -- green
	gpu.fill(3, start_y, 2, 1, " ")
	gpu.setBackground(0x0000FF) -- blue
	gpu.fill(1, start_y + 1, 2, 1, " ")
	gpu.setBackground(0xFFFF00) -- yellow
	gpu.fill(3, start_y + 1, 2, 1, " ")

	gpu.setBackground(2316495) -- task bar blue
	gpu.fill(5, start_y, max_x - 2, 2, " ")
end

---@diagnostic disable-next-line: unused-local
local function mouse_handler(event, x, y)
	if event == "touch" then
		if x < 5 then
			program_menu()
		end
	end
end

return {
	draw_taskbar = draw_taskbar,
	mouse_handler = mouse_handler,
}
