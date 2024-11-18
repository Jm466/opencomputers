return function()
	local events = require("ventanos_data/events")
	local wm = require("ventanos_data/window_manager")
	local term = require("term")

	term.setCursor(1, 1)

	wm.start()
	wm.draw_desktop()
	wm.draw_memory()

	events.start()

	while true do
		os.sleep(math.huge)
	end
end
