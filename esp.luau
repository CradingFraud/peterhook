local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local lp = Players.LocalPlayer
local character = nil
if lp.Character then character = lp.Character end
lp.CharacterAdded:Connect(function(char) character = char end)
local Camera = game.Workspace.CurrentCamera

local Math = {}

Math.getcorners = function(target, isModel, isPart)
	local corners3D = {}

	if isPart then
		local part = target
		if not part or not part:IsA("BasePart") then
			return {x=0,y=0},{x=0,y=0},false
		end
		local cf = part.CFrame
		local hx,hy,hz = part.Size.X*.5, part.Size.Y*.5, part.Size.Z*.5
		corners3D = {
			cf*Vector3.new(-hx,-hy,-hz), cf*Vector3.new( hx,-hy,-hz),
			cf*Vector3.new(-hx, hy,-hz), cf*Vector3.new( hx, hy,-hz),
			cf*Vector3.new(-hx,-hy, hz), cf*Vector3.new( hx,-hy, hz),
			cf*Vector3.new(-hx, hy, hz), cf*Vector3.new( hx, hy, hz),
		}
	else
		local parts = {}
		local desc = isModel and target:GetDescendants() or target:GetChildren()
		for _, v in ipairs(desc) do
			if v:IsA("BasePart") and v.Transparency < 1
				and v.Name ~= "Handle"
				and not v:FindFirstAncestorOfClass("Accessory")
			then
				table.insert(parts, v)
			end
		end

		if #parts == 0 then
			for _, v in ipairs(desc) do
				if v:IsA("BasePart") then table.insert(parts, v) end
			end
		end
		if #parts == 0 then return {x=0,y=0},{x=0,y=0},false end

		for _, part in ipairs(parts) do
			local cf = part.CFrame
			local hx,hy,hz = part.Size.X*.5, part.Size.Y*.5, part.Size.Z*.5
			table.insert(corners3D, cf*Vector3.new(-hx,-hy,-hz))
			table.insert(corners3D, cf*Vector3.new( hx,-hy,-hz))
			table.insert(corners3D, cf*Vector3.new(-hx, hy,-hz))
			table.insert(corners3D, cf*Vector3.new( hx, hy,-hz))
			table.insert(corners3D, cf*Vector3.new(-hx,-hy, hz))
			table.insert(corners3D, cf*Vector3.new( hx,-hy, hz))
			table.insert(corners3D, cf*Vector3.new(-hx, hy, hz))
			table.insert(corners3D, cf*Vector3.new( hx, hy, hz))
		end
	end

	local minX,minY =  math.huge, math.huge
	local maxX,maxY = -math.huge,-math.huge
	local anyOnscreen = false
	local ss = Camera.ViewportSize

	for _, pt in ipairs(corners3D) do
		local sp, on = Camera:WorldToViewportPoint(pt)
		if sp.Z > 0 then
			if on then anyOnscreen = true end
			if sp.X >= -50 and sp.X <= ss.X + 50 and sp.Y >= -50 and sp.Y <= ss.Y + 50 then
				minX = math.min(minX, sp.X)
				minY = math.min(minY, sp.Y)
				maxX = math.max(maxX, sp.X)
				maxY = math.max(maxY, sp.Y)
			end
		end
	end

	if minX == math.huge then return {x=0,y=0},{x=0,y=0},false end
	return {x=minX, y=minY}, {x=maxX, y=maxY}, anyOnscreen
end

local ImageManager = {}
ImageManager.screenGui  = nil
ImageManager.images     = {}
ImageManager.assetCache = {}
ImageManager.pendingResolve = {}
ImageManager.pendingLabels  = {}

function ImageManager:Init()
	if not self.screenGui then
		self.screenGui = Instance.new("ScreenGui")
		self.screenGui.Name = "ESP_Images"
		self.screenGui.ResetOnSpawn = false
		self.screenGui.IgnoreGuiInset = true
		self.screenGui.DisplayOrder = 100
		self.screenGui.Enabled = true
		self.screenGui.Parent = CoreGui
	end
end

function ImageManager:ResolveAsset(url)
	if self.assetCache[url] then return self.assetCache[url] end
	if string.find(url,"^rbxassetid://") or string.find(url,"^rbxasset://") then
		self.assetCache[url] = url; return url
	end
	if tonumber(url) then
		local r = "rbxassetid://"..url; self.assetCache[url]=r; return r
	end
	if not self.pendingResolve[url] then
		self.pendingResolve[url] = true
		task.spawn(function()
			local ext = string.match(url,"%.(%a+)%??") or "png"
			local safeName = string.sub(string.gsub(url,"[^%w]","_"),-50)
			local filename = "esp_"..safeName.."."..ext
			local requestFn = syn and syn.request or http and http.request or request
			local ok,res = pcall(function() return requestFn({Url=url,Method="GET"}) end)
			local data = ok and res and res.Body
			if not ok or not data or data=="" or (res and res.StatusCode~=200) then
				warn("[ImageManager] HTTP failed: "..url); self.pendingResolve[url]=nil; return
			end
			if not pcall(writefile,filename,data) then
				warn("[ImageManager] writefile failed"); self.pendingResolve[url]=nil; return
			end
			local aok,assetId = pcall(getcustomasset,filename)
			if not aok or not assetId or assetId=="" then
				warn("[ImageManager] getcustomasset failed"); self.pendingResolve[url]=nil; return
			end
			self.assetCache[url] = assetId
			if self.pendingLabels[url] then
				for _,img in ipairs(self.pendingLabels[url]) do
					if img and img.Parent then pcall(function() img.Image=assetId end) end
				end
				self.pendingLabels[url] = nil
			end
		end)
	end
	return nil
end

function ImageManager:SetImageAsync(imageLabel, url)
	if not imageLabel or not imageLabel.Parent then return end
	local resolved = self:ResolveAsset(url)
	if resolved then
		if imageLabel.Image ~= resolved then pcall(function() imageLabel.Image=resolved end) end
	else
		if not self.pendingLabels[url] then self.pendingLabels[url]={} end
		local already = false
		for _,lbl in ipairs(self.pendingLabels[url]) do
			if lbl==imageLabel then already=true; break end
		end
		if not already then table.insert(self.pendingLabels[url],imageLabel) end
	end
end

function ImageManager:CreateImage(id)
	if self.images[id] then return self.images[id] end
	local img = Instance.new("ImageLabel")
	img.Name = id; img.BackgroundTransparency=1; img.Visible=false
	img.Parent = self.screenGui
	self.images[id] = img; return img
end
function ImageManager:GetImage(id) return self.images[id] end
function ImageManager:RemoveImage(id)
	if self.images[id] then
		local img = self.images[id]
		for _,labels in pairs(self.pendingLabels) do
			for i=#labels,1,-1 do if labels[i]==img then table.remove(labels,i) end end
		end
		img:Destroy(); self.images[id]=nil
	end
