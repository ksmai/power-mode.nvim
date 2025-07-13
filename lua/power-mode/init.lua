local kitty = require("power-mode.kitty")

local M = {}

local Particle = {}

function Particle:new()
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.x = 0
	o.y = 0
	o.vx = 0
	o.vy = 0
	return o
end

function Particle:update()
	self.x = self.x + self.vx
	self.y = self.y + self.vy
end

local ParticleSystem = {}

function ParticleSystem:new()
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.lightness = 0
	o.decay = 0
	o.num_particles = 0
	o.particles = {}

	return o
end

function ParticleSystem:use(lightness, decay, num_particles)
	self.lightness = lightness
	self.decay = decay
	self.num_particles = num_particles

	local to_create = num_particles - #self.particles
	if to_create > 0 then
		for _ = 1, to_create do
			table.insert(self.particles, Particle:new())
		end
	end
end

function ParticleSystem:update()
	self.lightness = self.lightness * self.decay

	for i = 1, self.num_particles do
		self.particles[i]:update()
	end
end

function ParticleSystem:get_intensity(x, y)
	local result = 0

	for i = 1, self.num_particles do
		local p = self.particles[i]
		local dx = x - p.x
		local dy = y - p.y
		local d = math.max(0.0001, math.sqrt(dx * dx + dy * dy))
		result = result + self.lightness / math.pow(d, 1.3)
	end

	return result
end

local window_size

local function compute_window_size()
	if window_size ~= nil then
		return
	end

	local ffi = require("ffi")
	ffi.cdef([[
        int ioctl(int __fd, unsigned long int __request, ...);
        typedef struct winsize {
        unsigned short ws_row;
        unsigned short ws_col;
        unsigned short ws_xpixel;
        unsigned short ws_ypixel;
        };
    ]])
	local sz = ffi.new("struct winsize")
	ffi.C.ioctl(0, 21523, sz)

	window_size = {
		screen_w = sz.ws_xpixel,
		screen_h = sz.ws_ypixel,
		rows = sz.ws_row,
		cols = sz.ws_col,
		cell_w = sz.ws_xpixel / sz.ws_col,
		cell_h = sz.ws_ypixel / sz.ws_row,
	}
end

local Canvas = {}

function Canvas:new()
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.w = 0
	o.h = 0
	o.bytes = {}
	o.blank = nil

	return o
end

function Canvas:use(w, h)
	if self.w == w and self.h == h then
		return
	end

	self.blank = nil
	self.w = w
	self.h = h

	self.bytes = {}
	for _ = 1, w * h * 4 do
		table.insert(self.bytes, "\x00")
	end
end

function Canvas:get_blank()
	if self.blank == nil then
		self.blank = {}

		for _ = 1, self.w * self.h * 4 do
			table.insert(self.blank, "\x00")
		end
	end

	return self.blank
end

local HomingAnimation = {}

function HomingAnimation:new(canvas, particles)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	compute_window_size()
	local w = window_size.cell_w
	local h = window_size.cell_h

	local gap = 33
	local color = { r = 0x31, g = 0xf5, b = 0xeb }

	canvas:use(5 * w, 3 * h)
	o.id = kitty.create_image(canvas.w, canvas.h, canvas:get_blank())
	particles:use(5, 0.9, 12)

	for i = 1, particles.num_particles do
		local p = particles.particles[i]
		local x = 1.0 * w + 2.0 * w * math.random()
		local y = 1.1 * h + 0.8 * h * math.random()
		p.x = x
		p.y = y

		local center_x = 1.0 * w + 1.0 * w * math.random()
		local center_y = 1.0 * h + 1.0 * h * math.random()
		local dx = center_x - x
		local dy = center_y - y
		local norm = math.max(0.0001, math.sqrt(dx * dx + dy * dy))
		p.vx = dx / norm * 1.0 * (2 * math.random() - 0.5)
		p.vy = dy / norm * 0.8 * (2 * math.random() - 0.5)
	end

	for _ = 1, 100 do
		local max_a = 0

		for y = 0, (canvas.h - 1) do
			for x = 0, (canvas.w - 1) do
				local intensity = particles:get_intensity(x + 0.5, y + 0.5)
				local r = math.min(255, math.floor(color.r * intensity))
				local g = math.min(255, math.floor(color.g * intensity))
				local b = math.min(255, math.floor(color.b * intensity))
				local t = math.min(1, math.max(0, intensity - 0.6))
				local e = t * t * (3 - 2 * t)
				local a = math.min(255, math.floor(255 * e))
				local i = (y * canvas.w + x) * 4
				canvas.bytes[i + 1] = string.char(r)
				canvas.bytes[i + 2] = string.char(g)
				canvas.bytes[i + 3] = string.char(b)
				canvas.bytes[i + 4] = string.char(a)

				max_a = math.max(max_a, a)
			end
		end

		kitty.create_frame(o.id, canvas.w, canvas.h, gap, canvas.bytes)

		particles:update()

		if max_a < 0.1 then
			kitty.create_frame(o.id, canvas.w, canvas.h, gap, canvas:get_blank())
			break
		end
	end

	return o
