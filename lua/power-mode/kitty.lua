local uv = vim.uv
-- Allow for loop to be used on older versions
if not uv then
	uv = vim.loop
end

local stdout = uv.new_tty(1, false)
if not stdout then
	error("Failed to open stdout")
end

local M = {}

local q = 1
local next_id = math.random(65536, 16777216)
local BEGIN = "\x1b_G"
local END = "\x1b\\"

-- https://github.com/edluffy/hologram.nvim/blob/main/lua/hologram/terminal.lua#L77
local function get_chunked(data)
	local str = vim.base64.encode(table.concat(data))
	local chunks = {}
	for i = 1, #str, 4096 do
		local chunk = str:sub(i, i + 4096 - 1):gsub("%s", "")
		if #chunk > 0 then
			table.insert(chunks, chunk)
		end
	end
	return chunks
end

local function write_data(data, control_payload)
	local chunks = get_chunked(data)
	local m = #chunks > 1 and 1 or 0
	local is_frame = string.match(control_payload, "a=f")
	control_payload = control_payload .. ",m=" .. m

	for i, chunk in ipairs(chunks) do
		local cmd = string.format("%s%s;%s%s", BEGIN, control_payload, chunk, END)
		stdout:write(cmd)

		if i == #chunks - 1 then
			control_payload = "m=0"
		else
			control_payload = "m=1"
		end

		if is_frame then
			control_payload = control_payload .. ",a=f"
		end
	end
end

local placeholder_id = nil

local function create_placeholder()
	if placeholder_id == nil then
		placeholder_id = M.create_image(1, 1, { 0, 0, 0, 0 })
	end
end

function M.create_image(w, h, data)
	if #data ~= w * h * 4 then
		error("Incorrect length for image data")
	end

	local id = next_id
	next_id = next_id + 1

	local control_payload = string.format("f=32,s=%d,v=%d,a=t,i=%d,q=%d", w, h, id, q)
	write_data(data, control_payload)

	return id
end

function M.create_frame(id, w, h, gap, data)
	if #data ~= w * h * 4 then
		error("Incorrect length for image data")
	end

	local control_payload = string.format("f=32,s=%d,v=%d,a=f,i=%d,z=%d,q=%d", w, h, id, gap, q)
	write_data(data, control_payload)
end

function M.run_animation(id, offset_x, offset_y)
	create_placeholder()

	local cmd = string.format(
		"%sa=a,i=%d,p=%d,c=1,q=%d%s%sa=a,i=%d,p=%d,s=3,v=2,r=1,z=0,q=%d%s%sa=p,i=%d,p=%d,C=1,q=%d%s%sa=p,i=%d,p=%d,P=%d,Q=%d,H=%d,V=%d,C=1,q=%d%s",
		BEGIN,
		id,
		id,
		q,
		END,
		BEGIN,
		id,
		id,
		q,
		END,
		BEGIN,
		placeholder_id,
		id,
		q,
		END,
		BEGIN,
		id,
		id,
		placeholder_id,
		id,
		offset_x,
		offset_y,
		q,
		END
	)

	stdout:write(cmd)
end

return M
