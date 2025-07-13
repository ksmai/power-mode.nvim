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

function ParticleSystem:new(num_particles)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.a = 1
	o.da = 0.9
	o.particles = {}
	for _ = 1, num_particles do
		table.insert(o.particles, Particle:new())
	end

	return o
end

function ParticleSystem:reset(x_min, x_max, y_min, y_max, vx_min, vx_max, vy_min, vy_max, a, da)
	self.a = a
	self.da = da

	for _, p in ipairs(self.particles) do
		p.x = x_min + (x_max - x_min) * math.random()
		p.y = y_min + (y_max - y_min) * math.random()
		p.vx = vx_min + (vx_max - vx_min) * math.random()
		p.vy = vy_min + (vy_max - vy_min) * math.random()
	end
end

function ParticleSystem:update()
	self.a = self.a * self.da

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
		result = result + self.a / math.pow(d, 1.3)
	end

	return result
end

local Canvas = {}

function Canvas:new()
	local o = {}
	setmetatable(o, self)
	self.__index = self

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

	o.w = sz.ws_xpixel / sz.ws_col * 3
	o.h = sz.ws_ypixel / sz.ws_row * 3
	o.bytes = {}
	o.blank = {}

	for i = 1, o.w * o.h * 4 do
		o.bytes[i] = "\x00"
		o.blank[i] = "\x00"
	end

	return o
end

local Animation = {}

function Animation:new(canvas, particles)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.canvas = canvas
	o.particles = particles
	o.id = kitty.create_image(canvas.w, canvas.h, canvas.blank)
	o.gap = 33

	return o
end

function Animation:generate_frames()
	local color = { r = 0x31, g = 0xf5, b = 0xeb }
	self.particles:reset(0, self.canvas.w, 0, self.canvas.h, -1, 1, -1, 1, 4, 0.9)

	for _ = 1, 100 do
		local max_a = 0

		for y = 0, (self.canvas.h - 1) do
			for x = 0, (self.canvas.w - 1) do
				local intensity = self.particles:get_intensity(x, y)
				local r = math.min(255, math.floor(color.r * intensity))
				local g = math.min(255, math.floor(color.g * intensity))
				local b = math.min(255, math.floor(color.b * intensity))
				local t = math.min(1, math.max(0, intensity * 2))
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
			kitty.create_frame(self.id, self.canvas.w, self.canvas.h, self.gap, self.canvas.blank)
			break
		end
	end
end

function Animation:run()
	kitty.run_animation(self.id)
end

local init = true
local run = true
local animation

function M.setup(opts)
	opts = opts or {}

	vim.api.nvim_create_autocmd("InsertCharPre", {
		callback = function()
			if init then
				init = false

				local canvas = Canvas:new()
				local particles = ParticleSystem:new(16)
				animation = Animation:new(canvas, particles)
				animation:generate_frames()
			end

			if run then
				-- run = false
				animation:run()
			end
		end,
	})
end

return M