end
function ImageManager:Cleanup()
	for _,img in pairs(self.images) do img:Destroy() end
	self.images={}; self.assetCache={}; self.pendingResolve={}; self.pendingLabels={}
	if self.screenGui then self.screenGui:Destroy(); self.screenGui=nil end
end
ImageManager:Init()

local function IsPartVisible(part)
	if not part or not part.Parent then return false end
	if not character or not character.Parent then return false end
	local camPos  = Camera.CFrame.Position
	local partPos = part.Position
	local dir     = partPos - camPos
	local ray     = Ray.new(camPos, dir)
	local hit     = workspace:FindPartOnRayWithIgnoreList(ray,{part.Parent,character})
	return hit==nil or hit==part or hit:IsDescendantOf(part.Parent)
end

local function createDefaultSettings()
	return {
		box         = {enabled=false,transparency=1,color=Color3.new(1,1,1),thickness=1},
		boxoutline  = {enabled=false,transparency=1,color=Color3.new(0,0,0),thickness=1},
		healthbar   = {
			enabled=false,dynamiccolor=true,
			healthcolor=Color3.new(0,1,0),backgroundcolor=Color3.new(0,0,0),
			borderthickness=1,width=1,gap=3,backgroundenabled=true,
			healthtext={enabled=false,size=9,color=Color3.new(1,1,1),
						outline=true,outlinecolor=Color3.new(0,0,0),usedynamiccolor=false}
		},
		weaponimage = {enabled=false,size=32,transparency=1,gap=4},
		text        = {spacing=2,flags={padding=4,spacing=3},
					   priority={top={},bottom={},flags={}}},
		name     = {enabled=false,top=true, transparency=1,color=Color3.new(1,1,1),size=11,outline=true,outlinecolor=Color3.new(0,0,0),priority=1},
		distance = {enabled=false,top=false,transparency=1,color=Color3.new(1,1,1),size=11,outline=true,outlinecolor=Color3.new(0,0,0),priority=1},
		weapon   = {enabled=false,top=false,transparency=1,color=Color3.new(1,1,1),size=11,outline=true,outlinecolor=Color3.new(0,0,0),priority=2},
		testing  = {enabled=false,transparency=1,color=Color3.new(0,0,0),size=11,outline=true,outlinecolor=Color3.new(0,0,0),priority=1},
		skeleton = {enabled=false,transparency=1,color=Color3.new(1,1,1),thickness=1},
		chams    = {
			enabled=false,color=Color3.fromHex("#7385ff"),transparency=0.3,
			glow=true,glowcolor=Color3.fromHex("#73b8ff"),updatefrequency=2,
			vischeck={enabled=false,bodypart="Head",
					  visiblecolor=Color3.new(0,1,0),notvisiblecolor=Color3.new(1,0,0),
					  visibleglowcolor=Color3.new(0,1,0),notvisibleglowcolor=Color3.new(1,0,0),
					  updatefrequency=0.1}
		},
		imagebox = {enabled=false,url="",transparency=1,color=Color3.new(1,1,1),rounding=0},
		oofarrows= {enabled=false,radius=200,size=UDim2.new(0,40,0,40),
					image="rbxassetid://7566538552",transparency=1,
					color=Color3.fromRGB(255,255,255),rotation=true,testmode=false},
		vischeckimage = {enabled=false,bodypart="Head",visibleimage="",notvisibleimage="",
						 visiblecolor=Color3.fromRGB(255,255,255),notvisiblecolor=Color3.fromRGB(255,255,255),
						 size=24,gap=4,updatefrequency=0.1,priority=1},
		healthcheck = false,
	}
end

local Fonts = {}
local function _RegisterFontFile(name,weight,style,asset)
	if getcustomasset then
		if not isfile(asset.Id) then writefile(asset.Id,asset.Font) end
		local data = {name=name,faces={{name="Regular",weight=weight,style=style,assetId=getcustomasset(asset.Id)}}}
		writefile(name..".font",game:GetService("HttpService"):JSONEncode(data))
		return getcustomasset(name..".font")
	else
		return Font.new("rbxasset://fonts/families/Ubuntu.json",Enum.FontWeight.Bold)
	end
end
Fonts.SmallestPixel = Font.new("rbxasset://fonts/families/SourceSansPro.json",Enum.FontWeight.Regular)
Fonts.Pixel         = Font.new("rbxasset://fonts/families/Ubuntu.json",Enum.FontWeight.Bold)

local EntityType = {}
EntityType.__index = EntityType

function EntityType.new(name, customSettings)
	local self = setmetatable({},EntityType)
	self.name    = name
	self.enabled = true
	self.settings = createDefaultSettings()

	if customSettings then
		for k,v in pairs(customSettings) do
			if self.settings[k] then
				if type(v)=="table" then
					for sk,sv in pairs(v) do self.settings[k][sk]=sv end
				else
					self.settings[k]=v
				end
			end
		end
	end

	for textType,data in pairs(self.settings) do
		if type(data)=="table" and type(data.priority)=="number" then
			if data.top==true then
				self.settings.text.priority.top[textType]=data.priority
			elseif data.top==false then
				self.settings.text.priority.bottom[textType]=data.priority
			else
				self.settings.text.priority.flags[textType]=data.priority
			end
		end
	end

	self.entities = {
		box={},boxoutline={},healthbar={},healthbarbackground={},healthbartext={},
		skeleton={},chams={},imagebox={},oofarrows={},vischeckimage={},weaponimage={},
		images={top={},bottom={},flags={}},
		text  ={top={},bottom={},flags={}}
	}

	for textType,data in pairs(self.settings) do
		if type(data)=="table" and data.priority~=nil then
			if self.settings.text.priority.flags[textType] then
				self.entities.text.flags[textType]={}; self.entities.images.flags[textType]={}
			elseif data.top==true then
				self.entities.text.top[textType]={}; self.entities.images.top[textType]={}
			elseif data.top==false then
				self.entities.text.bottom[textType]={}; self.entities.images.bottom[textType]={}
			end
		end
	end

	self.valid={};self.validr6={};self.isModel={};self.isPart={}
	self.displayNames={};self.customData={}
	self.mins={};self.maxes={};self.onscreens={}
	self.textoffsets={};self.imageoffsets={}
	self.connections={};self.deathConnections={}

	self._chamAdornments = {}
	self._chamLastKey     = {}
	return self
end

