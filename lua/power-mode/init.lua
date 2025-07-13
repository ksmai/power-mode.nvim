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

	o.lightness = 1
	o.decay = 0.9
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

	for _, p in ipairs(self.particles) do
		p:update()
	end
end

function ParticleSystem:get_intensity(x, y)
	local result = 0

	for _, p in ipairs(self.particles) do
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
	if self.w ~= w or self.h ~= h then
		self.blank = nil
	end

	self.w = w
	self.h = h

	local to_create = w * h * 4 - #self.bytes
	if to_create > 0 then
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

local Animation = {}

function Animation:new(canvas, particles)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.canvas = canvas
	o.particles = particles
	o.id = nil
	o.gap = 33
	o.color = { r = 0x31, g = 0xf5, b = 0xeb }

	return o
end

function Animation:generate_frames()
	compute_window_size()
	local w = window_size.cell_w
	local h = window_size.cell_h

	self.canvas:use(4 * w, 3 * h)
	self.id = kitty.create_image(self.canvas.w, self.canvas.h, self.canvas:get_blank())
	self.particles:use(5, 0.9, 16)

	for i = 1, self.particles.num_particles do
		local x = 1.0 * w + 2.0 * w * math.random()
		local y = 1.1 * h + 0.8 * h * math.random()
		self.particles.particles[i].x = x
		self.particles.particles[i].y = y

		local center_x = 1.0 * w + 1.0 * w * math.random()
		local center_y = 1.0 * h + 1.0 * h * math.random()
		local dx = center_x - x
		local dy = center_y - y
		local norm = math.max(0.0001, math.sqrt(dx * dx + dy * dy))
		self.particles.particles[i].vx = dx / norm * 1.2 * (3 * math.random() - 1)
		self.particles.particles[i].vy = dy / norm * 1.0 * (3 * math.random() - 1)
	end

	for _ = 1, 100 do
		local max_a = 0

		for y = 0, (self.canvas.h - 1) do
			for x = 0, (self.canvas.w - 1) do
				local intensity = self.particles:get_intensity(x + 0.5, y + 0.5)
				local r = math.min(255, math.floor(self.color.r * intensity))
				local g = math.min(255, math.floor(self.color.g * intensity))
				local b = math.min(255, math.floor(self.color.b * intensity))
				local t = math.min(1, math.max(0, intensity - 0.6))
				local e = t * t * (3 - 2 * t)
				local a = math.min(255, math.floor(255 * e))
				local i = (y * self.canvas.w + x) * 4
				self.canvas.bytes[i + 1] = string.char(r)
				self.canvas.bytes[i + 2] = string.char(g)
				self.canvas.bytes[i + 3] = string.char(b)
				self.canvas.bytes[i + 4] = string.char(a)

				max_a = math.max(max_a, a)
			end
		end

		kitty.create_frame(self.id, self.canvas.w, self.canvas.h, self.gap, self.canvas.bytes)

		self.particles:update()

		if max_a < 0.1 then
			kitty.create_frame(self.id, self.canvas.w, self.canvas.h, self.gap, self.canvas:get_blank())
			break
		end
	end
end

function Animation:run()
	if self.id == nil then
		error("Animation frames have not been generated")
	end

	kitty.run_animation(self.id, -1, -1)
end

local initialized = false
local run = true
local animation
local canvas
local particles

local function initialize()
	if initialized then
		return
	end

	initialized = true

	canvas = Canvas:new()
	particles = ParticleSystem:new()
	animation = Animation:new(canvas, particles)
	animation:generate_frames()
end

function M.setup(opts)
	opts = opts or {}

	vim.api.nvim_create_autocmd("InsertEnter", {
		callback = function()
			initialize()
		end,
	})

	vim.api.nvim_create_autocmd("InsertCharPre", {
		callback = function()
			if run then
				-- run = false
				animation:run()
			end
		end,
	})
end

return M