end

function HomingAnimation:run()
	kitty.run_animation(self.id, -1, -1)
end

local ExplodeAnimation = {}

function ExplodeAnimation:new(canvas, particles)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	compute_window_size()
	local w = window_size.cell_w
	local h = window_size.cell_h

	local gap = 33
	local color = { r = 0xff, g = 0x74, b = 0x0a }

	canvas:use(3 * w, 3 * h)
	o.id = kitty.create_image(canvas.w, canvas.h, canvas:get_blank())
	particles:use(2, 0.9, 20)

	for i = 1, particles.num_particles do
		local p = particles.particles[i]
		local x = 1.0 * w + 1.0 * w * math.random()
		local y = 1.0 * h + 1.0 * h * math.random()
		p.x = x
		p.y = y

		local dx = 1.0 * (3 * math.random() - 2)
		local dy = 0.5 * (3 * math.random() - 2)
		local norm = math.max(0.0001, math.sqrt(dx * dx + dy * dy))
		p.vx = dx / norm * 0.8
		p.vy = dy / norm * 0.5
	end

	for _ = 1, 100 do
		local max_a = 0

		for y = 0, (canvas.h - 1) do
			for x = 0, (canvas.w - 1) do
				local intensity = particles:get_intensity(x + 0.5, y + 0.5)
				local r = math.min(255, math.floor(color.r * intensity))
				local g = math.min(255, math.floor(color.g * intensity))
				local b = math.min(255, math.floor(color.b * intensity))
				local t = math.min(1, math.max(0, intensity - 0.6))
				local e = t * t * (3 - 2 * t)
				local a = math.min(255, math.floor(255 * e))
				local i = (y * canvas.w + x) * 4
				canvas.bytes[i + 1] = string.char(r)
				canvas.bytes[i + 2] = string.char(g)
				canvas.bytes[i + 3] = string.char(b)
				canvas.bytes[i + 4] = string.char(a)

				max_a = math.max(max_a, a)
			end
		end

		kitty.create_frame(o.id, canvas.w, canvas.h, gap, canvas.bytes)

		particles:update()

		if max_a < 0.1 then
			kitty.create_frame(o.id, canvas.w, canvas.h, gap, canvas:get_blank())
			break
		end
	end

	return o
end

function ExplodeAnimation:run()
	kitty.run_animation(self.id, -1, -1)
end

local AnimationSet = {}

function AnimationSet:new(particles, Class, num)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	local canvas = Canvas:new()

	o.next = 1
	o.animations = {}
	for _ = 1, num do
		local animation = Class:new(canvas, particles)
		table.insert(o.animations, animation)
	end

	return o
end

function AnimationSet:run()
	self.animations[self.next]:run()

	self.next = self.next + 1
	if self.next > #self.animations then
		self.next = 1
	end
end

local initialized = false
local run = true
local on_insert
local on_remove
local particles

local function initialize()
	if initialized then
		return
	end

	initialized = true

	particles = ParticleSystem:new()
	on_insert = AnimationSet:new(particles, HomingAnimation, 16)
	on_remove = AnimationSet:new(particles, ExplodeAnimation, 16)
end

function M.setup(opts)
	opts = opts or {}

	local r
	local c

	vim.api.nvim_create_autocmd("InsertEnter", {
		callback = function()
			initialize()
			r, c = unpack(vim.api.nvim_win_get_cursor(0))
		end,
	})

	vim.api.nvim_create_autocmd("TextChangedI", {
		callback = function()
			local new_r, new_c = unpack(vim.api.nvim_win_get_cursor(0))

			if run then
				-- run = false

				if new_r == r and new_c > c then
					on_insert:run()
				elseif new_r < r or new_r == r and new_c < c then
					on_remove:run()
				end
			end

			r = new_r
			c = new_c
		end,
	})
end

return M
