--!strict
-- What each night asks of you:
--   survive  make it from 12 AM to 6 AM
--   keys     find 4 keys (each tag shows a digit), unlock the exit, type the code
--   power    start 3 generators (loud!), then take the service lift
--   collect  take 6 photographs
--   hearts   destroy 3 hearts (it knows each time), then run for the portal

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Build = require(script.Parent.Build)
local Maze = require(ReplicatedStorage.Shared.Maze)
local Nights = require(ReplicatedStorage.Shared.Nights)
local Exit = require(script.Parent.Exit)
local Interactables = require(script.Parent.Interactables)
local MonsterAI = require(script.Parent.MonsterAI)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Remotes = ReplicatedStorage.Remotes
local GameState = ReplicatedStorage.GameState

export type Ctx = {
	night: Nights.Night,
	layout: Maze.Layout,
	world: WorldBuilder.World,
	interactables: Interactables.Interactables,
	monster: MonsterAI.MonsterAI,
	exit: Exit.Exit,
	isAlive: (player: Player) -> boolean,
	notifyAll: (text: string, style: string?) -> (),
	notify: (player: Player, text: string, style: string?) -> (),
	setProgress: (text: string) -> (),
	winAll: (kind: string) -> (),
}

export type Objective = { destroy: () -> () }

local Objectives = {}

local prompt = Interactables.prompt
local rootOf = Interactables.rootOf

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function openExit(ctx: Ctx, message: string)
	ctx.exit:open()
	GameState:SetAttribute("ExitOpen", true)
	ctx.notifyAll(message, "danger")
	ctx.monster:onExitOpened()
end

---------------------------------------------------------------------------
-- SURVIVE: 12 AM -> 6 AM

local function survive(ctx: Ctx): Objective
	local total = ctx.night.surviveSeconds or 300
	local started = os.clock()
	local lastHour = 0
	local lastText = ""
	local done = false
	GameState:SetAttribute("Hour", 0)
	ctx.setProgress("12:00 AM")
	local connection = RunService.Heartbeat:Connect(function()
		if done then
			return
		end
		local minutes = math.clamp(math.floor((os.clock() - started) / total * 360), 0, 360)
		local hour = minutes // 60
		local text = string.format("%d:%02d AM", if hour == 0 then 12 else hour, minutes % 60)
		if text ~= lastText then
			lastText = text
			ctx.setProgress(text)
		end
		if hour > lastHour then
			lastHour = hour
			GameState:SetAttribute("Hour", hour)
			if hour < 6 then
				ctx.monster:setAggression(hour)
				if hour == 1 then
					ctx.monster:awaken()
					ctx.notifyAll("1:00 AM. It's awake.", "danger")
				elseif hour == 3 then
					ctx.notifyAll("3:00 AM. The witching hour. It knows where you are.", "danger")
					ctx.monster:frenzy(15, nil)
				elseif hour == 5 then
					ctx.notifyAll("5:00 AM. One more hour.")
				else
					ctx.notifyAll(string.format("%d:00 AM.", hour))
				end
			end
		end
		if minutes >= 360 then
			done = true
			ctx.winAll("survived")
		end
	end)
	return {
		destroy = function()
			connection:Disconnect()
		end,
	}
end

---------------------------------------------------------------------------
-- KEYS: 4 keys -> padlocks -> keypad code -> exit

