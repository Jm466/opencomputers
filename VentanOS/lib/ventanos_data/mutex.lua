local thread = require("thread")
local util = require("ventanos_data/util")

---@class Mutex
---@field package locked_by thread
---@field package occupied boolean
---@field package threads_waiting thread[]
---@field package n_threads integer
---@field release function
---@field acquire function

---@class RegionMutex
---@field package locked_by {thread: thread, x: integer, y: integer, width: integer, height: integer}[]
---@field package occupied boolean
---@field package threads_waiting {thread: thread, x: integer, y: integer, width: integer, height: integer}[]
---@field release fun(x: integer, y: integer, width: integer, height: integer)
---@field acquire function

--- Locks a mutex
---@param lock Mutex
local function acquire(lock)
	while lock.occupied do
	end

	lock.occupied = true

	if lock.locked_by then
		if lock.locked_by == thread.current() then
			lock.occupied = false
			lock:release()
			util.stack_trace("A thread tried to lock a mutex already locked by itself!")
		end

		local t = thread.current()

		local i = 1
		while lock.threads_waiting[i] ~= nil do
			i = i + 1
		end

		lock.threads_waiting[i] = t
		lock.n_threads = lock.n_threads + 1

		lock.occupied = false
		t:suspend()

		lock.threads_waiting[i] = nil
		lock.n_threads = lock.n_threads - 1
	else
		lock.locked_by = thread.current()
	end

	--print("locked " .. tostring(lock))

	lock.occupied = false
end

--- Unlocks a mutex
---@param lock Mutex
local function release(lock)
	while lock.occupied do
	end

	lock.occupied = true

	if lock.n_threads > 0 then
		for i = 1, lock.n_threads do
			if lock.threads_waiting[i] ~= nil then
				lock.threads_waiting[i]:resume()
				return
			end
		end
	else
		lock.locked_by = nil
		--print("unlock " .. tostring(lock))
	end

	lock.occupied = false
end

--- Creates a new mutex
---@return Mutex mutex
local function new_mutex()
	return setmetatable({
		locked_by = nil,
		occupied = false,
		threads_waiting = {},
		n_threads = 0,
	}, {
		__index = {
			acquire = acquire,
			release = release,
		},
	})
end

return { new_mutex = new_mutex }