function EntityType:CalculateTextOffsets(id,min,max)
	self.textoffsets[id]  = {top={},bottom={},flags={}}
	self.imageoffsets[id] = {top={},bottom={},flags={}}

	for textType,priority in pairs(self.settings.text.priority.top) do
		if self.settings[textType] and self.settings[textType].enabled then
			local loc=priority
			for i,v in pairs(self.settings.text.priority.top) do
				if v<priority and self.settings[i] and not self.settings[i].enabled then loc=loc-1 end
			end
			self.textoffsets[id].top[textType]={location=loc,offset=(self.settings.text.spacing+self.settings[textType].size)*loc}
		end
	end

	for textType,priority in pairs(self.settings.text.priority.bottom) do
		if self.settings[textType] and self.settings[textType].enabled then
			local loc=priority
			for i,v in pairs(self.settings.text.priority.bottom) do
				if v<priority and self.settings[i] and not self.settings[i].enabled then loc=loc-1 end
			end
			local offset=self.settings.text.spacing+(self.settings.text.spacing+self.settings[textType].size)*(loc-1)
			self.textoffsets[id].bottom[textType]={location=loc,offset=offset}
		end
	end

	local enabledFlags={}
	for textType,priority in pairs(self.settings.text.priority.flags) do
		if self.settings[textType] and self.settings[textType].enabled then
			table.insert(enabledFlags,{name=textType,priority=priority,height=self.settings[textType].size})
		end
	end
	table.sort(enabledFlags,function(a,b) return a.priority<b.priority end)
	local cum=self.settings.text.flags.padding
	for _,item in ipairs(enabledFlags) do
		self.textoffsets[id].flags[item.name]={location=_,offset=cum}
		cum=cum+item.height+self.settings.text.flags.spacing
	end
end

function EntityType:IsValid(target,id)
	if not target or not target.Parent then return false end
	if self.isPart[id] then return true end

	if self.settings.healthcheck then
		local hum = target:FindFirstChildOfClass("Humanoid")
		if not hum or not (hum.Health > 0) then return false end
	else
		local hum = target:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 then return false end
	end
	return true
end

function EntityType:CheckR6(char)
	return char:FindFirstChild("Torso") ~= nil
end

local Friends = {}

local heldItemImages = {
	["Bruno's M4A1"]="rbxassetid://15574295393",["Crossbow"]="rbxassetid://15305596532",
	["Salvaged Shovel"]="rbxassetid://15073386763",["Salvaged Pipe Rifle"]="rbxassetid://15092314723",
	["Steel Axe"]="rbxassetid://15132541486",["Salvaged RPG"]="rbxassetid://15132772506",
	["Small Medkit"]="rbxassetid://15132566142",["Yellow Keycard"]="rbxassetid://15303938691",
	["Salvaged Pump Action"]="rbxassetid://15092313032",["Pink Keycard"]="rbxassetid://15303938752",
	["Salvaged SMG"]="rbxassetid://15132874040",["Salvaged AK47"]="rbxassetid://14882620172",
	["Boulder"]="rbxassetid://15304806846",["Care Package Signal"]="rbxassetid://15132798244",
	["Salvaged AK74u"]="rbxassetid://15073408197",["Dynamite Stick"]="rbxassetid://15127430886",
	["Military Barrett"]="rbxassetid://15346280030",["Nail Gun"]="rbxassetid://15305104734",
	["Iron Shard Hatchet"]="rbxassetid://15132541025",["Military M4A1"]="rbxassetid://15346201415",
	["Wooden Spear"]="rbxassetid://15303292373",["Dynamite Bundle"]="rbxassetid://15127431071",
	["Stone Spear"]="rbxassetid://15303292549",["Salvaged P250"]="rbxassetid://15305065991",
	["Iron Shard Pickaxe"]="rbxassetid://15132541267",["Military PKM"]="rbxassetid://15346287550",
	["Steel Shovel"]="rbxassetid://15132541679",["Timed Charge"]="rbxassetid://15132620220",
	["Steel Pickaxe"]="rbxassetid://15132541554",["Lighter"]="rbxassetid://15128007580",
	["Blueprint"]="rbxassetid://15132469785",["Salvaged M14"]="rbxassetid://14882876522",
	["Machete"]="rbxassetid://16249771824",["Stone Hatchet"]="rbxassetid://15073617325",
	["Bandage"]="rbxassetid://14134567329",["Saw Bat"]="rbxassetid://16249771997",
	["Wooden Bow"]="rbxassetid://15313266356",["Military Grenade"]="rbxassetid://15346283342",
	["Health Pen"]="rbxassetid://15304289469",["Candy Cane"]="rbxassetid://15132567147",
	["Hammer"]="rbxassetid://15318044673",["Military AA12"]="rbxassetid://15346289730",
	["Salvaged Python"]="rbxassetid://15188995729",["Purple Keycard"]="rbxassetid://15303938707",
	["Bone Tool"]="rbxassetid://15073616534",["Stone Pickaxe"]="rbxassetid://15073617163",
	["Salvaged Skorpion"]="rbxassetid://15369212859",["Salvaged Break Action"]="rbxassetid://15188994406",
}

local ESP = {
	entityTypes={},
	whitelistedWeapons={},
	renderConnection=nil,
	chamsRunning=false,
	Enabled=true,
	Friends=Friends,
	heldItemImages=heldItemImages,
	Fonts=Fonts,
	activeFont=Fonts.Pixel,
	chamsContainer=nil,
}

function ESP:SetFont(n)
	if type(n)=="string" then
		self.activeFont=self.Fonts[n] or self.Fonts.Pixel
	else
		self.activeFont=n
	end
end
function ESP:SetEnabled(e) self.Enabled=e end

function ESP:CreateEntityType(name,customSettings)
	if self.entityTypes[name] then return self.entityTypes[name] end
	local et = EntityType.new(name,customSettings)
	self.entityTypes[name]=et
	return et
end
function ESP:GetEntityType(name) return self.entityTypes[name] end

function ESP:RemoveEntityType(name)
	local et=self.entityTypes[name]; if not et then return end
	for id in pairs(et.valid) do self:_RemoveAllESP(et,id) end
	for _,c in pairs(et.connections) do if c then c:Disconnect() end end
	for _,c in pairs(et.deathConnections) do if c then c:Disconnect() end end
	self.entityTypes[name]=nil
end

function ESP:SetEntityTypeEnabled(name,enabled)
	local et=self.entityTypes[name]; if et then et.enabled=enabled end
end

function ESP:TrackPlayer(player,entityTypeName)
	entityTypeName=entityTypeName or "players"
	local et=self.entityTypes[entityTypeName]
	if not et then return end
	if player==lp then return end
	for _,fid in ipairs(self.Friends) do if player.UserId==fid then return end end

	local id=player.UserId
	local function onChar(char)
		et.valid[id]         = char
		et.validr6[id]       = et:CheckR6(char)
		et.isModel[id]       = false
		et.isPart[id]        = false
		et.displayNames[id]  = player.Name
		if et.deathConnections[id] then et.deathConnections[id]:Disconnect() end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			et.deathConnections[id] = hum.Died:Connect(function()
				self:_CleanChams(et,id)
			end)
		end
	end
	if player.Character then onChar(player.Character) end
	et.connections[id]=player.CharacterAdded:Connect(onChar)