local function keys(ctx: Ctx): Objective
	local world = ctx.world
	local layout = ctx.layout
	local wctx = world.ctx
	local folder = Instance.new("Folder")
	folder.Name = "Keys"
	folder.Parent = world.model
	local count = #layout.spots
	local found = 0
	local mask = table.create(count, "_")
	local padlocks: { { BasePart } } = {}
	local padlocksLeft = count
	local exitOpen = false
	local lastTry: { [Player]: number } = {}
	local connections: { RBXScriptConnection } = {}
	local metal = rgb(196, 196, 190)

	local function progressText(): string
		return string.format("KEYS %d/%d     CODE  %s", found, count, table.concat(mask, " "))
	end
	ctx.setProgress(progressText())
	GameState:SetAttribute("CodeMask", table.concat(mask))

	-- padlocks + chain on the exit, keypad beside it
	local exit = ctx.exit
	for i = 0, 12 do
		wctx.decor(wctx.part(folder, "Chain", Vector3.new(0.32, 0.18, 0.18), exit:hubSide(-2.4 + i * 0.4, 5.1 + math.sin(i * 0.5) * 0.15) * CFrame.new(0, 0, -0.08) * CFrame.Angles(i % 2 * math.rad(90), 0, 0), Enum.Material.Metal, rgb(120, 120, 120), nil))
	end
	for i = 1, count do
		local x = -1.05 + (i - 1) * (2.1 / math.max(count - 1, 1))
		local y = 4.4 + (i % 2) * 0.55
		local body = wctx.decor(wctx.part(folder, "Padlock", Vector3.new(0.55, 0.65, 0.25), exit:hubSide(x, y), Enum.Material.Metal, rgb(150, 150, 146), nil))
		local shackle = wctx.decor(wctx.part(folder, "Shackle", Vector3.new(0.38, 0.45, 0.08), exit:hubSide(x, y + 0.5), Enum.Material.Metal, rgb(180, 180, 176), nil))
		table.insert(padlocks, { body, shackle })
	end
	local keypad = wctx.part(folder, "Keypad", Vector3.new(1.2, 1.8, 0.3), exit:hubSide(exit.width / 2 + 1.15, 4.8) * CFrame.new(0, 0, 0.15), Enum.Material.Metal, rgb(40, 40, 42), nil)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.Parent = keypad
	local screen = Instance.new("TextLabel")
	screen.BackgroundColor3 = rgb(12, 12, 12)
	screen.BorderSizePixel = 0
	screen.Size = UDim2.fromScale(1, 1)
	screen.Font = Enum.Font.Code
	screen.TextScaled = true
	screen.TextColor3 = rgb(210, 210, 210)
	screen.Parent = gui
	local glow = Instance.new("PointLight")
	glow.Range = 7
	glow.Brightness = 0.5
	glow.Parent = keypad

	local function refreshKeypad()
		if exitOpen then
			screen.Text = "OPEN"
		elseif padlocksLeft > 0 then
			screen.Text = string.format("LOCKED\n%d/%d", count - padlocksLeft, count)
		else
			screen.Text = "ENTER\nCODE"
		end
	end
	refreshKeypad()

	local keypadPrompt = prompt(keypad, "Use", "Keypad", 0, 7)
	keypadPrompt.Triggered:Connect(function(player: Player)
		if exitOpen or not ctx.isAlive(player) then
			return
		end
		if padlocksLeft > 0 then
			Audio.play("KeypadError", keypad, 0.8, 1, 50)
			ctx.notify(player, string.format("%d padlocks still hold the door. Find the keys.", padlocksLeft))
			return
		end
		Remotes.OpenKeypad:FireClient(player)
	end)

	table.insert(connections, Remotes.SubmitCode.OnServerEvent:Connect(function(player: Player, code: unknown)
		if typeof(code) ~= "string" or #code > 8 or exitOpen or padlocksLeft > 0 or not ctx.isAlive(player) then
			return
		end
		local now = os.clock()
		local last = lastTry[player]
		if last and now - last < 0.8 then
			return
		end
		lastTry[player] = now
		local root = rootOf(player)
		if not root or (root.Position - keypad.Position).Magnitude > 16 then
			return
		end
		if code == layout.code then
			exitOpen = true
			refreshKeypad()
			ctx.setProgress("THE EXIT IS OPEN")
			openExit(ctx, "The exit is open. RUN.")
		else
			Audio.play("KeypadError", keypad, 1.3, 1, 100)
			screen.Text = "WRONG"
			task.delay(1.2, function()
				if keypad.Parent then
					refreshKeypad()
				end
			end)
			ctx.notify(player, "Wrong code. That buzzer was loud...")
			ctx.monster:hearNoise(keypad.Position, 70)
		end
	end))

	-- the keys, on crates at the back of dead ends
	for index, cell in layout.spots do
		local frame = Interactables.spotFrame(world, cell)
		local crate = wctx.part(folder, "KeyCrate", Vector3.new(2.6, 2.6, 2.6), frame * CFrame.new(0, 1.3, 0), Enum.Material.WoodPlanks, rgb(96, 86, 74), nil)
		crate.CollisionGroup = "Furniture"
		local model = Instance.new("Model")
		model.Name = "Key" .. index
		local base = frame * CFrame.new(0, 2.68, 0) * CFrame.Angles(0, world.random:NextNumber(0, math.pi * 2), 0)
		local shaft = wctx.decor(wctx.part(model, "Shaft", Vector3.new(1.6, 0.18, 0.18), base * CFrame.new(0.2, 0, 0), Enum.Material.Metal, metal, nil))
		shaft.CanQuery = true
		shaft.Reflectance = 0.15
		wctx.decor(wctx.part(model, "Bow", Vector3.new(0.12, 0.9, 0.9), base * CFrame.new(-0.85, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Metal, metal, Enum.PartType.Cylinder))
		wctx.decor(wctx.part(model, "Tooth", Vector3.new(0.16, 0.12, 0.4), base * CFrame.new(0.85, 0, 0.22), Enum.Material.Metal, metal, nil))
		wctx.decor(wctx.part(model, "Tooth", Vector3.new(0.16, 0.12, 0.28), base * CFrame.new(0.55, 0, 0.16), Enum.Material.Metal, metal, nil))
		local tag = wctx.decor(wctx.part(model, "Tag", Vector3.new(0.6, 0.03, 0.8), base * CFrame.new(-1.6, 0, 0.3) * CFrame.Angles(0, 0.3, 0), Enum.Material.SmoothPlastic, rgb(220, 214, 198), nil))
		local tagGui = Instance.new("SurfaceGui")
		tagGui.Face = Enum.NormalId.Top
		tagGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		tagGui.PixelsPerStud = 120
		tagGui.Parent = tag
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.SpecialElite
		label.TextScaled = true
		label.TextColor3 = rgb(20, 20, 20)
		local digits = {}
		for i = 1, #layout.code do
			digits[i] = if i == index then string.sub(layout.code, i, i) else "_"
		end
		label.Text = table.concat(digits, " ")
		label.Parent = tagGui
		local glint = Instance.new("PointLight")
		glint.Range = 6
		glint.Brightness = 0.9
		glint.Parent = shaft
		model.PrimaryPart = shaft
		model.Parent = folder

		prompt(shaft, "Take", "Key", 0.5, 8).Triggered:Connect(function(player: Player)
			if not ctx.isAlive(player) or model.Parent == nil then
				return
			end
			Audio.play("KeyPickup", crate, 1, 1, 70)
			model:Destroy()
			found += 1
			mask[index] = string.sub(layout.code, index, index)
			GameState:SetAttribute("CodeMask", table.concat(mask))
			ctx.setProgress(progressText())
			if padlocksLeft > 0 then
				local lock = padlocks[padlocksLeft]
				padlocksLeft -= 1
				for _, p in lock do
					p.Anchored = false
					p.CanCollide = true
				end
				Audio.play("Unlock", keypad, 0.9, 0.9, 120)
				refreshKeypad()
			end
			ctx.notifyAll(string.format("%s found a key. The tag reads   %s", player.DisplayName, table.concat(digits, " ")), "key")
			ctx.monster:setAggression(found)
			ctx.monster:awaken()
			ctx.monster:hearNoise(crate.Position, 45)
			if found >= count then
				ctx.notifyAll("Every padlock is open. Get to the keypad by the exit.", "key")
			end
		end)
	end

	return {
		destroy = function()
			for _, c in connections do
				c:Disconnect()
			end
		end,
	}
end

---------------------------------------------------------------------------
-- POWER: 3 generators, then the lift

local function power(ctx: Ctx): Objective
	local world = ctx.world
	local layout = ctx.layout
	local wctx = world.ctx
	local folder = Instance.new("Folder")
	folder.Name = "Generators"
	folder.Parent = world.model
	local count = #layout.spots
	local running = 0
	ctx.setProgress(string.format("GENERATORS 0/%d", count))

	-- each lamp belongs to the nearest generator
	local maps = {}
	for i, cell in layout.spots do
		maps[i] = Maze.distances(layout, cell)
	end
	local zones: { { Build.Lamp } } = {}
	for i = 1, count do
		zones[i] = {}
	end
	for _, lamp in world.lamps do
		local cell = lamp.cell
		if cell and not lamp.light.Enabled then
			local best, bestDist = 1, math.huge
			for i, dist in maps do
				local d = dist[Maze.key(cell.x, cell.z)] or math.huge
				if d < bestDist then
					best, bestDist = i, d
				end
			end
			table.insert(zones[best], lamp)
		end
	end

	local panelLabel: TextLabel? = nil
	local panel = world.model:FindFirstChild("PowerPanel", true)
	if panel then
		panelLabel = panel:FindFirstChildWhichIsA("TextLabel", true)
	end

	for i, cell in layout.spots do
		local frame = Interactables.spotFrame(world, cell)
		local model = Instance.new("Model")
		model.Name = "Generator" .. i
		local base = wctx.part(model, "Generator", Vector3.new(4.4, 3.2, 2.8), frame * CFrame.new(0, 1.6, 0), Enum.Material.Metal, rgb(150, 120, 40), nil)
		base.CollisionGroup = "Furniture"
		wctx.part(model, "Engine", Vector3.new(2.6, 1.4, 2.2), frame * CFrame.new(-0.4, 3.9, 0), Enum.Material.Metal, rgb(60, 62, 60), nil).CollisionGroup = "Furniture"
		wctx.decor(wctx.part(model, "Exhaust", Vector3.new(3, 0.5, 0.5), frame * CFrame.new(1.5, 4.6, 0.6) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.CorrodedMetal, rgb(80, 60, 50), Enum.PartType.Cylinder))
		wctx.decor(wctx.part(model, "Fan", Vector3.new(0.2, 2.2, 2.2), frame * CFrame.new(-2.3, 1.7, 0) * CFrame.Angles(0, 0, 0), Enum.Material.Metal, rgb(40, 40, 40), Enum.PartType.Cylinder))
		for s = 0, 3 do
			wctx.decor(wctx.part(model, "Stripe", Vector3.new(0.6, 0.6, 0.05), frame * CFrame.new(-1.6 + s * 1.1, 0.6, -1.43) * CFrame.Angles(0, 0, math.rad(45)), Enum.Material.SmoothPlastic, rgb(20, 20, 20), nil))
		end
		local status = wctx.decor(wctx.part(model, "Status", Vector3.new(0.5, 0.5, 0.5), frame * CFrame.new(1.4, 3.45, -0.9), Enum.Material.Neon, rgb(255, 40, 30), Enum.PartType.Ball))
		local statusLight = Instance.new("PointLight")
		statusLight.Range = 8
		statusLight.Brightness = 1
		statusLight.Color = rgb(255, 40, 30)
		statusLight.Parent = status
		model.Parent = folder

		local started = false
		local p = prompt(base, "Start", "Generator", 3.5, 9)
		p.Triggered:Connect(function(player: Player)
			if started or not ctx.isAlive(player) then
				return
			end
			started = true
			p.Enabled = false
			running += 1
			status.Color = rgb(60, 255, 90)
			statusLight.Color = rgb(60, 255, 90)
			Audio.play("GeneratorStart", base, 1.6, 1, 160)
			local hum = Audio.create("GeneratorLoop", base, 1)
			if hum then
				hum.RollOffMinDistance = 8
				hum.RollOffMaxDistance = 70
				task.delay(2.8, function()
					if hum.Parent then
						hum:Play()
					end
				end)
			end
			-- lights come back in this part of the tunnels
			task.delay(1.6, function()
				for _, lamp in zones[i] do
					if lamp.bulb.Parent then
						lamp.light.Enabled = true
						local on = lamp.bulb:GetAttribute("OnColor")
						if typeof(on) == "Color3" then
							lamp.bulb.Color = on
						end
					end
				end
				Audio.play("PowerUp", base, 1.2, 1, 140)
			end)
			ctx.setProgress(string.format("GENERATORS %d/%d", running, count))
			if panelLabel then
				panelLabel.Text = string.format("MAIN POWER\n%d/%d", running, count)
			end
			ctx.monster:setAggression(running)
			ctx.monster:hearNoise(base.Position, 400) -- the whole system hears it
			ctx.monster:awaken()
			if running >= count then
				if panelLabel then
					panelLabel.Text = "LIFT\nONLINE"
					panelLabel.TextColor3 = rgb(80, 255, 120)
				end
				ctx.setProgress("THE LIFT HAS POWER")
				openExit(ctx, "The lift has power. GET OUT.")
			else
				ctx.notifyAll(string.format("%s started a generator. That was LOUD. (%d/%d)", player.DisplayName, running, count), "key")
			end
		end)
	end

	return {
		destroy = function() end,
	}
end

---------------------------------------------------------------------------
-- COLLECT: 6 photographs

local PHOTO_LINES = {
	"The photo shows this hall. Someone is standing behind the camera.",
	"A photo of a statue. It's facing the camera. In the next one it isn't.",
	"A group photo. Every face has been scratched out.",
	"The photo shows you. Taken from behind. Tonight.",
	"A photo of the exhibit. One plinth is empty.",
	"The last photograph shows a door that wasn't there before.",
}

local function collect(ctx: Ctx): Objective
	local world = ctx.world
	local layout = ctx.layout
	local wctx = world.ctx
	local folder = Instance.new("Folder")
	folder.Name = "Photographs"
	folder.Parent = world.model
	local count = #layout.spots
	local taken = 0
	ctx.setProgress(string.format("PHOTOGRAPHS 0/%d", count))

	for i, cell in layout.spots do
		local frame = Interactables.spotFrame(world, cell)
		local model = Instance.new("Model")
		model.Name = "Photo" .. i
		for _, leg in { -0.8, 0.8 } do
			wctx.decor(wctx.part(model, "EaselLeg", Vector3.new(0.18, 5.2, 0.18), frame * CFrame.new(leg, 2.5, 0) * CFrame.Angles(math.rad(-8), 0, 0), Enum.Material.Wood, rgb(80, 60, 40), nil))
		end
		wctx.decor(wctx.part(model, "EaselBack", Vector3.new(0.18, 5, 0.18), frame * CFrame.new(0, 2.4, 0.8) * CFrame.Angles(math.rad(18), 0, 0), Enum.Material.Wood, rgb(80, 60, 40), nil))
		local photo = wctx.part(model, "Photograph", Vector3.new(2, 2.4, 0.1), frame * CFrame.new(0, 3.9, -0.15) * CFrame.Angles(math.rad(-8), 0, 0), Enum.Material.SmoothPlastic, rgb(230, 228, 220), nil)
		photo.CanCollide = false
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.Parent = photo
		local backdrop = Instance.new("Frame")
		backdrop.Position = UDim2.fromScale(0.08, 0.06)
		backdrop.Size = UDim2.fromScale(0.84, 0.72)
		backdrop.BackgroundColor3 = rgb(70, 72, 76)
		backdrop.BorderSizePixel = 0
		backdrop.Parent = gui
		-- a dark figure in every photograph
		local head = Instance.new("Frame")
		head.AnchorPoint = Vector2.new(0.5, 0.5)
		head.Position = UDim2.fromScale(0.3 + (i % 3) * 0.2, 0.32)
		head.Size = UDim2.fromScale(0.16, 0.16)
		head.BackgroundColor3 = rgb(10, 10, 12)
		head.BorderSizePixel = 0
		head.Parent = backdrop
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = head
		local body = Instance.new("Frame")
		body.AnchorPoint = Vector2.new(0.5, 0)
		body.Position = UDim2.fromScale(0.3 + (i % 3) * 0.2, 0.4)
		body.Size = UDim2.fromScale(0.22, 0.6)
		body.BackgroundColor3 = rgb(10, 10, 12)
		body.BorderSizePixel = 0
		body.Parent = backdrop
		local caption = Instance.new("TextLabel")
		caption.BackgroundTransparency = 1
		caption.Position = UDim2.fromScale(0, 0.8)
		caption.Size = UDim2.fromScale(1, 0.18)
		caption.Font = Enum.Font.SpecialElite
		caption.TextScaled = true
		caption.TextColor3 = rgb(40, 40, 40)
		caption.Text = string.format("no. %d", i)
		caption.Parent = gui
		local glint = Instance.new("PointLight")
		glint.Range = 7
		glint.Brightness = 0.8
		glint.Color = rgb(220, 230, 255)
		glint.Parent = photo
		model.Parent = folder

		prompt(photo, "Take", "Photograph", 0.6, 8).Triggered:Connect(function(player: Player)
			if not ctx.isAlive(player) or model.Parent == nil then
				return
			end
			model:Destroy()
			taken += 1
			Audio.play("PagePickup", nil, 1)
			ctx.setProgress(string.format("PHOTOGRAPHS %d/%d", taken, count))
			ctx.monster:setAggression(taken)
			ctx.notify(player, PHOTO_LINES[math.min(taken, #PHOTO_LINES)], "note")
			if taken >= count then
				ctx.winAll("collected")
			else
				ctx.notifyAll(string.format("%s took a photograph. (%d/%d)", player.DisplayName, taken, count), "key")
			end
		end)
	end

	return {
		destroy = function() end,
	}
end

---------------------------------------------------------------------------
-- HEARTS: 3 hearts, then the portal

local function hearts(ctx: Ctx): Objective
	local world = ctx.world
	local layout = ctx.layout
	local wctx = world.ctx
	local folder = Instance.new("Folder")
	folder.Name = "Hearts"
	folder.Parent = world.model
	local count = #layout.spots
	local broken = 0
	ctx.setProgress(string.format("HEARTS 0/%d", count))
	local CORE = rgb(200, 20, 110)

	for i, cell in layout.spots do
		local frame = Interactables.spotFrame(world, cell)
		local model = Instance.new("Model")
		model.Name = "Heart" .. i
		local altar = wctx.part(model, "Altar", Vector3.new(5, 2.4, 5), frame * CFrame.new(0, 1.2, 0), Enum.Material.Basalt, rgb(16, 12, 20), nil)
		altar.CollisionGroup = "Furniture"
		local heart = wctx.decor(wctx.part(model, "Heart", Vector3.new(3, 3, 3), frame * CFrame.new(0, 4.6, 0), Enum.Material.Neon, CORE, Enum.PartType.Ball))
		heart.CanQuery = true
		heart:AddTag("Heart")
		for v = 1, 8 do
			local a = v * 0.785
			wctx.decor(wctx.part(model, "Vein", Vector3.new(0.18, 4.6, 0.18), frame * CFrame.new(math.cos(a) * 1.6, 4.4, math.sin(a) * 1.6) * CFrame.Angles(math.cos(a) * 0.35, 0, math.sin(a) * 0.35), Enum.Material.Neon, rgb(120, 20, 160), nil))
		end
		for b = 1, 4 do
			local a = b * 1.57 + 0.4
			wctx.part(model, "Bone", Vector3.new(0.35, 6, 0.35), frame * CFrame.new(math.cos(a) * 2.2, 5, math.sin(a) * 2.2) * CFrame.Angles(math.cos(a) * -0.3, 0, math.sin(a) * 0.3), Enum.Material.SmoothPlastic, rgb(210, 200, 220), nil)
		end
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 2
		light.Color = CORE
		light.Parent = heart
		local pulse = Audio.create("HeartPulseLoop", heart, 1.6)
		if pulse then
			pulse.RollOffMinDistance = 6
			pulse.RollOffMaxDistance = 80
			pulse:Play()
		end
		model.Parent = folder

		local p = prompt(heart, "Destroy", "Heart", 3, 9)
		p.Triggered:Connect(function(player: Player)
			if not ctx.isAlive(player) or heart.Parent == nil then
				return
			end
			local where = heart.Position
			heart:Destroy()
			light:Destroy()
			for _ = 1, 14 do
				local shard = wctx.part(folder, "Shard", Vector3.new(0.5, 0.5, 0.5), CFrame.new(where), Enum.Material.Neon, CORE, nil)
				shard.Anchored = false
				shard.CanCollide = true
				shard.AssemblyLinearVelocity = Vector3.new(world.random:NextNumber(-30, 30), world.random:NextNumber(10, 40), world.random:NextNumber(-30, 30))
				TweenService:Create(shard, TweenInfo.new(4), { Transparency = 1 }):Play()
				task.delay(4, function()
					shard:Destroy()
				end)
			end
			Audio.playAt("HeartShatter", where, 2, 1, 400)
			broken += 1
			ctx.setProgress(string.format("HEARTS %d/%d", broken, count))
			ctx.monster:setAggression(broken)
			if broken >= count then
				ctx.setProgress("THE WAY OUT IS OPEN")
				openExit(ctx, "The last heart is still. The way out is open. RUN.")
			else
				ctx.notifyAll(string.format("A heart stops beating. IT KNOWS WHERE %s IS. (%d/%d)", string.upper(player.DisplayName), broken, count), "danger")
				ctx.monster:frenzy(14, player)
			end
		end)
	end

	return {
		destroy = function() end,
	}
end

local BY_KIND: { [string]: (Ctx) -> Objective } = {
	survive = survive,
	keys = keys,
	power = power,
	collect = collect,
	hearts = hearts,
}

function Objectives.start(ctx: Ctx): Objective
	local start = BY_KIND[ctx.night.objective] or survive
	return start(ctx)
end

return Objectives
