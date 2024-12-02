function Redraw()
	fill(1, 1)
	setCursor(1, 1)
	print("Viewport", getViewport())
end

function Touch(x, y, button)
	print("Pressed button " .. tostring(button) .. " at x:" .. tostring(x) .. ", y:" .. tostring(y))
end

function Drop(x, y, button)
	print("Released button " .. tostring(button) .. " at x:" .. tostring(x) .. ", y:" .. tostring(y))
end

function Drag(x, y, button)
	print("Dragging button " .. tostring(button) .. " at x:" .. tostring(x) .. ", y:" .. tostring(y))
end

function Scroll(_, _, direcction)
	if direcction == -1 then
		print("Scrolling downwards")
	else
		print("Scrolling upwards")
	end
end
