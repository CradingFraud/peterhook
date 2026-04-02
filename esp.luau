local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local lp = Players.LocalPlayer
local character = nil
if lp.Character then
    character = lp.Character
end
lp.CharacterAdded:Connect(function(char)
    character = char
end)
local Camera = game.Workspace.CurrentCamera

local Math = {}
Math.calculateExtent = function(cf, size)
    local r = cf.RightVector
    local u = cf.UpVector
    local b = cf.LookVector

    local hx = size.X * 0.5
    local hy = size.Y * 0.5
    local hz = size.Z * 0.5

    return Vector3.new(
        math.abs(r.X)*hx + math.abs(u.X)*hy + math.abs(b.X)*hz,
        math.abs(r.Y)*hx + math.abs(u.Y)*hy + math.abs(b.Y)*hz,
        math.abs(r.Z)*hx + math.abs(u.Z)*hy + math.abs(b.Z)*hz
    )
end

Math.minMaxFromExtent = function(cf, extent)
    local c = cf.Position
    return c - extent, c + extent
end

Math.getboundingbox = function(instances: {BasePart}, orientation: CFrame?)
    local min = Vector3.new(math.huge, math.huge, math.huge)
    local max = Vector3.new(-math.huge, -math.huge, -math.huge)

    local pivot = orientation or CFrame.new()
    local firstPart = nil

    local handParts = {LeftHand=true, RightHand=true, LeftLowerArm=true, RightLowerArm=true, LeftUpperArm=true, RightUpperArm=true}

    for _, part in ipairs(instances) do
        if part:IsA("BasePart") and not handParts[part.Name] and part.Transparency < 1 then
            if not firstPart then
                firstPart = part
                pivot = CFrame.new(part.Position) * (orientation or CFrame.new())
            end

            local cf = pivot:Inverse() * part.CFrame
            local hx, hy, hz = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5

            local corners = {
                cf * Vector3.new( hx,  hy,  hz),
                cf * Vector3.new(-hx,  hy,  hz),
                cf * Vector3.new( hx, -hy,  hz),
                cf * Vector3.new(-hx, -hy,  hz),
                cf * Vector3.new( hx,  hy, -hz),
                cf * Vector3.new(-hx,  hy, -hz),
                cf * Vector3.new( hx, -hy, -hz),
                cf * Vector3.new(-hx, -hy, -hz),
            }

            for _, corner in ipairs(corners) do
                min = Vector3.new(
                    math.min(min.X, corner.X),
                    math.min(min.Y, corner.Y),
                    math.min(min.Z, corner.Z)
                )
                max = Vector3.new(
                    math.max(max.X, corner.X),
                    math.max(max.Y, corner.Y),
                    math.max(max.Z, corner.Z)
                )
            end
        end
    end

    if not firstPart then
        return CFrame.new(), Vector3.new()
    end

    local centerLocal = (min + max) * 0.5
    local size = max - min
    local centerWorld = pivot * CFrame.new(centerLocal)

    return centerWorld, size
end
Math.getcorners = function(target, isModel, isPart)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOnscreen = false

    if isPart then
        local part = target
        if not part or not part:IsA("BasePart") then
            return {x = 0, y = 0}, {x = 0, y = 0}, false
        end

        local size = part.Size / 2
        local cf = part.CFrame
        
        local corners = {
            cf * Vector3.new(-size.X, -size.Y, -size.Z),
            cf * Vector3.new(size.X, -size.Y, -size.Z),
            cf * Vector3.new(-size.X, size.Y, -size.Z),
            cf * Vector3.new(size.X, size.Y, -size.Z),
            cf * Vector3.new(-size.X, -size.Y, size.Z),
            cf * Vector3.new(size.X, -size.Y, size.Z),
            cf * Vector3.new(-size.X, size.Y, size.Z),
            cf * Vector3.new(size.X, size.Y, size.Z),
        }
        
        for _, corner in ipairs(corners) do
            local screenPos, onscreen = Camera:WorldToViewportPoint(corner)
            if screenPos.Z > 0 then
                if onscreen then anyOnscreen = true end
                minX = math.min(minX, screenPos.X)
                minY = math.min(minY, screenPos.Y)
                maxX = math.max(maxX, screenPos.X)
                maxY = math.max(maxY, screenPos.Y)
            end
        end

        if minX == math.huge then
            return {x = 0, y = 0}, {x = 0, y = 0}, false
        end
        return {x = minX, y = minY}, {x = maxX, y = maxY}, anyOnscreen
    end

    local partsToProject = {}
    
    if isModel then
        local children = target:GetDescendants()
        local head = nil
        local torso = nil
        local upperTorso = nil
        local lowerTorso = nil
        local leftFoot = nil
        local rightFoot = nil
        local leftLowerLeg = nil
        local rightLowerLeg = nil
        
        for _, v in pairs(children) do
            if v:IsA("BasePart") then
                if v.Name == "Head" then head = v
                elseif v.Name == "Torso" then torso = v
                elseif v.Name == "UpperTorso" then upperTorso = v
                elseif v.Name == "LowerTorso" then lowerTorso = v
                elseif v.Name == "LeftFoot" then leftFoot = v
                elseif v.Name == "RightFoot" then rightFoot = v
                elseif v.Name == "LeftLowerLeg" then leftLowerLeg = v
                elseif v.Name == "RightLowerLeg" then rightLowerLeg = v end
            end
        end
        
        if head then table.insert(partsToProject, head) end
        if torso then table.insert(partsToProject, torso) end
        if upperTorso then table.insert(partsToProject, upperTorso) end
        if lowerTorso then table.insert(partsToProject, lowerTorso) end
        if leftFoot then table.insert(partsToProject, leftFoot) end
        if rightFoot then table.insert(partsToProject, rightFoot) end
        if leftLowerLeg then table.insert(partsToProject, leftLowerLeg) end
        if rightLowerLeg then table.insert(partsToProject, rightLowerLeg) end
    else
        local children = target:GetChildren()
        local head = target:FindFirstChild("Head")
        local torso = target:FindFirstChild("Torso")
        local upperTorso = target:FindFirstChild("UpperTorso")
        local lowerTorso = target:FindFirstChild("LowerTorso")
        local leftFoot = target:FindFirstChild("LeftFoot")
        local rightFoot = target:FindFirstChild("RightFoot")
        local leftLowerLeg = target:FindFirstChild("LeftLowerLeg")
        local rightLowerLeg = target:FindFirstChild("RightLowerLeg")
        
        if head then table.insert(partsToProject, head) end
        if torso then table.insert(partsToProject, torso) end
        if upperTorso then table.insert(partsToProject, upperTorso) end
        if lowerTorso then table.insert(partsToProject, lowerTorso) end
        if leftFoot then table.insert(partsToProject, leftFoot) end
        if rightFoot then table.insert(partsToProject, rightFoot) end
        if leftLowerLeg then table.insert(partsToProject, leftLowerLeg) end
        if rightLowerLeg then table.insert(partsToProject, rightLowerLeg) end
    end

    if #partsToProject == 0 then
        return {x = 0, y = 0}, {x = 0, y = 0}, false
    end

    for _, part in ipairs(partsToProject) do
        if part and part.Parent then
            local size = part.Size / 2
            local cf = part.CFrame
            
            local corners = {
                cf * Vector3.new(-size.X, -size.Y, -size.Z),
                cf * Vector3.new(size.X, -size.Y, -size.Z),
                cf * Vector3.new(-size.X, size.Y, -size.Z),
                cf * Vector3.new(size.X, size.Y, -size.Z),
                cf * Vector3.new(-size.X, -size.Y, size.Z),
                cf * Vector3.new(size.X, -size.Y, size.Z),
                cf * Vector3.new(-size.X, size.Y, size.Z),
                cf * Vector3.new(size.X, size.Y, size.Z),
            }
            
            for _, corner in ipairs(corners) do
                local screenPos, onscreen = Camera:WorldToViewportPoint(corner)
                if screenPos.Z > 0 then
                    if onscreen then anyOnscreen = true end
                    minX = math.min(minX, screenPos.X)
                    minY = math.min(minY, screenPos.Y)
                    maxX = math.max(maxX, screenPos.X)
                    maxY = math.max(maxY, screenPos.Y)
                end
            end
        end
    end

    if minX == math.huge or maxX == -math.huge then
        return {x = 0, y = 0}, {x = 0, y = 0}, false
    end

    return {x = minX, y = minY}, {x = maxX, y = maxY}, anyOnscreen
end

