local Button = require("VTK/Button")
local Spacer = require("VTK/Spacer")

local frame = require("VTK").init()

-- `init` defines all global functions from the VentanOS signals interface(see https://github.com/Jm466/opencomputers/tree/master/VentanOS#signals-interface)
-- after the program is loaded all these global functions are cleared from the environment
-- we can save `Redraw` so we can call a redraw of the whole window
local global_redraw = _ENV.Redraw

function Main()
	local b1 = Button.new()
	b1.text = "Swap"
	b1:add_click_listener(function()
		if frame.layout_orientation == "horizontal" then
			frame.layout_orientation = "vertical"
		else
			frame.layout_orientation = "horizontal"
		end

		global_redraw()
	end)

	local b2 = Button.new()
	b2.text = "Add button"
	b2:add_click_listener(function()
		local b = Button.new()
		b.text = "Added"
		b:add_click_listener(function()
			b.background_color = b.background_color + 0x141414
			if b.background_color > 0xffffff then
				b.background_color = b.background_color - 0xb77e4e
			end
		end)
		frame:add_component(Spacer.new())
		frame:add_component(b)
		global_redraw()
	end)
	frame:add_component(b1)
	frame:add_component(Spacer.new())
	frame:add_component(b2)
	frame.scrollable = true
end