end

function ESP:TrackModel(entityTypeName,model,displayName)
	local et=self.entityTypes[entityTypeName]; if not et then return end
	if not model or not model:IsA("Model") then return end
	local id=HttpService:GenerateGUID(false)
	et.valid[id]=model; et.isModel[id]=true; et.isPart[id]=false
	et.displayNames[id]=displayName or model.Name
	et.connections[id]=model.AncestryChanged:Connect(function(_,p)
		if not p then self:Untrack(entityTypeName,id) end
	end)
	return id
end

function ESP:TrackPart(entityTypeName,part,displayName)
	local et=self.entityTypes[entityTypeName]; if not et then return end
	if not part or not part:IsA("BasePart") then return end
	local id=HttpService:GenerateGUID(false)
	et.valid[id]=part; et.isModel[id]=false; et.isPart[id]=true
	et.displayNames[id]=displayName or part.Name
	et.connections[id]=part.AncestryChanged:Connect(function(_,p)
		if not p then self:Untrack(entityTypeName,id) end
	end)
	return id
end

function ESP:TrackModels(entityTypeName,models,getDisplayName)
	local ids={}
	for _,m in pairs(models) do
		table.insert(ids, self:TrackModel(entityTypeName,m,getDisplayName and getDisplayName(m) or m.Name))
	end
	return ids
end

function ESP:Untrack(entityTypeName,id)
	local et=self.entityTypes[entityTypeName]; if not et then return end
	self:_RemoveAllESP(et,id)
	et.valid[id]=nil;et.validr6[id]=nil;et.isModel[id]=nil;et.isPart[id]=nil
	et.displayNames[id]=nil;et.customData[id]=nil
	et.mins[id]=nil;et.maxes[id]=nil;et.onscreens[id]=nil
	et.textoffsets[id]=nil;et.imageoffsets[id]=nil
	et._chamLastKey[id]=nil
	if et.connections[id] then et.connections[id]:Disconnect(); et.connections[id]=nil end
	if et.deathConnections[id] then et.deathConnections[id]:Disconnect(); et.deathConnections[id]=nil end
end

function ESP:UntrackAll(entityTypeName)
	local et=self.entityTypes[entityTypeName]; if not et then return end
	for id in pairs(et.valid) do self:Untrack(entityTypeName,id) end
end

function ESP:SetSetting(n,cat,k,v) local et=self.entityTypes[n]; if et and et.settings[cat] then et.settings[cat][k]=v end end
function ESP:GetSetting(n,cat,k)  local et=self.entityTypes[n]; if et and et.settings[cat] then return et.settings[cat][k] end end
function ESP:UpdateSettings(n,settings)
	local et=self.entityTypes[n]; if not et then return end
	for cat,vals in pairs(settings) do if et.settings[cat] then for k,v in pairs(vals) do et.settings[cat][k]=v end end end
end
function ESP:SetPlayerSetting(cat,k,v) self:SetSetting("players",cat,k,v) end
function ESP:GetPlayerSetting(cat,k)   return self:GetSetting("players",cat,k) end
function ESP:SetCustomData(n,id,k,v)
	local et=self.entityTypes[n]; if not et then return end
	if not et.customData[id] then et.customData[id]={} end; et.customData[id][k]=v
end
function ESP:GetCustomData(n,id,k)
	local et=self.entityTypes[n]; if not et then return nil end
	return et.customData[id] and et.customData[id][k]
end
function ESP:GetTrackedIDs(n)
	local et=self.entityTypes[n]; if not et then return {} end
	local ids={}; for id in pairs(et.valid) do table.insert(ids,id) end; return ids
end
function ESP:GetDisplayName(n,id) local et=self.entityTypes[n]; return et and et.displayNames[id] or "Unknown" end
function ESP:SetDisplayName(n,id,name) local et=self.entityTypes[n]; if et then et.displayNames[id]=name end end

local function HealthColor(pct)
	pct=math.clamp(pct,0,1)
	if pct>=0.5 then return Color3.new(1-(pct-0.5)*2,1,0)
	else return Color3.new(1,pct*2,0) end
end

local function newText(et,textType)
	local t=Drawing.new("Text")
	pcall(function() t.FontFace=ESP.activeFont end)
	t.Outline=true
	t.Size=et.settings[textType].size
	t.Color=et.settings[textType].color
	t.OutlineColor=et.settings[textType].outlinecolor
	t.Transparency=et.settings[textType].transparency
	t.Outline=et.settings[textType].outline
	t.Visible=false
	return t
end

function ESP:_HandleBox(et,id)
	local min,max,on=et.mins[id],et.maxes[id],et.onscreens[id]
	local s=et.settings.box
	local so=et.settings.boxoutline
	local isValid=et:IsValid(et.valid[id],id)
	local show=on and s.enabled and isValid

	if not et.entities.box[id] then
		local outline=Drawing.new("Square"); outline.Visible=false
		local box=Drawing.new("Square"); box.Visible=false
		et.entities.box[id]=box; et.entities.boxoutline[id]=outline
	end

	local box=et.entities.box[id]; local outline=et.entities.boxoutline[id]
	if show then
		local ss=Camera.ViewportSize
		local clampedMinX=math.clamp(min.x,0,ss.X)
		local clampedMinY=math.clamp(min.y,0,ss.Y)
		local clampedMaxX=math.clamp(max.x,0,ss.X)
		local clampedMaxY=math.clamp(max.y,0,ss.Y)
		local pos=Vector2.new(clampedMinX,clampedMinY)
		local sz=Vector2.new(clampedMaxX-clampedMinX,clampedMaxY-clampedMinY)
		box.Position=pos; box.Size=sz
		box.Thickness=s.thickness; box.Color=s.color; box.Transparency=s.transparency
		box.Visible=true
		if so.enabled then
			outline.Position=pos; outline.Size=sz
			outline.Thickness=s.thickness+so.thickness*2
			outline.Color=so.color; outline.Transparency=so.transparency
			outline.Visible=true
		else outline.Visible=false end
	else box.Visible=false; outline.Visible=false end
end