local ImageManager = {}
ImageManager.screenGui = nil
ImageManager.images = {}
ImageManager.assetCache = {}
ImageManager.pendingResolve = {}
ImageManager.pendingLabels = {}

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

    if self.assetCache[url] then
        return self.assetCache[url]
    end

    if string.find(url, "^rbxassetid://") or string.find(url, "^rbxasset://") then
        self.assetCache[url] = url
        return url
    end

    if tonumber(url) then
        local result = "rbxassetid://" .. url
        self.assetCache[url] = result
        return result
    end

    if not self.pendingResolve[url] then
        self.pendingResolve[url] = true

        task.spawn(function()

            local ext = string.match(url, "%.(%a+)%??") or "png"

            local safeName = string.gsub(url, "[^%w]", "_")
            safeName = string.sub(safeName, -50)
            local filename = "esp_" .. safeName .. "." .. ext

            local requestFn = syn and syn.request or http and http.request or request
            local ok, res = pcall(function()
                return requestFn({ Url = url, Method = "GET" })
            end)
            local data = ok and res and res.Body

            if not ok or not data or data == "" or (res and res.StatusCode ~= 200) then
                warn("[ImageManager] HTTP request failed for: " .. url .. " (status: " .. tostring(res and res.StatusCode) .. ")")
                self.pendingResolve[url] = nil
                return
            end

            local writeOk = pcall(writefile, filename, data)
            if not writeOk then
                warn("[ImageManager] writefile failed for: " .. filename)
                self.pendingResolve[url] = nil
                return
            end

            local assetOk, assetId = pcall(getcustomasset, filename)
            if not assetOk or not assetId or assetId == "" then
                warn("[ImageManager] getcustomasset failed for: " .. filename)
                self.pendingResolve[url] = nil
                return
            end

            self.assetCache[url] = assetId

            if self.pendingLabels[url] then
                for _, img in ipairs(self.pendingLabels[url]) do
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

function ImageManager:SetImageAsync(imageLabel, url)
    if not imageLabel or not imageLabel.Parent then return end

    local resolved = self:ResolveAsset(url)
    if resolved then

        if imageLabel.Image ~= resolved then
            pcall(function() imageLabel.Image = resolved end)
        end
    else

        if not self.pendingLabels[url] then
            self.pendingLabels[url] = {}
        end

        local alreadyQueued = false
        for _, lbl in ipairs(self.pendingLabels[url]) do
            if lbl == imageLabel then alreadyQueued = true break end
        end
        if not alreadyQueued then
            table.insert(self.pendingLabels[url], imageLabel)
        end
    end
end

function ImageManager:CreateImage(id)
    if self.images[id] then
        return self.images[id]
    end

    local imageLabel = Instance.new("ImageLabel")
    imageLabel.Name = id
    imageLabel.BackgroundTransparency = 1
    imageLabel.Visible = false
    imageLabel.Parent = self.screenGui

    self.images[id] = imageLabel
    return imageLabel
end

function ImageManager:GetImage(id)
    return self.images[id]
end

function ImageManager:RemoveImage(id)
    if self.images[id] then
        local img = self.images[id]

        for url, labels in pairs(self.pendingLabels) do
            for i = #labels, 1, -1 do
                if labels[i] == img then
                    table.remove(labels, i)
                end
            end
        end
        img:Destroy()
        self.images[id] = nil
    end
end

function ImageManager:Cleanup()
    for id, img in pairs(self.images) do
        img:Destroy()
    end
    self.images = {}
    self.assetCache = {}
    self.pendingResolve = {}
    self.pendingLabels = {}
    if self.screenGui then
        self.screenGui:Destroy()
        self.screenGui = nil
    end
end

ImageManager:Init()

local function IsPartVisible(part)
    if not part or not part.Parent then
        return false
    end

    if not character or not character.Parent then
        return false
    end

    local camPos = Camera.CFrame.Position
    local partPos = part.Position

    local ray = Ray.new(camPos, (partPos - camPos).Unit * (partPos - camPos).Magnitude)
    local hitPart = workspace:FindPartOnRayWithIgnoreList(ray, {part.Parent, character})

    return hitPart == nil or hitPart == part or hitPart:IsDescendantOf(part.Parent)
end

local function createDefaultSettings()
    return {
        box = {
            enabled = false,
            transparency = 1,
            color = Color3.new(1, 1, 1),
            thickness = 1
        },
        boxoutline = {
            enabled = false,
            transparency = 1,
            color = Color3.new(0, 0, 0),
            thickness = 1
        },
        healthbar = {
            enabled = false,
            dynamiccolor = true,
            healthcolor = Color3.new(0, 1, 0),
            backgroundcolor = Color3.new(0, 0, 0),
            borderthickness = 1,
            width = 1,
            gap = 3,
            backgroundenabled = true,
            healthtext = {
                enabled = false,
                size = 9,
                color = Color3.new(1, 1, 1),
                outline = true,
                outlinecolor = Color3.new(0, 0, 0),
                usedynamiccolor = false,
            },
        },
        weaponimage = {
            enabled = false,
            size = 32,
            transparency = 1,
            gap = 4,
        },
        text = {
            spacing = 2,
            flags = {
                padding = 4,
                spacing = 3
            },
            priority = {
                top = {},
                bottom = {},
                flags = {}
            }
        },
        name = {
            enabled = false,
            top = true,
            transparency = 1,
            color = Color3.new(1, 1, 1),
            size = 11,
            outline = true,
            outlinecolor = Color3.new(0, 0, 0),
            priority = 1
        },
        distance = {
            enabled = false,
            top = false,
            transparency = 1,
            color = Color3.new(1, 1, 1),
            size = 11,
            outline = true,
            outlinecolor = Color3.new(0, 0, 0),
            priority = 1
        },
        weapon = {
            enabled = false,
            top = false,
            transparency = 1,
            color = Color3.new(1, 1, 1),
            size = 11,
            outline = true,
            outlinecolor = Color3.new(0, 0, 0),
            priority = 2
        },
        testing = {
            enabled = false,
            transparency = 1,
            color = Color3.new(0, 0, 0),
            size = 11,
            outline = true,
            outlinecolor = Color3.new(0, 0, 0),
            priority = 1
        },
        skeleton = {
            enabled = false,
            transparency = 1,
            color = Color3.new(1, 1, 1),
            thickness = 1
        },
        chams = {
            enabled = false,
            color = Color3.fromHex("#7385ff"),
            transparency = 0.3,
            glow = true,
            glowcolor = Color3.fromHex("#73b8ff"),
            updatefrequency = 2,
            vischeck = {
                enabled = false,
                bodypart = "Head",
                visiblecolor = Color3.new(0, 1, 0),
                notvisiblecolor = Color3.new(1, 0, 0),
                visibleglowcolor = Color3.new(0, 1, 0),
                notvisibleglowcolor = Color3.new(1, 0, 0),
                updatefrequency = 0.1
            }
        },
        imagebox = {
            enabled = false,
            url = "https://raw.githubusercontent.com/tatar0071/IonHub/main/Assets/peter_griffin.png",
            transparency = 1,
            color = Color3.new(1, 1, 1),
            rounding = 0
        },
        oofarrows = {
            enabled = false,
            radius = 200,
            size = UDim2.new(0, 40, 0, 40),
            image = "rbxassetid://7566538552",
            transparency = 1,
            color = Color3.fromRGB(255, 255, 255),
            rotation = true,
            testmode = false
        },
        vischeckimage = {
            enabled = false,
            bodypart = "Head",
            visibleimage = "",
            notvisibleimage = "",
            visiblecolor = Color3.fromRGB(255, 255, 255),
            notvisiblecolor = Color3.fromRGB(255, 255, 255),
            size = 24,
            gap = 4,
            updatefrequency = 0.1,
            priority = 1
        },
        healthcheck = true
    }
end

local Fonts = {}

local function _RegisterFontFile(name, weight, style, asset)
    if getcustomasset then
        if not isfile(asset.Id) then
            writefile(asset.Id, asset.Font)
        end
        local data = {
            name = name,
            faces = {
                {
                    name = "Regular",
                    weight = weight,
                    style = style,
                    assetId = getcustomasset(asset.Id)
                }
            }
        }
        writefile(name .. ".font", game:GetService("HttpService"):JSONEncode(data))
        return getcustomasset(name .. ".font")
    else
        return Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
    end
end

-- Minecraft Font Base64
local MinecraftBase64 = "AAEAAAANAIAAAwBQRFNJRwAAAAEAAQX0AAAACEdERUYDBAAkAAEF/AAAAChPUy8y1NZFSAAAANwAAABgY21hcNZo3swAAQp8AAAIOGdhc3AAAAADAAEF7AAAAAhnbHlmEGqBuwAAGjgAANTQaGVhZAZHGCYAAPpgAAAANmhoZWERQQ7WAAAZ9AAAACRobXR4Ywj7gAAA+pgAAAtUbG9jYQEl1TwAAO8IAAALWG1heHAC4wA8AAAaGAAAACBuYW1lomnC7QABBiQAAARWcG9zdN5ON9IAAAE8AAAYuAADBGEBkAAFAAQDAAMAAAABgAMAAwAAAAMAAEwBMgAAAAAEAAAAAAAAAKAAAL9AAGB7AAAAAAAAAABGU1RSAEAAIPsCCQADAAAACoD9wAAAAf8AAAAAB4AJAAAAACAAAQACAAAAAAAAAJgATAAAAAAAAAAAAAAAAAAAAAAAAAAAAtUAAAABAAIAAwAEAAUABgAHAAgACQAKAAsADAANAA4ADwAQABEAEgATABQAFQAWABcAGAAZABoAGwAcAB0AHgAfACAAIQAiACMAJAAlACYAJwAoACkAKgArACwALQAuAC8AMAAxADIAMwA0ADUANgA3ADgAOQA6ADsAPAA9AD4APwBAAEEAQgBDAEQARQBGAEcASABJAEoASwBMAE0ATgBPAFAAUQBSAFMAVABVAFYAVwBYAFkAWgBbAFwAXQBeAF8AYABhAKMAhACFAL0AlgDoAIYAjgCLAJ0AqQCkAIoA2gCDAJMA8gDzAI0AlwCIAMMA3gDxAJ4AqgD1APQA9gCiAK0AyQDHAK4AYgBjAJAAZADLAGUAyADKAM8AzADNAM4A6QBmANMA0ADRAK8AZwDwAJEA1gDUANUAaADrAO0AiQBqAGkAawBtAGwAbgCgAG8AcQBwAHIAcwB1AHQAdgB3AOoAeAB6AHkAewB9AHwAuAChAH8AfgCAAIEA7ADuALoBAgEDAQQBBQEGAQcA/QD+AQgBCQEKAQsA/wEAAQwBDQEOAQEBDwEQAREBEgETARQBFQEWARcBGAEZARoA+AD5ARsBHAEdAR4BHwEgASEBIgEjASQBJQEmAScBKAEpASoA+gDXASsBLAEtAS4BLwEwATEBMgEzATQBNQE2ATcBOAE5AOIA4wE6ATsBPAE9AT4BPwFAAUEBQgFDAUQBRQFGAUcBSACwALEBSQFKAUsBTAFNAU4BTwFQAVEBUgD7APwA5ADlAVMBVAFVAVYBVwFYAVkBWgFbAVwBXQFeAV8BYAFhAWIBYwFkAWUBZgFnAWgAuwFpAWoBawFsAOYA5wFtAW4BbwFwAKYBcQFyAXMBdAF1AXYBdwF4AXkBegF7AXwBfQF+AX8BgAGBAYIBgwGEAYUBhgGHAYgBiQGKANgA4QGLAYwBjQDbANwA3QDgANkA3wGOAY8BkAGRAZIBkwGUAZUBlgGXAZgBmQGaAZsBnAGdAZ4BnwGgAaEBogGjAaQBpQGmAacBqAGpAaoBqwGsAa0BrgGvAbABsQGyAJ8BswG0AbUBtgG3AbgBuQG6AbsBvAG9Ab4BvwHAAcEBwgHDAcQBxQHGAccByACbAckBygHLAcwBzQHOAc8B0AHRAdIB0wHUAdUB1gHXAdgB2QHaAdsB3AHdAd4B3wHgAeEB4gHjAeQB5QHmAecB6AHpAeoB6wHsAe0B7gHvAfAB8QHyAfMB9AH1AfYB9wH4AfkB+gH7AfwB/QH+Af8CAAIBAgICAwIEAgUCBgIHAggCCQIKAgsCDAINAg4CDwIQAhECEgITAhQCFQIWAhcCGAIZAhoCGwIcAh0CHgIfAiACIQIiAiMCJAIlAiYCJwIoAikCKgIrAiwCLQIuAi8CMAIxAjICMwI0AjUCNgI3AjgCOQI6AjsCPAI9Aj4CPwJAAkECQgJDAkQCRQJGAkcCSAJJAkoCSwJMAk0CTgJPAlACUQJSAlMCVAJVAlYCVwJYAlkCWgJbAlwCXQJeAl8CYAJhAmICYwJkAmUCZgJnAmgCaQJqAmsCbAJtAm4CbwJwAnECcgJzAnQCdQJ2AncCeAJ5AnoCewJ8An0CfgJ/AoACgQKCAoMChAKFAoYChwKIAokCigC2ALcAxAKLALQAtQDFAowAggDCAIcCjQCrAMYCjgKPApACkQC+AL8AvAKSApMClAKVApYClwKYApkCmgKbApwCnQKeAp8CoAKhAqICowKkAqUCpgKnAqgCqQKqAqsCrAKtAq4CrwKwAIwCsQKyArMCtAK1ArYCtwK4ArkCugK7ArwCvQK+Ar8CwALBAsICwwLEAsUCxgLHAsgCyQLKAssAqAClAJIAnALMAKcAjwCUAJUCzQLOAs8C0ALRAtIC0wLUAtUC1gLXAtgC2QLaAtsC3ALdAt4AwADBB0FtYWNyb24HYW1hY3JvbgZBYnJldmUGYWJyZXZlB0FvZ29uZWsHYW9nb25lawtDY2lyY3VtZmxleAtjY2lyY3VtZmxleARDZG90BGNkb3QGRGNhcm9uBmRjYXJvbgZEY3JvYXQHRW1hY3JvbgdlbWFjcm9uBkVicmV2ZQZlYnJldmUERWRvdARlZG90B0VvZ29uZWsHZW9nb25lawZFY2Fyb24GZWNhcm9uC0djaXJjdW1mbGV4C2djaXJjdW1mbGV4BEdkb3QEZ2RvdAhHY2VkaWxsYQhnY2VkaWxsYQtIY2lyY3VtZmxleAtoY2lyY3VtZmxleARIYmFyBGhiYXIGSXRpbGRlBml0aWxkZQdJbWFjcm9uB2ltYWNyb24GSWJyZXZlBmlicmV2ZQdJb2dvbmVrB2lvZ29uZWsCSUoCaWoLSmNpcmN1bWZsZXgLamNpcmN1bWZsZXgIS2NlZGlsbGEIa2NlZGlsbGEMa2dyZWVubGFuZGljBkxhY3V0ZQZsYWN1dGUITGNlZGlsbGEIbGNlZGlsbGEGTGNhcm9uBmxjYXJvbgRMZG90BGxkb3QGTmFjdXRlBm5hY3V0ZQhOY2VkaWxsYQhuY2VkaWxsYQZOY2Fyb24GbmNhcm9uC25hcG9zdHJvcGhlA0VuZwNlbmcHT21hY3JvbgdvbWFjcm9uBk9icmV2ZQZvYnJldmUJT2RibGFjdXRlCW9kYmxhY3V0ZQZSYWN1dGUGcmFjdXRlCFJjZWRpbGxhCHJjZWRpbGxhBlJjYXJvbgZyY2Fyb24GU2FjdXRlBnNhY3V0ZQtTY2lyY3VtZmxleAtzY2lyY3VtZmxleAhUY2VkaWxsYQh0Y2VkaWxsYQZUY2Fyb24GdGNhcm9uBFRiYXIEdGJhcgZVdGlsZGUGdXRpbGRlB1VtYWNyb24HdW1hY3JvbgZVYnJldmUGdWJyZXZlBVVyaW5nBXVyaW5nCVVkYmxhY3V0ZQl1ZGJsYWN1dGUHVW9nb25lawd1b2dvbmVrC1djaXJjdW1mbGV4C3djaXJjdW1mbGV4C1ljaXJjdW1mbGV4C3ljaXJjdW1mbGV4BlphY3V0ZQZ6YWN1dGUEWmRvdAR6ZG90BWxvbmdzB0J0b3BiYXIHYnRvcGJhcgVTY2h3YQdac3Ryb2tlB3pzdHJva2UDRXpoB0dzdHJva2UHZ3N0cm9rZQZHY2Fyb24GZ2Nhcm9uBktjYXJvbgZrY2Fyb24HT29nb25lawdvb2dvbmVrCEV6aGNhcm9uCGV6aGNhcm9uCkFyaW5nYWN1dGUKYXJpbmdhY3V0ZQdBRWFjdXRlB2FlYWN1dGULT3NsYXNoYWN1dGULb3NsYXNoYWN1dGUMU2NvbW1hYWNjZW50DHNjb21tYWFjY2VudAtUY29tbWFiZWxvdwt0Y29tbWFiZWxvdwhkb3RsZXNzagVzY2h3YQNlemgQZmlyc3R0b25lY2hpbmVzZRFzZWNvbmR0b25lY2hpbmVzZRFmb3VydGh0b25lY2hpbmVzZRBudW1lcmFsc2lnbmdyZWVrFW51bWVyYWxzaWdubG93ZXJncmVlaw1xdWVzdGlvbmdyZWVrBXRvbm9zDmRpYWx5dGlrYXRvbm9zCkFscGhhdG9ub3MJYW5vdGVsZWlhDEVwc2lsb250b25vcwhFdGF0b25vcwlJb3RhdG9ub3MMT21pY3JvbnRvbm9zDFVwc2lsb250b25vcwpPbWVnYXRvbm9zEWlvdGFkaWVyZXNpc3Rvbm9zBUFscGhhBEJldGEFR2FtbWEKRGVsdGFncmVlawdFcHNpbG9uBFpldGEDRXRhBVRoZXRhBElvdGEFS2FwcGEGTGFtYmRhAk11Ak51AlhpB09taWNyb24CUGkDUmhvBVNpZ21hA1RhdQdVcHNpbG9uA1BoaQNDaGkDUHNpDElvdGFkaWVyZXNpcw9VcHNpbG9uZGllcmVzaXMKYWxwaGF0b25vcwxlcHNpbG9udG9ub3MIZXRhdG9ub3MJaW90YXRvbm9zFHVwc2lsb25kaWVyZXNpc3Rvbm9zBWFscGhhBGJldGEFZ2FtbWEFZGVsdGEHZXBzaWxvbgR6ZXRhA2V0YQV0aGV0YQRpb3RhBWthcHBhBmxhbWJkYQdtdWdyZWVrAm51AnhpB29taWNyb24DcmhvBnNpZ21hMQVzaWdtYQN0YXUHdXBzaWxvbgNwaGkDY2hpA3BzaQVvbWVnYQxpb3RhZGllcmVzaXMPdXBzaWxvbmRpZXJlc2lzDG9taWNyb250b25vcwx1cHNpbG9udG9ub3MKb21lZ2F0b25vcwd1bmkwM0Q3B3VuaTA0MDAJYWZpaTEwMDIzCWFmaWkxMDA1MQlhZmlpMTAwNTIJYWZpaTEwMDUzCWFmaWkxMDA1NAlhZmlpMTAwNTUJYWZpaTEwMDU2CWFmaWkxMDA1NwlhZmlpMTAwNTgJYWZpaTEwMDU5CWFmaWkxMDA2MAlhZmlpMTAwNjEHdW5pMDQwRAlhZmlpMTAwNjIJYWZpaTEwMTQ1CUFjeXJpbGxpYwlhZmlpMTAwMTgJYWZpaTEwMDE5CWFmaWkxMDAyMAlhZmlpMTAwMjEJYWZpaTEwMDIyCWFmaWkxMDAyNAlhZmlpMTAwMjUJYWZpaTEwMDI2CWFmaWkxMDAyNwlhZmlpMTAwMjgJYWZpaTEwMDI5CWFmaWkxMDAzMAlhZmlpMTAwMzEJYWZpaTEwMDMyCWFmaWkxMDAzMwlhZmlpMTAwMzQJYWZpaTEwMDM1CWFmaWkxMDAzNglhZmlpMTAwMzcJYWZpaTEwMDM4CWFmaWkxMDAzOQlhZmlpMTAwNDAJYWZpaTEwMDQxCWFmaWkxMDA0MglhZmlpMTAwNDMJYWZpaTEwMDQ0CWFmaWkxMDA0NQlhZmlpMTAwNDYJYWZpaTEwMDQ3CWFmaWkxMDA0OAlhZmlpMTAwNDkJYWN5cmlsbGljCWFmaWkxMDA2NglhZmlpMTAwNjcJYWZpaTEwMDY4CWFmaWkxMDA2OQlhZmlpMTAwNzAJYWZpaTEwMDcyCWFmaWkxMDA3MwlhZmlpMTAwNzQJYWZpaTEwMDc1CWFmaWkxMDA3NglhZmlpMTAwNzcJYWZpaTEwMDc4CWFmaWkxMDA3OQlhZmlpMTAwODAJYWZpaTEwMDgxCWFmaWkxMDA4MglhZmlpMTAwODMJYWZpaTEwMDg0CWFmaWkxMDA4NQlhZmlpMTAwODYJYWZpaTEwMDg3CWFmaWkxMDA4OAlhZmlpMTAwODkJYWZpaTEwMDkwCWFmaWkxMDA5MQlhZmlpMTAwOTIJYWZpaTEwMDkzCWFmaWkxMDA5NAlhZmlpMTAwOTUJYWZpaTEwMDk2CWFmaWkxMDA5Nwd1bmkwNDUwCWFmaWkxMDA3MQlhZmlpMTAwOTkJYWZpaTEwMTAwCWFmaWkxMDEwMQlhZmlpMTAxMDIJYWZpaTEwMTAzCWFmaWkxMDEwNAlhZmlpMTAxMDUJYWZpaTEwMTA2CWFmaWkxMDEwNwlhZmlpMTAxMDgJYWZpaTEwMTA5B3VuaTA0NUQJYWZpaTEwMTEwCWFmaWkxMDE5MwlhZmlpMTAxNDYJYWZpaTEwMTk0CWFmaWkxMDE0NwlhZmlpMTAxOTUJYWZpaTEwMTQ4CWFmaWkxMDE5Ngd1bmkwNDhBB3VuaTA0OEIHdW5pMDQ4Qwd1bmkwNDhEB3VuaTA0OEUHdW5pMDQ4RglhZmlpMTAwNTAJYWZpaTEwMDk4EUdoZXN0cm9rZWN5cmlsbGljEWdoZXN0cm9rZWN5cmlsbGljFFpoZWRlc2NlbmRlcmN5cmlsbGljFHpoZWRlc2NlbmRlcmN5cmlsbGljE1plZGVzY2VuZGVyY3lyaWxsaWMTemVkZXNjZW5kZXJjeXJpbGxpYxNLYWRlc2NlbmRlcmN5cmlsbGljE2thZGVzY2VuZGVyY3lyaWxsaWMYS2F2ZXJ0aWNhbHN0cm9rZWN5cmlsbGljGGthdmVydGljYWxzdHJva2VjeXJpbGxpYxFLYWJhc2hraXJjeXJpbGxpYxFrYWJhc2hraXJjeXJpbGxpYxNFbmRlc2NlbmRlcmN5cmlsbGljE2VuZGVzY2VuZGVyY3lyaWxsaWMTRXNkZXNjZW5kZXJjeXJpbGxpYxNlc2Rlc2NlbmRlcmN5cmlsbGljEVVzdHJhaWdodGN5cmlsbGljEXVzdHJhaWdodGN5cmlsbGljF1VzdHJhaWdodHN0cm9rZWN5cmlsbGljF3VzdHJhaWdodHN0cm9rZWN5cmlsbGljE0hhZGVzY2VuZGVyY3lyaWxsaWMTaGFkZXNjZW5kZXJjeXJpbGxpYxRDaGVkZXNjZW5kZXJjeXJpbGxpYxRjaGVkZXNjZW5kZXJjeXJpbGxpYxlDaGV2ZXJ0aWNhbHN0cm9rZWN5cmlsbGljGWNoZXZlcnRpY2Fsc3Ryb2tlY3lyaWxsaWMMU2hoYWN5cmlsbGljDHNoaGFjeXJpbGxpYxBwYWxvY2hrYWN5cmlsbGljEFpoZWJyZXZlY3lyaWxsaWMQemhlYnJldmVjeXJpbGxpYwd1bmkwNEM1B3VuaTA0QzYORW5ob29rY3lyaWxsaWMOZW5ob29rY3lyaWxsaWMHdW5pMDRDOQd1bmkwNENBB3VuaTA0Q0QHdW5pMDRDRQd1bmkwNENGEUFkaWVyZXNpc2N5cmlsbGljEWFkaWVyZXNpc2N5cmlsbGljC0FpZWN5cmlsbGljC2FpZWN5cmlsbGljDVNjaHdhY3lyaWxsaWMJYWZpaTEwODQ2D0ltYWNyb25jeXJpbGxpYw9pbWFjcm9uY3lyaWxsaWMRSWRpZXJlc2lzY3lyaWxsaWMRaWRpZXJlc2lzY3lyaWxsaWMRT2RpZXJlc2lzY3lyaWxsaWMRb2RpZXJlc2lzY3lyaWxsaWMPT2JhcnJlZGN5cmlsbGljD29iYXJyZWRjeXJpbGxpYwd1bmkwNEVDB3VuaTA0RUQPVW1hY3JvbmN5cmlsbGljD3VtYWNyb25jeXJpbGxpYxFVZGllcmVzaXNjeXJpbGxpYxF1ZGllcmVzaXNjeXJpbGxpYwZXZ3JhdmUGd2dyYXZlBldhY3V0ZQZ3YWN1dGUJV2RpZXJlc2lzCXdkaWVyZXNpcwd1bmkxRTlFBllncmF2ZQZ5Z3JhdmURcXVvdGVsZWZ0cmV2ZXJzZWQHdW5pMjAxRgd1bmkyMDIzBm1pbnV0ZQZzZWNvbmQNcHJpbWVyZXZlcnNlZAd1bmkyMDM2DHplcm9zdXBlcmlvcgd1bmkyMDcxDGZvdXJzdXBlcmlvcgxmaXZlc3VwZXJpb3ILc2l4c3VwZXJpb3INc2V2ZW5zdXBlcmlvcg1laWdodHN1cGVyaW9yDG5pbmVzdXBlcmlvcgx6ZXJvaW5mZXJpb3ILb25laW5mZXJpb3ILdHdvaW5mZXJpb3INdGhyZWVpbmZlcmlvcgxmb3VyaW5mZXJpb3IMZml2ZWluZmVyaW9yC3NpeGluZmVyaW9yDXNldmVuaW5mZXJpb3INZWlnaHRpbmZlcmlvcgxuaW5laW5mZXJpb3IDd29uBEV1cm8HdW5pMjBBRQd1bmkyMEIxB3VuaTIwQjQHdW5pMjBCOAd1bmkyMEI5B3VuaTIwQkEJYWZpaTYxMjQ4CWFmaWk2MTI4OQlhZmlpNjEzNTIHdW5pMjExNwd1bmkyMTIwCWVzdGltYXRlZAd1bmkyMTUwB3VuaTIxNTEHdW5pMjE1MghvbmV0aGlyZAl0d290aGlyZHMHdW5pMjE1NQd1bmkyMTU2B3VuaTIxNTcHdW5pMjE1OAd1bmkyMTU5B3VuaTIxNUEJb25lZWlnaHRoDHRocmVlZWlnaHRocwtmaXZlZWlnaHRocwxzZXZlbmVpZ2h0aHMJYXJyb3dsZWZ0B2Fycm93dXAKYXJyb3dyaWdodAlhcnJv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wMDAwMABgP6AwAGA/oDAwMDAwMDAwAAAAAQAAAPAA8AJwAADAAkADQARAAARETMRFTUhETMRATUzFSU1MxXAAkDA/cDA/oDABIADAP0AwMADAPxABIDAwMDAwAAABAAAA8ADwAnAAAMACQANABEAABERMxEVNSERMxEBNTMVNTUzFcACQMD9wMDABIADAP0AwMADAPxABIDAwMDAwAAAAAAFAAADwAPACcAAAwAJAA0AEQAVAAARETMRFTUhETMRATUzFTM1MxUlNTMVwAJAwP0AwMDA/oDABIADAP0AwMADAPxABIDAwMDAwMDAAAAAAAQAAAPAA8AJAAADAAkADQARAAARETMRFTUhETMRATUzFTM1MxXAAkDA/QDAwMAEgAMA/QDAwAMA/EAEgMDAwMAAAAAABQAAAwADwAnAAAMABwAPABMAFwAAETUhFQERMxEBNSE1IREzEQE1MxU1NTMVAwD9AMACQP3AAkDA/cDAwAMAwMACQAJA/cD+gMDAAkD8QASAwMDAwMAAAAMAAAMAA8AJAAADAAcAEwAAAREzEQE1IRUBETMRMxUjFSEVIREDAMD9wAGA/QDAwMACQP3ABUABgP6AAYDAwPxABgD9wMDAwP6AAAADAAADAAPAB4AAAwAHAA8AABE1IRUBETMRATUhNSERMxEDAP0AwAJA/cACQMADAMDAAkACQP3A/oDAwAJA/EAAAwAAA8ADwAqAAAsADwATAAARETMVITUzESMRIRERNSEVATUhFcACQMDA/cACQP3AAkADwASAwMD7gAMA/QAEgMDAAYDAwAAABAAAA8ADwAkAAAMADQARABUAABE1MxUVNSE1ITUhNTMRATUhFQE1IRXAAkD9wAJAwP0AAkD9wAJABIDAwMDAwMDA/QADAMDAAYDAwAAAAAACAAADwAPACoAACwATAAARETMVITUzESMRIRERETMVMzUzEcACQMDA/cDAwMADwASAwMD7gAMA/QAEgAJAwMD9wAAAAAQAAAPAA8AJwAADAA0AEQAZAAARNTMVFTUhNSE1ITUzEQE1IRUBETMVMzUzEcACQP3AAkDA/QACQP3AwMDABIDAwMDAwMDA/QADAMDAAYABgMDA/oAAAAADAAACQAPACQAABQARABUAAAERMxUzFQERMxUhNTMRIxEhERE1IRUCQMDA/EDAAkDAwP3AAkAC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AAAAAAADAAADAAPAB4AABwALAA8AABERMxEhFSERAREzEQE1IRXAAkD9wAJAwP0AAkADAAPA/oDA/oACQAGA/oABgMDAAAAAAAQAAAMAA8AHgAADAAcACwAPAAABETMRATUhFSURMxERNSEVAwDA/QACQP0AwAMAAwABgP6AAYDAwMABgP6AAYDAwAAAAwAAA8ADwAeAAAMABwAPAAATNSEVJREzESERITUhFSMRwAGA/cDAAYD+gAMAwAPAwMDAAkD9wAJAwMD9wAAAAAEAAAPAA8AHgAAHAAABESE1IRUhEQGA/oADwP6AA8ADAMDA/QAAAAADAAADwAPAB4AAAwAHAAsAABM1IRUlETMRIREzEcACQP0AwAJAwAPAwMDAAwD9AAMA/QAAAwAAAwADwAeAAAMABwAVAAABETMRIREzERMRIzUzESEVIxEzFSMRAwDA/EDAwMDAAYDAwMAFQAGA/oACQP3A/cABgMACQMD+gMD+gAAAAAAJAAADAAPAB4AAAwAHAAsADwATABcAGwAfACMAABERMxEhETMRATUzFTM1MxUlNTMVJTUzFTM1MxUlNTMVITUzFcACQMD9AMDAwP6AwP6AwMDA/QDAAkDAAwABgP6AAYD+gAGAwMDAwMDAwMDAwMDAwMDAwMAAAAADAAADAAPAB4AAAwAPABMAABERMxETESM1MxEzETMVIxETETMRwMDAwMDAwMDABUACQP3A/cABgMACQP3AwP6AAkACQP3AAAAFAAADwAPAB4AAAwAHAAsADwATAAATNTMVMzUzFSURMxEhETMRIREzEcDAwMD+gMD9wMACQMADwMDAwMDAAYD+gAMA/QADAP0AAAAAAwAAA8ACQAkAAAMABwALAAATETMRATUzFTM1MxXAwP6AwMDAA8ADwPxABIDAwMDAAAAAAAUAAAPAA8AJAAADAAcACwAPABMAABM1IRUlETMRIREzEQE1MxUzNTMVwAJA/QDAAkDA/QDAwMADwMDAwAMA/QADAP0AA8DAwMDAAAAEAAADwAPAB4AAAwAHAAsADwAAEzUhFSURMxEhETMRATUhFcACQP0AwAJAwP0AAkADwMDAwAJA/cACQP3AAkDAwAAAAAQAAAPAA8AJwAADAAcACwAPAAATNSEVJREzESERMxEBETMRwAJA/QDAAkDA/cDAA8DAwMADAP0AAwD9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AADDrAAAxEAAAMTIAADFYAAAxggAAMacAADHOAAAx9gAAMhwAADIyAAAySAAAMl4AADJ1AAAyjwAAMqoAADLDAAAy2QAAMvIAADMJAAAzMwAAM0YAADNdAAAzdwAAM4MAADOPAAAzqgAAM7sAADPRAAAz5wAAM+4AADP4AAA0AwAANBUAADQhAAA0NQAANFIAADRhAAA0eQAANI0AADSYAAA0pwAANLoAADTLAAA03AAANPMAADUBAAA1DwAANSEAADU0AABAAAAAgAANpQQ/l8PPPUACwYAAAAAANA0HEwAAAAA0DOsHP6AAkAIQAqAAAAACAACAAEAAAAAAYAAAAAAAAABgAAAAYAAAAGAAAADAAAABIAAAASAAAAEgAAABIAAAAGAAAADwAAAA8AAAAPAAAAEgAAAAYAAAASAAAABgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAABgAAAAYAAAAPAAAAEgAAAA8AAAASAAAAFQAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAADAAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAADAAAABIAAAAMAAAAEgAAABIAAAAJAAAAEgAAABIAAAASAAAAEgAAABIAAAAPAAAAEgAAABIAAAAGAAAAEgAAAA8AAAAJAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAAAwAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAPAAAABgAAAA8AAAAVAAAABgAAAA8AAAASAAAAEgAAABIAAAAGAAAAEgAAAA8AAwAYAAAADAAAAA8AAAAPAAAAGAAAABIAAAAMAAAAEgAAAAwAAAAMAAAACQAAABIAAAASAAAABgAAAAwAAwAMAAAADAAAAA8AAAAbAAAAGwAAABsAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAHgAAABIAAAASAAAAEgAAABIAAAASAAAADAAAAAwAAAAMAAAADAAAABUAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAPAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAeAAAAEgAAABIAAAASAAAAEgAAABIAAAAGA/0ACQAAAAkD/QAJA/0AEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABgAAAAVAAAAFQAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABUAAAAPA/0ADwP9AAwAAAAJA/0ADAAAAAkD/QAMAAAACQAAAAwAAAAGAAAAHgAAABgAAAASAAAAFQAAABIAAAAPAAAADwAAABIAAAAJAAAAEgAAAAkAAAASAAAADAAAABIAAAAMAAAAFQAAAAwAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAYAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAeAAAAHgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAAAwAAAASAAAAEgAAABIAAAAMAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAPAAAAEgAAAA8AAAASAAAAEgAAABIAAAASAAAAEgAAABUAAAAVAAAAEgAAABIAAAASAAAADwAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAAB4AAAAeAAAAEgAAABIAAAASAAAAEgAAABIAAAAMAAAAEgAAABIAAAASAAAADAAAAAwAAAAMAAAACQAAAAkAAAAMAAAACQADAAwAAAAJAAAAEgAAAA8AAAAJAAAACQAAAAYAAAAGAAAAEgAAABgAAAAGAAAAGAAAABgAAAASAAAAGAAAABgAAAAYAAAADwP9ABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAADAAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAAAwAAAASAAAAEgAAABIAAAASAAAABgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAADwAAAAYAAAAPAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAADAAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAVAAAAEgAAABIAAAASAAAADAAAAAwAAAASAAAAHgAAAB4AAAAVAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAVAAAAEgAAABIAAAAVAAAAFQAAABgAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAAA8AAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAYAAAAEgAAABUAAAASAAAAEgAAABUAAAASAAAAFQAAAA8AAAASAAAAEgAAABIAAAASAAAAEgAAABUAAAASAAAAEgAAABIAAAAGAAAADAAAABIAAAAbAAAAGwAAABUAAAAPAAAAEgAAABIAAAASAAAAFQAAABUAAAASAAAAEgAAABIAAAASAAAAFQAAABUAAAAVAAAAEgAAABIAAAASAAAAEgAAABIAAAAVAAAAFQAAABUAAAAVAAAAEgAAABIAAAAVAAAADwAAABIAAAASAAAAFQAAABIAAAAVAAAAFQAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABUAAAAVAAAAFQAAABUAAAASAAAAEgAAABIAAAASAAAABgAAABIAAAASAAAAFQAAABUAAAASAAAAEgAAABUAAAAVAAAAFQAAABIAAAAGAAAAEgAAABIAAAAeAAAAHgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAAJAAAACQAAAAkAAAAJAAAADwAAAA8AAAAPAAAADwAAAAwAAAAMAAAACQAAAAwAAAASAAAAGAAAAAwAAAASAAAADAAAABIAAAAJAAAACQAAAAwD+gAMAAAABgAAAAwAAAAMAAAADAAAAAwAAAAMAAAADAAAAAwAAAAMAAAADAAAAAwAAAAMAAAADAAAAAwAAAAMAAAADAAAAAwAAAASAAAAEgAAABIAAAASAAAAEgAAABIAAAASAAAAEgAAABgAAAAPAAAAGwAAABgAAAAYAAAAGAAAABUAAAAbAAAAGwAAACQAAAAbAAAAGwAAABsAAAAbAAAAGwAAABsAAAAbAAAAGwAAABsAAAAbAAAAGwAAABsAAAAYAAAAGAAAABgAAAAYAAAAGAAAABUAAwAYAAAAGAAAABgAAAAYAAAAGAAAABIAAAAbAAAAGAAAABIAAAASAAAAFQAAABIAAAAVAAAAFQAAAAwAAAAMAAAAEgAAABIAAAAPAAAADwAAABUAAAAVAAAAEgAAABUAAAAPAAAAFQAAABUAAAAPAAAADwAAABIAAAAJAAAACQAAABUAAAAYAAAAAAQAB//8AAgAAAAEAAAAAAAEAAAAOAAAAGAAgAAAAAgABAAEC1AABAAQAAAACAAAAAQAAAAEAAAAAABoBPgABAAAAAAAAABsAAAABAAAAAAABAAsAGwABAAAAAAACAAcAJgABAAAAAAADAA8ALQABAAAAAAAEAA8APAABAAAAAAAFAAsASwABAAAAAAAGABMAVgABAAAAAAAIABYAaQABAAAAAAAJAAwAfwABAAAAAAALABYAiwABAAAAAAAMABYAoQABAAAAAAANACgAtwABAAAAAAATACkA3wADAAEECQAAADYBCAADAAEECQABABYBPgADAAEECQACAA4BVAADAAEECQADAB4BYgADAAEECQAEAB4BgAADAAEECQAFABYBngADAAEECQAGACYBtAADAAEECQAIACwB2gADAAEECQAJABgCBgADAAEECQALACwCHgADAAEECQAMACwCSgADAAEECQANAFACdgADAAEECQATAFICxkNvcHlyaWdodCBBbmRyZXcgVHlsZXIgMjAxNE1pbmVjcmFmdGlhUmVndWxhck1pbmVjcmFmdGlhIDIuME1pbmVjcmFmdGlhIDIuMFZlcnNpb24gMi4wTWluZWNyYWZ0aWEtUmVndWxhcmh0dHA6Ly9hbmRyZXd0eWxlci5uZXRBbmRyZXcgVHlsZXJodHRwOi8vYW5kcmV3dHlsZXIubmV0aHR0cDovL2FuZHJld3R5bGVyLm5ldENyZWF0aXZlIENvbW1vbnMgQXR0cmlidXRpb24gU2hhcmUgQWxpa2VGaXZlIGJpZyBxdWFja2luZyB6ZXBoeXJzIGpvbHQgbXkgd2F4IGJlZABDAG8AcAB5AHIAaQBnAGgAdAAgAEEAbgBkAHIAZQB3ACAAVAB5AGwAZQByACAAMgAwADEANABNAGkAbgBlAGMAcgBhAGYAdABpAGEAUgBlAGcAdQBsAGEAcgBNAGkAbgBlAGMAcgBhAGYAdABpAGEAIAAyAC4AMABNAGkAbgBlAGMAcgBhAGYAdABpAGEAIAAyAC4AMABWAGUAcgBzAGkAbwBuACAAMgAuADAATQBpAG4AZQBjAHIAYQBmAHQAaQBhAC0AUgBlAGcAdQBsAGEAcgBoAHQAdABwADoALwAvAGEAbgBkAHIAZQB3AHQAeQBsAGUAcgAuAG4AZQB0AEEAbgBkAHIAZQB3ACAAVAB5AGwAZQByAGgAdAB0AHAAOgAvAC8AYQBuAGQAcgBlAHcAdAB5AGwAZQByAC4AbgBlAHQAaAB0AHQAcAA6AC8ALwBhAG4AZAByAGUAdwB0AHkAbABlAHIALgBuAGUAdABDAHIAZQBhAHQAaQB2AGUAIABDAG8AbQBtAG8AbgBzACAAQQB0AHQAcgBpAGIAdQB0AGkAbwBuACAAUwBoAGEAcgBlACAAQQBsAGkAawBlAEYAaQB2AGUAIABiAGkAZwAgAHEAdQBhAGMAawBpAG4AZwAgAHoAZQBwAGgAeQByAHMAIABqAG8AbAB0ACAAbQB5ACAAdwBhAHgAIABiAGUAZAAAAAAAAwAAAAMAAAAeAAEAAAAAAyYAAwABAAAFMAAAAAQDCAAAAK4AgAAGAC4AfgCsAX8BgwGPAZIBtwHrAe8B/wIbAjcCWQKSAscCywLdA3UDfgOKA4wDoQPOA9cEXwRjBHUEkwSdBKMEqwSzBLsEwgTKBM8E1QTZBOkE8R6FHp4e8yAjICYgMCAzIDYgOiBEIHEgeSCJIKkgrCCuILEgtCC6IQUhEyEXISAhIiEuIV4hmSIG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"

-- SmallestPixel Font Base64
local SmallFontBase64 = "AAEAAAAMAIAAAwBAT1MvMmSz/H0AAAFIAAAAYFZETVhoYG/3AAAGmAAABeBjbWFwel+AIwAADHgAAAUwZ2FzcP//AAEAAGP4AAAACGdseWa90hIhAAARqAAARRRoZWFk/hqSzwAAAMwAAAA2aGhlYQegBbsAAAEEAAAAJGhtdHhmdgAAAAABqAAABPBsb2Nh73HeDAAAVrwAAAJ6bWF4cAFBADMAAAEoAAAAIG5hbWX/R4pVAABZOAAABC1wb3N0fPqooAAAXWgAAAaOAAEAAAABAAArGZw2Xw889QAJA+gAAAAAzSamLgAAAADNJqljAAD/OASwAyAAAAAJAAIAAAAAAAAAAQAAAu7/BgAABRQAAABkBLAAAQAAAAAAAAAAAAAAAAAAATwAAQAAATwAMgAEAAAAAAABAAAAAAAAAAAAAAAAAAAAAAADAfMBkAAFAAACvAKKAAD/nAK8AooAAAD6ADIA+gAAAgAAAAAAAAAAAIAAAi8AAAAKAAAAAAAAAABQWVJTAEAAICEiAu7/BgAAAyAAyAAAAAUAAAAAAPoB9AAAACAAAAH0AAAAAAAAAfQAAAH0AAACWAAAAlgAAAJYAAAAyAAAAS0AAAEtAAABkAAAAZAAAAEsAAABkAAAAMgAAAJYAAAB9AAAAZAAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAMgAAAEsAAABkAAAAZAAAAGQAAAB9AAAAfQAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAZAAAAH0AAAB9AAAAfQAAAJYAAAB9AAAAfQAAAH0AAAB9AAAAfQAAAH0AAABkAAAAfQAAAGQAAACWAAAAfQAAAGQAAAB9AAAASwAAAJYAAABLAAAAlgAAAH0AAABLAAAAfQAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAfQAAAH0AAABkAAAAfQAAAH0AAAB9AAAAlgAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAfQAAAGQAAAB9AAAAZAAAAJYAAAB9AAAAZAAAAH0AAABkAAAAMgAAAGQAAAB9AAAAlgAAAH0AAABLAAAAfQAAAJYAAACWAAAAZAAAAGQAAACWAAAAyAAAAJYAAABkAAAAlgAAAH0AAACWAAAAZAAAAJYAAABLAAAASwAAAJYAAACWAAAASwAAAGQAAAB9AAAA4QAAAJYAAABkAAAAlgAAAH0AAACWAAAAZAAAAGQAAABkAAAAfQAAAH0AAAB9AAAAMgAAAH0AAAB9AAAAyAAAAH0AAACvAAAAfQAAAEsAAADIAAAAZAAAAGQAAABkAAAAZAAAAGQAAAB9AAAAlgAAAJYAAAAyAAAAfQAAAK8AAAB9AAAArwAAAH0AAAB9AAAAfQAAAGQAAAB9AAAAfQAAAH0AAAB9AAAAlgAAAH0AAACWAAAAfQAAAH0AAAB9AAAAfQAAAH0AAACWAAAAfQAAAH0AAAB9AAAAfQAAAH0AAABkAAAAfQAAAJYAAAB9AAAAlgAAAH0AAACWAAAArwAAAJYAAACvAAAAfQAAAH0AAACWAAAAfQAAAH0AAAB9AAAAfQAAAH0AAACWAAAAfQAAAJYAAAB9AAAAfQAAAH0AAAB9AAAAfQAAAJYAAAB9AAAAfQAAAH0AAAB9AAAAfQAAAGQAAAB9AAAAlgAAAH0AAACWAAAAfQAAAJYAAACvAAAAlgAAAK8AAAB9AAAAfQAAAJYAAAB9AAAAfQAAAH0AAAAyAAAAlgAAAH0AAABkAAAAZAAAAH0AAAB9AAAAfQAAAEsAAABkAAAAZAAAAH0AAAFFAAABRQAAAUUAAAB9AAAAfQAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAlgAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAZAAAAGQAAABkAAAAZAAAAJYAAAB9AAAAfQAAAH0AAAB9AAAAfQAAAH0AAABkAAAAlgAAAH0AAAB9AAAAfQAAAH0AAABkAAAAfQAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAfQAAAH0AAACWAAAAfQAAAH0AAAB9AAAAfQAAAH0AAABkAAAAZAAAAGQAAABkAAAAlgAAAH0AAAB9AAAAfQAAAH0AAAB9AAAAfQAAAGQAAACWAAAAfQAAAH0AAAB9AAAAfQAAAGQAAAB9AAAAZAAAAJYAAACWAAAAfQAAAH0AAABkAAAAfQAAAH0AAAB9AAAAZAAAAH0AAACWAAAAMgAAAGQAAAAAAABAAEBAQEBAAwA+Aj/AAgAB//+AAkACP/+AAoACP/+AAsACf/9AAwACv/9AA0AC//9AA4ADP/9AA8ADP/9ABAADf/8ABEADv/8ABIAD//8ABMAEP/8ABQAEP/8ABUAEf/7ABYAEv/7ABcAE//7ABgAFP/7ABkAFP/7ABoAFf/6ABsAFv/6ABwAF//6AB0AGP/6AB4AGP/6AB8AGf/5ACAAGv/5ACEAG//5ACIAHP/5ACMAHP/5ACQAHf/4ACUAHv/4ACYAH//4ACcAIP/4ACgAIP/4ACkAIf/3ACoAIv/3ACsAI//3ACwAJP/3AC0AJP/3AC4AJf/2AC8AJv/2ADAAJ//2ADEAKP/2ADIAKP/2ADMAKf/1ADQAKv/1ADUAK//1ADYALP/1ADcALP/1ADgALf/0ADkALv/0ADoAL//0ADsAMP/0ADwAMP/0AD0AMf/zAD4AMv/zAD8AM//zAEAANP/zAEEANP/zAEIANf/yAEMANv/yAEQAN//yAEUAOP/yAEYAOP/yAEcAOf/xAEgAOv/xAEkAO//xAEoAPP/xAEsAPP/xAEwAPf/wAE0APv/wAE4AP//wAE8AQP/wAFAAQP/wAFEAQf/vAFIAQv/vAFMAQ//vAFQARP/vAFUARP/vAFYARf/uAFcARv/uAFgAR//uAFkASP/uAFoASP/uAFsASf/tAFwASv/tAF0AS//tAF4ATP/tAF8ATP/tAGAATf/sAGEATv/sAGIAT//sAGMAUP/sAGQAUP/sAGUAUf/rAGYAUv/rAGcAU//rAGgAVP/rAGkAVP/rAGoAVf/qAGsAVv/qAGwAV//qAG0AWP/qAG4AWP/qAG8AWf/pAHAAWv/pAHEAW//pAHIAXP/pAHMAXP/pAHQAXf/oAHUAXv/oAHYAX//oAHcAYP/oAHgAYP/oAHkAYf/nAHoAYv/nAHsAY//nAHwAZP/nAH0AZP/nAH4AZf/mAH8AZv/mAIAAZ//mAIEAaP/mAIIAaP/mAIMAaf/lAIQAav/lAIUAa//lAIYAbP/lAIcAbP/lAIgAbf/kAIkAbv/kAIoAb//kAIsAcP/kAIwAcP/kAI0Acf/jAI4Acv/jAI8Ac//jAJAAdP/jAJEAdP/jAJIAdf/iAJMAdv/iAJQAd//iAJUAeP/iAJYAeP/iAJcAef/hAJgAev/hAJkAe//hAJoAfP/hAJsAfP/hAJwAff/gAJ0Afv/gAJ4Af//gAJ8AgP/gAKAAgP/gAKEAgf/fAKIAgv/fAKMAg//fAKQAhP/fAKUAhP/fAKYAhf/eAKcAhv/eAKgAh//eAKkAiP/eAKoAiP/eAKsAif/dAKwAiv/dAK0Ai//d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ATkBOgE7ATwBPQE+AT8BQAFBAUIBQwFEAUUBRgFHAUgBSQFKAUsBTAFNAU4BTwFQAVEBUgFTAVQBVQFWAVcBWAFZAVoBWwFcAV0BXgFfAWABYQFiAWMBZAFlAWYAowCEAIUAlgCOAJ0A8gDzAI0A3gDxAJ4A9QD0APYAogCtAMkAxwCuAGIAYwCQAGQAywBlAMgAygDPAMwAzQDOAOkAZgDTANAA0QCvAGcA8ACRANYA1ADVAGgA6wDtAIkAagBpAGsAbQBsAG4AoABvAHEAcAByAHMAdQB0AHYAdwDqAHgAegB5AHsAfQB8ALgAoQB/AH4AgACBAOwA7gC6ALAAsQDkAOUAuwDmAOcApgDYANkABgAEAAUFLm51bGwJYWZpaTEwMDUxCWFmaWkxMDA1MglhZmlpMTAxMDAERXVybwlhZmlpMTAwNTgJYWZpaTEwMDU5CWFmaWkxMDA2MQlhZmlpMTAwNjAJYWZpaTEwMTQ1CWFmaWkxMDA5OQlhZmlpMTAxMDYJYWZpaTEwMTA3CWFmaWkxMDEwOQlhZmlpMTAxMDgJYWZpaTEwMTkzCWFmaWkxMDA2MglhZmlpMTAxMTAJYWZpaTEwMDU3CWFmaWkxMDA1MAlhZmlpMTAwMjMJYWZpaTEwMDUzB3VuaTAwQUQJYWZpaTEwMDU2CWFmaWkxMDA1NQlhZmlpMTAxMDMJYWZpaTEwMDk4DnBlcmlvZGNlbnRlcmVkCWFmaWkxMDA3MQlhZmlpNjEzNTIJYWZpaTEwMTAxCWFmaWkxMDEwNQlhZmlpMTAwNTQJYWZpaTEwMTAyCWFmaWkxMDEwNAlhZmlpMTAwMTcJYWZpaTEwMDE4CWFmaWkxMDAxOQlhZmlpMTAwMjAJYWZpaTEwMDIxCWFmaWkxMDAyMglhZmlpMTAwMjQJYWZpaTEwMDI1CWFmaWkxMDAyNglhZmlpMTAwMjcJYWZpaTEwMDI4CWFmaWkxMDAyOQlhZmlpMTAwMzAJYWZpaTEwMDMxCWFmaWkxMDAzMglhZmlpMTAwMzMJYWZpaTEwMDM0CWFmaWkxMDAzNQlhZmlpMTAwMzYJYWZpaTEwMDM3CWFmaWkxMDAzOAlhZmlpMTAwMzkJYWZpaTEwMDQwCWFmaWkxMDA0MQlhZmlpMTAwNDIJYWZpaTEwMDQzCWFmaWkxMDA0NAlhZmlpMTAwNDUJYWZpaTEwMDQ2CWFmaWkxMDA0NwlhZmlpMTAwNDgJYWZpaTEwMDQ5CWFmaWkxMDA2NQlhZmlpMTAwNjYJYWZpaTEwMDY3CWFmaWkxMDA2OAlhZmlpMTAwNjkJYWZpaTEwMDcwCWFmaWkxMDA3MglhZmlpMTAwNzMJYWZpaTEwMDc0CWFmaWkxMDA3NQlhZmlpMTAwNzYJYWZpaTEwMDc3CWFmaWkxMDA3OAlhZmlpMTAwNzkJYWZpaTEwMDgwCWFmaWkxMDA4MQlhZmlpMTAwODIJYWZpaTEwMDgzCWFmaWkxMDA4NAlhZmlpMTAwODUJYWZpaTEwMDg2CWFmaWkxMDA4NwlhZmlpMTAwODgJYWZpaTEwMDg5CWFmaWkxMDA5MAlhZmlpMTAwOTEJYWZpaTEwMDkyCWFmaWkxMDA5MwlhZmlpMTAwOTQJYWZpaTEwMDk1CWFmaWkxMDA5NglhZmlpMTAwOTcNYWZpaTEwMDQ1LjAwMQ1hZmlpMTAwNDcuMDAxAAAAAAAB//8AAA==";

if getcustomasset then
    Fonts.SmallestPixel = Font.new(
        _RegisterFontFile("SmallestPixel7", 400, "normal",
            {Id = "smallest-pixel7.ttf", Font = crypt.base64.decode(SmallFontBase64)})
    )
    Fonts.Pixel = Font.new(
        _RegisterFontFile("Minecraft", 400, "normal",
            {Id = "Minecraft.ttf", Font = crypt.base64.decode(MinecraftBase64)})
    )
else
    Fonts.SmallestPixel = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular)
    Fonts.Pixel = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
