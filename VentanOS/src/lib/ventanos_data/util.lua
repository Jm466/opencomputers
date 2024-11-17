---@class Rectangle
---@field x integer
---@field y integer
---@field width integer
---@field height integer

--- Returns wether a point is in a rectangle
---@param rect Rectangle
---@param x integer
---@param y integer
---@return boolean
local function in_rectangle(rect, x, y)
	return x >= rect.x and y >= rect.y and x < rect.x + rect.width and y < rect.y + rect.height
end

--- Finds wether two rectangles intersect and, if they do, return the intersection rectangle
---@param a Rectangle
---@param b Rectangle
---@return Rectangle|nil intersection
local function get_intersection(a, b)
	if
		a.x + a.width - 1 <= b.x
		or b.x + b.width - 1 <= a.x
		or a.y + a.height - 1 <= b.y
		or b.y + b.height - 1 <= a.y
	then
		return
	end

	local inter = {}

	inter.x = a.x > b.x and a.x or b.x
	inter.y = a.y > b.y and a.y or b.y
	inter.width = (a.width + a.x < b.width + b.x and a.width + a.x or b.width + b.x) - (a.x < b.x and b.x or a.x)
	inter.height = (a.height + a.y < b.height + b.y and a.height + a.y or b.height + b.y) - (a.y < b.y and b.y or a.y)

	return inter
end

--- Returns the shape that is the result from subtracting b to a, if there is none return an empty table
---@param a Rectangle
---@param b Rectangle
---@return Rectangle[] shape Table with zero to four rectangles that represent the resulting shape
local function subtract(a, b)
	local inter = get_intersection(a, b)
	if inter == nil then
		return {}
	end

	---@type Rectangle[]
	local rectangles = {}

	if inter.x > a.x then -- left side
		rectangles[#rectangles + 1] = { x = a.x, y = a.y, width = inter.x - a.x, height = a.height }
	end
	if inter.y > a.y then -- top side
		rectangles[#rectangles + 1] = { x = inter.x, y = a.y, width = inter.width, height = inter.y - a.y }
	end
	if inter.x + inter.width < a.x + a.width then -- right side
		rectangles[#rectangles + 1] = {
			x = inter.x + inter.width,
			y = a.y,
			width = a.x + a.width - inter.x - inter.width,
			height = a.height,
		}
	end
	if inter.y + inter.height < a.y + a.height then -- bottom side
		rectangles[#rectangles + 1] = {
			x = inter.x,
			y = inter.y + inter.height,
			width = inter.width,
			height = a.height - inter.height,
		}
	end

	return #rectangles > 0 and rectangles or {}
end

---@param regions Rectangle[]
---@param rect Rectangle
local function subtract_rectangle_from_regions(regions, rect)
	error("subtract_rectangle_from_regions unimplemented")
end

--- Copy regions from one buffer to another, the destination must be large enough
---@param buff_dest integer
---@param x_dest integer
---@param y_dest integer
---@param x_source integer
---@param y_source integer
---@param regions Rectangle[]
local function bitblt_regions(buff_dest, x_dest, y_dest, x_source, y_source, regions)
	error("bitblt_regions unimplemented")
end

---@param message string Error message to print
---@param func function|nil Function that caused the error
local function stack_trace(message, func)
	local call_id = 2
	local info

	local gpu = require("component").gpu

	gpu.setBackground(16711680)
	gpu.setForeground(16777215)

	if func then
		info = debug.getinfo(func)
		print(tostring(info.short_src) .. ":" .. tostring(info.linedefined))
	end

	info = debug.getinfo(call_id)
	while info do
		print(tostring(info.short_src) .. ":" .. (info.name and info.name or tostring(info.linedefined)))
		call_id = call_id + 1
		info = debug.getinfo(call_id)
	end
	error(message)
end

return {
	get_intersection = get_intersection,
	subtract = subtract,
	in_rectangle = in_rectangle,
	bitblt_regions = bitblt_regions,
	stack_trace = stack_trace,
}
