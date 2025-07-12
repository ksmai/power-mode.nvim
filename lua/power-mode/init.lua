local M = {}

local uv = vim.uv
-- Allow for loop to be used on older versions
if not uv then
	uv = vim.loop
end

local stdout = uv.new_tty(1, false)
if not stdout then
	error("failed to open stdout")
end

local init = true
local run = true

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

function ParticleSystem:new(num_particles, da)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.a = 1
	o.da = da
	o.particles = {}
	for _ = 1, num_particles do
		table.insert(o.particles, Particle:new())
	end

	return o
end

function ParticleSystem:reset(x_min, x_max, y_min, y_max, vx_min, vx_max, vy_min, vy_max)
	self.a = 1

	for _, p in ipairs(self.particles) do
		p.x = x_min + (x_max - x_min) * math.random()
		p.y = y_min + (y_max - y_min) * math.random()
		p.vx = vx_min + (vx_max - vx_min) * math.random()
		p.vy = vy_min + (vy_max - vy_min) * math.random()
	end
end

function ParticleSystem:done()
	return self.a < 0.1
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
		local d = math.sqrt(dx * dx + dy * dy)

		if d == 0 then
			result = result + 1
		else
			result = result + 1 / math.pow(d, 1.5)
		end
	end

	return math.min(result, 1) * self.a
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

	o.w = sz.ws_xpixel / sz.ws_col
	o.h = sz.ws_ypixel / sz.ws_row
	o.size = o.w * o.h
	o.data = {}

	for i = 1, o.size * 3 do
		o.data[i] = 0
	end

	return o
end

function Canvas:set_color(x, y, r, g, b)
	local i = (y * self.w + x) * 3
	self.data[i + 1] = r
	self.data[i + 2] = g
	self.data[i + 3] = b
end

function M.setup(opts)
	opts = opts or {}

	vim.api.nvim_create_autocmd("InsertCharPre", {
		callback = function()
			local image = 666
			if init then
				init = false

				local color = { r = 0x31, g = 0xf5, b = 0xeb }
				local canvas = Canvas:new()
				local particles = ParticleSystem:new(16, 0.95)
				vim.print(ParticleSystem.reset)
				particles:reset(0, canvas.w, 0, canvas.h, -1, 1, -1, 1)

				local blank = vim.base64.encode(string.rep("\x00\x00\x00\x00", canvas.size))
				stdout:write(
					"\x1b_Gf=32,s="
						.. canvas.w
						.. ",v="
						.. canvas.h
						.. ",a=t,i="
						.. image
						.. ",q=1;"
						.. blank
						.. "\x1b\\"
				)

				while not particles:done() do
					particles:update()

					for y = 0, (canvas.h - 1) do
						for x = 0, (canvas.w - 1) do
							local intensity = particles:get_intensity(x, y)
							canvas:set_color(x, y, color.r * intensity, color.g * intensity, color.b * intensity)
						end
					end

					local data = {}
					local a = string.char(math.floor(256 * particles.a))

					for i, v in ipairs(canvas.data) do
						local c = string.char(v)
						table.insert(data, c)

						if i % 3 == 0 then
							table.insert(data, a)
						end
					end

					stdout:write(
						"\x1b_Gf=32,s="
							.. canvas.w
							.. ",v="
							.. canvas.h
							.. ",a=f,i="
							.. image
							.. ",z=16,q=1;"
							.. vim.base64.encode(table.concat(data))
							.. "\x1b\\"
					)
				end

				-- stdout:write(
				-- 	"\x1b_Gf=32,s="
				-- 		.. cell_size.w
				-- 		.. ",v="
				-- 		.. cell_size.h
				-- 		.. ",a=f,i=666,z=300,q=1;"
				-- 		.. blue
				-- 		.. "\x1b\\"
				-- )
				-- stdout:write(
				-- 	"\x1b_Gf=32,s="
				-- 		.. cell_size.w
				-- 		.. ",v="
				-- 		.. cell_size.h
				-- 		.. ",a=f,i=666,z=300,q=1;"
				-- 		.. blank
				-- 		.. "\x1b\\"
				-- )
				-- stdout:write("\x1b_Gf=32,s=8,v=8,a=f,i=666,q=1;" .. red .. "\x1b\\")
				-- stdout:write("\x1b_Gf=32,s=8,v=8,a=f,i=666,q=1;" .. white .. "\x1b\\")
			end

			if run then
				-- run = false
				stdout:write("\x1b_Ga=a,i=" .. image .. ",p=" .. image .. ",c=1\x1b\\")
				-- -- stdout:write("\x1b_Ga=d,d=i,i=666\x1b\\")
				stdout:write("\x1b_Ga=a,i=" .. image .. ",p=" .. image .. ",s=3,v=2,r=1,z=0\x1b\\")
				stdout:write("\x1b_Ga=p,i=" .. image .. ",p=" .. image .. ",C=1,q=1\x1b\\")
				-- p = p + 1
			end
		end,
	})
end

return M
