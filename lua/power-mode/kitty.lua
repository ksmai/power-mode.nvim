local M = {}

local uv = vim.uv
-- Allow for loop to be used on older versions
if not uv then
	uv = vim.loop
end

local stdout = uv.new_tty(1, false)
if not stdout then
	error("Failed to open stdout")
end

local q = 1
local i = math.random(65536, 16777216)

function M.create_image(w, h, data)
	local id = i
	i = i + 1

	if #data ~= w * h * 4 then
		error("Incorrect length for image data")
	end

	local cmd =
		string.format("\x1b_Gf=32,s=%d,v=%d,a=t,i=%d,q=%d;%s\x1b\\", w, h, id, q, vim.base64.encode(table.concat(data)))
	stdout:write(cmd)
	return id
end

function M.create_frame(id, w, h, gap, data)
	if #data ~= w * h * 4 then
		error("Incorrect length for image data")
	end

	local cmd = string.format(
		"\x1b_Gf=32,s=%d,v=%d,a=f,i=%d,z=%d,q=%d;%s\x1b\\",
		w,
		h,
		id,
		gap,
		q,
		vim.base64.encode(table.concat(data))
	)
	stdout:write(cmd)
end

function M.run_animation(id)
	local cmd = string.format(
		"\x1b_Ga=a,i=%d,p=%d,c=1,q=%d\x1b\\\x1b_Ga=a,i=%d,p=%d,s=3,v=2,r=1,z=0,q=%d\x1b\\\x1b_Ga=p,i=%d,p=%d,C=1,q=%d\x1b\\",
		id,
		id,
		q,
		id,
		id,
		q,
		id,
		id,
		q
	)

	stdout:write(cmd)
end

return M