end

local EntityType = {}
EntityType.__index = EntityType

function EntityType.new(name, customSettings)
    local self = setmetatable({}, EntityType)

    self.name = name
    self.enabled = true

    self.settings = createDefaultSettings()

    if customSettings then
        for key, value in pairs(customSettings) do
            if self.settings[key] then
                if type(value) == "table" then
                    for subkey, subvalue in pairs(value) do
                        self.settings[key][subkey] = subvalue
                    end
                else
                    self.settings[key] = value
                end
            end
        end
    end

    for textType, data in pairs(self.settings) do
        if type(data) == "table" and type(data.priority) == "number" then

            if data.top == true then
                self.settings.text.priority.top[textType] = data.priority

            elseif data.top == false then
                self.settings.text.priority.bottom[textType] = data.priority

            else

                self.settings.text.priority.flags[textType] = data.priority

            end
        end
    end

    self.entities = {
        box = {},
        boxoutline = {},
        healthbar = {},
        healthbarbackground = {},
        healthbartext = {},
        skeleton = {},
        chams = {},
        imagebox = {},
        oofarrows = {},
        vischeckimage = {},
        weaponimage = {},
        images = {top = {}, bottom = {}, flags = {}},
        text = {top = {}, bottom = {}, flags = {}}
    }

    for textType, data in pairs(self.settings) do
        if type(data) == "table" and data.priority ~= nil then
            if self.settings.text.priority.flags[textType] then
                self.entities.text.flags[textType] = {}
                self.entities.images.flags[textType] = {}
            elseif data.top == true then
                self.entities.text.top[textType] = {}
                self.entities.images.top[textType] = {}
            elseif data.top == false then
                self.entities.text.bottom[textType] = {}
                self.entities.images.bottom[textType] = {}
            end
        end
    end

    self.valid = {}
    self.validr6 = {}
    self.isModel = {}
    self.isPart = {}
    self.displayNames = {}
    self.customData = {}

    self.mins = {}
    self.maxes = {}
    self.onscreens = {}
    self.textoffsets = {}
    self.imageoffsets = {}

    self.connections = {}

    self.deathConnections = {}

    return self
