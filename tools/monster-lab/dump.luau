-- Builds monsters from a Monsters-style module with real Roblox datatypes and
-- dumps every part (size, CFrame, colour, material, shape) to JSON for rendering.
--   lune run dump.luau <module.luau> <outdir> <Kind> [<Kind> ...]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local args = process.args
local modulePath, outDir = args[1], args[2]

local fakeAudio = {
	create = function()
		return nil
	end,
}
local env = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	script = { Parent = { Audio = fakeAudio } },
	require = function(m)
		return m
	end,
	math = math,
	table = table,
	string = string,
	typeof = typeof,
	print = print,
	error = error,
	ipairs = ipairs,
	pairs = pairs,
	tostring = tostring,
	assert = assert,
	setmetatable = setmetatable,
}
local Monsters = luau.load(fs.readFile(modulePath), { debugName = modulePath, environment = env })()

local function round(x: number): number
	return math.floor(x * 10000 + 0.5) / 10000
end

for i = 3, #args do
	local spec = args[i]
	local kind, pose, decoy = string.match(spec, "^([^@!]+)@?(%d*)(!?)$")
	local rig = Monsters.build(kind, { preview = true, decoy = decoy == "!" })
	if pose ~= "" and Monsters.applyStatuePose then
		Monsters.applyStatuePose(rig, tonumber(pose), nil)
		Monsters.solve(rig)
	end
	local parts = {}
	local lights = {}
	local minY = math.huge
	for _, d in rig.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local c = { d.CFrame:GetComponents() }
			for k, v in c do
				c[k] = round(v)
			end
			local mesh = d:FindFirstChildWhichIsA("SpecialMesh")
			local shape = if d:IsA("Part") then d.Shape.Name else "Block"
			if d:IsA("WedgePart") then
				shape = "Wedge"
			elseif d:IsA("CornerWedgePart") then
				shape = "CornerWedge"
			end
			if mesh then
				shape = "Mesh" .. mesh.MeshType.Name
			end
			table.insert(parts, {
				name = d.Name,
				size = { round(d.Size.X), round(d.Size.Y), round(d.Size.Z) },
				cf = c,
				color = { round(d.Color.R), round(d.Color.G), round(d.Color.B) },
				material = d.Material.Name,
				shape = shape,
				transparency = d.Transparency,
				reflectance = d.Reflectance,
				shadow = d.CastShadow,
			})
			-- rough lowest point (bounding sphere of the box along Y)
			local half = d.Size / 2
			local cf = d.CFrame
			local lowest = math.huge
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = cf:PointToWorldSpace(roblox.Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						lowest = math.min(lowest, p.Y)
					end
				end
			end
			if mesh or shape == "Ball" then
				lowest = cf.Position.Y - math.max(half.X, half.Y, half.Z) * 0.8
			end
			minY = math.min(minY, lowest)
		elseif d:IsA("PointLight") then
			local p = d.Parent :: any
			table.insert(lights, {
				pos = { round(p.CFrame.X), round(p.CFrame.Y), round(p.CFrame.Z) },
				color = { d.Color.R, d.Color.G, d.Color.B },
				range = d.Range,
				brightness = d.Brightness,
			})
		end
	end
	local name = kind .. (if pose ~= "" then "@" .. pose else "") .. decoy
	fs.writeFile(outDir .. "/" .. name .. ".json", serde.encode("json", { kind = kind, parts = parts, lights = lights, rootHeight = rig.rootHeight }))
	print(string.format("%-14s %3d parts  lowest y %.2f", name, #parts, minY))
end
