return {
	---@param handler WindowHandler
	redraw_handler = function(handler)
		handler:fill(1, 1)
		handler:setCursor(1, 1)
		handler:print("Redraw called")
		handler:print("Viewport", handler:getViewport())
	end,
	---@param handler WindowHandler
	touch_handler = function(handler, x, y, button)
		handler:print("Pressed button " .. tostring(button) .. " at x:" .. tostring(x) .. ", y:" .. tostring(y))
	end,
	drop_handler = function(handler, x, y, button)
		handler:print("Released button " .. tostring(button) .. " at x:" .. tostring(x) .. ", y:" .. tostring(y))
	end,
	drag_handler = function(handler, x, y, button)
		handler:print("Dragging button " .. tostring(button) .. " at x:" .. tostring(x) .. ", y:" .. tostring(y))
	end,
	scroll_handler = function(handler, _, _, direcction)
		if direcction == -1 then
			handler:print("Scrolling downwards")
			handler:print("Printed")
		else
			handler:print("Scrolling upwards")
		end
	end,
}