end

function EntityType:CalculateTextOffsets(id, min, max)
    if not self.textoffsets[id] then
        self.textoffsets[id] = {top = {}, bottom = {}, flags = {}}
    end

    if not self.imageoffsets[id] then
        self.imageoffsets[id] = {top = {}, bottom = {}, flags = {}}
    end

    for textType, priority in pairs(self.settings.text.priority.top) do
        if self.settings[textType] and self.settings[textType].enabled then
            local location = priority
            for i, v in pairs(self.settings.text.priority.top) do
                if v < priority and self.settings[i] and not self.settings[i].enabled then
                    location -= 1
                end
            end
            local offset = (self.settings.text.spacing + self.settings[textType].size) * location
            self.textoffsets[id].top[textType] = {location = location, offset = offset}
        end
    end

    for textType, priority in pairs(self.settings.text.priority.bottom) do
        if self.settings[textType] and self.settings[textType].enabled then
            local location = priority
            for i, v in pairs(self.settings.text.priority.bottom) do
                if v < priority and self.settings[i] and not self.settings[i].enabled then
                    location -= 1
                end
            end
            local offset = self.settings.text.spacing + (self.settings.text.spacing + self.settings[textType].size) * (location - 1)
            self.textoffsets[id].bottom[textType] = {location = location, offset = offset}
        end
    end

    local enabledFlags = {}
    for textType, priority in pairs(self.settings.text.priority.flags) do
        if self.settings[textType] and self.settings[textType].enabled then
            table.insert(enabledFlags, {
                name = textType,
                priority = priority,
                height = self.settings[textType].size
            })
        end
    end

    table.sort(enabledFlags, function(a, b) return a.priority < b.priority end)

    local cumulativeOffset = self.settings.text.flags.padding
    for i, item in ipairs(enabledFlags) do
        self.textoffsets[id].flags[item.name] = {
            location = i,
            offset = cumulativeOffset
        }

        cumulativeOffset = cumulativeOffset + item.height + self.settings.text.flags.spacing
    end
end

function EntityType:IsValid(target, id)
    if not target or not target.Parent then
        return false
    end

    if self.isPart[id] then
        return true
    end

    if self.settings.healthcheck then
        local hum = target:FindFirstChild("Humanoid") or target:FindFirstChildOfClass("Humanoid")
        if not hum then
            return false
        end

        if not (hum.Health > 0) then
            return false
        end
    end

    return true
end

function EntityType:CheckR6(char)
    if char:FindFirstChild('RightHand') then
        return false
    end
    return true
end

local ESPEnabled = true

local Friends = {}

local heldItemImages = {
    ["Bruno's M4A1"]          = "rbxassetid://15574295393",
    ["Crossbow"]              = "rbxassetid://15305596532",
    ["Salvaged Shovel"]       = "rbxassetid://15073386763",
    ["Salvaged Pipe Rifle"]   = "rbxassetid://15092314723",
    ["Steel Axe"]             = "rbxassetid://15132541486",
    ["Salvaged RPG"]          = "rbxassetid://15132772506",
    ["Small Medkit"]          = "rbxassetid://15132566142",
    ["Yellow Keycard"]        = "rbxassetid://15303938691",
    ["Salvaged Pump Action"]  = "rbxassetid://15092313032",
    ["Pink Keycard"]          = "rbxassetid://15303938752",
    ["Salvaged SMG"]          = "rbxassetid://15132874040",
    ["Salvaged AK47"]         = "rbxassetid://14882620172",
    ["Boulder"]               = "rbxassetid://15304806846",
    ["Care Package Signal"]   = "rbxassetid://15132798244",
    ["Salvaged AK74u"]        = "rbxassetid://15073408197",
    ["ez shovel"]             = "rbxassetid://15073386763",
    ["Dynamite Stick"]        = "rbxassetid://15127430886",
    ["Military Barrett"]      = "rbxassetid://15346280030",
    ["Nail Gun"]              = "rbxassetid://15305104734",
    ["Iron Shard Hatchet"]    = "rbxassetid://15132541025",
    ["Military M4A1"]         = "rbxassetid://15346201415",
    ["Wooden Spear"]          = "rbxassetid://15303292373",
    ["Dynamite Bundle"]       = "rbxassetid://15127431071",
    ["Stone Spear"]           = "rbxassetid://15303292549",
    ["Salvaged P250"]         = "rbxassetid://15305065991",
    ["Iron Shard Pickaxe"]    = "rbxassetid://15132541267",
    ["Military PKM"]          = "rbxassetid://15346287550",
    ["Steel Shovel"]          = "rbxassetid://15132541679",
    ["Timed Charge"]          = "rbxassetid://15132620220",
    ["Steel Pickaxe"]         = "rbxassetid://15132541554",
    ["Lighter"]               = "rbxassetid://15128007580",
    ["Blueprint"]             = "rbxassetid://15132469785",
    ["Salvaged M14"]          = "rbxassetid://14882876522",
    ["Machete"]               = "rbxassetid://16249771824",
    ["Stone Hatchet"]         = "rbxassetid://15073617325",
    ["Bandage"]               = "rbxassetid://14134567329",
    ["Saw Bat"]               = "rbxassetid://16249771997",
    ["Wooden Bow"]            = "rbxassetid://15313266356",
    ["Military Grenade"]      = "rbxassetid://15346283342",
    ["Health Pen"]            = "rbxassetid://15304289469",
    ["Candy Cane"]            = "rbxassetid://15132567147",
    ["Hammer"]                = "rbxassetid://15318044673",
    ["Military AA12"]         = "rbxassetid://15346289730",
    ["Salvaged Python"]       = "rbxassetid://15188995729",
    ["Purple Keycard"]        = "rbxassetid://15303938707",
    ["Bone Tool"]             = "rbxassetid://15073616534",
    ["Stone Pickaxe"]         = "rbxassetid://15073617163",
    ["Salvaged Skorpion"]     = "rbxassetid://15369212859",
    ["Salvaged Break Action"] = "rbxassetid://15188994406",
}

