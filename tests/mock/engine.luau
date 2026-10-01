-- A tiny fake Roblox engine for running the game's scripts under Lune.
--
-- Real datatypes (Vector3, CFrame, Enum, UDim2...) come from @lune/roblox. Instances,
-- services, signals, remotes, the task scheduler and time are mocked here. Raycasts
-- are answered from the maze grid, so line-of-sight works like in the real game.
-- Server and client run in the same fake DataModel; remotes are routed between them.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local LuneCFrame = roblox.CFrame

-- Lune's CFrame.lookAt and CFrame.new(position, target) point the wrong way along Z.
-- Scripts get this CFrame table instead, which behaves like Roblox's.
local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-6 then
		return LuneCFrame.new(at)
	end
	look = look.Unit
	local right = look:Cross(up or Vector3.new(0, 1, 0))
	if right.Magnitude < 1e-4 then
		right = look:Cross(Vector3.new(0, 0, 1))
	end
	right = right.Unit
	return LuneCFrame.fromMatrix(at, right, right:Cross(look), -look)
end
local CFrame = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return LuneCFrame.new(...)
	end,
}, { __index = LuneCFrame })

local Engine = {}
Engine.CFrame = CFrame

Engine.time = 0
Engine.delayed = {} :: { { at: number, fn: (...any) -> (), args: { any } } }
Engine.sleeping = {} :: { { at: number, co: thread } }
Engine.layout = nil :: any
Engine.Maze = nil :: any
Engine.log = {} :: { string }
Engine.errors = {} :: { string }
Engine.localPlayer = nil :: any
Engine.renderSteps = {} :: { { name: string, priority: number, fn: (number) -> () } }
Engine.tagged = {} :: { [string]: { any } }
Engine.tagSignals = {} :: { [string]: any }

---------------------------------------------------------------------------
-- Threads

local function report(err: any, co: thread?)
	local msg = tostring(err)
	if co then
		msg ..= "\n" .. debug.traceback(co)
	end
	table.insert(Engine.errors, msg)
	print("SCRIPT ERROR: " .. msg)
end