function ESP:_HandleHealthbar(et,id)
	local min,max,on=et.mins[id],et.maxes[id],et.onscreens[id]
	local s=et.settings.healthbar
	local isValid=et:IsValid(et.valid[id],id)
	local show=on and s.enabled and isValid

	if not et.entities.healthbar[id] then
		local bg=Drawing.new("Square"); bg.Filled=true; bg.Visible=false
		local bar=Drawing.new("Square"); bar.Filled=true; bar.Visible=false
		local htxt=Drawing.new("Text"); htxt.Visible=false; htxt.Center=true
		pcall(function() htxt.FontFace=ESP.activeFont end)
		et.entities.healthbarbackground[id]=bg
		et.entities.healthbar[id]=bar
		et.entities.healthbartext[id]=htxt
	end

	local bg=et.entities.healthbarbackground[id]
	local bar=et.entities.healthbar[id]
	local htxt=et.entities.healthbartext[id]

	if show then
		local target=et.valid[id]
		local hum=target:FindFirstChildOfClass("Humanoid")
		local hp=hum and hum.Health or 100
		local mhp=hum and hum.MaxHealth or 100
		local pct=(mhp>0) and (hp/mhp) or 0
		local left=min.x-s.gap-s.width-s.borderthickness
		local height=max.y-min.y
		local healthchange=height*(1-pct)

		if s.backgroundenabled then
			bg.Position=Vector2.new(left-s.borderthickness,min.y-s.borderthickness)
			bg.Size=Vector2.new(s.width+s.borderthickness*2,height+s.borderthickness*2)
			bg.Color=s.backgroundcolor; bg.Transparency=1; bg.Visible=true
		else bg.Visible=false end

		bar.Position=Vector2.new(left,min.y+healthchange)
		bar.Size=Vector2.new(s.width,math.max(0,height-healthchange))
		bar.Color=s.dynamiccolor and HealthColor(pct) or s.healthcolor
		bar.Transparency=1; bar.Visible=true

		if s.healthtext.enabled then
			local hs=s.healthtext
			htxt.Text=tostring(math.floor(hp+0.5))
			htxt.Color=(hs.usedynamiccolor) and HealthColor(pct) or hs.color
			htxt.Size=hs.size; htxt.Outline=hs.outline; htxt.OutlineColor=hs.outlinecolor
			htxt.Position=Vector2.new(left-s.borderthickness-12,min.y+healthchange)
			htxt.Visible=true
		else htxt.Visible=false end
	else
		bar.Visible=false; bg.Visible=false; if htxt then htxt.Visible=false end
	end
end

function ESP:_HandleText(et,id,textType)
	local setting=et.settings[textType]
	if type(setting)~="table" or not setting.color or setting.priority==nil then return end

	local place
	if et.settings.text.priority.flags[textType] then place="flags"
	elseif setting.top==true then place="top"
	else place="bottom" end

	local root=et.entities.text
	root[place]=root[place] or {}
	root[place][textType]=root[place][textType] or {}

	local min,max,on=et.mins[id],et.maxes[id],et.onscreens[id]
	local isValid=et:IsValid(et.valid[id],id)
	local show=on and setting.enabled and isValid

	if not root[place][textType][id] then
		root[place][textType][id]=newText(et,textType)
		root[place][textType][id].Center=(place~="flags")
	end

	local txt=root[place][textType][id]
	txt.Visible=show

	if show and et.textoffsets[id] and et.textoffsets[id][place][textType] then
		txt.Color=setting.color; txt.Size=setting.size
		txt.Transparency=setting.transparency
		txt.Outline=setting.outline; txt.OutlineColor=setting.outlinecolor

		local offset=et.textoffsets[id][place][textType].offset
		local cx=min.x+(max.x-min.x)/2

		if textType=="name" then
			txt.Text=et.displayNames[id] or "Unknown"
		elseif textType=="distance" and character then
			local target=et.valid[id]
			local tp=target:IsA("Model") and target:GetPivot().Position
					   or (target:IsA("BasePart") and target.Position or target.Position)
			txt.Text="["..tostring(math.round((character:GetPivot().Position-tp).Magnitude)).." m]"
		elseif textType=="weapon" then
			txt.Text="["..(self:_GetWeaponName(et.valid[id]) or "None").."]"
		else
			txt.Text="["..textType:upper().."]"
		end

		if place=="flags" then
			txt.Position=Vector2.new(max.x, min.y+offset)
		elseif place=="top" then
			txt.Position=Vector2.new(cx, min.y-offset)
		else
			txt.Position=Vector2.new(cx, max.y+offset)
		end
	end
end

local function makeLines(names)
	local t={}
	for _,n in ipairs(names) do
		local l=Drawing.new("Line")
		l.Visible=false; l.From=Vector2.zero; l.To=Vector2.one
		t[n]={line=l}
	end
	return t
end

local R6_BONES = {"Head_Spine","Spine","LeftArm","LeftArm_UpperTorso",
				  "RightArm","RightArm_UpperTorso","LeftLeg","LeftLeg_LowerTorso",
				  "RightLeg","RightLeg_LowerTorso"}

local R15_BONES = {"Head_UpperTorso","UpperTorso_LowerTorso",
				   "UpperTorso_LeftUpperArm","LeftUpperArm_LeftLowerArm","LeftLowerArm_LeftHand",
				   "UpperTorso_RightUpperArm","RightUpperArm_RightLowerArm","RightLowerArm_RightHand",
				   "LowerTorso_LeftUpperLeg","LeftUpperLeg_LeftLowerLeg","LeftLowerLeg_LeftFoot",
				   "LowerTorso_RightUpperLeg","RightUpperLeg_RightLowerLeg","RightLowerLeg_RightFoot"}

local function vp(part)
	if not part then return nil end
	local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
	if sp.Z <= 0 then return nil end
	return Vector2.new(sp.X, sp.Y)
end