local ESP = {
    entityTypes = {},
    whitelistedWeapons = {"Salvaged AK47"},
    r15parts = {"HumanoidRootPart", "RightHand", "RightLowerArm", "RightUpperArm", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "Head"},
    r6parts = {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "HumanoidRootPart"},
    renderConnection = nil,
    chamsConnection = nil,
    imageCache = {},
    Enabled = true,
    Friends = Friends,
    heldItemImages = heldItemImages,
    Fonts = Fonts,
    activeFont = Fonts.Pixel,
    chamsContainer = nil, -- Folder in CoreGui; adornments parented here to avoid workspace detection
    team = {}, -- Table to store team member UserIds
    teamCheckEnabled = false, -- Toggle team check on/off
}

function ESP:SetFont(nameOrObject)
    if type(nameOrObject) == "string" then
        local f = self.Fonts[nameOrObject]
        if not f then
            warn("[ESP] Font '" .. nameOrObject .. "' not found in ESP.Fonts. Register it first with ESP:AddFont().")
            return
        end
        self.activeFont = f
    else
        self.activeFont = nameOrObject
    end
end

function ESP:AddFont(name, ttfFilename, base64Data)
    if not getcustomasset then
        warn("[ESP] AddFont requires getcustomasset support. Falling back to active font.")
        return
    end
    local fontAsset = _RegisterFontFile(name, 400, "normal", {Id = ttfFilename, Font = crypt.base64.decode(base64Data)})
    self.Fonts[name] = Font.new(fontAsset)
    return self.Fonts[name]
end

function ESP:SetEnabled(enabled)
    self.Enabled = enabled
end

function ESP:CreateEntityType(name, customSettings)
    if self.entityTypes[name] then
        warn("Entity type '" .. name .. "' already exists!")
        return self.entityTypes[name]
    end

    local entityType = EntityType.new(name, customSettings)
    self.entityTypes[name] = entityType

    return entityType
end

function ESP:GetEntityType(name)
    return self.entityTypes[name]
end

function ESP:RemoveEntityType(name)
    local entityType = self.entityTypes[name]
    if not entityType then
        warn("Entity type '" .. name .. "' does not exist!")
        return
    end

    for id, _ in pairs(entityType.valid) do
        self:_RemoveAllESP(entityType, id)
    end

    for _, conn in pairs(entityType.connections) do
        if conn then
            conn:Disconnect()
        end
    end

    for _, conn in pairs(entityType.deathConnections) do
        if conn then
            conn:Disconnect()
        end
    end

    self.entityTypes[name] = nil

end

function ESP:SetEntityTypeEnabled(name, enabled)
    local entityType = self.entityTypes[name]
    if not entityType then
        warn("Entity type '" .. name .. "' does not exist!")
        return
    end

    entityType.enabled = enabled
end

function ESP:TrackPlayer(player, entityTypeName)
    entityTypeName = entityTypeName or "players"
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    if player == lp then
        return
    end

    for _, friendId in ipairs(self.Friends) do
        if player.UserId == friendId then
            return
        end
    end

    if self.teamCheckEnabled and self.team[player.UserId] then
        return
    end

    local id = player.UserId

    local function onCharacter(char)
        -- Clean up old character's ESP before setting up new one
        self:_RemoveAllESP(entityType, id)

        entityType.valid[id] = char
        entityType.validr6[id] = entityType:CheckR6(char)
        entityType.isModel[id] = false
        entityType.isPart[id] = false
        entityType.displayNames[id] = player.Name

        if entityType.deathConnections[id] then
            entityType.deathConnections[id]:Disconnect()
            entityType.deathConnections[id] = nil
        end

        local hum = char:FindFirstChild("Humanoid") or char:FindFirstChildOfClass("Humanoid")
        if hum then
            entityType.deathConnections[id] = hum.Died:Connect(function()
                self:_RemoveAllESP(entityType, id)
            end)
        end
    end

    if player.Character then
        onCharacter(player.Character)
    end

    entityType.connections[id] = player.CharacterAdded:Connect(onCharacter)
end

function ESP:TrackModel(entityTypeName, model, displayName)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    if not model or not model:IsA("Model") then
        warn("Invalid model provided!")
        return
    end

    local id = HttpService:GenerateGUID(false)

    entityType.valid[id] = model
    entityType.isModel[id] = true
    entityType.isPart[id] = false
    entityType.displayNames[id] = displayName or model.Name

    entityType.connections[id] = model.AncestryChanged:Connect(function(_, parent)
        if not parent then

            self:Untrack(entityTypeName, id)
        end
    end)

    return id
end

function ESP:TrackPart(entityTypeName, part, displayName)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    if not part or not part:IsA("BasePart") then
        warn("Invalid part provided!")
        return
    end

    local id = HttpService:GenerateGUID(false)

    entityType.valid[id] = part
    entityType.isModel[id] = false
    entityType.isPart[id] = true
    entityType.displayNames[id] = displayName or part.Name

    entityType.connections[id] = part.AncestryChanged:Connect(function(_, parent)
        if not parent then

            self:Untrack(entityTypeName, id)
        end
    end)

    return id
end

function ESP:TrackModels(entityTypeName, models, getDisplayName)
    local ids = {}
    for _, model in pairs(models) do
        local displayName = getDisplayName and getDisplayName(model) or model.Name
        local id = self:TrackModel(entityTypeName, model, displayName)
        table.insert(ids, id)
    end
    return ids
end

function ESP:Untrack(entityTypeName, id)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    self:_RemoveAllESP(entityType, id)

    entityType.valid[id] = nil
    entityType.validr6[id] = nil
    entityType.isModel[id] = nil
    entityType.isPart[id] = nil
    entityType.displayNames[id] = nil
    entityType.customData[id] = nil
    entityType.mins[id] = nil
    entityType.maxes[id] = nil
    entityType.onscreens[id] = nil
    entityType.textoffsets[id] = nil
    entityType.imageoffsets[id] = nil
    if entityType._chamLastColor then
        entityType._chamLastColor[id] = nil
    end

    if entityType.connections[id] then
        entityType.connections[id]:Disconnect()
        entityType.connections[id] = nil
    end

    if entityType.deathConnections[id] then
        entityType.deathConnections[id]:Disconnect()
        entityType.deathConnections[id] = nil
    end

end

function ESP:UntrackAll(entityTypeName)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    for id, _ in pairs(entityType.valid) do
        self:Untrack(entityTypeName, id)
    end
end

function ESP:SetSetting(entityTypeName, category, key, value)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    if not entityType.settings[category] then
        warn("Setting category '" .. category .. "' does not exist!")
        return
    end

    entityType.settings[category][key] = value
end

function ESP:GetSetting(entityTypeName, category, key)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("[ESP] Entity type '" .. entityTypeName .. "' does not exist!")
        return nil
    end

    if not entityType.settings[category] then
        warn("[ESP] Setting category '" .. category .. "' does not exist!")
        return nil
    end

    return entityType.settings[category][key]
end

function ESP:UpdateSettings(entityTypeName, settings)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    for category, values in pairs(settings) do
        if entityType.settings[category] then
            for key, value in pairs(values) do
                entityType.settings[category][key] = value
            end
        end
    end
end

function ESP:SetPlayerSetting(category, key, value)
    return self:SetSetting("players", category, key, value)
end

function ESP:GetPlayerSetting(category, key)
    return self:GetSetting("players", category, key)
end

function ESP:SetCustomData(entityTypeName, id, key, value)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    if not entityType.customData[id] then
        entityType.customData[id] = {}
    end

    entityType.customData[id][key] = value
end

function ESP:GetCustomData(entityTypeName, id, key)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        return nil
    end

    if not entityType.customData[id] then
        return nil
    end

    return entityType.customData[id][key]
end

function ESP:AddWhitelistedWeapon(weaponName)
    table.insert(self.whitelistedWeapons, weaponName)
end

function ESP:RemoveWhitelistedWeapon(weaponName)
    local index = table.find(self.whitelistedWeapons, weaponName)
    if index then
        table.remove(self.whitelistedWeapons, index)
    end
end

function ESP:GetTrackedIDs(entityTypeName)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return {}
    end

    local ids = {}
    for id, _ in pairs(entityType.valid) do
        table.insert(ids, id)
    end
    return ids
end

function ESP:GetDisplayName(entityTypeName, id)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        return "Unknown"
    end

    return entityType.displayNames[id] or "Unknown"
end

function ESP:SetDisplayName(entityTypeName, id, name)
    local entityType = self.entityTypes[entityTypeName]

    if not entityType then
        warn("Entity type '" .. entityTypeName .. "' does not exist!")
        return
    end

    entityType.displayNames[id] = name
end

function ESP:_CreateBox(entityType, id, min, max, onscreen)
    local outline = Drawing.new('Square')
    outline.Visible = onscreen
    outline.Transparency = entityType.settings.boxoutline.transparency
    outline.Color = entityType.settings.boxoutline.color
    outline.Thickness = entityType.settings.box.thickness + entityType.settings.boxoutline.thickness * 2

    local box = Drawing.new('Square')
    box.Visible = onscreen
    box.Transparency = entityType.settings.box.transparency
    box.Color = entityType.settings.box.color
    box.Thickness = entityType.settings.box.thickness

    if onscreen and min and max and min.x and min.y and max.x and max.y then
        local pos = Vector2.new(min.x, min.y)
        outline.Position = pos
        box.Position = pos
        local length = math.max(30, max.x - min.x)
        local height = math.max(30, max.y - min.y)
        length = math.min(length, 500)
        height = math.min(height, 500)
        outline.Size = Vector2.new(length, height)
        box.Size = Vector2.new(length, height)
    end

    entityType.entities.box[id] = box
    entityType.entities.boxoutline[id] = outline
end

function ESP:_CreateText(entityType, id, textType, min, max, onscreen)
    local text = Drawing.new('Text')
    text.Visible = onscreen

    pcall(function()
        text.FontFace = ESP.activeFont
    end)

    local place = 'bottom'
    if entityType.settings[textType].top then
        place = 'top'
    elseif entityType.settings.text.priority.flags[textType] then
        place = 'flags'
    end

    text.Transparency = entityType.settings[textType].transparency
    text.Color = entityType.settings[textType].color
    text.Size = entityType.settings[textType].size
    text.Outline = entityType.settings[textType].outline
    text.OutlineColor = entityType.settings[textType].outlinecolor
    text.Center = place ~= 'flags'

    if textType == "name" then
        text.Text = entityType.displayNames[id] or "Unknown"
    elseif textType == "distance" then
        text.Text = '[0 m]'
    elseif textType == "weapon" then
        text.Text = '[None]'
    else
        text.Text = '[' .. textType:upper() .. ']'
    end

    if onscreen and entityType.textoffsets[id] and entityType.textoffsets[id][place][textType] then
        local offset = entityType.textoffsets[id][place][textType].offset
        local yPos
        local xPos

        if place == 'flags' then
            yPos = min.y + offset
            xPos = max.x
        else
            yPos = place == 'top' and (min.y - offset) or (max.y + offset)
            xPos = min.x + (max.x - min.x) / 2
        end

        text.Position = Vector2.new(xPos, yPos)
    end

    entityType.entities.text[place][textType][id] = text

end

local function HealthColor(pct)
    pct = math.clamp(pct, 0, 1)
    if pct >= 0.5 then
        return Color3.new(1 - (pct - 0.5) * 2, 1, 0)
    else
        return Color3.new(1, pct * 2, 0)
    end
end

function ESP:_CreateHealthbar(entityType, id, min, max, onscreen)
    local left = min.x - entityType.settings.healthbar.gap - entityType.settings.healthbar.width - entityType.settings.healthbar.borderthickness
    local height = max.y - min.y

    local background = Drawing.new("Square")
    background.Visible = onscreen and entityType.settings.healthbar.backgroundenabled
    background.Transparency = 1
    background.Color = entityType.settings.healthbar.backgroundcolor
    background.Filled = true

    local bar = Drawing.new('Square')
    bar.Visible = onscreen
    bar.Transparency = 1
    bar.Filled = true

    local htxt = Drawing.new('Text')
    htxt.Visible = false
    htxt.Center = true
    htxt.Outline = entityType.settings.healthbar.healthtext.outline
    htxt.OutlineColor = entityType.settings.healthbar.healthtext.outlinecolor
    htxt.Color = entityType.settings.healthbar.healthtext.color
    htxt.Size = entityType.settings.healthbar.healthtext.size
    pcall(function() htxt.FontFace = ESP.activeFont end)

    if onscreen then
        if entityType.settings.healthbar.backgroundenabled then
            local size = Vector2.new(entityType.settings.healthbar.width + entityType.settings.healthbar.borderthickness * 2, height + entityType.settings.healthbar.borderthickness * 2)
            local pos = Vector2.new(left - entityType.settings.healthbar.borderthickness, min.y - entityType.settings.healthbar.borderthickness)
            background.Position = pos
            background.Size = size
        end

        local target = entityType.valid[id]
        local hum = target:FindFirstChild("Humanoid") or target:FindFirstChildOfClass("Humanoid")
        local health = 100
        local maxhealth = 100

        if hum then
            health = hum.Health
            maxhealth = hum.MaxHealth
        end

        local pct = (maxhealth > 0) and (health / maxhealth) or 0
        local healthchange = height * (1 - pct)

        local size = Vector2.new(entityType.settings.healthbar.width, height - healthchange)
        local pos = Vector2.new(left, min.y + healthchange)

        bar.Color = entityType.settings.healthbar.dynamiccolor and HealthColor(pct) or entityType.settings.healthbar.healthcolor
        bar.Size = size
        bar.Position = pos

        if entityType.settings.healthbar.healthtext.enabled then
            local hs = entityType.settings.healthbar.healthtext
            local textColor = (hs.usedynamiccolor) and HealthColor(pct) or hs.color
            htxt.Text = tostring(math.floor(health + 0.5))
            htxt.Color = textColor
            htxt.Position = Vector2.new(left - entityType.settings.healthbar.borderthickness - 12, min.y + healthchange)
            htxt.Visible = true
        end
    end

    entityType.entities.healthbar[id] = bar
    entityType.entities.healthbarbackground[id] = background
    entityType.entities.healthbartext[id] = htxt
end

function ESP:_CreateSkeleton(entityType, id, min, max, onscreen)
    local bones
    if entityType.validr6[id] == true then

        bones = {
            Head_Spine = {line = Drawing.new('Line')},
            Spine = {line = Drawing.new('Line')},
            LeftArm = {line = Drawing.new('Line')},
            LeftArm_UpperTorso = {line = Drawing.new('Line')},
            RightArm = {line = Drawing.new('Line')},
            RightArm_UpperTorso = {line = Drawing.new('Line')},
            LeftLeg = {line = Drawing.new('Line')},
            LeftLeg_LowerTorso = {line = Drawing.new('Line')},
            RightLeg = {line = Drawing.new('Line')},
            RightLeg_LowerTorso = {line = Drawing.new('Line')}
        }
    else

        bones = {
            Head_UpperTorso = {line = Drawing.new('Line')},
            UpperTorso_LowerTorso = {line = Drawing.new('Line')},
            UpperTorso_LeftUpperArm = {line = Drawing.new('Line')},
            LeftUpperArm_LeftLowerArm = {line = Drawing.new('Line')},
            LeftLowerArm_LeftHand = {line = Drawing.new('Line')},
            UpperTorso_RightUpperArm = {line = Drawing.new('Line')},
            RightUpperArm_RightLowerArm = {line = Drawing.new('Line')},
            RightLowerArm_RightHand = {line = Drawing.new('Line')},
            LowerTorso_LeftUpperLeg = {line = Drawing.new('Line')},
            LeftUpperLeg_LeftLowerLeg = {line = Drawing.new('Line')},
            LeftLowerLeg_LeftFoot = {line = Drawing.new('Line')},
            LowerTorso_RightUpperLeg = {line = Drawing.new('Line')},
            RightUpperLeg_RightLowerLeg = {line = Drawing.new('Line')},
            RightLowerLeg_RightFoot = {line = Drawing.new('Line')},
            LeftArm = {line = Drawing.new('Line')},
            LeftArm_UpperTorso = {line = Drawing.new('Line')},
            RightArm = {line = Drawing.new('Line')},
            RightArm_UpperTorso = {line = Drawing.new('Line')},
            LeftLeg = {line = Drawing.new('Line')},
            LeftLeg_LowerTorso = {line = Drawing.new('Line')},
            RightLeg = {line = Drawing.new('Line')},
            RightLeg_LowerTorso = {line = Drawing.new('Line')}
        }
    end

    for i, v in pairs(bones) do
        v.line.Visible = false
        v.line.From = Vector2.new(0, 0)
        v.line.To = Vector2.new(1, 1)
        v.line.Color = entityType.settings.skeleton.color
        v.line.Thickness = entityType.settings.skeleton.thickness
        v.line.Transparency = entityType.settings.skeleton.transparency
    end

    entityType.entities.skeleton[id] = bones