function Engine.resume(co: thread, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(err, co)
	end
end

local function spawnThread(fn, ...)
	local co = coroutine.create(fn)
	Engine.resume(co, ...)
	return co
end

---------------------------------------------------------------------------
-- Signals

local Signal = {}
Signal.__index = Signal

function Signal.new(sticky: boolean?)
	return setmetatable({ handlers = {}, waiting = {}, fired = false, sticky = sticky == true, args = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self.handlers
	local entry = { fn = fn }
	table.insert(handlers, entry)
	if self.sticky and self.fired then
		spawnThread(fn, table.unpack(self.args))
	end
	return {
		Connected = true,
		Disconnect = function(conn)
			conn.Connected = false
			local i = table.find(handlers, entry)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal:Once(fn)
	if self.sticky and self.fired then
		spawnThread(fn, table.unpack(self.args))
		return { Connected = false, Disconnect = function() end }
	end
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	self.fired = true
	self.args = { ... }
	for _, entry in table.clone(self.handlers) do
		spawnThread(entry.fn, ...)
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, co in waiting do
		Engine.resume(co, ...)
	end
end

function Signal:Wait()
	if self.sticky and self.fired then
		return table.unpack(self.args)
	end
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end

Engine.Signal = Signal

local EVENTS = {
	Triggered = true,
	Touched = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Changed = true,
	Died = true,
	Completed = true,
	Heartbeat = true,
	RenderStepped = true,
	Stepped = true,
	PlayerRemoving = true,
	PlayerAdded = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	Activated = true,
	MoveToFinished = true,
	Event = true,
	InputBegan = true,
	InputEnded = true,
	Loaded = true,
	MouseEnter = true,
	MouseLeave = true,
	PromptShown = true,
	PromptHidden = true,
	PromptButtonHoldBegan = true,
	PromptButtonHoldEnded = true,
}

---------------------------------------------------------------------------
-- Instances

local SUPER: { [string]: string } = {
	Part = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	Workspace = "Model",
	PointLight = "Light",
	SpotLight = "Light",
	SurfaceLight = "Light",
	TextLabel = "GuiObject",
	TextButton = "GuiButton",
	GuiButton = "GuiObject",
	Frame = "GuiObject",
	SurfaceGui = "LayerCollector",
	ScreenGui = "LayerCollector",
	BlurEffect = "PostEffect",
	ColorCorrectionEffect = "PostEffect",
}

local DEFAULTS: { [string]: { [string]: any } } = {
	Part = { Anchored = false, Size = Vector3.new(4, 1, 2), CFrame = CFrame.new(), Transparency = 0, CanCollide = true, AssemblyLinearVelocity = Vector3.zero, Color = roblox.Color3.new(0.6, 0.6, 0.6) },
	Humanoid = { WalkSpeed = 16, Health = 100, MaxHealth = 100, HipHeight = 2, MoveDirection = Vector3.zero, CameraOffset = Vector3.zero },
	Sound = { Volume = 0.5, PlaybackSpeed = 1 },
	ProximityPrompt = { Enabled = true },
	PointLight = { Enabled = true, Brightness = 1, Range = 8, Color = roblox.Color3.new(1, 1, 1) },
	SpotLight = { Enabled = true, Brightness = 1, Range = 16, Color = roblox.Color3.new(1, 1, 1) },
	SurfaceLight = { Enabled = true, Brightness = 1, Range = 16, Color = roblox.Color3.new(1, 1, 1) },
	Camera = { CFrame = CFrame.new(0, 10, 0), FieldOfView = 70 },
	TextLabel = { TextTransparency = 0, BackgroundTransparency = 0, Text = "", LayoutOrder = 0 },
	TextButton = { TextTransparency = 0, BackgroundTransparency = 0, Text = "", LayoutOrder = 0 },
	Frame = { BackgroundTransparency = 0, Visible = true },
	ScreenGui = { Enabled = true },
	BlurEffect = { Size = 0 },
	ColorCorrectionEffect = { Contrast = 0, Brightness = 0 },
}

local Methods = {}
local ClassMethods: { [string]: { [string]: any } } = {}
local InstanceMT = {}

local function isInstance(v: any): boolean
	return type(v) == "table" and getmetatable(v) == InstanceMT
end
Engine.isInstance = isInstance

local function newInstance(className: string, name: string?)
	local self = {
		ClassName = className,
		Name = name or className,
		_children = {},
		_attributes = {},
		_attrSignals = {},
		_propSignals = {},
		_events = {},
		_props = {},
		_parent = nil,
	}
	local defaults = DEFAULTS[className]
	if defaults then
		for k, v in defaults do
			self._props[k] = v
		end
	end
	return setmetatable(self, InstanceMT)
end
Engine.newInstance = newInstance

local function isA(className: string, target: string): boolean
	local c: string? = className
	while c do
		if c == target then
			return true
		end
		c = SUPER[c]
	end
	return target == "Instance"
end

InstanceMT.__index = function(t, k)
	local cm = ClassMethods[rawget(t, "ClassName")]
	if cm and cm[k] then
		return cm[k]
	end
	local m = Methods[k]
	if m then
		return m
	end
	if k == "Parent" then
		return rawget(t, "_parent")
	end
	local props = rawget(t, "_props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	if k == "Position" and isA(rawget(t, "ClassName"), "BasePart") then
		local cf = props.CFrame
		return if cf then cf.Position else nil
	end
	if EVENTS[k] then
		local events = rawget(t, "_events")
		events[k] = events[k] or Signal.new(k == "Completed")
		return events[k]
	end
	for _, c in rawget(t, "_children") do
		if c.Name == k then
			return c
		end
	end
	return nil
end

InstanceMT.__newindex = function(t, k, v)
	if k == "Parent" then
		local old = rawget(t, "_parent")
		if old then
			local siblings = rawget(old, "_children")
			local i = table.find(siblings, t)
			if i then
				table.remove(siblings, i)
			end
		end
		rawset(t, "_parent", v)
		if v then
			table.insert(rawget(v, "_children"), t)
		end
		return
	end
	local props = rawget(t, "_props")
	if k == "Position" and isA(rawget(t, "ClassName"), "BasePart") then
		local cf = props.CFrame or CFrame.new()
		props.CFrame = CFrame.new(v) * cf.Rotation
		return
	end
	props[k] = v
	local s = rawget(t, "_propSignals")[k]
	if s then
		s:Fire()
	end
end

InstanceMT.__tostring = function(t)
	return t.ClassName .. "(" .. t.Name .. ")"
end

function Methods.IsA(self, className: string): boolean
	return isA(self.ClassName, className)
end

function Methods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end

function Methods.GetDescendants(self)
	local out = {}
	local function walk(inst)
		for _, c in rawget(inst, "_children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function Methods.FindFirstChild(self, name: string, recursive: boolean?)
	for _, c in rawget(self, "_children") do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in rawget(self, "_children") do
			local found = c:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function Methods.WaitForChild(self, name: string)
	local found = self:FindFirstChild(name)
	assert(found, "WaitForChild would hang forever: " .. tostring(self) .. "." .. name)
	return found
end

function Methods.FindFirstChildOfClass(self, className: string)
	for _, c in rawget(self, "_children") do
		if c.ClassName == className then
			return c
		end
	end
	return nil
end

function Methods.FindFirstChildWhichIsA(self, className: string, recursive: boolean?)
	for _, c in rawget(self, "_children") do
		if c:IsA(className) then
			return c
		end
	end
	if recursive then
		for _, c in rawget(self, "_children") do
			local found = c:FindFirstChildWhichIsA(className, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function Methods.FindFirstAncestorOfClass(self, className: string)
	local p = rawget(self, "_parent")
	while p do
		if p.ClassName == className then
			return p
		end
		p = rawget(p, "_parent")
	end
	return nil
end

function Methods.Destroy(self)
	if self.ClassName == "Model" and Engine.onDestroy then
		Engine.onDestroy(self)
	end
	self.Parent = nil
	rawset(self, "_destroyed", true)
end

function Methods.ClearAllChildren(self)
	for _, c in table.clone(rawget(self, "_children")) do
		c:Destroy()
	end
end

function Methods.SetAttribute(self, name: string, value: any)
	local attributes = rawget(self, "_attributes")
	local old = attributes[name]
	attributes[name] = value
	local s = rawget(self, "_attrSignals")[name]
	if s and old ~= value then
		s:Fire()
	end
end

function Methods.GetAttribute(self, name: string)
	return rawget(self, "_attributes")[name]
end

function Methods.GetAttributeChangedSignal(self, name: string)
	local signals = rawget(self, "_attrSignals")
	signals[name] = signals[name] or Signal.new()
	return signals[name]
end

function Methods.GetPropertyChangedSignal(self, name: string)
	local signals = rawget(self, "_propSignals")
	signals[name] = signals[name] or Signal.new()
	return signals[name]
end

function Methods.GetPivot(self)
	if self:IsA("BasePart") then
		return self.CFrame
	end
	local primary = self.PrimaryPart
	if primary then
		return primary.CFrame
	end
	return CFrame.new()
end

function Methods.PivotTo(self, cf)
	if self:IsA("BasePart") then
		self.CFrame = cf
		return
	end
	local delta = cf * self:GetPivot():Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end

local function tag(inst, name: string)
	Engine.tagged[name] = Engine.tagged[name] or {}
	table.insert(Engine.tagged[name], inst)
	local s = Engine.tagSignals[name]
	if s then
		s:Fire(inst)
	end
end

function Methods.AddTag(self, name: string)
	tag(self, name)
end

function Methods.MoveTo(self, target)
	rawset(self, "_moveTarget", target)
end

for _, name in { "SetStateEnabled", "SetNetworkOwner" } do
	Methods[name] = function() end
end
ClassMethods.Sound = {
	Play = function() end,
	Stop = function() end,
}

-- remotes: routed between the fake server and the single fake client
Methods.FireServer = function(self, ...)
	self.OnServerEvent:Fire(Engine.localPlayer, ...)
end
Methods.FireClient = function(self, player, ...)
	if player == Engine.localPlayer then
		self.OnClientEvent:Fire(...)
	end
end
Methods.FireAllClients = function(self, ...)
	self.OnClientEvent:Fire(...)
end

local function makeCharacter(player)
	local character = newInstance("Model", player.Name)
	local root = newInstance("Part", "HumanoidRootPart")
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = character
	local head = newInstance("Part", "Head")
	head.Size = Vector3.new(1, 1, 1)
	head.CFrame = CFrame.new(0, 4.5, 0)
	head.Parent = character
	newInstance("Humanoid", "Humanoid").Parent = character
	character.PrimaryPart = root
	return character
end
Engine.makeCharacter = makeCharacter

ClassMethods.Player = {
	LoadCharacterAsync = function(self)
		local old = self.Character
		if old then
			old:Destroy()
		end
		local character = makeCharacter(self)
		character.Parent = Engine.workspace
		self.Character = character
		self.CharacterAdded:Fire(character)
	end,
}

ClassMethods.BindableEvent = {
	Fire = function(self, ...)
		self.Event:Fire(...)
	end,
}

local InstanceLib = {}
function InstanceLib.new(className: string, parent: any?)
	local inst = newInstance(className)
	if parent then
		inst.Parent = parent
	end
	return inst
end
Engine.Instance = InstanceLib

---------------------------------------------------------------------------
-- Datatype stand-ins Lune doesn't provide

local Random = {}
Random.__index = Random
function Random.new(seed: number?)
	local s = math.floor(seed or (os.clock() * 1e6)) % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return setmetatable({ s = s }, Random)
end
function Random:_next(): number
	self.s = (self.s * 16807) % 2147483647
	return (self.s - 1) / 2147483646
end
function Random:NextNumber(a: number?, b: number?): number
	local r = self:_next()
	if a and b then
		return a + r * (b - a)
	end
	return r
end
function Random:NextInteger(a: number, b: number): number
	return a + math.floor(self:_next() * (b - a + 1))
end
Engine.Random = Random

local TweenInfo = {}
function TweenInfo.new(...)
	return { args = { ... } }
end
Engine.TweenInfo = TweenInfo

local RaycastParams = {}
function RaycastParams.new()
	return {}
end
Engine.RaycastParams = RaycastParams

---------------------------------------------------------------------------
-- Grid raycasts: blocked when the segment crosses a wall edge of the maze

local function cellAt(p)
	local C = Engine.layout.cellSize
	return math.floor(p.X / C), math.floor(p.Z / C)
end

local function edgeBetween(ax, az, bx, bz): string
	local Maze = Engine.Maze
	local layout = Engine.layout
	if bx == ax + 1 and bz == az then
		return Maze.getEdge(layout, ax, az, "E")
	elseif bx == ax - 1 and bz == az then
		return Maze.getEdge(layout, ax, az, "W")
	elseif bz == az + 1 and bx == ax then
		return Maze.getEdge(layout, ax, az, "N")
	elseif bz == az - 1 and bx == ax then
		return Maze.getEdge(layout, ax, az, "S")
	end
	return "wall"
end

-- Can you get from cell a to cell b in one step (a diagonal corner cut only counts
-- if one of the two L-shaped routes is open)?
function Engine.canCross(ax, az, bx, bz): boolean
	local Maze = Engine.Maze
	if ax == bx and az == bz then
		return true
	end
	if math.abs(ax - bx) + math.abs(az - bz) == 1 then
		return Maze.isPassable(edgeBetween(ax, az, bx, bz))
	end
	if math.abs(ax - bx) == 1 and math.abs(az - bz) == 1 then
		local viaX = Maze.isPassable(edgeBetween(ax, az, bx, az)) and Maze.isPassable(edgeBetween(bx, az, bx, bz))
		local viaZ = Maze.isPassable(edgeBetween(ax, az, ax, bz)) and Maze.isPassable(edgeBetween(ax, bz, bx, bz))
		return viaX or viaZ
	end
	return false
end

local function gridCast(origin, direction)
	if not Engine.layout then
		return nil
	end
	local len = direction.Magnitude
	local steps = math.max(1, math.ceil(len / 0.5))
	local px, pz = cellAt(origin)
	for i = 1, steps do
		local p = origin + direction * (i / steps)
		local cx, cz = cellAt(p)
		if cx ~= px or cz ~= pz then
			if not Engine.canCross(px, pz, cx, cz) then
				return { Position = p, Distance = (p - origin).Magnitude }
			end
			px, pz = cx, cz
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Services

function Engine.makeGame(serverFolder, sharedFolder, clientFolder, remoteNames: { string })
	Engine.tagged = {}
	Engine.tagSignals = {}
	Engine.renderSteps = {}
	local game = newInstance("DataModel", "Game")
	local services = {}
	local function service(name: string)
		local s = newInstance(name, name)
		s.Parent = game
		services[name] = s
		return s
	end

	ClassMethods.DataModel = {
		GetService = function(_self, name: string)
			return services[name] or service(name)
		end,
		IsLoaded = function()
			return true
		end,
	}

	local workspace = service("Workspace")
	Engine.workspace = workspace
	local terrain = newInstance("Terrain", "Terrain")
	terrain.Parent = workspace
	local camera = newInstance("Camera", "Camera")
	camera.Parent = workspace
	rawget(workspace, "_props").Terrain = terrain
	rawget(workspace, "_props").CurrentCamera = camera
	ClassMethods.Workspace = {
		Raycast = function(_self, origin, direction, _params)
			return gridCast(origin, direction)
		end,
		Spherecast = function(_self, origin, _radius, direction, _params)
			return gridCast(origin, direction)
		end,
	}

	local rs = service("ReplicatedStorage")
	sharedFolder.Parent = rs
	local remotes = newInstance("Folder", "Remotes")
	remotes.Parent = rs
	for _, name in remoteNames do
		newInstance("RemoteEvent", name).Parent = remotes
	end
	newInstance("Folder", "GameState").Parent = rs

	local sss = service("ServerScriptService")
	serverFolder.Parent = sss

	local players = service("Players")
	rawset(players, "_list", {})
	ClassMethods.Players = {
		GetPlayers = function(self)
			return table.clone(rawget(self, "_list"))
		end,
		GetPlayerFromCharacter = function(self, character)
			for _, p in rawget(self, "_list") do
				if p.Character == character then
					return p
				end
			end
			return nil
		end,
	}

	local starterPlayer = service("StarterPlayer")
	local sps = newInstance("StarterPlayerScripts", "StarterPlayerScripts")
	sps.Parent = starterPlayer
	if clientFolder then
		clientFolder.Parent = sps
	end

	service("RunService")
	ClassMethods.RunService = {
		IsStudio = function()
			return false
		end,
		BindToRenderStep = function(_self, name: string, priority: number, fn)
			for i, step in Engine.renderSteps do
				if step.name == name then
					table.remove(Engine.renderSteps, i)
					break
				end
			end
			table.insert(Engine.renderSteps, { name = name, priority = priority, fn = fn })
			table.sort(Engine.renderSteps, function(a, b)
				return a.priority < b.priority
			end)
		end,
		UnbindFromRenderStep = function(_self, name: string)
			for i, step in Engine.renderSteps do
				if step.name == name then
					table.remove(Engine.renderSteps, i)
					return
				end
			end
		end,
	}

	service("CollectionService")
	ClassMethods.CollectionService = {
		AddTag = function(_self, inst, name: string)
			tag(inst, name)
		end,
		GetTagged = function(_self, name: string)
			local out = {}
			for _, inst in Engine.tagged[name] or {} do
				if inst.Parent then
					table.insert(out, inst)
				end
			end
			return out
		end,
		GetInstanceAddedSignal = function(_self, name: string)
			Engine.tagSignals[name] = Engine.tagSignals[name] or Signal.new()
			return Engine.tagSignals[name]
		end,
		GetInstanceRemovedSignal = function()
			return Signal.new()
		end,
	}

	service("PhysicsService")
	ClassMethods.PhysicsService = {
		RegisterCollisionGroup = function() end,
		CollisionGroupSetCollidable = function() end,
	}

	service("TweenService")
	ClassMethods.TweenService = {
		Create = function(_self, inst, _info, goal)
			local tween = newInstance("Tween", "Tween")
			rawset(tween, "_target", inst)
			rawset(tween, "_goal", goal)
			return tween
		end,
	}
	ClassMethods.Tween = {
		Play = function(self)
			local target = rawget(self, "_target")
			for k, v in rawget(self, "_goal") do
				target[k] = v
			end
			self.Completed:Fire()
		end,
	}

	service("Debris")
	ClassMethods.Debris = {
		AddItem = function(_self, inst, seconds)
			table.insert(Engine.delayed, {
				at = Engine.time + (seconds or 10),
				fn = function()
					inst:Destroy()
				end,
				args = {},
			})
		end,
	}

	service("SoundService")
	service("Lighting")

	service("StarterGui")
	ClassMethods.StarterGui = {
		SetCoreGuiEnabled = function() end,
		SetCore = function() end,
	}

	service("ContextActionService")
	Engine.actions = {}
	ClassMethods.ContextActionService = {
		BindAction = function(_self, name: string, fn, _touch: boolean, ...)
			Engine.actions[name] = fn
		end,
		UnbindAction = function(_self, name: string)
			Engine.actions[name] = nil
		end,
		SetTitle = function() end,
		SetPosition = function() end,
	}

	service("UserInputService")

	return game, workspace
end

-- A Player object for the local (and only) client.
function Engine.addPlayer(game, name: string, userId: number)
	local players = game:GetService("Players")
	local player = newInstance("Player", name)
	player.DisplayName = name
	player.UserId = userId
	newInstance("PlayerGui", "PlayerGui").Parent = player
	player.Parent = players
	table.insert(rawget(players, "_list"), player)
	rawget(players, "_props").LocalPlayer = player
	Engine.localPlayer = player
	return player
end

---------------------------------------------------------------------------
-- task library + clock

function Engine.makeTask()
	return {
		delay = function(seconds: number?, fn, ...)
			table.insert(Engine.delayed, { at = Engine.time + (seconds or 0), fn = fn, args = { ... } })
		end,
		spawn = function(fn, ...)
			return spawnThread(fn, ...)
		end,
		defer = function(fn, ...)
			table.insert(Engine.delayed, { at = Engine.time, fn = fn, args = { ... } })
		end,
		wait = function(seconds: number?)
			local co = coroutine.running()
			table.insert(Engine.sleeping, { at = Engine.time + math.max(seconds or 0, 1 / 60), co = co })
			coroutine.yield()
			return seconds or 0
		end,
	}
end

function Engine.runScheduled()
	local due = {}
	local keep = {}
	for _, item in Engine.delayed do
		if item.at <= Engine.time then
			table.insert(due, item)
		else
			table.insert(keep, item)
		end
	end
	Engine.delayed = keep
	for _, item in due do
		spawnThread(item.fn, table.unpack(item.args))
	end

	local wake = {}
	local sleep = {}
	for _, item in Engine.sleeping do
		if item.at <= Engine.time then
			table.insert(wake, item)
		else
			table.insert(sleep, item)
		end
	end
	Engine.sleeping = sleep
	for _, item in wake do
		Engine.resume(item.co)
	end
end

---------------------------------------------------------------------------
-- Module loading: maps script.Parent / ReplicatedStorage.Shared to files

function Engine.folderFromDir(name: string, dir: string)
	local folder = newInstance("Folder", name)
	for _, file in fs.readDir(dir) do
		local moduleName, kind = string.match(file, "^([^%.]+)%.?(%a*)%.luau$")
		if moduleName then
			local className = if kind == "server" then "Script" elseif kind == "client" then "LocalScript" else "ModuleScript"
			local m = newInstance(className, moduleName)
			rawset(m, "__file", dir .. "/" .. file)
			-- read now: Lune's file IO yields, which would strand our script coroutines
			rawset(m, "__source", fs.readFile(dir .. "/" .. file))
			m.Parent = folder
		end
	end
	return folder
end

function Engine.makeLoader(globals: { [string]: any })
	local cache = {}
	local function load(target)
		local file = rawget(target, "__file")
		assert(file, "require() of something that isn't a module: " .. tostring(target))
		local env = table.clone(globals)
		env.script = target
		env.require = function(t)
			local f = rawget(t, "__file")
			if cache[f] == nil then
				cache[f] = load(t)
			end
			return cache[f]
		end
		local chunk = luau.load(rawget(target, "__source"), { debugName = file, environment = env })
		return chunk()
	end
	local function require(target)
		local f = rawget(target, "__file")
		if cache[f] == nil then
			cache[f] = load(target)
		end
		return cache[f]
	end
	-- run a Script/LocalScript in its own thread, like the engine would
	local function runScript(target)
		return spawnThread(function()
			load(target)
		end)
	end
	return require, runScript
end

function Engine.typeof(v: any): string
	if isInstance(v) then
		return "Instance"
	end
	return typeof(v)
end

-- Advance the world one frame: timers, threads, heartbeat, render steps.
function Engine.step(game, dt: number)
	Engine.time += dt
	Engine.runScheduled()
	local run = game:GetService("RunService")
	run.Heartbeat:Fire(dt)
	run.RenderStepped:Fire(dt)
	for _, step in table.clone(Engine.renderSteps) do
		local ok, err = pcall(step.fn, dt)
		if not ok then
			report(err)
		end
	end
end

return Engine
