return {
	redraw_handler = function() end,
	main = function(handler)
		require("ventanos_data/window_manager").draw_desktop()
		handler:kill()
	end,
}