end

function ESP:_CreateImageBox(entityType, id, min, max, onscreen)
    local img = ImageManager:GetImage("imagebox_" .. id)
    if not img then
        img = ImageManager:CreateImage("imagebox_" .. id)
    end

    ImageManager:SetImageAsync(img, entityType.settings.imagebox.url)
    img.ImageTransparency = 1 - entityType.settings.imagebox.transparency
    img.ImageColor3 = entityType.settings.imagebox.color
    img.Visible = onscreen

    if onscreen and min and max and min.x and min.y and max.x and max.y then
        local size = Vector2.new(math.max(30, max.x - min.x), math.max(30, max.y - min.y))
        img.Size = UDim2.new(0, size.X, 0, size.Y)
        img.Position = UDim2.new(0, min.x, 0, min.y)
        img.AnchorPoint = Vector2.new(0, 0)
    end

    entityType.entities.imagebox[id] = img
end

function ESP:_UpdateBox(entityType, id, min, max, onscreen)
    local box = entityType.entities.box[id]
    local outline = entityType.entities.boxoutline[id]

    if not box or not outline then
        return
    end

    local isValid = entityType:IsValid(entityType.valid[id], id)

    if onscreen and entityType.settings.box.enabled and isValid and min and max and min.x and min.y and max.x and max.y then
        box.Visible = true
        box.Transparency = entityType.settings.box.transparency
        box.Color = entityType.settings.box.color
        box.Thickness = entityType.settings.box.thickness

        local pos = Vector2.new(min.x, min.y)
        box.Position = pos

        local length = math.max(30, max.x - min.x)
        local height = math.max(30, max.y - min.y)
        length = math.min(length, 500)
        height = math.min(height, 500)
        local size = Vector2.new(length, height)
        box.Size = size

        if entityType.settings.boxoutline.enabled then
            outline.Visible = true
            outline.Transparency = entityType.settings.boxoutline.transparency
            outline.Color = entityType.settings.boxoutline.color
            outline.Thickness = entityType.settings.box.thickness + entityType.settings.boxoutline.thickness * 2
            outline.Position = pos
            outline.Size = size
        else
            outline.Visible = false
        end
        return
    end

    box.Visible = false
    outline.Visible = false
end

function ESP:_UpdateText(entityType, id, textType, min, max, onscreen)
    local place = 'bottom'
    if entityType.settings[textType].top then
        place = 'top'
    elseif entityType.settings.text.priority.flags[textType] then
        place = 'flags'
    end

    local text = entityType.entities.text[place][textType][id]

    if not text then

        return
    end

    local isValid = entityType:IsValid(entityType.valid[id], id)

    text.Visible = onscreen and entityType.settings[textType].enabled and isValid

    if onscreen and entityType.settings[textType].enabled and isValid and entityType.textoffsets[id] and entityType.textoffsets[id][place][textType] then

        if textType == "distance" and character then
            local target = entityType.valid[id]
            local targetPos = nil
            
            pcall(function()
                if target:IsA("Model") then
                    targetPos = target:GetPivot().Position
                elseif target:IsA("BasePart") then
                    targetPos = target.Position
                end
            end)
            
            if not targetPos then
                targetPos = Vector3.new(0, 0, 0)
            end
            local distance = (character:GetPivot().Position - targetPos).Magnitude
            distance = math.round(distance)
            text.Text = '['..tostring(distance)..' m]'
        elseif textType == "weapon" then
            local target = entityType.valid[id]
            local weaponName = self:_GetWeaponName(target)
            text.Text = '[' .. (weaponName or 'None') .. ']'
        elseif textType == "name" then
            text.Text = entityType.displayNames[id] or "Unknown"
        end

        text.Transparency = entityType.settings[textType].transparency
        text.Color = entityType.settings[textType].color
        text.Size = entityType.settings[textType].size
        text.Outline = entityType.settings[textType].outline
        text.OutlineColor = entityType.settings[textType].outlinecolor

        local offset = entityType.textoffsets[id][place][textType].offset
        local yPos
        local xPos

        if place == 'flags' then
            yPos = min.y + offset
            xPos = max.x
        else
            yPos = place == 'top' and (min.y - offset) or (max.y + offset)
            xPos = min.x + (max.x - min.x) / 2
        end

        text.Position = Vector2.new(xPos, yPos)
    end
end

function ESP:_UpdateHealthbar(entityType, id, min, max, onscreen)
    local background = entityType.entities.healthbarbackground[id]
    local bar = entityType.entities.healthbar[id]
    local htxt = entityType.entities.healthbartext[id]

    if not background or not bar then
        return
    end

    local isValid = entityType:IsValid(entityType.valid[id], id)
    local showBar = onscreen and entityType.settings.healthbar.enabled and isValid

    background.Visible = showBar and entityType.settings.healthbar.backgroundenabled
    bar.Visible = showBar

    if htxt then
        htxt.Visible = showBar and entityType.settings.healthbar.healthtext.enabled
    end

    if showBar then
        local left = min.x - entityType.settings.healthbar.gap - entityType.settings.healthbar.width - entityType.settings.healthbar.borderthickness
        local height = max.y - min.y

        if entityType.settings.healthbar.backgroundenabled then
            background.Transparency = 1
            background.Color = entityType.settings.healthbar.backgroundcolor

            local size = Vector2.new(entityType.settings.healthbar.width + entityType.settings.healthbar.borderthickness * 2, height + entityType.settings.healthbar.borderthickness * 2)
            local pos = Vector2.new(left - entityType.settings.healthbar.borderthickness, min.y - entityType.settings.healthbar.borderthickness)
            background.Position = pos
            background.Size = size
        end

        bar.Transparency = 1

        local target = entityType.valid[id]
        local hum = target:FindFirstChild("Humanoid") or target:FindFirstChildOfClass("Humanoid")
        local health = 100
        local maxhealth = 100

        if hum then
            health = hum.Health
            maxhealth = hum.MaxHealth
        end

        local pct = (maxhealth > 0) and (health / maxhealth) or 0
        local healthchange = height * (1 - pct)

        bar.Color = entityType.settings.healthbar.dynamiccolor and HealthColor(pct) or entityType.settings.healthbar.healthcolor

        local size = Vector2.new(entityType.settings.healthbar.width, height - healthchange)
        local pos = Vector2.new(left, min.y + healthchange)
        bar.Size = size
        bar.Position = pos

        if htxt and entityType.settings.healthbar.healthtext.enabled then
            local hs = entityType.settings.healthbar.healthtext
            local textColor = (hs.usedynamiccolor) and HealthColor(pct) or hs.color
            htxt.Text = tostring(math.floor(health + 0.5))
            htxt.Color = textColor
            htxt.Size = hs.size
            htxt.Outline = hs.outline
            htxt.OutlineColor = hs.outlinecolor
            htxt.Position = Vector2.new(left - entityType.settings.healthbar.borderthickness - 12, min.y + healthchange)
            htxt.Visible = true
        end
    end
end

function ESP:_UpdateSkeleton(entityType, id, min, max, onscreen)
    if not entityType.entities.skeleton[id] then
        self:_CreateSkeleton(entityType, id, min, max, onscreen)
        if not entityType.entities.skeleton[id] then
            return
        end
    end

    local bones = entityType.entities.skeleton[id]
    local target = entityType.valid[id]

    local isValid = entityType:IsValid(target, id)

    if entityType.validr6[id] == true then

        if target and (target:FindFirstChild("Humanoid") or target:FindFirstChildOfClass("Humanoid")) and target:FindFirstChild("HumanoidRootPart") then
            local hum = target:FindFirstChild("Humanoid") or target:FindFirstChildOfClass("Humanoid")
            if isValid and onscreen then
                local head = target:FindFirstChild('Head')
                local torso = target:FindFirstChild('Torso')
                local leftArm = target:FindFirstChild('Left Arm')
                local rightArm = target:FindFirstChild('Right Arm')
                local leftLeg = target:FindFirstChild('Left Leg')
                local rightLeg = target:FindFirstChild('Right Leg')

                if head and torso and leftArm and rightArm and leftLeg and rightLeg then
                    local H, H_onscreen = Camera:WorldToViewportPoint(head.Position)
                    local UT, UT_onscreen = Camera:WorldToViewportPoint((torso.CFrame * CFrame.new(0, torso.Size.Y/4, 0)).Position)
                    local LT, LT_onscreen = Camera:WorldToViewportPoint((torso.CFrame * CFrame.new(0, -torso.Size.Y/4, 0)).Position)

                    local LA_Height = leftArm.Size.Y/2 - 0.2
                    local LUA, LUA_onscreen = Camera:WorldToViewportPoint((leftArm.CFrame * CFrame.new(0, LA_Height, 0)).Position)
                    local LLA, LLA_onscreen = Camera:WorldToViewportPoint((leftArm.CFrame * CFrame.new(0, -LA_Height, 0)).Position)

                    local RA_Height = rightArm.Size.Y/2 - 0.2
                    local RUA, RUA_onscreen = Camera:WorldToViewportPoint((rightArm.CFrame * CFrame.new(0, RA_Height, 0)).Position)
                    local RLA, RLA_onscreen = Camera:WorldToViewportPoint((rightArm.CFrame * CFrame.new(0, -RA_Height, 0)).Position)

                    local LL_Height = leftLeg.Size.Y/2 - 0.2
                    local LUL, LUL_onscreen = Camera:WorldToViewportPoint((leftLeg.CFrame * CFrame.new(0, LL_Height, 0)).Position)
                    local LLL, LLL_onscreen = Camera:WorldToViewportPoint((leftLeg.CFrame * CFrame.new(0, -LL_Height, 0)).Position)

                    local RL_Height = rightLeg.Size.Y/2 - 0.2
                    local RUL, RUL_onscreen = Camera:WorldToViewportPoint((rightLeg.CFrame * CFrame.new(0, RL_Height, 0)).Position)
                    local RLL, RLL_onscreen = Camera:WorldToViewportPoint((rightLeg.CFrame * CFrame.new(0, -RL_Height, 0)).Position)

                    if H.Z > 0 and UT.Z > 0 then
                        bones.Head_Spine.line.From = Vector2.new(H.X, H.Y)
                        bones.Head_Spine.line.To = Vector2.new(UT.X, UT.Y)
                    else bones.Head_Spine.line.Visible = false end
                    
                    if UT.Z > 0 and LT.Z > 0 then
                        bones.Spine.line.From = Vector2.new(UT.X, UT.Y)
                        bones.Spine.line.To = Vector2.new(LT.X, LT.Y)
                    else bones.Spine.line.Visible = false end
                    
                    if LUA.Z > 0 and LLA.Z > 0 then
                        bones.LeftArm.line.From = Vector2.new(LUA.X, LUA.Y)
                        bones.LeftArm.line.To = Vector2.new(LLA.X, LLA.Y)
                    else bones.LeftArm.line.Visible = false end
                    
                    if UT.Z > 0 and LUA.Z > 0 then
                        bones.LeftArm_UpperTorso.line.From = Vector2.new(UT.X, UT.Y)
                        bones.LeftArm_UpperTorso.line.To = Vector2.new(LUA.X, LUA.Y)
                    else bones.LeftArm_UpperTorso.line.Visible = false end
                    
                    if RUA.Z > 0 and RLA.Z > 0 then
                        bones.RightArm.line.From = Vector2.new(RUA.X, RUA.Y)
                        bones.RightArm.line.To = Vector2.new(RLA.X, RLA.Y)
                    else bones.RightArm.line.Visible = false end
                    
                    if UT.Z > 0 and RUA.Z > 0 then
                        bones.RightArm_UpperTorso.line.From = Vector2.new(UT.X, UT.Y)
                        bones.RightArm_UpperTorso.line.To = Vector2.new(RUA.X, RUA.Y)
                    else bones.RightArm_UpperTorso.line.Visible = false end
                    
                    if LUL.Z > 0 and LLL.Z > 0 then
                        bones.LeftLeg.line.From = Vector2.new(LUL.X, LUL.Y)
                        bones.LeftLeg.line.To = Vector2.new(LLL.X, LLL.Y)
                    else bones.LeftLeg.line.Visible = false end
                    
                    if LT.Z > 0 and LUL.Z > 0 then
                        bones.LeftLeg_LowerTorso.line.From = Vector2.new(LT.X, LT.Y)
                        bones.LeftLeg_LowerTorso.line.To = Vector2.new(LUL.X, LUL.Y)
                    else bones.LeftLeg_LowerTorso.line.Visible = false end
                    
                    if RUL.Z > 0 and RLL.Z > 0 then
                        bones.RightLeg.line.From = Vector2.new(RUL.X, RUL.Y)
                        bones.RightLeg.line.To = Vector2.new(RLL.X, RLL.Y)
                    else bones.RightLeg.line.Visible = false end
                    
                    if LT.Z > 0 and RUL.Z > 0 then
                        bones.RightLeg_LowerTorso.line.From = Vector2.new(LT.X, LT.Y)
                        bones.RightLeg_LowerTorso.line.To = Vector2.new(RUL.X, RUL.Y)
                    else bones.RightLeg_LowerTorso.line.Visible = false end

                    for i, v in pairs(bones) do
                        if v.line.From ~= Vector2.new(0,0) and v.line.To ~= Vector2.new(0,0) then
                            v.line.Visible = true
                        end
                    end
                else
                    for i, v in pairs(bones) do
                        v.line.Visible = false
                    end
                end
            else
                for i, v in pairs(bones) do
                    v.line.Visible = false
                end
            end
        else
            for i, v in pairs(bones) do
                v.line.Visible = false
            end
        end
    else

        if target and (target:FindFirstChild("Humanoid") or target:FindFirstChildOfClass("Humanoid")) and target:FindFirstChild("HumanoidRootPart") then
            local hum = target:FindFirstChild("Humanoid") or target:FindFirstChildOfClass("Humanoid")
            if isValid and onscreen then
                local head = target:FindFirstChild('Head')
                local upperTorso = target:FindFirstChild('UpperTorso')
                local lowerTorso = target:FindFirstChild('LowerTorso')
                local leftUpperArm = target:FindFirstChild('LeftUpperArm')
                local leftLowerArm = target:FindFirstChild('LeftLowerArm')
                local leftHand = target:FindFirstChild('LeftHand')
                local rightUpperArm = target:FindFirstChild('RightUpperArm')
                local rightLowerArm = target:FindFirstChild('RightLowerArm')
                local rightHand = target:FindFirstChild('RightHand')
                local leftUpperLeg = target:FindFirstChild('LeftUpperLeg')
                local leftLowerLeg = target:FindFirstChild('LeftLowerLeg')
                local leftFoot = target:FindFirstChild('LeftFoot')
                local rightUpperLeg = target:FindFirstChild('RightUpperLeg')
                local rightLowerLeg = target:FindFirstChild('RightLowerLeg')
                local rightFoot = target:FindFirstChild('RightFoot')

                if head and upperTorso and lowerTorso then
                    local H, H_onscreen = Camera:WorldToViewportPoint(head.Position)
                    local UT, UT_onscreen = Camera:WorldToViewportPoint(upperTorso.Position)
                    local LT, LT_onscreen = Camera:WorldToViewportPoint(lowerTorso.Position)

                    local LUA = leftUpperArm and Camera:WorldToViewportPoint(leftUpperArm.Position)
                    local LLA = leftLowerArm and Camera:WorldToViewportPoint(leftLowerArm.Position)
                    local LH = leftHand and Camera:WorldToViewportPoint(leftHand.Position)

                    local RUA = rightUpperArm and Camera:WorldToViewportPoint(rightUpperArm.Position)
                    local RLA = rightLowerArm and Camera:WorldToViewportPoint(rightLowerArm.Position)
                    local RH = rightHand and Camera:WorldToViewportPoint(rightHand.Position)

                    local LUL = leftUpperLeg and Camera:WorldToViewportPoint(leftUpperLeg.Position)
                    local LLL = leftLowerLeg and Camera:WorldToViewportPoint(leftLowerLeg.Position)
                    local LF = leftFoot and Camera:WorldToViewportPoint(leftFoot.Position)

                    local RUL = rightUpperLeg and Camera:WorldToViewportPoint(rightUpperLeg.Position)
                    local RLL = rightLowerLeg and Camera:WorldToViewportPoint(rightLowerLeg.Position)
                    local RF = rightFoot and Camera:WorldToViewportPoint(rightFoot.Position)

                    if H and UT and H.Z > 0 and UT.Z > 0 then
                        if bones and bones.Head_UpperTorso then
                            bones.Head_UpperTorso.line.From = Vector2.new(H.X, H.Y)
                            bones.Head_UpperTorso.line.To = Vector2.new(UT.X, UT.Y)
                            bones.Head_UpperTorso.line.Visible = true
                        end
                    else 
                        if bones and bones.Head_UpperTorso then
                            bones.Head_UpperTorso.line.Visible = false 
                        end
                    end

                    if UT and LT and UT.Z > 0 and LT.Z > 0 then
                        if bones and bones.UpperTorso_LowerTorso then
                            bones.UpperTorso_LowerTorso.line.From = Vector2.new(UT.X, UT.Y)
                            bones.UpperTorso_LowerTorso.line.To = Vector2.new(LT.X, LT.Y)
                            bones.UpperTorso_LowerTorso.line.Visible = true
                        end
                    else 
                        if bones and bones.UpperTorso_LowerTorso then
                            bones.UpperTorso_LowerTorso.line.Visible = false
                        end
                    end

                    if LUA and LLA and LH and LUA.Z > 0 and LLA.Z > 0 and LH.Z > 0 then
                        if bones and bones.UpperTorso_LeftUpperArm then
                            bones.UpperTorso_LeftUpperArm.line.From = Vector2.new(UT.X, UT.Y)
                            bones.UpperTorso_LeftUpperArm.line.To = Vector2.new(LUA.X, LUA.Y)
                            bones.UpperTorso_LeftUpperArm.line.Visible = true
                        end
                        if bones and bones.LeftUpperArm_LeftLowerArm then
                            bones.LeftUpperArm_LeftLowerArm.line.From = Vector2.new(LUA.X, LUA.Y)
                            bones.LeftUpperArm_LeftLowerArm.line.To = Vector2.new(LLA.X, LLA.Y)
                            bones.LeftUpperArm_LeftLowerArm.line.Visible = true
                        end
                        if bones and bones.LeftLowerArm_LeftHand then
                            bones.LeftLowerArm_LeftHand.line.From = Vector2.new(LLA.X, LLA.Y)
                            bones.LeftLowerArm_LeftHand.line.To = Vector2.new(LH.X, LH.Y)
                            bones.LeftLowerArm_LeftHand.line.Visible = true
                        end
                    else
                        if bones and bones.UpperTorso_LeftUpperArm then
                            bones.UpperTorso_LeftUpperArm.line.Visible = false
                        end
                        if bones and bones.LeftUpperArm_LeftLowerArm then
                            bones.LeftUpperArm_LeftLowerArm.line.Visible = false
                        end
                        if bones and bones.LeftLowerArm_LeftHand then
                            bones.LeftLowerArm_LeftHand.line.Visible = false
                        end
                    end

                    if RUA and RLA and RH and RUA.Z > 0 and RLA.Z > 0 and RH.Z > 0 then
                        if bones and bones.UpperTorso_RightUpperArm then
                            bones.UpperTorso_RightUpperArm.line.From = Vector2.new(UT.X, UT.Y)
                            bones.UpperTorso_RightUpperArm.line.To = Vector2.new(RUA.X, RUA.Y)
                            bones.UpperTorso_RightUpperArm.line.Visible = true
                        end
                        if bones and bones.RightUpperArm_RightLowerArm then
                            bones.RightUpperArm_RightLowerArm.line.From = Vector2.new(RUA.X, RUA.Y)
                            bones.RightUpperArm_RightLowerArm.line.To = Vector2.new(RLA.X, RLA.Y)
                            bones.RightUpperArm_RightLowerArm.line.Visible = true
                        end
                        if bones and bones.RightLowerArm_RightHand then
                            bones.RightLowerArm_RightHand.line.From = Vector2.new(RLA.X, RLA.Y)
                            bones.RightLowerArm_RightHand.line.To = Vector2.new(RH.X, RH.Y)
                            bones.RightLowerArm_RightHand.line.Visible = true
                        end
                    else
                        if bones and bones.UpperTorso_RightUpperArm then
                            bones.UpperTorso_RightUpperArm.line.Visible = false
                        end
                        if bones and bones.RightUpperArm_RightLowerArm then
                            bones.RightUpperArm_RightLowerArm.line.Visible = false
                        end
                        if bones and bones.RightLowerArm_RightHand then
                            bones.RightLowerArm_RightHand.line.Visible = false
                        end
                    end

                    if LUL and LLL and LF and LUL.Z > 0 and LLL.Z > 0 and LF.Z > 0 then
                        if bones and bones.LowerTorso_LeftUpperLeg then
                            bones.LowerTorso_LeftUpperLeg.line.From = Vector2.new(LT.X, LT.Y)
                            bones.LowerTorso_LeftUpperLeg.line.To = Vector2.new(LUL.X, LUL.Y)
                            bones.LowerTorso_LeftUpperLeg.line.Visible = true
                        end
                        if bones and bones.LeftUpperLeg_LeftLowerLeg then
                            bones.LeftUpperLeg_LeftLowerLeg.line.From = Vector2.new(LUL.X, LUL.Y)
                            bones.LeftUpperLeg_LeftLowerLeg.line.To = Vector2.new(LLL.X, LLL.Y)
                            bones.LeftUpperLeg_LeftLowerLeg.line.Visible = true
                        end
                        if bones and bones.LeftLowerLeg_LeftFoot then
                            bones.LeftLowerLeg_LeftFoot.line.From = Vector2.new(LLL.X, LLL.Y)
                            bones.LeftLowerLeg_LeftFoot.line.To = Vector2.new(LF.X, LF.Y)
                            bones.LeftLowerLeg_LeftFoot.line.Visible = true
                        end
                    else
                        if bones and bones.LowerTorso_LeftUpperLeg then
                            bones.LowerTorso_LeftUpperLeg.line.Visible = false
                        end
                        if bones and bones.LeftUpperLeg_LeftLowerLeg then
                            bones.LeftUpperLeg_LeftLowerLeg.line.Visible = false
                        end
                        if bones and bones.LeftLowerLeg_LeftFoot then
                            bones.LeftLowerLeg_LeftFoot.line.Visible = false
                        end
                    end

                    if RUL and RLL and RF and RUL.Z > 0 and RLL.Z > 0 and RF.Z > 0 then
                        if bones and bones.LowerTorso_RightUpperLeg then
                            bones.LowerTorso_RightUpperLeg.line.From = Vector2.new(LT.X, LT.Y)
                            bones.LowerTorso_RightUpperLeg.line.To = Vector2.new(RUL.X, RUL.Y)
                            bones.LowerTorso_RightUpperLeg.line.Visible = true
                        end
                        if bones and bones.RightUpperLeg_RightLowerLeg then
                            bones.RightUpperLeg_RightLowerLeg.line.From = Vector2.new(RUL.X, RUL.Y)
                            bones.RightUpperLeg_RightLowerLeg.line.To = Vector2.new(RLL.X, RLL.Y)
                            bones.RightUpperLeg_RightLowerLeg.line.Visible = true
                        end
                        if bones and bones.RightLowerLeg_RightFoot then
                            bones.RightLowerLeg_RightFoot.line.From = Vector2.new(RLL.X, RLL.Y)
                            bones.RightLowerLeg_RightFoot.line.To = Vector2.new(RF.X, RF.Y)
                            bones.RightLowerLeg_RightFoot.line.Visible = true
                        end
                    else
                        if bones and bones.LowerTorso_RightUpperLeg then
                            bones.LowerTorso_RightUpperLeg.line.Visible = false
                        end
                        if bones and bones.RightUpperLeg_RightLowerLeg then
                            bones.RightUpperLeg_RightLowerLeg.line.Visible = false
                        end
                        if bones and bones.RightLowerLeg_RightFoot then
                            bones.RightLowerLeg_RightFoot.line.Visible = false
                        end
                    end
                else
                    for i, v in pairs(bones) do
                        v.line.Visible = false
                    end
                end
            else
                for i, v in pairs(bones) do
                    v.line.Visible = false
                end
            end
        else
            for i, v in pairs(bones) do
                v.line.Visible = false
            end
        end
    end
