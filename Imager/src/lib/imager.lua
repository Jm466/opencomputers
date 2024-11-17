local bit32 = require("bit32")
local gpu = require("component").gpu

--- Prints image to the screen
---@param path string Path to the file that contains the image
---@param x_dest integer|nil X coordinate of the pixel of the screen that will display the top-left most pixel of the image
---@param y_dest integer|nil Y coordinate of the pixel of the screen that will display the top-left most pixel of the image
---@param x_source integer|nil X coordinate of the top-left most pixel of the screen to be displayed
---@param y_source integer|nil Y coordinate of the top-left most pixel of the screen to be displayed
---@param max_width integer|nil Maximun width of the image to be displayed(the image will be cropped)
---@param max_height integer|nil Maximun heigth of the image to be displayed(the image will be cropped)
local function print_ppm(path, x_dest, y_dest, x_source, y_source, max_width, max_height)
	if path == nil then
		print("path must not be nil")
		return
	end

	local file = io.open(path, "rb")

	if file == nil then
		print("Could not open file")
		return
	end

	if file:read(2) ~= "P6" then
		print("This image is not in PPM format")
		return
	end
	file:seek("set", 3)

	local function get_input()
		local readed = file:read("l")
		while string.sub(readed, 1, 1) == "#" do
			readed = file:read("l")
		end
		return readed
	end
	local input = string.gmatch(get_input(), "%d+")
	local img_width = tonumber(input())
	local img_heigth = tonumber(input())
	local img_colors = tonumber(get_input())

	x_dest = x_dest == nil and 0 or x_dest - 1
	y_dest = y_dest == nil and 0 or y_dest - 1
	x_source = x_source == nil and 1 or x_source
	y_source = y_source == nil and 1 or y_source
	max_width = max_width == nil and img_width or max_width
	max_height = max_height == nil and img_heigth or max_height

	if y_source > 1 then
		file:seek("cur", img_width * (y_source - 1) * 3)
	end

	local max_x = x_source + max_width - 1
	local max_y = y_source + max_height - 1

	local res_x, res_y = gpu.getResolution()
	if max_x > res_x then
		max_x = res_x
		max_width = max_x - x_source + 1
	end
	if max_y > res_y then
		max_y = res_y
		max_height = max_y - y_source + 1
	end

	for j_dest = y_source, max_y do
		if x_source > 1 then
			file:seek("cur", (x_source - 1) * 3)
		end
		for i_dest = x_source, max_x do
			gpu.setBackground(
				bit32.arshift(file:read(1):byte(), -16) + bit32.arshift(file:read(1):byte(), -8) + file:read(1):byte()
			)
			gpu.fill(i_dest + x_dest, j_dest + y_dest, 1, 1, " ")
		end
		if max_x < img_width then
			file:seek("cur", (img_width - max_x) * 3)
		end
	end
	file:close()
end

return {
	print_ppm = print_ppm,
}
