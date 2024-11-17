local imager = require("imager")

local background_path = "/usr/lib/ventanos_data/backgrounds/"

do
	local t2_background = "background80x25.ppm" -- 80x25
	local t3_background = "background160x50.ppm" -- 160x50

	local max_x = require("component").gpu.getViewport()
	if max_x == 160 then
		background_path = background_path .. t3_background
	else
		background_path = background_path .. t2_background
	end
end

local function draw_background(x, y, width, height)
	imager.print_ppm(background_path, x, y, x, y, width, height)
end

return {
	draw_background = draw_background,
}