function ESP:_HandleSkeleton(et,id)
	local target=et.valid[id]
	local min,max,on=et.mins[id],et.maxes[id],et.onscreens[id]
	local isValid=et:IsValid(target,id)
	local show=on and et.settings.skeleton.enabled and isValid

	if not et.entities.skeleton[id] then
		et.entities.skeleton[id]={
			r6  = makeLines(R6_BONES),
			r15 = makeLines(R15_BONES),
		}
	end

	local bones=et.entities.skeleton[id]

	if not show or not target or not target.Parent then
		for _,b in pairs(bones.r6)  do b.line.Visible=false end
		for _,b in pairs(bones.r15) do b.line.Visible=false end
		return
	end

	local isR6 = target:FindFirstChild("Torso") ~= nil
	et.validr6[id] = isR6

	for _,b in pairs(isR6 and bones.r15 or bones.r6) do b.line.Visible=false end

	local active = isR6 and bones.r6 or bones.r15

	local sc=et.settings.skeleton.color
	local st=et.settings.skeleton.transparency
	local sth=et.settings.skeleton.thickness
	for _,b in pairs(active) do
		b.line.Color=sc; b.line.Transparency=st; b.line.Thickness=sth
	end

	if isR6 then
		local H  = vp(target:FindFirstChild("Head"))
		local T  = target:FindFirstChild("Torso")
		local UT = T and Camera:WorldToViewportPoint((T.CFrame*CFrame.new(0,T.Size.Y/4,0)).Position)
		local LT = T and Camera:WorldToViewportPoint((T.CFrame*CFrame.new(0,-T.Size.Y/4,0)).Position)
		local LA = target:FindFirstChild("Left Arm")
		local RA = target:FindFirstChild("Right Arm")
		local LL = target:FindFirstChild("Left Leg")
		local RL = target:FindFirstChild("Right Leg")

		if not (H and T and LA and RA and LL and RL) then
			for _,b in pairs(active) do b.line.Visible=false end; return
		end

		if not UT or UT.Z <= 0 or not LT or LT.Z <= 0 then
			for _,b in pairs(active) do b.line.Visible=false end; return
		end

		local UTv=Vector2.new(UT.X,UT.Y)
		local LTv=Vector2.new(LT.X,LT.Y)
		local function limb(part)
			local hy=part.Size.Y/2-0.2
			local top=Camera:WorldToViewportPoint((part.CFrame*CFrame.new(0,hy,0)).Position)
			local bot=Camera:WorldToViewportPoint((part.CFrame*CFrame.new(0,-hy,0)).Position)
			if top.Z <= 0 or bot.Z <= 0 then return nil, nil end
			return Vector2.new(top.X,top.Y), Vector2.new(bot.X,bot.Y)
		end
		local LUA,LLA=limb(LA); local RUA,RLA=limb(RA)
		local LUL,LLL=limb(LL); local RUL,RLL=limb(RL)

		local function setLine(name,f,t)
			if f and t then
				active[name].line.From=f; active[name].line.To=t; active[name].line.Visible=true
			else active[name].line.Visible=false end
		end
		setLine("Head_Spine",H,UTv)
		setLine("Spine",UTv,LTv)
		setLine("LeftArm",LUA,LLA); setLine("LeftArm_UpperTorso",UTv,LUA)
		setLine("RightArm",RUA,RLA); setLine("RightArm_UpperTorso",UTv,RUA)
		setLine("LeftLeg",LUL,LLL); setLine("LeftLeg_LowerTorso",LTv,LUL)
		setLine("RightLeg",RUL,RLL); setLine("RightLeg_LowerTorso",LTv,RUL)
	else
		local H   = vp(target:FindFirstChild("Head"))
		local UT  = vp(target:FindFirstChild("UpperTorso"))
		local LT  = vp(target:FindFirstChild("LowerTorso"))
		if not (H and UT and LT) then
			for _,b in pairs(active) do b.line.Visible=false end; return
		end

		local LUA = vp(target:FindFirstChild("LeftUpperArm"))
		local LLA = vp(target:FindFirstChild("LeftLowerArm"))
		local LH  = vp(target:FindFirstChild("LeftHand"))
		local RUA = vp(target:FindFirstChild("RightUpperArm"))
		local RLA = vp(target:FindFirstChild("RightLowerArm"))
		local RH  = vp(target:FindFirstChild("RightHand"))
		local LUL = vp(target:FindFirstChild("LeftUpperLeg"))
		local LLL = vp(target:FindFirstChild("LeftLowerLeg"))
		local LF  = vp(target:FindFirstChild("LeftFoot"))
		local RUL = vp(target:FindFirstChild("RightUpperLeg"))
		local RLL = vp(target:FindFirstChild("RightLowerLeg"))
		local RF  = vp(target:FindFirstChild("RightFoot"))

		local function setLine(name,f,t)
			if f and t then
				active[name].line.From=f; active[name].line.To=t; active[name].line.Visible=true
			else active[name].line.Visible=false end
		end
		setLine("Head_UpperTorso",H,UT)
		setLine("UpperTorso_LowerTorso",UT,LT)
		setLine("UpperTorso_LeftUpperArm",UT,LUA); setLine("LeftUpperArm_LeftLowerArm",LUA,LLA); setLine("LeftLowerArm_LeftHand",LLA,LH)
		setLine("UpperTorso_RightUpperArm",UT,RUA); setLine("RightUpperArm_RightLowerArm",RUA,RLA); setLine("RightLowerArm_RightHand",RLA,RH)
		setLine("LowerTorso_LeftUpperLeg",LT,LUL); setLine("LeftUpperLeg_LeftLowerLeg",LUL,LLL); setLine("LeftLowerLeg_LeftFoot",LLL,LF)
		setLine("LowerTorso_RightUpperLeg",LT,RUL); setLine("RightUpperLeg_RightLowerLeg",RUL,RLL); setLine("RightLowerLeg_RightFoot",RLL,RF)
	end
end

function ESP:_HandleImageBox(et,id)
	local min,max,on=et.mins[id],et.maxes[id],et.onscreens[id]
	local s=et.settings.imagebox
	local isValid=et:IsValid(et.valid[id],id)
	local show=on and s.enabled and isValid

	local key="imagebox_"..id
	local img=ImageManager:GetImage(key)
	if not img then img=ImageManager:CreateImage(key) end
	if s.url and s.url~="" then ImageManager:SetImageAsync(img,s.url) end
	img.Visible=show
	if show then
		img.ImageTransparency=1-s.transparency; img.ImageColor3=s.color
		img.Size=UDim2.new(0,max.x-min.x,0,max.y-min.y)
		img.Position=UDim2.new(0,min.x,0,min.y)
	end
end

function ESP:_HandleOOFArrows(et,id,target)
	local s=et.settings.oofarrows
	local key="oofarrow_"..id
	if not s.enabled then
		local a=ImageManager:GetImage(key); if a then a.Visible=false end; return
	end
	local targetPos
	if et.isPart[id] then targetPos=target.Position
	else
		local hrp=target:FindFirstChild("HumanoidRootPart")
		if not hrp then local a=ImageManager:GetImage(key); if a then a.Visible=false end; return end
		targetPos=hrp.Position
	end
	local sp,onScreen=Camera:WorldToViewportPoint(targetPos)
	local ss=Camera.ViewportSize
	local reallyOn=onScreen and sp.X>50 and sp.X<ss.X-50 and sp.Y>50 and sp.Y<ss.Y-50 and sp.Z>0
	if reallyOn then local a=ImageManager:GetImage(key); if a then a.Visible=false end; return end

	local camCF=Camera.CFrame
	local to=targetPos-camCF.Position
	local dist=to.Magnitude
	local flat=Vector3.new(to.X,0,to.Z)
	flat=(flat.Magnitude>0.01) and flat.Unit or camCF.LookVector
	local fwd=Vector3.new(camCF.LookVector.X,0,camCF.LookVector.Z)
	fwd=(fwd.Magnitude>0.01) and fwd.Unit or Vector3.new(0,0,1)
	local right=Vector3.new(camCF.RightVector.X,0,camCF.RightVector.Z)
	right=(right.Magnitude>0.01) and right.Unit or Vector3.new(1,0,0)
	local dotUp=to.Y/dist
	local rot
	if math.abs(dotUp)>0.5 then rot=dotUp<0 and 180 or 0
	else rot=math.deg(math.atan2(flat:Dot(right),flat:Dot(fwd))) end
	local angle=math.rad(rot)
	local ax=ss.X/2+math.sin(angle)*s.radius
	local ay=ss.Y/2-math.cos(angle)*s.radius

	local arrow=ImageManager:GetImage(key)
	if not arrow then
		arrow=ImageManager:CreateImage(key)
		ImageManager:SetImageAsync(arrow,s.image)
		arrow.AnchorPoint=Vector2.new(0.5,0.5); arrow.ZIndex=10; arrow.BackgroundTransparency=1
	end
	arrow.ImageTransparency=1-s.transparency; arrow.ImageColor3=s.color; arrow.Size=s.size
	arrow.Position=UDim2.new(0,ax,0,ay)
	if s.rotation then arrow.Rotation=rot end
	arrow.Visible=true
