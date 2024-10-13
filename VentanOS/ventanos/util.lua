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
	if a.x + a.width <= b.x or b.x + b.width <= a.x or a.y + a.height <= b.y or b.y + b.height <= a.y then
		return
	end

	---@type Rectangle
	local inter

	inter.x = a.x > b.x and a.x or b.x
	inter.y = a.y > b.y and a.y or b.y
	inter.width = (a.width + a.x < b.width + b.x and a.width or b.width) - inter.x + 1
	inter.height = (a.height + a.y < b.height + b.y and a.height or b.height) - inter.y + 1

	return inter
end

--- Returns the shape that is the result from subtracting b to a, if there is none return nil
---@param a Rectangle
---@param b Rectangle
---@return integer|nil n_rectangles
---@return table shape Table with one to four rectangles that represent the resulting shape
local function subtract(a, b)
	local inter = get_intersection(a, b)
	if inter == nil or a.width <= 2 or a.height <= 2 then
		return nil, {}
	end

	---@type Rectangle[]
	local rectangles
	local index_rectangles = 1

	if inter.x > a.x then -- left side
		rectangles[index_rectangles] = { x = a.x, y = a.y, width = inter.x - a.x, height = a.height }
		index_rectangles = index_rectangles + 1
	end
	if inter.y > a.y then -- top side
		rectangles[index_rectangles] = { x = inter.x, y = a.y, width = inter.width, height = inter.y - a.y }
		index_rectangles = index_rectangles + 1
	end
	if inter.x + inter.width < a.x + a.width then
		rectangles[index_rectangles] = {
			x = inter.x + inter.width,
			y = a.y,
			width = a.x + a.width - inter.x - inter.width,
			height = a.height,
		}
		index_rectangles = index_rectangles + 1
	end
	if inter.y + inter.height < a.y + a.height then
		rectangles[index_rectangles] =
			{ x = inter.x, y = inter.y + inter.height, width = inter.width, height = inter.y - a.y }
		index_rectangles = index_rectangles + 1
	end

	if index_rectangles > 1 then
		return index_rectangles - 1, rectangles
	end

	return nil, {}
end

return {
	get_intersection = get_intersection,
	subtract = subtract,
	in_rectangle = in_rectangle,
}
