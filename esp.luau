-- ============================================================
--  ESP System - Clean Rewrite
--  Fixes: bounding-box clamping, weapon detection, degenerate
--         box rejection, chams container leak, tool lookup.
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui    = game:GetService("CoreGui")

local lp        = Players.LocalPlayer
local Camera    = workspace.CurrentCamera

-- ── local aliases ────────────────────────────────────────────
local mhuge  = math.huge
local mmin   = math.min
local mmax   = math.max
local mclamp = math.clamp
local mfloor = math.floor
local mabs   = math.abs
local mrad   = math.rad
local matan2 = math.atan2
local mround = math.round
local V2     = Vector2.new
local V3     = Vector3.new
local CF     = CFrame.new

-- ── local player character tracking ──────────────────────────
local localChar = lp.Character
lp.CharacterAdded:Connect(function(c) localChar = c end)

-- ════════════════════════════════════════════════════════════
--  MATH HELPERS
-- ════════════════════════════════════════════════════════════
local Math = {}

--[[
    Returns the 2-D screen bounding box for a target.
    Only on-screen corners (Z > 0) that fall within viewport
    bounds are counted – no clamping, no edge-piling.
    Returns min {x,y}, max {x,y}, anyOnScreen bool.
]]
function Math.GetCorners(target, isModel, isPart)
    local minX, minY =  mhuge,  mhuge
    local maxX, maxY = -mhuge, -mhuge
    local anyOn      = false
    local vp         = Camera.ViewportSize
    local vpX, vpY   = vp.X, vp.Y

    local function processPart(cf, hx, hy, hz)
        local p  = cf.Position
        local rx = cf.RightVector
        local uy = cf.UpVector
        local lz = cf.LookVector
        for sx = -1, 1, 2 do
            for sy = -1, 1, 2 do
                for sz = -1, 1, 2 do
                    local wx = p.X + rx.X*hx*sx + uy.X*hy*sy + lz.X*hz*sz
                    local wy = p.Y + rx.Y*hx*sx + uy.Y*hy*sy + lz.Y*hz*sz
                    local wz = p.Z + rx.Z*hx*sx + uy.Z*hy*sy + lz.Z*hz*sz
                    local sp, onScreen = Camera:WorldToViewportPoint(V3(wx, wy, wz))
                    if sp.Z <= 0 then continue end          -- behind camera → skip
                    local cx, cy = sp.X, sp.Y
                    if onScreen then anyOn = true end
                    if cx >= 0 and cx <= vpX and cy >= 0 and cy <= vpY then
                        if cx < minX then minX = cx end
                        if cy < minY then minY = cy end
                        if cx > maxX then maxX = cx end
                        if cy > maxY then maxY = cy end
                    end
                end
            end
        end
    end

    if isPart then
        local part = target
        if not part or not part:IsA("BasePart") then
            return {x=0,y=0}, {x=0,y=0}, false
        end
        processPart(part.CFrame, part.Size.X*.5, part.Size.Y*.5, part.Size.Z*.5)
    else
        local parts = {}
        local desc  = isModel and target:GetDescendants() or target:GetChildren()
        for _, v in ipairs(desc) do
            if v:IsA("BasePart") and v.Transparency < 1
                and v.Name ~= "Handle"
                and not v:FindFirstAncestorOfClass("Accessory")
            then
                parts[#parts+1] = v
            end
        end
        if #parts == 0 then
            for _, v in ipairs(desc) do
                if v:IsA("BasePart") then parts[#parts+1] = v end
            end
        end
        if #parts == 0 then return {x=0,y=0}, {x=0,y=0}, false end
        for i = 1, #parts do
            local pt = parts[i]
            processPart(pt.CFrame, pt.Size.X*.5, pt.Size.Y*.5, pt.Size.Z*.5)
        end
    end

    -- no corners landed on screen
    if minX == mhuge then return {x=0,y=0}, {x=0,y=0}, false end
    -- degenerate (edge-on / very far) – skip boxes smaller than 4 px
    if (maxX - minX) < 4 or (maxY - minY) < 4 then
        return {x=0,y=0}, {x=0,y=0}, false
    end

    return {x=minX, y=minY}, {x=maxX, y=maxY}, anyOn
end

-- Health → Color3 (green → yellow → red)
local function HealthColor(pct)
    pct = mclamp(pct, 0, 1)
    if pct >= 0.5 then
        return Color3.new(1 - (pct - 0.5) * 2, 1, 0)
    else
        return Color3.new(1, pct * 2, 0)
    end
end

-- ════════════════════════════════════════════════════════════
--  IMAGE MANAGER
-- ════════════════════════════════════════════════════════════
local ImageManager = {}
ImageManager.screenGui      = nil
ImageManager.images         = {}
ImageManager.assetCache     = {}
ImageManager.pendingResolve = {}
ImageManager.pendingLabels  = {}

function ImageManager:Init()
    if self.screenGui then return end
    local g = Instance.new("ScreenGui")
    g.Name            = "ESP_Images"
    g.ResetOnSpawn    = false
    g.IgnoreGuiInset  = true
    g.DisplayOrder    = 100
    g.Enabled         = true
    g.Parent          = CoreGui
    self.screenGui    = g
end

function ImageManager:ResolveAsset(url)
    if self.assetCache[url] then return self.assetCache[url] end
    if url:find("^rbxassetid://") or url:find("^rbxasset://") then
        self.assetCache[url] = url; return url
    end
    if tonumber(url) then
        local r = "rbxassetid://" .. url
        self.assetCache[url] = r; return r
    end
    -- async HTTP fetch (exploit-only path)
    if not self.pendingResolve[url] then
        self.pendingResolve[url] = true
        task.spawn(function()
            local ext      = url:match("%.(%a+)%??") or "png"
            local safeName = url:gsub("[^%w]", "_"):sub(-50)
            local filename = "esp_" .. safeName .. "." .. ext
            local reqFn    = (syn and syn.request) or (http and http.request) or request
            local ok, res  = pcall(function() return reqFn({ Url = url, Method = "GET" }) end)
            if not ok or not res or res.StatusCode ~= 200 or not res.Body or res.Body == "" then
                warn("[ImageManager] HTTP failed: " .. url)
                self.pendingResolve[url] = nil; return
            end
            if not pcall(writefile, filename, res.Body) then
                warn("[ImageManager] writefile failed")
                self.pendingResolve[url] = nil; return
            end
            local aok, assetId = pcall(getcustomasset, filename)
            if not aok or not assetId or assetId == "" then
                warn("[ImageManager] getcustomasset failed")
                self.pendingResolve[url] = nil; return
            end
            self.assetCache[url] = assetId
            local pending = self.pendingLabels[url]
            if pending then
                for _, img in ipairs(pending) do
                    if img and img.Parent then
                        pcall(function() img.Image = assetId end)
                    end
                end
                self.pendingLabels[url] = nil
            end
        end)
    end
    return nil
end

function ImageManager:SetImageAsync(label, url)
    if not label or not label.Parent then return end
    local resolved = self:ResolveAsset(url)
    if resolved then
        if label.Image ~= resolved then
            pcall(function() label.Image = resolved end)
        end
        return
    end
    if not self.pendingLabels[url] then self.pendingLabels[url] = {} end
    local list = self.pendingLabels[url]
    for i = 1, #list do if list[i] == label then return end end
    list[#list+1] = label
end

function ImageManager:Create(id)
    if self.images[id] then return self.images[id] end
    local img = Instance.new("ImageLabel")
    img.Name                = id
    img.BackgroundTransparency = 1
    img.Visible             = false
    img.Parent              = self.screenGui
    self.images[id]         = img
    return img
end

function ImageManager:Get(id)    return self.images[id] end
function ImageManager:Ensure(id) return self.images[id] or self:Create(id) end

function ImageManager:Remove(id)
    local img = self.images[id]; if not img then return end
    for _, list in pairs(self.pendingLabels) do
        for i = #list, 1, -1 do
            if list[i] == img then table.remove(list, i) end
        end
    end
    img:Destroy()
    self.images[id] = nil
end

function ImageManager:Cleanup()
    for _, img in pairs(self.images) do img:Destroy() end
    self.images         = {}
    self.assetCache     = {}
    self.pendingResolve = {}
    self.pendingLabels  = {}
    if self.screenGui then self.screenGui:Destroy(); self.screenGui = nil end
end

ImageManager:Init()

-- ════════════════════════════════════════════════════════════
--  VISIBILITY CHECK
-- ════════════════════════════════════════════════════════════
local function IsPartVisible(part)
    if not part or not part.Parent then return false end
    if not localChar or not localChar.Parent then return false end
    local origin = Camera.CFrame.Position
    local dir    = part.Position - origin
    local hit    = workspace:FindPartOnRayWithIgnoreList(
        Ray.new(origin, dir),
        { part.Parent, localChar }
    )
    return hit == nil or hit == part or hit:IsDescendantOf(part.Parent)
end

-- ════════════════════════════════════════════════════════════
--  DEFAULT SETTINGS FACTORY
-- ════════════════════════════════════════════════════════════
local function DefaultSettings()
    return {
        box = {
            enabled = false, transparency = 1,
            color = Color3.new(1,1,1), thickness = 1,
        },
        boxoutline = {
            enabled = false, transparency = 1,
            color = Color3.new(0,0,0), thickness = 1,
        },
        healthbar = {
            enabled = false, dynamiccolor = true,
            healthcolor = Color3.new(0,1,0),
            backgroundcolor = Color3.new(0,0,0),
            borderthickness = 1, width = 1, gap = 3,
            backgroundenabled = true,
            healthtext = {
                enabled = false, size = 9,
                color = Color3.new(1,1,1),
                outline = true, outlinecolor = Color3.new(0,0,0),
                usedynamiccolor = false,
            },
        },
        weaponimage = { enabled = false, size = 32, transparency = 1, gap = 4 },
        text  = { spacing = 2, flags = { padding = 4, spacing = 3 },
                  priority = { top = {}, bottom = {}, flags = {} } },
        name     = { enabled=false, top=true,  transparency=1, color=Color3.new(1,1,1), size=11, outline=true, outlinecolor=Color3.new(0,0,0), priority=1 },
        distance = { enabled=false, top=false, transparency=1, color=Color3.new(1,1,1), size=11, outline=true, outlinecolor=Color3.new(0,0,0), priority=1 },
        weapon   = { enabled=false, top=false, transparency=1, color=Color3.new(1,1,1), size=11, outline=true, outlinecolor=Color3.new(0,0,0), priority=2 },
        testing  = { enabled=false, transparency=1, color=Color3.new(0,0,0), size=11, outline=true, outlinecolor=Color3.new(0,0,0), priority=1 },
        skeleton = { enabled=false, transparency=1, color=Color3.new(1,1,1), thickness=1 },
        chams = {
            enabled = false,
            color   = Color3.fromHex("#7385ff"), transparency = 0.3,
            glow    = true, glowcolor = Color3.fromHex("#73b8ff"),
            updatefrequency = 2,
            vischeck = {
                enabled          = false, bodypart = "Head",
                visiblecolor     = Color3.new(0,1,0), notvisiblecolor = Color3.new(1,0,0),
                visibleglowcolor = Color3.new(0,1,0), notvisibleglowcolor = Color3.new(1,0,0),
                updatefrequency  = 0.1,
            },
        },
        imagebox  = { enabled=false, url="", transparency=1, color=Color3.new(1,1,1), rounding=0 },
        oofarrows = {
            enabled = false, radius = 200,
            size    = UDim2.new(0,40,0,40),
            image   = "rbxassetid://7566538552",
            transparency = 1, color = Color3.fromRGB(255,255,255),
            rotation = true, testmode = false,
        },
        vischeckimage = {
            enabled = false, bodypart = "Head",
            visibleimage = "", notvisibleimage = "",
            visiblecolor = Color3.fromRGB(255,255,255),
            notvisiblecolor = Color3.fromRGB(255,255,255),
            size = 24, gap = 4, updatefrequency = 0.1, priority = 1,
        },
        healthcheck = false,
    }
end

-- ════════════════════════════════════════════════════════════
--  FONTS
-- ════════════════════════════════════════════════════════════
local Fonts = {
    SmallestPixel = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular),
    Pixel         = Font.new("rbxasset://fonts/families/Ubuntu.json",        Enum.FontWeight.Bold),
}

-- ════════════════════════════════════════════════════════════
--  ENTITY TYPE
-- ════════════════════════════════════════════════════════════
local EntityType = {}
EntityType.__index = EntityType

function EntityType.new(name, custom)
    local self = setmetatable({}, EntityType)
    self.name     = name
    self.enabled  = true
    self.settings = DefaultSettings()

    -- merge custom overrides
    if custom then
        for k, v in pairs(custom) do
            if self.settings[k] ~= nil then
                if type(v) == "table" and type(self.settings[k]) == "table" then
                    for sk, sv in pairs(v) do self.settings[k][sk] = sv end
                else
                    self.settings[k] = v
                end
            end
        end
    end

    -- build priority lookup
    local tp = self.settings.text.priority
    for tType, data in pairs(self.settings) do
        if type(data) == "table" and type(data.priority) == "number" then
            if     data.top == true  then tp.top[tType]    = data.priority
            elseif data.top == false then tp.bottom[tType] = data.priority
            else                          tp.flags[tType]  = data.priority end
        end
    end

    -- drawing entity stores
    self.entities = {
        box={}, boxoutline={},
        healthbar={}, healthbarbackground={}, healthbartext={},
        skeleton={}, chams={},
        imagebox={}, oofarrows={}, vischeckimage={}, weaponimage={},
        images = { top={}, bottom={}, flags={} },
        text   = { top={}, bottom={}, flags={} },
    }
    for tType, data in pairs(self.settings) do
        if type(data) == "table" and data.priority ~= nil then
            if     tp.flags[tType]  then
                self.entities.text.flags[tType] = {}
                self.entities.images.flags[tType] = {}
            elseif data.top == true then
                self.entities.text.top[tType] = {}
                self.entities.images.top[tType] = {}
            elseif data.top == false then
                self.entities.text.bottom[tType] = {}
                self.entities.images.bottom[tType] = {}
            end
        end
    end

    -- per-id state
    self.valid           = {}
    self.validr6         = {}
    self.isModel         = {}
    self.isPart          = {}
    self.displayNames    = {}
    self.customData      = {}
    self.mins            = {}
    self.maxes           = {}
    self.onscreens       = {}
    self.textoffsets     = {}
    self.imageoffsets    = {}
    self.connections     = {}
    self.deathConnections= {}
    self._chamAdornments = {}
    self._chamLastKey    = {}
    self._offsetDirty    = {}
    self._vischeckState  = {}

    return self
end

function EntityType:MarkDirty(id)
    self._offsetDirty[id] = true
end

function EntityType:RecalcOffsets(id)
    if not self._offsetDirty[id] then return end
    self._offsetDirty[id] = false

    self.textoffsets[id]  = { top={}, bottom={}, flags={} }
    self.imageoffsets[id] = { top={}, bottom={}, flags={} }

    local tp = self.settings.text.priority

    for tType, priority in pairs(tp.top) do
        if self.settings[tType] and self.settings[tType].enabled then
            local loc = priority
            for k, v in pairs(tp.top) do
                if v < priority and self.settings[k] and not self.settings[k].enabled then
                    loc = loc - 1
                end
            end
            self.textoffsets[id].top[tType] = {
                location = loc,
                offset   = (self.settings.text.spacing + self.settings[tType].size) * loc,
            }
        end
    end

    for tType, priority in pairs(tp.bottom) do
        if self.settings[tType] and self.settings[tType].enabled then
            local loc = priority
            for k, v in pairs(tp.bottom) do
                if v < priority and self.settings[k] and not self.settings[k].enabled then
                    loc = loc - 1
                end
            end
            local off = self.settings.text.spacing
                      + (self.settings.text.spacing + self.settings[tType].size) * (loc - 1)
            self.textoffsets[id].bottom[tType] = { location = loc, offset = off }
        end
    end

    local enabledFlags = {}
    for tType, priority in pairs(tp.flags) do
        if self.settings[tType] and self.settings[tType].enabled then
            enabledFlags[#enabledFlags+1] = {
                name = tType, priority = priority,
                height = self.settings[tType].size,
            }
        end
    end
    table.sort(enabledFlags, function(a,b) return a.priority < b.priority end)
    local cum = self.settings.text.flags.padding
    for _, item in ipairs(enabledFlags) do
        self.textoffsets[id].flags[item.name] = { location = _, offset = cum }
        cum = cum + item.height + self.settings.text.flags.spacing
    end
end

function EntityType:IsValid(target, id)
    if not target or not target.Parent then return false end
    if self.isPart[id] then return true end
    local hum = target:FindFirstChildOfClass("Humanoid")
    if self.settings.healthcheck then
        return hum ~= nil and hum.Health > 0
    end
    return not (hum and hum.Health <= 0)
end

-- ════════════════════════════════════════════════════════════
--  WEAPON IMAGES TABLE
-- ════════════════════════════════════════════════════════════
local heldItemImages = {
    ["Bruno's M4A1"]       = "rbxassetid://15574295393",
    ["Crossbow"]           = "rbxassetid://15305596532",
    ["Salvaged Shovel"]    = "rbxassetid://15073386763",
    ["Salvaged Pipe Rifle"]= "rbxassetid://15092314723",
    ["Steel Axe"]          = "rbxassetid://15132541486",
    ["Salvaged RPG"]       = "rbxassetid://15132772506",
    ["Small Medkit"]       = "rbxassetid://15132566142",
    ["Yellow Keycard"]     = "rbxassetid://15303938691",
    ["Salvaged Pump Action"]="rbxassetid://15092313032",
    ["Pink Keycard"]       = "rbxassetid://15303938752",
    ["Salvaged SMG"]       = "rbxassetid://15132874040",
    ["Salvaged AK47"]      = "rbxassetid://14882620172",
    ["Boulder"]            = "rbxassetid://15304806846",
    ["Care Package Signal"]= "rbxassetid://15132798244",
    ["Salvaged AK74u"]     = "rbxassetid://15073408197",
    ["Dynamite Stick"]     = "rbxassetid://15127430886",
    ["Military Barrett"]   = "rbxassetid://15346280030",
    ["Nail Gun"]           = "rbxassetid://15305104734",
    ["Iron Shard Hatchet"] = "rbxassetid://15132541025",
    ["Military M4A1"]      = "rbxassetid://15346201415",
    ["Wooden Spear"]       = "rbxassetid://15303292373",
    ["Dynamite Bundle"]    = "rbxassetid://15127431071",
    ["Stone Spear"]        = "rbxassetid://15303292549",
    ["Salvaged P250"]      = "rbxassetid://15305065991",
    ["Iron Shard Pickaxe"] = "rbxassetid://15132541267",
    ["Military PKM"]       = "rbxassetid://15346287550",
    ["Steel Shovel"]       = "rbxassetid://15132541679",
    ["Timed Charge"]       = "rbxassetid://15132620220",
    ["Steel Pickaxe"]      = "rbxassetid://15132541554",
    ["Lighter"]            = "rbxassetid://15128007580",
    ["Blueprint"]          = "rbxassetid://15132469785",
    ["Salvaged M14"]       = "rbxassetid://14882876522",
    ["Machete"]            = "rbxassetid://16249771824",
    ["Stone Hatchet"]      = "rbxassetid://15073617325",
    ["Bandage"]            = "rbxassetid://14134567329",
    ["Saw Bat"]            = "rbxassetid://16249771997",
    ["Wooden Bow"]         = "rbxassetid://15313266356",
    ["Military Grenade"]   = "rbxassetid://15346283342",
    ["Health Pen"]         = "rbxassetid://15304289469",
    ["Candy Cane"]         = "rbxassetid://15132567147",
    ["Hammer"]             = "rbxassetid://15318044673",
    ["Military AA12"]      = "rbxassetid://15346289730",
    ["Salvaged Python"]    = "rbxassetid://15188995729",
    ["Purple Keycard"]     = "rbxassetid://15303938707",
    ["Bone Tool"]          = "rbxassetid://15073616534",
    ["Stone Pickaxe"]      = "rbxassetid://15073617163",
    ["Salvaged Skorpion"]  = "rbxassetid://15369212859",
    ["Salvaged Break Action"]="rbxassetid://15188994406",
}

-- ════════════════════════════════════════════════════════════
--  SKELETON HELPERS
-- ════════════════════════════════════════════════════════════
local R6_BONES  = {
    "Head_Spine","Spine",
    "LeftArm","LeftArm_UpperTorso",
    "RightArm","RightArm_UpperTorso",
    "LeftLeg","LeftLeg_LowerTorso",
    "RightLeg","RightLeg_LowerTorso",
}
local R15_BONES = {
    "Head_UpperTorso","UpperTorso_LowerTorso",
    "UpperTorso_LeftUpperArm","LeftUpperArm_LeftLowerArm","LeftLowerArm_LeftHand",
    "UpperTorso_RightUpperArm","RightUpperArm_RightLowerArm","RightLowerArm_RightHand",
    "LowerTorso_LeftUpperLeg","LeftUpperLeg_LeftLowerLeg","LeftLowerLeg_LeftFoot",
    "LowerTorso_RightUpperLeg","RightUpperLeg_RightLowerLeg","RightLowerLeg_RightFoot",
}

local function makeBoneLines(names)
    local t = {}
    for _, n in ipairs(names) do
        local l = Drawing.new("Line")
        l.Visible = false; l.From = V2(0,0); l.To = V2(1,1)
        t[n] = { line = l }
    end
    return t
end

-- Project a part's centre to screen (returns V2 or nil if behind cam)
local function vp(part)
    if not part then return nil end
    local sp = Camera:WorldToViewportPoint(part.Position)
    if sp.Z <= 0 then return nil end
    return V2(sp.X, sp.Y)
end

-- Project a world position offset from a part's CFrame
local function vpCF(part, offsetCF)
    if not part then return nil end
    local sp = Camera:WorldToViewportPoint((part.CFrame * offsetCF).Position)
    if sp.Z <= 0 then return nil end
    return V2(sp.X, sp.Y)
end

-- ════════════════════════════════════════════════════════════
--  ESP CORE
-- ════════════════════════════════════════════════════════════
local ESP = {
    entityTypes     = {},
    whitelistedWeapons = {},
    chamsRunning    = false,
    Enabled         = true,
    Friends         = {},
    heldItemImages  = heldItemImages,
    Fonts           = Fonts,
    activeFont      = Fonts.Pixel,
    chamsContainer  = nil,
}

-- ── Font ─────────────────────────────────────────────────────
function ESP:SetFont(n)
    self.activeFont = (type(n)=="string")
        and (self.Fonts[n] or self.Fonts.Pixel)
        or  n
end

function ESP:SetEnabled(e) self.Enabled = e end

-- ── Entity-type lifecycle ─────────────────────────────────────
function ESP:CreateEntityType(name, custom)
    if self.entityTypes[name] then return self.entityTypes[name] end
    local et = EntityType.new(name, custom)
    self.entityTypes[name] = et
    return et
end

function ESP:GetEntityType(name)   return self.entityTypes[name] end

function ESP:RemoveEntityType(name)
    local et = self.entityTypes[name]; if not et then return end
    for id in pairs(et.valid) do self:_RemoveAll(et, id) end
    for _, c in pairs(et.connections)      do if c then c:Disconnect() end end
    for _, c in pairs(et.deathConnections) do if c then c:Disconnect() end end
    self.entityTypes[name] = nil
end

function ESP:SetEntityTypeEnabled(name, enabled)
    local et = self.entityTypes[name]
    if et then et.enabled = enabled end
end

-- ── Tracking ──────────────────────────────────────────────────
function ESP:TrackPlayer(player, typeName)
    typeName = typeName or "players"
    local et = self.entityTypes[typeName]
    if not et or player == lp then return end
    for _, fid in ipairs(self.Friends) do
        if player.UserId == fid then return end
    end
    local id = player.UserId

    local function onChar(char)
        et.valid[id]   = char
        et.validr6[id] = char:FindFirstChild("Torso") ~= nil
        et.isModel[id] = false
        et.isPart[id]  = false
        et.displayNames[id] = player.Name
        et:MarkDirty(id)
        if et.deathConnections[id] then
            et.deathConnections[id]:Disconnect()
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            et.deathConnections[id] = hum.Died:Connect(function()
                self:_CleanChams(et, id)
            end)
        end
    end

    if player.Character then onChar(player.Character) end
    et.connections[id] = player.CharacterAdded:Connect(onChar)
end

function ESP:TrackModel(typeName, model, displayName)
    local et = self.entityTypes[typeName]; if not et then return end
    if not model or not model:IsA("Model") then return end
    local id = HttpService:GenerateGUID(false)
    et.valid[id]        = model
    et.isModel[id]      = true
    et.isPart[id]       = false
    et.displayNames[id] = displayName or model.Name
    et:MarkDirty(id)
    et.connections[id]  = model.AncestryChanged:Connect(function(_, p)
        if not p then self:Untrack(typeName, id) end
    end)
    return id
end

function ESP:TrackPart(typeName, part, displayName)
    local et = self.entityTypes[typeName]; if not et then return end
    if not part or not part:IsA("BasePart") then return end
    local id = HttpService:GenerateGUID(false)
    et.valid[id]        = part
    et.isModel[id]      = false
    et.isPart[id]       = true
    et.displayNames[id] = displayName or part.Name
    et:MarkDirty(id)
    et.connections[id]  = part.AncestryChanged:Connect(function(_, p)
        if not p then self:Untrack(typeName, id) end
    end)
    return id
end

function ESP:TrackModels(typeName, models, getDisplayName)
    local ids = {}
    for _, m in pairs(models) do
        ids[#ids+1] = self:TrackModel(typeName, m,
            getDisplayName and getDisplayName(m) or m.Name)
    end
    return ids
end

function ESP:Untrack(typeName, id)
    local et = self.entityTypes[typeName]; if not et then return end
    self:_RemoveAll(et, id)
    et.valid[id]           = nil
    et.validr6[id]         = nil
    et.isModel[id]         = nil
    et.isPart[id]          = nil
    et.displayNames[id]    = nil
    et.customData[id]      = nil
    et.mins[id]            = nil
    et.maxes[id]           = nil
    et.onscreens[id]       = nil
    et.textoffsets[id]     = nil
    et.imageoffsets[id]    = nil
    et._chamLastKey[id]    = nil
    et._offsetDirty[id]    = nil
    et._vischeckState[id]  = nil
    if et.connections[id]      then et.connections[id]:Disconnect();      et.connections[id]      = nil end
    if et.deathConnections[id] then et.deathConnections[id]:Disconnect(); et.deathConnections[id] = nil end
end

function ESP:UntrackAll(typeName)
    local et = self.entityTypes[typeName]; if not et then return end
    for id in pairs(et.valid) do self:Untrack(typeName, id) end
end

-- ── Settings helpers ──────────────────────────────────────────
function ESP:SetSetting(name, cat, k, v)
    local et = self.entityTypes[name]; if not et or not et.settings[cat] then return end
    et.settings[cat][k] = v
    for id in pairs(et.valid) do et:MarkDirty(id) end
end

function ESP:GetSetting(name, cat, k)
    local et = self.entityTypes[name]
    return et and et.settings[cat] and et.settings[cat][k]
end

function ESP:UpdateSettings(name, settings)
    local et = self.entityTypes[name]; if not et then return end
    for cat, vals in pairs(settings) do
        if et.settings[cat] then
            for k, v in pairs(vals) do et.settings[cat][k] = v end
        end
    end
    for id in pairs(et.valid) do et:MarkDirty(id) end
end

function ESP:SetPlayerSetting(cat, k, v) self:SetSetting("players", cat, k, v) end
function ESP:GetPlayerSetting(cat, k)    return self:GetSetting("players", cat, k) end

function ESP:SetCustomData(name, id, k, v)
    local et = self.entityTypes[name]; if not et then return end
    if not et.customData[id] then et.customData[id] = {} end
    et.customData[id][k] = v
end

function ESP:GetCustomData(name, id, k)
    local et = self.entityTypes[name]; if not et then return nil end
    return et.customData[id] and et.customData[id][k]
end

function ESP:GetTrackedIDs(name)
    local et = self.entityTypes[name]; if not et then return {} end
    local ids = {}
    for id in pairs(et.valid) do ids[#ids+1] = id end
    return ids
end

function ESP:GetDisplayName(name, id)
    local et = self.entityTypes[name]
    return (et and et.displayNames[id]) or "Unknown"
end

function ESP:SetDisplayName(name, id, newName)
    local et = self.entityTypes[name]
    if et then et.displayNames[id] = newName end
end

-- ════════════════════════════════════════════════════════════
--  DRAWING HELPERS
-- ════════════════════════════════════════════════════════════
local function hideAll(et, id)
    local ents = et.entities
    for _, key in ipairs({"box","boxoutline","healthbar","healthbarbackground","healthbartext"}) do
        local e = ents[key][id]; if e then e.Visible = false end
    end
    local sk = ents.skeleton[id]
    if sk then
        for _, b in pairs(sk.r6)  do b.line.Visible = false end
        for _, b in pairs(sk.r15) do b.line.Visible = false end
    end
    for _, place in ipairs({"top","bottom","flags"}) do
        for _, texts in pairs(ents.text[place]) do
            local t = texts[id]; if t then t.Visible = false end
        end
    end
    for _, pfx in ipairs({"imagebox_","oofarrow_","vischeckimage_","weaponimage_"}) do
        local img = ImageManager:Get(pfx .. id)
        if img then img.Visible = false end
    end
end

local function newTextDrawing(et, tType)
    local s = et.settings[tType]
    local t = Drawing.new("Text")
    pcall(function() t.FontFace = ESP.activeFont end)
    t.Size         = s.size
    t.Color        = s.color
    t.OutlineColor = s.outlinecolor
    t.Transparency = s.transparency
    t.Outline      = s.outline
    t.Visible      = false
    return t
end

-- ════════════════════════════════════════════════════════════
--  RENDER HANDLERS
-- ════════════════════════════════════════════════════════════

-- ── Box ──────────────────────────────────────────────────────
function ESP:_HandleBox(et, id)
    local min, max, on = et.mins[id], et.maxes[id], et.onscreens[id]
    local s  = et.settings.box
    local so = et.settings.boxoutline

    if not et.entities.box[id] then
        local outline = Drawing.new("Square"); outline.Visible = false
        local box     = Drawing.new("Square"); box.Visible     = false
        et.entities.box[id]        = box
        et.entities.boxoutline[id] = outline
    end

    local box     = et.entities.box[id]
    local outline = et.entities.boxoutline[id]
    local show    = on and s.enabled and et:IsValid(et.valid[id], id)

    if show then
        local pos = V2(min.x, min.y)
        local sz  = V2(max.x - min.x, max.y - min.y)
        box.Position    = pos; box.Size        = sz
        box.Thickness   = s.thickness
        box.Color       = s.color
        box.Transparency= s.transparency
        box.Visible     = true
        if so.enabled then
            outline.Position     = pos; outline.Size        = sz
            outline.Thickness    = s.thickness + so.thickness * 2
            outline.Color        = so.color
            outline.Transparency = so.transparency
            outline.Visible      = true
        else
            outline.Visible = false
        end
    else
        box.Visible     = false
        outline.Visible = false
    end
end

-- ── Health Bar ───────────────────────────────────────────────
function ESP:_HandleHealthbar(et, id)
    local min, max, on = et.mins[id], et.maxes[id], et.onscreens[id]
    local s = et.settings.healthbar

    if not et.entities.healthbar[id] then
        local bg  = Drawing.new("Square"); bg.Filled  = true; bg.Visible  = false
        local bar = Drawing.new("Square"); bar.Filled = true; bar.Visible = false
        local ht  = Drawing.new("Text");   ht.Center  = true; ht.Visible  = false
        pcall(function() ht.FontFace = ESP.activeFont end)
        et.entities.healthbarbackground[id] = bg
        et.entities.healthbar[id]           = bar
        et.entities.healthbartext[id]       = ht
    end

    local bg  = et.entities.healthbarbackground[id]
    local bar = et.entities.healthbar[id]
    local ht  = et.entities.healthbartext[id]
    local show= on and s.enabled and et:IsValid(et.valid[id], id)

    if show then
        local target = et.valid[id]
        local hum    = target:FindFirstChildOfClass("Humanoid")
        local hp     = hum and hum.Health    or 100
        local mhp    = hum and hum.MaxHealth or 100
        local pct    = (mhp > 0) and (hp / mhp) or 0
        local height = max.y - min.y
        local hchange= height * (1 - pct)
        local left   = min.x - s.gap - s.width - s.borderthickness

        if s.backgroundenabled then
            bg.Position     = V2(left - s.borderthickness, min.y - s.borderthickness)
            bg.Size         = V2(s.width + s.borderthickness * 2, height + s.borderthickness * 2)
            bg.Color        = s.backgroundcolor
            bg.Transparency = 1
            bg.Visible      = true
        else
            bg.Visible = false
        end

        bar.Position     = V2(left, min.y + hchange)
        bar.Size         = V2(s.width, mmax(0, height - hchange))
        bar.Color        = s.dynamiccolor and HealthColor(pct) or s.healthcolor
        bar.Transparency = 1
        bar.Visible      = true

        local hs = s.healthtext
        if hs.enabled then
            ht.Text         = tostring(mfloor(hp + 0.5))
            ht.Color        = hs.usedynamiccolor and HealthColor(pct) or hs.color
            ht.Size         = hs.size
            ht.Outline      = hs.outline
            ht.OutlineColor = hs.outlinecolor
            ht.Position     = V2(left - s.borderthickness - 12, min.y + hchange)
            ht.Visible      = true
        else
            ht.Visible = false
        end
    else
        bar.Visible = false; bg.Visible = false; ht.Visible = false
    end
end

-- ── Text ─────────────────────────────────────────────────────
function ESP:_HandleText(et, id, tType)
    local setting = et.settings[tType]
    if type(setting) ~= "table" or not setting.color or setting.priority == nil then return end

    local tp    = et.settings.text.priority
    local place = tp.flags[tType] and "flags"
                  or (setting.top == true and "top" or "bottom")

    local byPlace = et.entities.text[place]
    if not byPlace[tType] then byPlace[tType] = {} end
    local byType = byPlace[tType]

    local min, max, on = et.mins[id], et.maxes[id], et.onscreens[id]
    local show = on and setting.enabled and et:IsValid(et.valid[id], id)

    if not byType[id] then
        byType[id] = newTextDrawing(et, tType)
        byType[id].Center = (place ~= "flags")
    end

    local txt = byType[id]
    if not show then txt.Visible = false; return end

    local offsets = et.textoffsets[id]
    if not offsets or not offsets[place][tType] then txt.Visible = false; return end

    txt.Color        = setting.color
    txt.Size         = setting.size
    txt.Transparency = setting.transparency
    txt.Outline      = setting.outline
    txt.OutlineColor = setting.outlinecolor
    txt.Visible      = true

    local offset = offsets[place][tType].offset
    local cx     = min.x + (max.x - min.x) * 0.5

    if tType == "name" then
        txt.Text = et.displayNames[id] or "Unknown"
    elseif tType == "distance" and localChar then
        local target = et.valid[id]
        local tp2    = target:IsA("Model")
            and target:GetPivot().Position
            or  target.Position
        txt.Text = "[" .. mround((localChar:GetPivot().Position - tp2).Magnitude) .. " m]"
    elseif tType == "weapon" then
        txt.Text = "[" .. (self:_GetWeaponName(et.valid[id]) or "None") .. "]"
    else
        txt.Text = "[" .. tType:upper() .. "]"
    end

    if     place == "flags"  then txt.Position = V2(max.x, min.y + offset)
    elseif place == "top"    then txt.Position = V2(cx,    min.y - offset)
    else                          txt.Position = V2(cx,    max.y + offset) end
end

-- ── Skeleton ─────────────────────────────────────────────────
function ESP:_HandleSkeleton(et, id)
    local target = et.valid[id]
    local on     = et.onscreens[id]
    local show   = on and et.settings.skeleton.enabled and et:IsValid(target, id)

    if not et.entities.skeleton[id] then
        et.entities.skeleton[id] = {
            r6  = makeBoneLines(R6_BONES),
            r15 = makeBoneLines(R15_BONES),
        }
    end

    local bones = et.entities.skeleton[id]

    if not show or not target or not target.Parent then
        for _, b in pairs(bones.r6)  do b.line.Visible = false end
        for _, b in pairs(bones.r15) do b.line.Visible = false end
        return
    end

    local isR6 = target:FindFirstChild("Torso") ~= nil
    et.validr6[id] = isR6

    local inactive = isR6 and bones.r15 or bones.r6
    for _, b in pairs(inactive) do b.line.Visible = false end

    local active = isR6 and bones.r6 or bones.r15
    local sc, st, sth = et.settings.skeleton.color,
                        et.settings.skeleton.transparency,
                        et.settings.skeleton.thickness

    local function setLine(name, f, t2)
        local b = active[name]
        if not b then return end
        if f and t2 then
            b.line.Color       = sc; b.line.Transparency = st
            b.line.Thickness   = sth
            b.line.From        = f; b.line.To = t2
            b.line.Visible     = true
        else
            b.line.Visible = false
        end
    end

    if isR6 then
        local T = target:FindFirstChild("Torso")
        if not T then for _, b in pairs(active) do b.line.Visible = false end; return end

        local H  = vp(target:FindFirstChild("Head"))
        local LA = target:FindFirstChild("Left Arm")
        local RA = target:FindFirstChild("Right Arm")
        local LL = target:FindFirstChild("Left Leg")
        local RL = target:FindFirstChild("Right Leg")
        if not (H and LA and RA and LL and RL) then
            for _, b in pairs(active) do b.line.Visible = false end; return
        end

        local hy4 = T.Size.Y * 0.25
        local UTv = vpCF(T, CF(0,  hy4, 0))
        local LTv = vpCF(T, CF(0, -hy4, 0))
        if not UTv or not LTv then
            for _, b in pairs(active) do b.line.Visible = false end; return
        end

        local function limbVP(part)
            local hy = part.Size.Y * 0.5 - 0.2
            return vpCF(part, CF(0, hy, 0)), vpCF(part, CF(0, -hy, 0))
        end
        local LUA, LLA = limbVP(LA); local RUA, RLA = limbVP(RA)
        local LUL, LLL = limbVP(LL); local RUL, RLL = limbVP(RL)

        setLine("Head_Spine",           H,   UTv)
        setLine("Spine",               UTv,  LTv)
        setLine("LeftArm",             LUA,  LLA)
        setLine("LeftArm_UpperTorso",  UTv,  LUA)
        setLine("RightArm",            RUA,  RLA)
        setLine("RightArm_UpperTorso", UTv,  RUA)
        setLine("LeftLeg",             LUL,  LLL)
        setLine("LeftLeg_LowerTorso",  LTv,  LUL)
        setLine("RightLeg",            RUL,  RLL)
        setLine("RightLeg_LowerTorso", LTv,  RUL)
    else
        local H  = vp(target:FindFirstChild("Head"))
        local UT = vp(target:FindFirstChild("UpperTorso"))
        local LT = vp(target:FindFirstChild("LowerTorso"))
        if not (H and UT and LT) then
            for _, b in pairs(active) do b.line.Visible = false end; return
        end

        setLine("Head_UpperTorso",            H,   UT)
        setLine("UpperTorso_LowerTorso",       UT,  LT)
        setLine("UpperTorso_LeftUpperArm",     UT,  vp(target:FindFirstChild("LeftUpperArm")))
        setLine("LeftUpperArm_LeftLowerArm",   vp(target:FindFirstChild("LeftUpperArm")),  vp(target:FindFirstChild("LeftLowerArm")))
        setLine("LeftLowerArm_LeftHand",       vp(target:FindFirstChild("LeftLowerArm")),  vp(target:FindFirstChild("LeftHand")))
        setLine("UpperTorso_RightUpperArm",    UT,  vp(target:FindFirstChild("RightUpperArm")))
        setLine("RightUpperArm_RightLowerArm", vp(target:FindFirstChild("RightUpperArm")), vp(target:FindFirstChild("RightLowerArm")))
        setLine("RightLowerArm_RightHand",     vp(target:FindFirstChild("RightLowerArm")), vp(target:FindFirstChild("RightHand")))
        setLine("LowerTorso_LeftUpperLeg",     LT,  vp(target:FindFirstChild("LeftUpperLeg")))
        setLine("LeftUpperLeg_LeftLowerLeg",   vp(target:FindFirstChild("LeftUpperLeg")),  vp(target:FindFirstChild("LeftLowerLeg")))
        setLine("LeftLowerLeg_LeftFoot",       vp(target:FindFirstChild("LeftLowerLeg")),  vp(target:FindFirstChild("LeftFoot")))
        setLine("LowerTorso_RightUpperLeg",    LT,  vp(target:FindFirstChild("RightUpperLeg")))
        setLine("RightUpperLeg_RightLowerLeg", vp(target:FindFirstChild("RightUpperLeg")), vp(target:FindFirstChild("RightLowerLeg")))
        setLine("RightLowerLeg_RightFoot",     vp(target:FindFirstChild("RightLowerLeg")), vp(target:FindFirstChild("RightFoot")))
    end
end

-- ── Image Box ────────────────────────────────────────────────
function ESP:_HandleImageBox(et, id)
    local min, max, on = et.mins[id], et.maxes[id], et.onscreens[id]
    local s    = et.settings.imagebox
    local show = on and s.enabled and et:IsValid(et.valid[id], id)
    local key  = "imagebox_" .. id
    local img  = ImageManager:Ensure(key)
    if s.url and s.url ~= "" then ImageManager:SetImageAsync(img, s.url) end
    img.Visible = show
    if show then
        img.ImageTransparency = 1 - s.transparency
        img.ImageColor3       = s.color
        img.Size              = UDim2.new(0, max.x - min.x, 0, max.y - min.y)
        img.Position          = UDim2.new(0, min.x, 0, min.y)
    end
end

-- ── OOF Arrows ──────────────────────────────────────────────
function ESP:_HandleOOFArrows(et, id, target)
    local s   = et.settings.oofarrows
    local key = "oofarrow_" .. id
    if not s.enabled then
        local a = ImageManager:Get(key); if a then a.Visible = false end; return
    end

    local targetPos
    if et.isPart[id] then
        targetPos = target.Position
    else
        local hrp = target:FindFirstChild("HumanoidRootPart")
        if not hrp then
            local a = ImageManager:Get(key); if a then a.Visible = false end; return
        end
        targetPos = hrp.Position
    end

    local sp, onScreen = Camera:WorldToViewportPoint(targetPos)
    local ss = Camera.ViewportSize
    if onScreen and sp.Z > 0
        and sp.X > 50 and sp.X < ss.X - 50
        and sp.Y > 50 and sp.Y < ss.Y - 50
    then
        local a = ImageManager:Get(key); if a then a.Visible = false end; return
    end

    local camCF = Camera.CFrame
    local to    = targetPos - camCF.Position
    local dist  = to.Magnitude
    local flat  = V3(to.X, 0, to.Z)
    flat  = (flat.Magnitude > 0.01) and flat.Unit or camCF.LookVector
    local fwd   = V3(camCF.LookVector.X, 0, camCF.LookVector.Z)
    fwd   = (fwd.Magnitude  > 0.01) and fwd.Unit  or V3(0, 0, 1)
    local right = V3(camCF.RightVector.X, 0, camCF.RightVector.Z)
    right = (right.Magnitude > 0.01) and right.Unit or V3(1, 0, 0)

    local dotUp = to.Y / dist
    local rot   = mabs(dotUp) > 0.5
        and (dotUp < 0 and 180 or 0)
        or  math.deg(matan2(flat:Dot(right), flat:Dot(fwd)))
    local angle = mrad(rot)
    local ax    = ss.X * 0.5 + math.sin(angle) * s.radius
    local ay    = ss.Y * 0.5 - math.cos(angle) * s.radius

    local arrow = ImageManager:Get(key)
    if not arrow then
        arrow = ImageManager:Create(key)
        ImageManager:SetImageAsync(arrow, s.image)
        arrow.AnchorPoint         = V2(0.5, 0.5)
        arrow.ZIndex              = 10
        arrow.BackgroundTransparency = 1
    end
    arrow.ImageTransparency = 1 - s.transparency
    arrow.ImageColor3       = s.color
    arrow.Size              = s.size
    arrow.Position          = UDim2.new(0, ax, 0, ay)
    if s.rotation then arrow.Rotation = rot end
    arrow.Visible           = true
end

-- ── Vischeck Image ───────────────────────────────────────────
function ESP:_HandleVischeckImage(et, id, target)
    local s   = et.settings.vischeckimage
    local key = "vischeckimage_" .. id
    if not s.enabled then
        local i = ImageManager:Get(key); if i then i.Visible = false end; return
    end

    local min, max, on = et.mins[id], et.maxes[id], et.onscreens[id]
    if not on or not et:IsValid(target, id) then
        local i = ImageManager:Get(key); if i then i.Visible = false end; return
    end

    if not et._vischeckState[id] then
        et._vischeckState[id] = { lastCheck = 0, isVis = false, lastUrl = nil, lastColor = nil }
    end
    local state = et._vischeckState[id]
    local now   = tick()
    if now - state.lastCheck >= (s.updatefrequency or 0.1) then
        state.lastCheck = now
        local p = target:FindFirstChild(s.bodypart or "Head")
        state.isVis = p ~= nil and IsPartVisible(p)
    end

    local url = state.isVis and s.visibleimage or s.notvisibleimage
    local col = state.isVis and s.visiblecolor  or s.notvisiblecolor
    if not url or url == "" then
        local i = ImageManager:Get(key); if i then i.Visible = false end; return
    end

    local img = ImageManager:Get(key)
    if not img then
        img = ImageManager:Create(key)
        img.Size                 = UDim2.new(0, s.size or 24, 0, s.size or 24)
        img.AnchorPoint          = V2(0, 0)
        img.ZIndex               = 10
        img.BackgroundTransparency = 1
    end
    if url ~= state.lastUrl then
        ImageManager:SetImageAsync(img, url); state.lastUrl = url
    end
    if col ~= state.lastColor then
        img.ImageColor3 = col or Color3.new(1,1,1); state.lastColor = col
    end
    local off = (et.textoffsets[id] and et.textoffsets[id].flags.vischeckimage)
        and et.textoffsets[id].flags.vischeckimage.offset or 0
    img.Position = UDim2.new(0, max.x + (s.gap or 4), 0, min.y + off)
    img.Visible  = true
end

-- ── Weapon Image ─────────────────────────────────────────────
function ESP:_HandleWeaponImage(et, id, target)
    local s   = et.settings.weaponimage
    local key = "weaponimage_" .. id
    local min, max = et.mins[id], et.maxes[id]
    local on  = et.onscreens[id]

    if not s.enabled or not on or not et:IsValid(target, id) then
        local i = ImageManager:Get(key); if i then i.Visible = false end; return
    end

    local wn  = self:_GetWeaponName(target)
    local url = wn and self.heldItemImages[wn]
    if not url then
        local i = ImageManager:Get(key); if i then i.Visible = false end; return
    end

    local img = ImageManager:Get(key)
    if not img then
        img = ImageManager:Create(key)
        img.AnchorPoint          = V2(0.5, 0)
        img.ZIndex               = 10
        img.BackgroundTransparency = 1
    end
    ImageManager:SetImageAsync(img, url)
    img.ImageTransparency = 1 - (s.transparency or 1)
    local sz = s.size or 32
    img.Size = UDim2.new(0, sz, 0, sz)

    local bottomEdge = max.y
    if et.textoffsets[id] then
        for tType, data in pairs(et.textoffsets[id].bottom) do
            local st = et.settings[tType]
            if st and st.enabled then
                local b = max.y + data.offset + st.size
                if b > bottomEdge then bottomEdge = b end
            end
        end
    end
    img.Position = UDim2.new(0, min.x + (max.x - min.x) * 0.5, 0, bottomEdge + (s.gap or 4))
    img.Visible  = true
end

-- ════════════════════════════════════════════════════════════
--  CHAMS
-- ════════════════════════════════════════════════════════════
function ESP:_EnsureChamsContainer()
    if not self.chamsContainer or not self.chamsContainer.Parent then
        local f = Instance.new("Folder")
        f.Name   = "RobloxGui"
        f.Parent = CoreGui
        self.chamsContainer = f
    end
end

function ESP:_CleanChams(et, id)
    if not et._chamAdornments[id] then return end
    for _, a in pairs(et._chamAdornments[id]) do
        if a and a.Parent then pcall(function() a:Destroy() end) end
    end
    et._chamAdornments[id] = nil
    et._chamLastKey[id]    = nil
end

function ESP:_UpdateChams(et, id, target)
    local s = et.settings.chams
    if not s.enabled then self:_CleanChams(et, id); return end
    if not target or not target.Parent then self:_CleanChams(et, id); return end
    if not et:IsValid(target, id) then self:_CleanChams(et, id); return end

    local mainColor = s.color
    local glowColor = s.glowcolor
    local trans     = s.transparency
    local doGlow    = s.glow

    if s.vischeck and s.vischeck.enabled then
        local cp = target:FindFirstChild(s.vischeck.bodypart or "Head")
        if cp then
            if IsPartVisible(cp) then
                mainColor = s.vischeck.visiblecolor
                glowColor = s.vischeck.visibleglowcolor
            else
                mainColor = s.vischeck.notvisiblecolor
                glowColor = s.vischeck.notvisibleglowcolor
            end
        end
    end

    local key = mainColor.R .. mainColor.G .. mainColor.B
             .. tostring(doGlow) .. tostring(trans)
    if et._chamLastKey[id] == key and et._chamAdornments[id] then return end

    self:_CleanChams(et, id)
    et._chamAdornments[id] = {}
    self:_EnsureChamsContainer()

    for _, part in ipairs(target:GetChildren()) do
        if not part:IsA("BasePart") or part.Transparency >= 1 then continue end
        local isHead = part.Name == "Head" or part.Name == "FakeHead"
        local function adorn(color, t2, zIdx)
            local a
            if isHead then
                a = Instance.new("CylinderHandleAdornment")
                a.Height = part.Size.Y; a.Radius = part.Size.X * 0.5
            else
                a = Instance.new("BoxHandleAdornment")
                a.Size = part.Size + V3(0.02, 0.02, 0.02)
            end
            a.Name        = "Chams"; a.AlwaysOnTop = true; a.ZIndex = zIdx
            a.Adornee     = part; a.Color3 = color; a.Transparency = t2
            a.Parent      = self.chamsContainer
            table.insert(et._chamAdornments[id], a)
        end
        if doGlow then
            adorn(Color3.new(glowColor.R*5, glowColor.G*5, glowColor.B*5), -1, 9)
        end
        adorn(mainColor, trans, 10)
    end
    et._chamLastKey[id] = key
end

-- ════════════════════════════════════════════════════════════
--  WEAPON NAME DETECTION  (fixed: tools live on character, not Humanoid)
-- ════════════════════════════════════════════════════════════
function ESP:_GetWeaponName(target)
    -- Tools are always parented to the character model itself.
    for _, c in ipairs(target:GetChildren()) do
        if c:IsA("Tool") then return c.Name end
    end
    -- Fallback: name-match against known item list
    for wn in pairs(self.heldItemImages) do
        if target:FindFirstChild(wn) then return wn end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════
--  CLEANUP
-- ════════════════════════════════════════════════════════════
function ESP:_RemoveAll(et, id)
    for _, key in ipairs({"box","boxoutline","healthbar","healthbarbackground","healthbartext"}) do
        if et.entities[key][id] then
            pcall(function() et.entities[key][id]:Remove() end)
            et.entities[key][id] = nil
        end
    end
    if et.entities.skeleton[id] then
        local bones = et.entities.skeleton[id]
        for _, set in pairs({ bones.r6, bones.r15 }) do
            for _, b in pairs(set) do pcall(function() b.line:Remove() end) end
        end
        et.entities.skeleton[id] = nil
    end
    for _, place in ipairs({"top","bottom","flags"}) do
        for _, texts in pairs(et.entities.text[place]) do
            if texts[id] then
                pcall(function() texts[id]:Remove() end)
                texts[id] = nil
            end
        end
    end
    self:_CleanChams(et, id)
    ImageManager:Remove("imagebox_"      .. id)
    ImageManager:Remove("oofarrow_"      .. id)
    ImageManager:Remove("vischeckimage_" .. id)
    ImageManager:Remove("weaponimage_"   .. id)
end

-- ════════════════════════════════════════════════════════════
--  RENDER LOOP
-- ════════════════════════════════════════════════════════════
local RENDER_NAME = "ESP_Render"

function ESP:Start()
    pcall(function() setfflag("AdornShadingAPI", "true") end)

    RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function()
        if not self.Enabled then
            for _, et in pairs(self.entityTypes) do
                for id in pairs(et.valid) do hideAll(et, id) end
            end
            return
        end

        for _, et in pairs(self.entityTypes) do
            if not et.enabled then continue end
            for id, target in pairs(et.valid) do
                if not et:IsValid(target, id) then
                    hideAll(et, id)
                    self:_CleanChams(et, id)
                    continue
                end

                local min, max, on = Math.GetCorners(
                    target,
                    et.isModel[id] or (not et.isPart[id]),
                    et.isPart[id]
                )
                et.mins[id]      = min
                et.maxes[id]     = max
                et.onscreens[id] = on

                et:RecalcOffsets(id)

                self:_HandleBox(et, id)
                self:_HandleHealthbar(et, id)
                self:_HandleSkeleton(et, id)
                self:_HandleImageBox(et, id)
                self:_HandleOOFArrows(et, id, target)
                self:_HandleVischeckImage(et, id, target)
                self:_HandleWeaponImage(et, id, target)

                for tType, data in pairs(et.settings) do
                    if type(data) == "table" and data.priority ~= nil then
                        self:_HandleText(et, id, tType)
                    end
                end
            end
        end
    end)

    -- Chams update loop (runs at its own, configurable frequency)
    self.chamsRunning = true
    task.spawn(function()
        while self.chamsRunning do
            local waitTime = 2
            for _, et in pairs(self.entityTypes) do
                if et.enabled and et.settings.chams then
                    local cw = et.settings.chams.updatefrequency or 2
                    if et.settings.chams.vischeck and et.settings.chams.vischeck.enabled then
                        cw = mmin(cw, et.settings.chams.vischeck.updatefrequency or cw)
                    end
                    waitTime = mmin(waitTime, cw)
                end
            end
            for _, et in pairs(self.entityTypes) do
                if et.enabled then
                    for id, target in pairs(et.valid) do
                        if et:IsValid(target, id) then
                            self:_UpdateChams(et, id, target)
                        else
                            self:_CleanChams(et, id)
                        end
                    end
                end
            end
            task.wait(waitTime)
        end
    end)
end

function ESP:Stop()
    self.chamsRunning = false
    RunService:UnbindFromRenderStep(RENDER_NAME)
    for _, et in pairs(self.entityTypes) do
        for id in pairs(et.valid) do self:_RemoveAll(et, id) end
    end
    ImageManager:Cleanup()
    if self.chamsContainer and self.chamsContainer.Parent then
        self.chamsContainer:Destroy()
        self.chamsContainer = nil
    end
end

-- ════════════════════════════════════════════════════════════
--  DEFAULT PLAYER TRACKING
-- ════════════════════════════════════════════════════════════
ESP:CreateEntityType("players")

Players.PlayerAdded:Connect(function(p)
    ESP:TrackPlayer(p, "players")
end)
Players.PlayerRemoving:Connect(function(p)
    ESP:Untrack("players", p.UserId)
end)
for _, p in ipairs(Players:GetPlayers()) do
    ESP:TrackPlayer(p, "players")
end

return ESP
