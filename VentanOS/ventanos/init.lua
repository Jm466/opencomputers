local events = require("/usr/ventanos/events")
local taskbar = require("/usr/ventanos/taskbar")

taskbar.draw_taskbar()

events.start()
