local vtk_button = require("VTK/button")
local vtk_spacer = require("VTK/spacer")

local frame = require("VTK").init()

function Main()
	local b1 = vtk_button.new_button()
	b1.text = "Swap"
	b1:add_click_listener(function()
		if frame.layout_orientation == "horizontal" then
			frame.layout_orientation = "vertical"
		else
			frame.layout_orientation = "horizontal"
		end

		_ENV.Redraw()
	end)

	local b2 = vtk_button.new_button()
	b2.text = "Add button"
	b2:add_click_listener(function()
		local b = vtk_button.new_button()
		b.text = "Added"
		b:add_click_listener(function()
			b.background_color = b.background_color + 0x141414
			if b.background_color > 0xffffff then
				b.background_color = b.background_color - 0xb77e4e
			end
		end)
		frame:add_component(vtk_spacer.new_spacer())
		frame:add_component(b)
		_ENV.Redraw()
	end)
	frame:add_component(b1)
	frame:add_component(vtk_spacer.new_spacer())
	frame:add_component(b2)
	frame.scrollable = true
end
