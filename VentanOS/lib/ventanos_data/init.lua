return function()
	local events = require("ventanos_data/events")
	local wm = require("ventanos_data/window_manager")
	local term = require("term")

	term.setCursorBlink(false)
	term.setCursor(1, 1)
	os.setenv("PS1", "")

	wm.draw_desktop()

	events.start()
end
