return function()
	local events = require("ventanos/events")
	local wm = require("ventanos/window_manager")
	local term = require("term")

	term.setCursor(1, 1)

	wm.start()
	wm.draw_desktop()
	wm.draw_memory()

	events.start()

	require("event").pull(_, "interrupted")

	print("interrupted!")

	events.stop()
end