end

function ESP:_HandleVischeckImage(et,id,target)
	local s=et.settings.vischeckimage
	local key="vischeckimage_"..id
	if not s.enabled then local i=ImageManager:GetImage(key); if i then i.Visible=false end; return end
	local min,max,on=et.mins[id],et.maxes[id],et.onscreens[id]
	local isValid=et:IsValid(target,id)
	if not on or not isValid then local i=ImageManager:GetImage(key); if i then i.Visible=false end; return end

	if not self._vischeckState then self._vischeckState={} end
	if not self._vischeckState[id] then self._vischeckState[id]={lastCheck=0,isVis=false,lastUrl=nil,lastColor=nil} end
	local state=self._vischeckState[id]
	local now=tick()
	if now-state.lastCheck>=(s.updatefrequency or 0.1) then
		state.lastCheck=now
		local p=target:FindFirstChild(s.bodypart or "Head")
		state.isVis=p~=nil and IsPartVisible(p)
	end
	local url=state.isVis and s.visibleimage or s.notvisibleimage
	local col=state.isVis and s.visiblecolor or s.notvisiblecolor
	if not url or url=="" then local i=ImageManager:GetImage(key); if i then i.Visible=false end; return end

	local img=ImageManager:GetImage(key)
	if not img then
		img=ImageManager:CreateImage(key)
		img.Size=UDim2.new(0,s.size or 24,0,s.size or 24)
		img.AnchorPoint=Vector2.new(0,0); img.ZIndex=10; img.BackgroundTransparency=1
	end
	if url~=state.lastUrl then ImageManager:SetImageAsync(img,url); state.lastUrl=url end
	if col~=state.lastColor then img.ImageColor3=col or Color3.new(1,1,1); state.lastColor=col end
	local offset=(et.textoffsets[id] and et.textoffsets[id].flags.vischeckimage) and et.textoffsets[id].flags.vischeckimage.offset or 0
	img.Position=UDim2.new(0,max.x+(s.gap or 4),0,min.y+offset); img.Visible=true
end

function ESP:_HandleWeaponImage(et,id,target)
	local s=et.settings.weaponimage
	local key="weaponimage_"..id
	local min,max=et.mins[id],et.maxes[id]
	local on=et.onscreens[id]; local isValid=et:IsValid(target,id)
	if not s.enabled or not on or not isValid then
		local i=ImageManager:GetImage(key); if i then i.Visible=false end; return
	end
	local wn=self:_GetWeaponName(target)
	local url=wn and self.heldItemImages[wn]
	if not url then local i=ImageManager:GetImage(key); if i then i.Visible=false end; return end

	local img=ImageManager:GetImage(key)
	if not img then
		img=ImageManager:CreateImage(key)
		img.AnchorPoint=Vector2.new(0.5,0); img.ZIndex=10; img.BackgroundTransparency=1
	end
	ImageManager:SetImageAsync(img,url)
	img.ImageTransparency=1-(s.transparency or 1)
	local sz=s.size or 32; img.Size=UDim2.new(0,sz,0,sz)

	local bottomEdge=max.y
	if et.textoffsets[id] then
		for textType,data in pairs(et.textoffsets[id].bottom) do
			local st=et.settings[textType]
			if st and st.enabled then
				local b=max.y+data.offset+st.size
				if b>bottomEdge then bottomEdge=b end
			end
		end
	end
	img.Position=UDim2.new(0,min.x+(max.x-min.x)/2,0,bottomEdge+(s.gap or 4))
	img.Visible=true
end

function ESP:_EnsureChamsContainer()
	if not self.chamsContainer or not self.chamsContainer.Parent then
		self.chamsContainer=Instance.new("Folder")
		self.chamsContainer.Name="RobloxGui"
		self.chamsContainer.Parent=CoreGui
	end
end

function ESP:_CleanChams(et,id)
	if et._chamAdornments[id] then
		for _,a in pairs(et._chamAdornments[id]) do
			if a and a.Parent then pcall(function() a:Destroy() end) end
		end
		et._chamAdornments[id]=nil
	end
	et._chamLastKey[id]=nil
end

function ESP:_UpdateChams(et,id,target)
	local s=et.settings.chams
	if not s.enabled then self:_CleanChams(et,id); return end
	if not target or not target.Parent then self:_CleanChams(et,id); return end
	if not et:IsValid(target,id) then self:_CleanChams(et,id); return end

	local mainColor=s.color; local glowColor=s.glowcolor
	local trans=s.transparency; local doGlow=s.glow

	if s.vischeck and s.vischeck.enabled then
		local cp=target:FindFirstChild(s.vischeck.bodypart or "Head")
		if cp then
			if IsPartVisible(cp) then
				mainColor=s.vischeck.visiblecolor; glowColor=s.vischeck.visibleglowcolor
			else
				mainColor=s.vischeck.notvisiblecolor; glowColor=s.vischeck.notvisibleglowcolor
			end
		end
	end

	local key=mainColor.R..mainColor.G..mainColor.B..tostring(doGlow)..tostring(trans)
	if et._chamLastKey[id]==key and et._chamAdornments[id] then return end

	self:_CleanChams(et,id)
	et._chamAdornments[id]={}
	self:_EnsureChamsContainer()

	for _,part in ipairs(target:GetChildren()) do
		if not part:IsA("BasePart") or part.Transparency>=1 then continue end
		local isHead=part.Name=="Head" or part.Name=="FakeHead"
		local function addorn(color,t,zIdx)
			local a
			if isHead then
				a=Instance.new("CylinderHandleAdornment")
				a.Height=part.Size.Y; a.Radius=part.Size.X*0.5
			else
				a=Instance.new("BoxHandleAdornment")
				a.Size=part.Size+Vector3.new(0.02,0.02,0.02)
			end
			a.Name="Chams"; a.AlwaysOnTop=true; a.ZIndex=zIdx
			a.Adornee=part; a.Color3=color; a.Transparency=t
			a.Parent=self.chamsContainer
			table.insert(et._chamAdornments[id],a)
		end
		if doGlow then addorn(Color3.new(glowColor.R*5,glowColor.G*5,glowColor.B*5),-1,9) end
		addorn(mainColor,trans,10)
	end
	et._chamLastKey[id]=key