end

function ESP:_UpdateImageBox(entityType, id, min, max, onscreen)
    local image = entityType.entities.imagebox[id]

    if not image then
        return
    end

    local isValid = entityType:IsValid(entityType.valid[id], id)

    image.Visible = onscreen and entityType.settings.imagebox.enabled and isValid

    if onscreen and entityType.settings.imagebox.enabled and isValid then
        if min and max and min.x and min.y and max.x and max.y then
            local size = Vector2.new(math.max(30, max.x - min.x), math.max(30, max.y - min.y))
            image.Size = UDim2.new(0, size.X, 0, size.Y)
            image.Position = UDim2.new(0, min.x, 0, min.y)
        end
    end
end

function ESP:_Remove(entityType, id, espType)

    local isText = entityType.settings[espType] and entityType.settings[espType].priority ~= nil

    if isText then
        local place = 'top'
        if entityType.settings.text.priority.flags[espType] then
            place = 'flags'
        elseif entityType.settings[espType].top == false then
            place = 'bottom'
        end

        if entityType.entities.text[place] and entityType.entities.text[place][espType] and entityType.entities.text[place][espType][id] then
            pcall(function()
                entityType.entities.text[place][espType][id]:Remove()
            end)
            entityType.entities.text[place][espType][id] = nil

        end
        return
    end

    if not entityType.entities[espType] or not entityType.entities[espType][id] then

        return
    end

    if espType == 'skeleton' then
        for _, bone in pairs(entityType.entities[espType][id]) do
            if bone and bone.line then
                pcall(function()
                    bone.line:Remove()
                end)
            end
        end
        entityType.entities[espType][id] = nil

        return
    end

    if espType == 'chams' then
        for _, adorn in pairs(entityType.entities[espType][id]) do
            if adorn then
                pcall(function() adorn:Destroy() end)
            end
        end
        entityType.entities[espType][id] = nil

        return
    end

    local success, error = pcall(function() entityType.entities[espType][id]:Remove() end)
    if not success then
        for _, obj in pairs(entityType.entities[espType][id]) do
            if typeof(obj) == 'table' then
                for _, newobj in pairs(obj) do
                    if typeof(newobj) == 'userdata' then
                        pcall(function() newobj:Remove() end)
                    end
                end
            elseif typeof(obj) == 'userdata' then
                pcall(function() obj:Remove() end)
            end
        end
    end

    entityType.entities[espType][id] = nil

end

function ESP:_GetWeaponName(target)
    local hum = target:FindFirstChild("Humanoid") or target:FindFirstChildOfClass("Humanoid")
    if hum then
        local equippedTool = hum:FindFirstChildOfClass("Tool")
        if equippedTool then return equippedTool.Name end
    end
    for _, child in pairs(target:GetChildren()) do
        if child:IsA("Tool") then return child.Name end
    end
    for weaponName, _ in pairs(self.heldItemImages) do
        if target:FindFirstChild(weaponName) then return weaponName end
    end
    return nil
end

function ESP:_HandleWeaponImage(entityType, id, target)
    local s = entityType.settings.weaponimage
    local min = entityType.mins[id]
    local max = entityType.maxes[id]
    local onscreen = entityType.onscreens[id]
    local isValid = entityType:IsValid(target, id)
    local imgKey = "weaponimage_" .. id

    if not s.enabled or not onscreen or not isValid then
        local img = ImageManager:GetImage(imgKey)
        if img then img.Visible = false end
        return
    end

    local weaponName = self:_GetWeaponName(target)
    local assetUrl = weaponName and self.heldItemImages[weaponName]

    if not assetUrl then
        local img = ImageManager:GetImage(imgKey)
        if img then img.Visible = false end
        return
    end

    local img = ImageManager:GetImage(imgKey)
    if not img then
        img = ImageManager:CreateImage(imgKey)
        img.AnchorPoint = Vector2.new(0.5, 0)
        img.ZIndex = 10
        img.BackgroundTransparency = 1
    end

    ImageManager:SetImageAsync(img, assetUrl)
    img.ImageTransparency = 1 - s.transparency
    local sz = s.size or 32
    img.Size = UDim2.new(0, sz, 0, sz)

    local bottomEdge = max.y
    if entityType.textoffsets[id] then
        for textType, data in pairs(entityType.textoffsets[id].bottom) do
            local setting = entityType.settings[textType]
            if setting and setting.enabled then
                local itemBottom = max.y + data.offset + setting.size
                if itemBottom > bottomEdge then
                    bottomEdge = itemBottom
                end
            end
        end
    end

    local centerX = min.x + (max.x - min.x) / 2
    img.Position = UDim2.new(0, centerX, 0, bottomEdge + (s.gap or 4))
    img.Visible = true
end

function ESP:_RemoveAllESP(entityType, id)

    for espType, _ in pairs(entityType.entities) do
        if espType ~= 'text' and espType ~= 'images' then
            self:_Remove(entityType, id, espType)
        end
    end

    for place, types in pairs(entityType.entities.text) do
        for espType, _ in pairs(types) do
            self:_Remove(entityType, id, espType)
        end
    end

    for place, types in pairs(entityType.entities.images) do
        for espType, _ in pairs(types) do
            self:_Remove(entityType, id, espType)
        end
    end

    ImageManager:RemoveImage("imagebox_" .. id)
    ImageManager:RemoveImage("oofarrow_" .. id)
    ImageManager:RemoveImage("vischeckimage_" .. id)
    ImageManager:RemoveImage("weaponimage_" .. id)

    if entityType.entities.healthbartext and entityType.entities.healthbartext[id] then
        pcall(function() entityType.entities.healthbartext[id]:Remove() end)
        entityType.entities.healthbartext[id] = nil
    end

end

function ESP:_HandleBox(entityType, id, target)
    if not target or not target.Parent then
        if entityType.entities.box[id] then
            entityType.entities.box[id].Visible = false
        end
        if entityType.entities.boxoutline[id] then
            entityType.entities.boxoutline[id].Visible = false
        end
        return
    end

    local min = entityType.mins[id]
    local max = entityType.maxes[id]
    local onscreen = entityType.onscreens[id]

    local targetPos = nil
    
    pcall(function()
        if target:IsA("Model") then
            targetPos = target:GetPivot().Position
        elseif target:IsA("BasePart") then
            targetPos = target.Position
        end
    end)
    
    if not targetPos then
        if entityType.entities.box[id] then
            entityType.entities.box[id].Visible = false
        end
        if entityType.entities.boxoutline[id] then
            entityType.entities.boxoutline[id].Visible = false
        end
        return
    end
    
    local distance = (targetPos - Camera.CFrame.Position).Magnitude
    local tooFar = distance > 300

    if not entityType.settings.box.enabled or tooFar then
        if entityType.entities.box[id] then
            entityType.entities.box[id].Visible = false
        end
        if entityType.entities.boxoutline[id] then
            entityType.entities.boxoutline[id].Visible = false
        end
        return
    end

    if not entityType.entities.box[id] then
        self:_CreateBox(entityType, id, min, max, onscreen)
    else
        self:_UpdateBox(entityType, id, min, max, onscreen)
    end
end

function ESP:_HandleText(entityType, id, textType, target)
    local setting = entityType.settings[textType]

    if type(setting) ~= "table"
        or not setting.color
        or setting.priority == nil
    then
        return
    end

    local min = entityType.mins[id]
    local max = entityType.maxes[id]
    local onscreen = entityType.onscreens[id]

    local place
    if entityType.settings.text.priority.flags[textType] then
        place = "flags"
    elseif setting.top == true then
        place = "top"
    else
        place = "bottom"
    end

    local textRoot = entityType.entities.text
    textRoot[place] = textRoot[place]       or {}
    textRoot[place][textType] = textRoot[place][textType] or {}

    if not setting.enabled then
        if textRoot[place][textType][id] then
            textRoot[place][textType][id].Visible = false
        end
        return
    end

    if not textRoot[place][textType][id] then
        self:_CreateText(entityType, id, textType, min, max, onscreen)
    else
        self:_UpdateText(entityType, id, textType, min, max, onscreen)
    end
end

function ESP:_HandleHealthbar(entityType, id, target)
    local min = entityType.mins[id]
    local max = entityType.maxes[id]
    local onscreen = entityType.onscreens[id]

    if not entityType.settings.healthbar.enabled then
        if entityType.entities.healthbar[id] then
            entityType.entities.healthbar[id].Visible = false
        end
        if entityType.entities.healthbarbackground[id] then
            entityType.entities.healthbarbackground[id].Visible = false
        end
        if entityType.entities.healthbartext[id] then
            entityType.entities.healthbartext[id].Visible = false
        end
        return
    end

    if not entityType.entities.healthbar[id] then
        self:_CreateHealthbar(entityType, id, min, max, onscreen)
    else
        self:_UpdateHealthbar(entityType, id, min, max, onscreen)
    end
end

function ESP:_HandleSkeleton(entityType, id, target)
    if not target or not target.Parent then
        return
    end

    local min = entityType.mins[id]
    local max = entityType.maxes[id]
    local onscreen = entityType.onscreens[id]

    local targetPos = nil
    
    pcall(function()
        if target:IsA("Model") then
            targetPos = target:GetPivot().Position
        elseif target:IsA("BasePart") then
            targetPos = target.Position
        end
    end)
    
    if not targetPos then
        if entityType.entities.skeleton[id] then
            for _, bone in pairs(entityType.entities.skeleton[id]) do
                if bone and bone.line then bone.line.Visible = false end
            end
        end
        return
    end
    
    local distance = (targetPos - Camera.CFrame.Position).Magnitude
    local tooFar = distance > 300

    if not entityType.settings.skeleton.enabled or tooFar then
        if entityType.entities.skeleton[id] then
            for _, bone in pairs(entityType.entities.skeleton[id]) do
                if bone and bone.line then bone.line.Visible = false end
            end
        end
        return
    end

    if not entityType.entities.skeleton[id] then
        self:_CreateSkeleton(entityType, id, min, max, onscreen)
    else
        self:_UpdateSkeleton(entityType, id, min, max, onscreen)
    end
end

function ESP:_HandleImageBox(entityType, id, target)
    if not target or not target.Parent then
        return
    end

    local min = entityType.mins[id]
    local max = entityType.maxes[id]
    local onscreen = entityType.onscreens[id]

    local targetPos = nil
    
    pcall(function()
        if target:IsA("Model") then
            targetPos = target:GetPivot().Position
        elseif target:IsA("BasePart") then
            targetPos = target.Position
        end
    end)
    
    if not targetPos then
        if entityType.entities.imagebox[id] then
            entityType.entities.imagebox[id].Visible = false
        end
        return
    end
    
    local distance = (targetPos - Camera.CFrame.Position).Magnitude
    local tooFar = distance > 300

    if not entityType.settings.imagebox.enabled or tooFar then
        if entityType.entities.imagebox[id] then
            entityType.entities.imagebox[id].Visible = false
        end
        return
    end

    if not entityType.entities.imagebox[id] then
        self:_CreateImageBox(entityType, id, min, max, onscreen)
    else
        self:_UpdateImageBox(entityType, id, min, max, onscreen)
    end
