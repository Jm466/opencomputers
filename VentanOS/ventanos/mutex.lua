local thread = require("thread")

---@class Mutex
---@field private locked boolean
---@field private occupied boolean
---@field private threads_waiting thread[]
---@field private n_waiting integer
---@field release function
---@field acquire function

--- Locks a mutex
local function acquire(self)
	while self.occupied do
	end

	self.occupied = true

	if self.locked then
		local i = 1
		while self.threads_waiting[i] ~= nil do
			i = i + 1
		end
		self.threads_waiting[i] = thread.current()
		self.n_waiting = self.n_waiting + 1

		self.occupied = false
		thread.current():suspend()

		self.threads_waiting[i] = nil
	end
end

--- Unlocks a mutex
local function release(self)
	while self.occupied do
	end

	self.occupied = true
	if self.n_waiting > 0 then
		for i = 1, self.n_waiting do
			if self.threads_waiting[i] ~= nil then
				self.n_waiting = self.n_waiting - 1
				---@diagnostic disable-next-line: undefined-field
				self.threads_waiting[i]:resume()
				return
			end
		end
	else
		self.locked = false
	end
end

--- Creates a new mutex
---@return Mutex mutex
local function new()
	return setmetatable({
		locked = false,
		occupied = false,
		threads_waiting = {},
		n_waiting = 0,
	}, {
		__index = {
			acquire = acquire,
			release = release,
		},
	})
end

return { new = new }