end

function ESP:_GetWeaponName(target)
	local hum=target:FindFirstChildOfClass("Humanoid")
	if hum then local t=hum:FindFirstChildOfClass("Tool"); if t then return t.Name end end
	for _,c in pairs(target:GetChildren()) do if c:IsA("Tool") then return c.Name end end
	for wn in pairs(self.heldItemImages) do if target:FindFirstChild(wn) then return wn end end
	return nil
end

function ESP:_RemoveAllESP(et,id)
	for _,key in ipairs({"box","boxoutline","healthbar","healthbarbackground","healthbartext"}) do
		if et.entities[key] and et.entities[key][id] then
			pcall(function() et.entities[key][id]:Remove() end)
			et.entities[key][id]=nil
		end
	end

	if et.entities.skeleton[id] then
		local bones=et.entities.skeleton[id]
		for _,set in pairs({bones.r6,bones.r15}) do
			if set then for _,b in pairs(set) do pcall(function() b.line:Remove() end) end end
		end
		et.entities.skeleton[id]=nil
	end

	for _,place in ipairs({"top","bottom","flags"}) do
		for textType,texts in pairs(et.entities.text[place] or {}) do
			if texts[id] then pcall(function() texts[id]:Remove() end); texts[id]=nil end
		end
	end

	self:_CleanChams(et,id)

	ImageManager:RemoveImage("imagebox_"..id)
	ImageManager:RemoveImage("oofarrow_"..id)
	ImageManager:RemoveImage("vischeckimage_"..id)
	ImageManager:RemoveImage("weaponimage_"..id)
end

local ESP_RENDER_NAME = "ESP_Render"

function ESP:Start()
	pcall(function() setfflag("AdornShadingAPI","true") end)

	RunService:BindToRenderStep(
		ESP_RENDER_NAME, Enum.RenderPriority.Camera.Value+1,
		function()
			if not self.Enabled then
				for _,et in pairs(self.entityTypes) do
					for id in pairs(et.valid) do
						for _,key in ipairs({"box","boxoutline","healthbar","healthbarbackground","healthbartext"}) do
							if et.entities[key] and et.entities[key][id] then et.entities[key][id].Visible=false end
						end
						if et.entities.skeleton[id] then
							local bones=et.entities.skeleton[id]
							for _,set in pairs({bones.r6,bones.r15}) do
								if set then for _,b in pairs(set) do b.line.Visible=false end end
							end
						end
						for _,place in ipairs({"top","bottom","flags"}) do
							for _,texts in pairs(et.entities.text[place] or {}) do
								if texts[id] then texts[id].Visible=false end
							end
						end
						for _,key in ipairs({"imagebox_","oofarrow_","vischeckimage_","weaponimage_"}) do
							local img=ImageManager:GetImage(key..id); if img then img.Visible=false end
						end
					end
				end
				return
			end

			for _,et in pairs(self.entityTypes) do
				if not et.enabled then continue end
				for id,target in pairs(et.valid) do
					local isValid=et:IsValid(target,id)
					if not isValid then
						for _,key in ipairs({"box","boxoutline","healthbar","healthbarbackground","healthbartext"}) do
							if et.entities[key] and et.entities[key][id] then et.entities[key][id].Visible=false end
						end
						if et.entities.skeleton[id] then
							local bones=et.entities.skeleton[id]
							for _,set in pairs({bones.r6,bones.r15}) do
								if set then for _,b in pairs(set) do b.line.Visible=false end end
							end
						end
						for _,place in ipairs({"top","bottom","flags"}) do
							for _,texts in pairs(et.entities.text[place] or {}) do
								if texts[id] then texts[id].Visible=false end
							end
						end
						for _,key in ipairs({"imagebox_","oofarrow_","vischeckimage_","weaponimage_"}) do
							local img=ImageManager:GetImage(key..id); if img then img.Visible=false end
						end
						self:_CleanChams(et,id)
						continue
					end

					local isModel=et.isModel[id] or (not et.isPart[id])
					local isPart =et.isPart[id]
					local min,max,on=Math.getcorners(target,isModel,isPart)
					et.mins[id]=min; et.maxes[id]=max; et.onscreens[id]=on

					et:CalculateTextOffsets(id,min,max)

					self:_HandleBox(et,id)
					self:_HandleHealthbar(et,id)
					self:_HandleSkeleton(et,id)
					self:_HandleImageBox(et,id)
					self:_HandleOOFArrows(et,id,target)
					self:_HandleVischeckImage(et,id,target)
					self:_HandleWeaponImage(et,id,target)

					for textType,data in pairs(et.settings) do
						if type(data)=="table" and data.priority~=nil then
							self:_HandleText(et,id,textType)
						end
					end
				end
			end
		end
	)

	self.chamsRunning=true
	task.spawn(function()
		while self.chamsRunning do
			local wait=2
			for _,et in pairs(self.entityTypes) do
				if et.enabled and et.settings.chams then
					local cw=et.settings.chams.updatefrequency or 2
					if et.settings.chams.vischeck and et.settings.chams.vischeck.enabled then
						cw=math.min(cw,et.settings.chams.vischeck.updatefrequency or cw)
					end
					wait=math.min(wait,cw)
				end
			end
			for _,et in pairs(self.entityTypes) do
				if not et.enabled then continue end
				for id,target in pairs(et.valid) do
					if et:IsValid(target,id) then
						self:_UpdateChams(et,id,target)
					else
						self:_CleanChams(et,id)
					end
				end
			end
			task.wait(wait)
		end
	end)
end

function ESP:Stop()
	self.chamsRunning=false
	RunService:UnbindFromRenderStep(ESP_RENDER_NAME)
	for _,et in pairs(self.entityTypes) do
		for id in pairs(et.valid) do self:_RemoveAllESP(et,id) end
	end
	ImageManager:Cleanup()
	if self.chamsContainer and self.chamsContainer.Parent then
		self.chamsContainer:Destroy(); self.chamsContainer=nil
	end
end

ESP:CreateEntityType("players")

Players.PlayerAdded:Connect(function(p)    ESP:TrackPlayer(p,"players") end)
Players.PlayerRemoving:Connect(function(p) ESP:Untrack("players",p.UserId) end)
for _,p in pairs(Players:GetPlayers()) do  ESP:TrackPlayer(p,"players") end

return ESP
