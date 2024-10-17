local fs = require("filesystem")

local PATH = {
	"/home",
}

---@return string[]
local function get_programs()
	local programs = {}

	---@param a string[]
	---@param b string[]
	---@return string[]
	local function add_all(a, b)
		for e in b do
			a[#a + 1] = e
		end
		return a
	end

	---@param path string
	---@return string[]
	local function get_files_of_directory(path)
		local files = {}
		local iter = fs.list(path)
		local file = iter()

		while file ~= nil do
			if fs.isDirectory(file) then
				add_all(files, get_files_of_directory(file))
			else
				files[#files + 1] = file
			end
		end

		return files
	end

	for i = 1, #PATH do
		local path = PATH[i]
		if fs.exists(path) then
			if fs.isDirectory(path) then
				add_all(programs, get_files_of_directory(path))
			else
				programs[#programs + 1] = path
			end
		end
	end

	return programs
end

---
---@param handler WindowHandler
local function renderer(handler)
	handler:fill(1, 1, 1000, 1000, " ")
	handler:set(1, 1, "Test")
end

local selected_last_touch
local function touch_handler() end

return function()
	local ventanos_api = require("ventanos")

	---@type WindowHandler
	local w = ventanos_api.new("Menú de programas", renderer, touch_handler, touch_handler)

	w:setTitle("Test")
end