end

function ESP:_HandleOOFArrows(entityType, id, target)
    local settings = entityType.settings

    if not settings.oofarrows.enabled then
        local arrow = ImageManager:GetImage("oofarrow_" .. id)
        if arrow then arrow.Visible = false end
        return
    end

    local targetPos = nil
    
    pcall(function()
        if entityType.isPart[id] then
            targetPos = target.Position
        else
            local hrp = target:FindFirstChild("HumanoidRootPart")
            if hrp then
                targetPos = hrp.Position
            end
        end
    end)
    
    if not targetPos then
        local arrow = ImageManager:GetImage("oofarrow_" .. id)
        if arrow then arrow.Visible = false end
        return
    end

    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return
    end

    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
    local screenSize = Camera.ViewportSize

    local isReallyOnScreen = onScreen
        and screenPos.X > 50 and screenPos.X < (screenSize.X - 50)
        and screenPos.Y > 50 and screenPos.Y < (screenSize.Y - 50)
        and screenPos.Z > 0

    if isReallyOnScreen then
        local arrow = ImageManager:GetImage("oofarrow_" .. id)
        if arrow then arrow.Visible = false end
        return
    end

    local camCFrame = Camera.CFrame
    local toTarget = targetPos - camCFrame.Position
    local distance = toTarget.Magnitude

    local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
    if flatDir.Magnitude > 0.01 then
        flatDir = flatDir.Unit
    else
        local lv = camCFrame.LookVector
        flatDir = Vector3.new(lv.X, 0, lv.Z).Unit
    end

    local camFwd = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z)
    if camFwd.Magnitude > 0.01 then camFwd = camFwd.Unit else camFwd = Vector3.new(0, 0, 1) end

    local camRight = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z)
    if camRight.Magnitude > 0.01 then camRight = camRight.Unit else camRight = Vector3.new(1, 0, 0) end

    local dotFwd = flatDir:Dot(camFwd)
    local dotRight = flatDir:Dot(camRight)
    local dotUp = toTarget.Y / distance

    local rotation
    if math.abs(dotUp) > 0.5 then
        rotation = dotUp < 0 and 180 or 0
    else
        rotation = math.deg(math.atan2(dotRight, dotFwd))
    end

    local angle = math.rad(rotation)
    local radius = settings.oofarrows.radius
    local arrowX = (screenSize.X / 2) + math.sin(angle) * radius
    local arrowY = (screenSize.Y / 2) - math.cos(angle) * radius

    local arrow = ImageManager:GetImage("oofarrow_" .. id)
    if not arrow then
        arrow = ImageManager:CreateImage("oofarrow_" .. id)

        ImageManager:SetImageAsync(arrow, settings.oofarrows.image)
        arrow.ImageTransparency = 1 - settings.oofarrows.transparency
        arrow.ImageColor3 = settings.oofarrows.color
        arrow.Size = settings.oofarrows.size
        arrow.AnchorPoint = Vector2.new(0.5, 0.5)
        arrow.ZIndex = 10
        arrow.BackgroundTransparency = settings.oofarrows.testmode and 0.5 or 1
        if settings.oofarrows.testmode then
            arrow.BackgroundColor3 = settings.oofarrows.color
        end
    end

    arrow.Position = UDim2.new(0, arrowX, 0, arrowY)
    if settings.oofarrows.rotation then
        arrow.Rotation = rotation
    end
    arrow.Visible = true
end

function ESP:_HandleVischeckImage(entityType, id, target)
    local s = entityType.settings.vischeckimage

    if not s.enabled then
        local img = ImageManager:GetImage("vischeckimage_" .. id)
        if img then img.Visible = false end
        return
    end

    local min = entityType.mins[id]
    local max = entityType.maxes[id]
    local onscreen = entityType.onscreens[id]
    local isValid = entityType:IsValid(target, id)

    if not onscreen or not isValid then
        local img = ImageManager:GetImage("vischeckimage_" .. id)
        if img then img.Visible = false end
        return
    end

    if not self._vischeckImageState then self._vischeckImageState = {} end
    if not self._vischeckImageState[id] then
        self._vischeckImageState[id] = { lastCheck = 0, isVisible = false, lastUrl = nil }
    end
    local state = self._vischeckImageState[id]

    local now = tick()
    if (now - state.lastCheck) >= (s.updatefrequency or 0.1) then
        state.lastCheck = now
        local checkPart = target:FindFirstChild(s.bodypart or "Head")
        state.isVisible = checkPart ~= nil and IsPartVisible(checkPart)
    end

    local targetUrl = state.isVisible and s.visibleimage    or s.notvisibleimage
    local targetColor = state.isVisible and s.visiblecolor    or s.notvisiblecolor

    if not targetUrl or targetUrl == "" then
        local img = ImageManager:GetImage("vischeckimage_" .. id)
        if img then img.Visible = false end
        return
    end

    local img = ImageManager:GetImage("vischeckimage_" .. id)
    if not img then
        img = ImageManager:CreateImage("vischeckimage_" .. id)
        local sz = s.size or 24
        img.Size = UDim2.new(0, sz, 0, sz)
        img.AnchorPoint = Vector2.new(0, 0)
        img.ZIndex = 10
        img.BackgroundTransparency = 1
    end

    if targetUrl ~= state.lastUrl then
        ImageManager:SetImageAsync(img, targetUrl)
        state.lastUrl = targetUrl
    end
    if targetColor ~= state.lastColor then
        img.ImageColor3 = targetColor or Color3.new(1, 1, 1)
        state.lastColor = targetColor
    end

    local offset = 0
    if entityType.textoffsets[id] and entityType.textoffsets[id].flags.vischeckimage then
        offset = entityType.textoffsets[id].flags.vischeckimage.offset
    end
    local xPos = max.x + (s.gap or 4)
    local yPos = min.y + offset
    img.Position = UDim2.new(0, xPos, 0, yPos)
    img.Visible = true
end

function ESP:_CreateAdornment(part, adornType, color, trans, zIndex, sizeOffset, extra)
    extra = extra or {}

    local adorn
    if adornType == "Cylinder" then
        adorn = Instance.new("CylinderHandleAdornment")
        adorn.Height = part.Size.Y + (extra.HeightOffset or 0)
        adorn.Radius = (part.Size.X * 0.5) + (extra.RadiusOffset or 0)
        adorn.CFrame = CFrame.new(Vector3.new(), Vector3.new(0, 1, 0))
    elseif adornType == "Box" then
        adorn = Instance.new("BoxHandleAdornment")
        adorn.Size = part.Size + (sizeOffset or Vector3.new(0, 0, 0))
    end

    adorn.Name = "Chams"
    adorn.AlwaysOnTop = true
    adorn.ZIndex = zIndex
    adorn.Adornee = part
    adorn.Color3 = color
    adorn.Transparency = trans or 0

    if extra.Shading then
        pcall(function()
            adorn.Shading = extra.Shading
        end)
    end

    -- Parent to CoreGui folder so adornments are hidden from workspace scanners.
    -- The Adornee property keeps them visually attached to the part.
    if not self.chamsContainer or not self.chamsContainer.Parent then
        self.chamsContainer = Instance.new("Folder")
        self.chamsContainer.Name = "RobloxGui"  -- blend in with existing CoreGui children
        self.chamsContainer.Parent = CoreGui
    end
    adorn.Parent = self.chamsContainer
    return adorn
end

function ESP:_RemoveAdorns(part)
    if not part then return end
    -- Adornments now live in chamsContainer, not as children of the part.
    -- Search the container and destroy any whose Adornee matches this part.
    if self.chamsContainer and self.chamsContainer.Parent then
        for _, obj in ipairs(self.chamsContainer:GetChildren()) do
            if (obj.Name == "Chams" or obj.Name == "Glow") and obj.Adornee == part then
                obj:Destroy()
            end
        end
    end
end

function ESP:_UpdateChams(entityType, id, target)
    if not entityType.settings.chams.enabled then
        if entityType.entities.chams[id] then
            for _, adorn in pairs(entityType.entities.chams[id]) do
                if adorn then pcall(function() adorn:Destroy() end) end
            end
            entityType.entities.chams[id] = nil
        end
        entityType._chamLastColor = entityType._chamLastColor or {}
        entityType._chamLastColor[id] = nil
        return
    end

    if not target or not target.Parent then return end

    local settings = entityType.settings.chams
    local mainColor = settings.color
    local glowColor = settings.glowcolor
    local trans = settings.transparency
    local doGlow = settings.glow

    if settings.vischeck and settings.vischeck.enabled then
        local checkPart = target:FindFirstChild(settings.vischeck.bodypart)
        if checkPart then
            if IsPartVisible(checkPart) then
                mainColor = settings.vischeck.visiblecolor
                glowColor = settings.vischeck.visibleglowcolor
            else
                mainColor = settings.vischeck.notvisiblecolor
                glowColor = settings.vischeck.notvisibleglowcolor
            end
        end
    end

    entityType._chamLastColor = entityType._chamLastColor or {}
    local lastColorKey = entityType._chamLastColor[id]
    local newColorKey = mainColor.R .. mainColor.G .. mainColor.B .. tostring(doGlow) .. tostring(trans)

    local needsRebuild = (lastColorKey ~= newColorKey) or (not entityType.entities.chams[id]) or (#entityType.entities.chams[id] == 0)

    if not needsRebuild then return end
    entityType._chamLastColor[id] = newColorKey

    if entityType.entities.chams[id] then
        for _, adorn in pairs(entityType.entities.chams[id]) do
            if adorn then pcall(function() adorn:Destroy() end) end
        end
    end
    entityType.entities.chams[id] = {}

    for _, part in pairs(target:GetChildren()) do
        if not part:IsA("BasePart") or part.Transparency >= 1 then continue end

        self:_RemoveAdorns(part)

        local isHead = part.Name == "Head" or part.Name == "FakeHead"

        if doGlow then
            local glowAdorn = self:_CreateAdornment(
                part,
                isHead and "Cylinder" or "Box",
                Color3.new(glowColor.R * 5, glowColor.G * 5, glowColor.B * 5),
                -1,
                isHead and 10 or 9,
                Vector3.new(0.03, 0.03, 0.03),
                {Shading = Enum.AdornShading.XRayShaded}
            )
            table.insert(entityType.entities.chams[id], glowAdorn)
        end

        local chamAdorn = self:_CreateAdornment(
            part,
            isHead and "Cylinder" or "Box",
            mainColor,
            trans,
            10,
            Vector3.new(0.02, 0.02, 0.02)
        )
        table.insert(entityType.entities.chams[id], chamAdorn)
    end
end

function ESP:Start()

    pcall(function()
        setfflag("AdornShadingAPI", "true")
    end)

    self.renderConnection = RunService:BindToRenderStep("ESP_Render", Enum.RenderPriority.Camera.Value + 1, function()
        if not self.Enabled then
            for typeName, entityType in pairs(self.entityTypes) do
                for id, _ in pairs(entityType.valid) do
                    if entityType.entities.box[id] then entityType.entities.box[id].Visible = false end
                    if entityType.entities.boxoutline[id] then entityType.entities.boxoutline[id].Visible = false end
                    if entityType.entities.healthbar[id] then entityType.entities.healthbar[id].Visible = false end
                    if entityType.entities.healthbarbackground[id] then entityType.entities.healthbarbackground[id].Visible = false end
                    if entityType.entities.healthbartext[id] then entityType.entities.healthbartext[id].Visible = false end
                    if entityType.entities.skeleton[id] then
                        for _, bone in pairs(entityType.entities.skeleton[id]) do
                            if bone and bone.line then bone.line.Visible = false end
                        end
                    end
                    if entityType.entities.imagebox[id] then entityType.entities.imagebox[id].Visible = false end
                    local arrow = ImageManager:GetImage("oofarrow_" .. id)
                    if arrow then arrow.Visible = false end
                    local vcimg = ImageManager:GetImage("vischeckimage_" .. id)
                    if vcimg then vcimg.Visible = false end
                    local wimg = ImageManager:GetImage("weaponimage_" .. id)
                    if wimg then wimg.Visible = false end
                    for place, types in pairs(entityType.entities.text) do
                        for textType, texts in pairs(types) do
                            if texts[id] then texts[id].Visible = false end
                        end
                    end
                end
            end
            return
        end

        for typeName, entityType in pairs(self.entityTypes) do
            if not entityType.enabled then
                continue
            end

            for id, target in pairs(entityType.valid) do
                local isValid = entityType:IsValid(target, id)

                if not isValid then

                    if entityType.entities.box[id] then
                        entityType.entities.box[id].Visible = false
                        entityType.entities.boxoutline[id].Visible = false
                    end

                    if entityType.entities.healthbar[id] then
                        entityType.entities.healthbar[id].Visible = false
                        entityType.entities.healthbarbackground[id].Visible = false
                        if entityType.entities.healthbartext[id] then
                            entityType.entities.healthbartext[id].Visible = false
                        end
                    end

                    if entityType.entities.skeleton[id] then
                        for _, bone in pairs(entityType.entities.skeleton[id]) do
                            if bone and bone.line then
                                bone.line.Visible = false
                            end
                        end
                    end

                    if entityType.entities.imagebox[id] then
                        entityType.entities.imagebox[id].Visible = false
                    end

                    local vischeckImg = ImageManager:GetImage("vischeckimage_" .. id)
                    if vischeckImg then vischeckImg.Visible = false end

                    local arrow = ImageManager:GetImage("oofarrow_" .. id)
                    if arrow then
                        arrow.Visible = false
                    end

                    local wimg = ImageManager:GetImage("weaponimage_" .. id)
                    if wimg then wimg.Visible = false end

                    for place, types in pairs(entityType.entities.text) do
                        for textType, texts in pairs(types) do
                            if texts[id] then
                                texts[id].Visible = false
                            end
                        end
                    end

                    continue
                end

                local isModel = entityType.isModel[id] or (not entityType.isPart[id])
                local isPart = entityType.isPart[id]
                local min, max, onscreen = Math.getcorners(target, isModel, isPart)

                entityType.mins[id] = min
                entityType.maxes[id] = max
                entityType.onscreens[id] = onscreen

                entityType:CalculateTextOffsets(id, min, max)

                self:_HandleBox(entityType, id, target)
                self:_HandleHealthbar(entityType, id, target)
                self:_HandleSkeleton(entityType, id, target)
                self:_HandleImageBox(entityType, id, target)
                self:_HandleOOFArrows(entityType, id, target)
                self:_HandleVischeckImage(entityType, id, target)
                self:_HandleWeaponImage(entityType, id, target)

                for textType, _ in pairs(entityType.settings) do
                    local setting = entityType.settings[textType]

                    if type(setting) == "table" and setting.priority ~= nil then
                        self:_HandleText(entityType, id, textType, target)
                    end
                end
            end
        end
    end)

    self.chamsRunning = true
    task.spawn(function()

        for typeName, entityType in pairs(self.entityTypes) do
            if not entityType.enabled then continue end
            for id, target in pairs(entityType.valid) do
                if entityType:IsValid(target, id) then
                    self:_UpdateChams(entityType, id, target)
                end
            end
        end

        while self.chamsRunning do
            local minWait = 2
            for typeName, entityType in pairs(self.entityTypes) do
                if entityType.enabled and entityType.settings.chams then
                    local chamWait = entityType.settings.chams.updatefrequency or 2
                    local effectiveWait = chamWait
                    if entityType.settings.chams.vischeck and entityType.settings.chams.vischeck.enabled then
                        effectiveWait = math.min(chamWait, entityType.settings.chams.vischeck.updatefrequency or chamWait)
                    end
                    minWait = math.min(minWait, effectiveWait)
                end
            end

            task.wait(minWait)
            if not self.chamsRunning then break end

            for typeName, entityType in pairs(self.entityTypes) do
                if not entityType.enabled then continue end
                for id, target in pairs(entityType.valid) do
                    if entityType:IsValid(target, id) then
                        self:_UpdateChams(entityType, id, target)
                    end
                end
            end
        end
    end)
end

function ESP:Stop()

    self.chamsRunning = false

    if self.renderConnection then
        self.renderConnection:Disconnect()
        self.renderConnection = nil
    end

    for typeName, entityType in pairs(self.entityTypes) do
        for id, _ in pairs(entityType.valid) do
            self:_RemoveAllESP(entityType, id)
        end
    end

    ImageManager:Cleanup()

    -- Clean up the CoreGui chams container
    if self.chamsContainer and self.chamsContainer.Parent then
        self.chamsContainer:Destroy()
        self.chamsContainer = nil
    end
end

ESP:CreateEntityType("players")

Players.PlayerAdded:Connect(function(player)
    ESP:TrackPlayer(player, "players")
end)

Players.PlayerRemoving:Connect(function(player)
    local playerType = ESP:GetEntityType("players")
    if playerType then
        local id = player.UserId
        ESP:Untrack("players", id)
    end
end)

for _, player in pairs(Players:GetPlayers()) do
    ESP:TrackPlayer(player, "players")
end

-- Team check refresh loop (every 5 seconds)
spawn(function()
    while true do
        wait(5)
        if ESP.teamCheckEnabled then
            -- Clear and rebuild team table
            table.clear(ESP.team)
            local lpTeam = lp.Team
            if lpTeam then
                for _, player in pairs(Players:GetPlayers()) do
                    if player ~= lp and player.Team == lpTeam then
                        ESP.team[player.UserId] = true
                    end
                end
            end
        end
    end
end)

return ESP
