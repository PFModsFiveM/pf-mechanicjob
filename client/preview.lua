local QBCore = exports['qb-core']:GetCoreObject()

-- =========================
-- COSMETIC PREVIEW SYSTEM (MOVED FROM damage.lua)
-- =========================
local PreviewSessions = PreviewSessions or {}
local PreviewVeh = PreviewVeh or nil

local function isMechanicJob()
    local pd = QBCore.Functions.GetPlayerData()
    return pd and pd.job and pd.job.name and Config.IsMechanicJob(pd.job.name) or false
end

local function getModDisplayName(veh, modType, index)
    if index == -1 then return 'Stock' end
    local lbl = GetModTextLabel(veh, modType, index)
    if lbl and lbl ~= '' then
        local nice = GetLabelText(lbl)
        if nice and nice ~= 'NULL' then return nice end
        return lbl
    end
    return ('Option %d'):format(index + 1)
end

local function captureVehicleAppearance(veh)
    if not DoesEntityExist(veh) then return nil end
    SetVehicleModKit(veh, 0)
    local snap = { mods={}, wheelType=nil, windowTint=nil, colors={} }
    local modTypes = {0,1,2,3,4,6,7,8,9,10,23,48}
    for _, m in ipairs(modTypes) do snap.mods[m] = GetVehicleMod(veh, m) end
    snap.wheelType = GetVehicleWheelType(veh) or 0
    snap.windowTint = GetVehicleWindowTint(veh) or 0
    local p,s = GetVehicleColours(veh)
    local pearl,wheelCol = GetVehicleExtraColours(veh)
    snap.colors.classic = {primary=p or 0, secondary=s or 0, pearl=pearl or 0, wheel=wheelCol or 0}
    if GetIsVehiclePrimaryColourCustom(veh) then
        local r,g,b = GetVehicleCustomPrimaryColour(veh)
        snap.colors.customPrimary = {r=r,g=g,b=b}
    end
    if GetIsVehicleSecondaryColourCustom(veh) then
        local r,g,b = GetVehicleCustomSecondaryColour(veh)
        snap.colors.customSecondary = {r=r,g=g,b=b}
    end
    return snap
end

local function applySnapshot(veh, snap)
    if not veh or not DoesEntityExist(veh) or not snap then return end
    SetVehicleModKit(veh, 0)
    if snap.wheelType then SetVehicleWheelType(veh, snap.wheelType) end
    for m, idx in pairs(snap.mods) do SetVehicleMod(veh, m, idx, false) end
    ClearVehicleCustomPrimaryColour(veh)
    ClearVehicleCustomSecondaryColour(veh)
    local c = snap.colors.classic or {primary=0,secondary=0,pearl=0,wheel=0}
    SetVehicleColours(veh, c.primary, c.secondary)
    SetVehicleExtraColours(veh, c.pearl, c.wheel)
    if snap.colors.customPrimary then
        SetVehicleCustomPrimaryColour(veh, snap.colors.customPrimary.r, snap.colors.customPrimary.g, snap.colors.customPrimary.b)
    end
    if snap.colors.customSecondary then
        SetVehicleCustomSecondaryColour(veh, snap.colors.customSecondary.r, snap.colors.customSecondary.g, snap.colors.customSecondary.b)
    end
    if snap.windowTint then SetVehicleWindowTint(veh, snap.windowTint) end
end

local function generatePreviewReceipt(veh, snapshot)
    if not Config.PreviewReceipt or not Config.PreviewReceipt.enabled then return nil end
    local current = captureVehicleAppearance(veh)
    if not current or not snapshot then return nil end
    local changes = {}
    for modType, oldIdx in pairs(snapshot.mods) do
        local newIdx = current.mods[modType]
        if newIdx ~= oldIdx then
            local nameMap = {
                [0]='Spoiler',[1]='Front Bumper',[2]='Rear Bumper',[3]='Side Skirts',
                [4]='Exhaust',[6]='Grille',[7]='Hood',[8]='Fender',[9]='Right Fender',
                [10]='Roof',[23]='Wheels',[48]='Livery'
            }
            changes[#changes+1] = {
                type='mod',
                name=nameMap[modType] or ('Mod '..modType),
                from=getModDisplayName(veh, modType, oldIdx),
                to=getModDisplayName(veh, modType, newIdx)
            }
        end
    end
    local old,new = snapshot.colors.customPrimary, current.colors.customPrimary
    if old or new then
        local a = old or {r=0,g=0,b=0}; local b = new or {r=0,g=0,b=0}
        if a.r~=b.r or a.g~=b.g or a.b~=b.b then
            changes[#changes+1] = { type='color', name='Primary Color',
                from=('RGB(%d,%d,%d)'):format(a.r,a.g,a.b),
                to=('RGB(%d,%d,%d)'):format(b.r,b.g,b.b) }
        end
    end
    old,new = snapshot.colors.customSecondary, current.colors.customSecondary
    if old or new then
        local a = old or {r=0,g=0,b=0}; local b = new or {r=0,g=0,b=0}
        if a.r~=b.r or a.g~=b.g or a.b~=b.b then
            changes[#changes+1] = { type='color', name='Secondary Color',
                from=('RGB(%d,%d,%d)'):format(a.r,a.g,a.b),
                to=('RGB(%d,%d,%d)'):format(b.r,b.g,b.b) }
        end
    end
    if snapshot.windowTint ~= current.windowTint then
        local tintNames={[0]='None',[1]='Pure Black',[2]='Dark Smoke',[3]='Light Smoke',[4]='Stock',[5]='Limo',[6]='Green'}
        changes[#changes+1] = { type='tint', name='Window Tint',
            from=tintNames[snapshot.windowTint] or 'Unknown',
            to=tintNames[current.windowTint] or 'Unknown' }
    end
    if #changes == 0 then return nil end
    return {
        timestamp = (GetCloudTimeAsInt and GetCloudTimeAsInt()) or (GetGameTimer and GetGameTimer()) or 0,
        vehicle = GetDisplayNameFromVehicleModel(GetEntityModel(veh)),
        plate = GetVehicleNumberPlateText(veh),
        changes = changes,
        changeCount = #changes
    }
end

local function endPreview(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local sess = PreviewSessions[veh]
    if not sess or not sess.active then return end
    local receiptData = generatePreviewReceipt(veh, sess.snapshot)
    applySnapshot(veh, sess.snapshot)
    PreviewSessions[veh] = nil
    pcall(function() TriggerEvent('qb-menu:client:closeMenu') end)
    if receiptData then TriggerServerEvent('pf_mech:givePreviewReceipt', receiptData) end
    QBCore.Functions.Notify('Preview ended. Vehicle restored.', 'primary')
    PreviewVeh = nil
end

local function ensurePreviewSession(veh)
    if PreviewSessions[veh] and PreviewSessions[veh].active then return true end
    local snap = captureVehicleAppearance(veh)
    if not snap then return false end
    PreviewSessions[veh] = { active = true, snapshot = snap }
    PreviewVeh = veh
    CreateThread(function()
        local ped = PlayerPedId()
        while PreviewSessions[veh] and PreviewSessions[veh].active do
            if IsControlJustReleased(0,322) or IsControlJustReleased(0,177) or IsControlJustReleased(0,200) then
                endPreview(veh); break
            end
            if not IsPedInAnyVehicle(ped,false) or GetVehiclePedIsIn(ped,false) ~= veh or GetPedInVehicleSeat(veh,-1) ~= ped then
                endPreview(veh); break
            end
            Wait(120)
        end
    end)
    return true
end

local function previewMod(veh, modType, index)
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, modType, index or -1, false)
end

local function applyPrimaryColor(veh, rgb)
    if not rgb then return end
    ClearVehicleCustomPrimaryColour(veh)
    SetVehicleCustomPrimaryColour(veh, rgb.r, rgb.g, rgb.b)
end
local function applySecondaryColor(veh, rgb)
    if not rgb then return end
    ClearVehicleCustomSecondaryColour(veh)
    SetVehicleCustomSecondaryColour(veh, rgb.r, rgb.g, rgb.b)
end

-- Missing helper previously implied
local function setClassicColor(veh, which, index)
    if not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh,0)
    if which == 'primary' then
        ClearVehicleCustomPrimaryColour(veh)
        local p,s = GetVehicleColours(veh)
        SetVehicleColours(veh, index, s)
    elseif which == 'secondary' then
        ClearVehicleCustomSecondaryColour(veh)
        local p,s = GetVehicleColours(veh)
        SetVehicleColours(veh, p, index)
    elseif which == 'pearl' then
        local _,w = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, index, w)
    elseif which == 'wheel' then
        local prl,_ = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, prl, index)
    end
end

local WindowTints = {
    {label='None', val=0},{label='Pure Black',val=1},{label='Dark Smoke',val=2},
    {label='Light Smoke',val=3},{label='Stock',val=4},{label='Limo',val=5},{label='Green',val=6}
}

local function buildModList(veh, modType)
    local list = {}
    SetVehicleModKit(veh,0)
    local count = GetNumVehicleMods(veh, modType) or 0
    list[#list+1] = { label = getModDisplayName(veh, modType, -1), index = -1 }
    for i=0,count-1 do
        list[#list+1] = { label = getModDisplayName(veh, modType, i), index = i }
    end
    return list
end

local function OpenQBMenu(entries)
    local ok = false
    local success = pcall(function()
        if exports and exports['qb-menu'] and exports['qb-menu'].openMenu then
            exports['qb-menu']:openMenu(entries); ok = true
        end
    end)
    if not success or not ok then TriggerEvent('qb-menu:client:openMenu', entries); ok = true end
    return ok
end

local function openModMenu(veh, label, modType)
    local m = { { header = label, isMenuHeader = true }, }
    for _, it in ipairs(buildModList(veh, modType)) do
        m[#m+1] = {
            header = it.label, shouldClose = false,
            params = { event='pf_mech:preview:setMod', args={ modType=modType, index=it.index, label=label } }
        }
    end
    m[#m+1] = { header='Back', params={ event='pf_mech:preview:openMain' } }
    OpenQBMenu(m)
end

local function openColorMenu(veh, which)
    local entries = {
        { header = (which == 'secondary' and 'Secondary Color' or which == 'pearl' and 'Pearlescent Color' or which == 'wheel' and 'Wheel Color' or 'Primary Color'), isMenuHeader = true },
        { header = 'Classic',    params = { event = 'pf_mech:preview:openPaintCategory', args = { which = which } } },
        { header = 'Metallic',   params = { event = 'pf_mech:preview:openPaintCategory', args = { which = which } } },
        { header = 'Matte',      params = { event = 'pf_mech:preview:openPaintCategory', args = { which = which } } },
        { header = 'Metals',     params = { event = 'pf_mech:preview:openPaintCategory', args = { which = which } } },
        { header = 'Util',       params = { event = 'pf_mech:preview:openPaintCategory', args = { which = which } } },
        { header = 'Chameleon',  params = { event = 'pf_mech:preview:openPaintCategory', args = { which = which } } },
    }
    OpenQBMenu(entries)
end

-- GTA 5 paint color tables (expand as needed)
local GTA5PaintColors = {
    classic = {
        { name = "Black", index = 0 }, { name = "Graphite", index = 1 }, { name = "Black Steel", index = 2 }, { name = "Dark Steel", index = 3 },
        { name = "Silver", index = 4 }, { name = "Bluish Silver", index = 5 }, { name = "Rolled Steel", index = 6 }, { name = "Shadow Silver", index = 7 },
        { name = "Stone Silver", index = 8 }, { name = "Midnight Silver", index = 9 }, { name = "Cast Iron Silver", index = 10 },
        { name = "Red", index = 27 }, { name = "Torino Red", index = 28 }, { name = "Formula Red", index = 29 }, { name = "Lava Red", index = 150 },
        { name = "Blaze Red", index = 30 }, { name = "Grace Red", index = 31 }, { name = "Garnet Red", index = 32 }, { name = "Sunset Red", index = 33 },
        { name = "Cabernet Red", index = 34 }, { name = "Candy Red", index = 35 }, { name = "Hot Pink", index = 135 }, { name = "Pfsiter Pink", index = 137 },
        { name = "Salmon Pink", index = 136 }, { name = "Sunrise Orange", index = 36 }, { name = "Orange", index = 38 }, { name = "Bright Orange", index = 138 },
        { name = "Gold", index = 99 }, { name = "Bronze", index = 90 }, { name = "Yellow", index = 88 }, { name = "Race Yellow", index = 89 },
        { name = "Dew Yellow", index = 91 }, { name = "Dark Green", index = 49 }, { name = "Racing Green", index = 50 }, { name = "Sea Green", index = 51 },
        { name = "Olive Green", index = 52 }, { name = "Bright Green", index = 53 }, { name = "Gasoline Green", index = 54 },
        { name = "Lime Green", index = 92 }, { name = "Midnight Blue", index = 141 }, { name = "Galaxy Blue", index = 61 },
        { name = "Dark Blue", index = 62 }, { name = "Saxon Blue", index = 63 }, { name = "Blue", index = 64 }, { name = "Mariner Blue", index = 65 },
        { name = "Harbor Blue", index = 66 }, { name = "Diamond Blue", index = 67 }, { name = "Surf Blue", index = 68 }, { name = "Nautical Blue", index = 69 },
        { name = "Racing Blue", index = 73 }, { name = "Ultra Blue", index = 70 }, { name = "Light Blue", index = 74 }, { name = "Chocolate Brown", index = 96 },
        { name = "Bison Brown", index = 101 }, { name = "Creeen Brown", index = 95 }, { name = "Feltzer Brown", index = 94 }, { name = "Maple Brown", index = 97 },
        { name = "Beechwood Brown", index = 103 }, { name = "Sienna Brown", index = 104 }, { name = "Saddle Brown", index = 98 }, { name = "Moss Brown", index = 100 },
        { name = "Woodbeech Brown", index = 102 }, { name = "Straw Brown", index = 99 }, { name = "Sandy Brown", index = 105 }, { name = "Bleached Brown", index = 106 },
        { name = "Schafter Purple", index = 71 }, { name = "Spinnaker Purple", index = 72 }, { name = "Midnight Purple", index = 142 },
        { name = "Bright Purple", index = 145 }, { name = "Cream", index = 107 }, { name = "Ice White", index = 111 }, { name = "Frost White", index = 112 }
    },
    metallic = {
        { name = "Black", index = 0 }, { name = "Graphite", index = 1 }, { name = "Black Steel", index = 2 }, { name = "Dark Steel", index = 3 },
        { name = "Silver", index = 4 }, { name = "Bluish Silver", index = 5 }, { name = "Rolled Steel", index = 6 }, { name = "Shadow Silver", index = 7 },
        { name = "Stone Silver", index = 8 }, { name = "Midnight Silver", index = 9 }, { name = "Cast Iron Silver", index = 10 },
        { name = "Red", index = 27 }, { name = "Torino Red", index = 28 }, { name = "Formula Red", index = 29 }, { name = "Lava Red", index = 150 },
        { name = "Blaze Red", index = 30 }, { name = "Grace Red", index = 31 }, { name = "Garnet Red", index = 32 }, { name = "Sunset Red", index = 33 },
        { name = "Cabernet Red", index = 34 }, { name = "Candy Red", index = 35 }, { name = "Hot Pink", index = 135 }, { name = "Pfsiter Pink", index = 137 },
        { name = "Salmon Pink", index = 136 }, { name = "Sunrise Orange", index = 36 }, { name = "Orange", index = 38 }, { name = "Bright Orange", index = 138 },
        { name = "Gold", index = 99 }, { name = "Bronze", index = 90 }, { name = "Yellow", index = 88 }, { name = "Race Yellow", index = 89 },
        { name = "Dew Yellow", index = 91 }, { name = "Dark Green", index = 49 }, { name = "Racing Green", index = 50 }, { name = "Sea Green", index = 51 },
        { name = "Olive Green", index = 52 }, { name = "Bright Green", index = 53 }, { name = "Gasoline Green", index = 54 },
        { name = "Lime Green", index = 92 }, { name = "Midnight Blue", index = 141 }, { name = "Galaxy Blue", index = 61 },
        { name = "Dark Blue", index = 62 }, { name = "Saxon Blue", index = 63 }, { name = "Blue", index = 64 }, { name = "Mariner Blue", index = 65 },
        { name = "Harbor Blue", index = 66 }, { name = "Diamond Blue", index = 67 }, { name = "Surf Blue", index = 68 }, { name = "Nautical Blue", index = 69 },
        { name = "Racing Blue", index = 73 }, { name = "Ultra Blue", index = 70 }, { name = "Light Blue", index = 74 }, { name = "Chocolate Brown", index = 96 },
        { name = "Bison Brown", index = 101 }, { name = "Creeen Brown", index = 95 }, { name = "Feltzer Brown", index = 94 }, { name = "Maple Brown", index = 97 },
        { name = "Beechwood Brown", index = 103 }, { name = "Sienna Brown", index = 104 }, { name = "Saddle Brown", index = 98 }, { name = "Moss Brown", index = 100 },
        { name = "Woodbeech Brown", index = 102 }, { name = "Straw Brown", index = 99 }, { name = "Sandy Brown", index = 105 }, { name = "Bleached Brown", index = 106 },
        { name = "Schafter Purple", index = 71 }, { name = "Spinnaker Purple", index = 72 }, { name = "Midnight Purple", index = 142 },
        { name = "Bright Purple", index = 145 }, { name = "Cream", index = 107 }, { name = "Ice White", index = 111 }, { name = "Frost White", index = 112 }
    },
    matte = {
        { name = "Matte Black", index = 12 }, { name = "Matte Gray", index = 13 }, { name = "Matte Light Gray", index = 14 },
        { name = "Matte Ice White", index = 131 }, { name = "Matte Blue", index = 83 }, { name = "Matte Dark Blue", index = 82 },
        { name = "Matte Midnight Blue", index = 84 }, { name = "Matte Midnight Purple", index = 149 }, { name = "Matte Schafter Purple", index = 148 },
        { name = "Matte Red", index = 39 }, { name = "Matte Dark Red", index = 40 }, { name = "Matte Orange", index = 41 },
        { name = "Matte Yellow", index = 42 }, { name = "Matte Lime Green", index = 55 }, { name = "Matte Green", index = 128 },
        { name = "Matte Forest Green", index = 151 }, { name = "Matte Foliage Green", index = 155 }, { name = "Matte Olive Darb", index = 152 },
        { name = "Matte Desert Brown", index = 153 }, { name = "Matte Foilage Brown", index = 154 }, { name = "Matte White", index = 131 }
    },
    metals = {
        { name = "Brushed Steel", index = 117 }, { name = "Brushed Black Steel", index = 118 }, { name = "Brushed Aluminum", index = 119 },
        { name = "Pure Gold", index = 158 }, { name = "Brushed Gold", index = 159 }
    },
    util = {
        { name = "Util Black", index = 15 }, { name = "Util Black Poly", index = 16 }, { name = "Util Dark Silver", index = 17 },
        { name = "Util Silver", index = 18 }, { name = "Util Gun Metal", index = 19 }, { name = "Util Shadow Silver", index = 20 },
        { name = "Util Red", index = 33 }, { name = "Util Bright Red", index = 34 }, { name = "Util Garnet Red", index = 35 },
        { name = "Util Dark Green", index = 51 }, { name = "Util Green", index = 52 }, { name = "Util Light Green", index = 53 },
        { name = "Util Dark Blue", index = 62 }, { name = "Util Midnight Blue", index = 63 }, { name = "Util Blue", index = 64 },
        { name = "Util Sea Foam Blue", index = 65 }, { name = "Util Lightning Blue", index = 66 }, { name = "Util Maui Blue Poly", index = 67 },
        { name = "Util Bright Blue", index = 68 }, { name = "Util Purple", index = 70 }, { name = "Util Dark Purple", index = 71 },
        { name = "Util Garnet Red", index = 72 }, { name = "Util Yellow", index = 88 }, { name = "Util Brown", index = 89 },
        { name = "Util Medium Brown", index = 90 }, { name = "Util Light Brown", index = 91 }, { name = "Util Cream", index = 93 }
    },
    chameleon = {
        { name = "Anod Red", index = 161 }, { name = "Anod Blue", index = 162 }, { name = "Anod Gold", index = 163 },
        { name = "Green/Blue Flip", index = 164 }, { name = "Purple/Green Flip", index = 165 }, { name = "Orange/Purple Flip", index = 166 },
        { name = "Red/Green Flip", index = 167 }, { name = "Blue/Green Flip", index = 168 }, { name = "Copper/Orange Flip", index = 169 },
        { name = "Silver/Purple Flip", index = 170 }, { name = "Magenta/Green Flip", index = 171 }, { name = "Gold/Purple Flip", index = 172 },
        { name = "Red/Orange Flip", index = 173 }, { name = "Blue/Purple Flip", index = 174 }, { name = "Green/Red Flip", index = 175 },
        { name = "Orange/Blue Flip", index = 176 }, { name = "Purple/Orange Flip", index = 177 }, { name = "Green/Yellow Flip", index = 178 },
        { name = "Blue/Red Flip", index = 179 }, { name = "Copper/Green Flip", index = 180 }, { name = "Silver/Blue Flip", index = 181 },
        { name = "Magenta/Blue Flip", index = 182 }, { name = "Gold/Green Flip", index = 183 }, { name = "Red/Blue Flip", index = 184 },
        { name = "Blue/Gold Flip", index = 185 }, { name = "Green/Blue/Red Flip", index = 186 }, { name = "Orange/Green Flip", index = 187 },
        { name = "Purple/Blue Flip", index = 188 }, { name = "Green/Orange Flip", index = 189 }, { name = "Blue/Orange Flip", index = 190 },
        { name = "Copper/Blue Flip", index = 191 }, { name = "Silver/Green Flip", index = 192 }, { name = "Magenta/Orange Flip", index = 193 },
        { name = "Gold/Blue Flip", index = 194 }, { name = "Red/Gold Flip", index = 195 }, { name = "Blue/Green/Gold Flip", index = 196 },
        { name = "Green/Red/Blue Flip", index = 197 }, { name = "Orange/Blue/Green Flip", index = 198 }, { name = "Purple/Green/Blue Flip", index = 199 }
    }
}

-- Show paint categories when clicking a color option (primary, secondary, etc)
local function openPaintCategoryMenu(veh, which)
    local menu = {
        { header = (which:gsub("^%l", string.upper)) .. " Paint Type", isMenuHeader = true },
        { header = "Classic",    params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "classic" } } },
        { header = "Metallic",   params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "metallic" } } },
        { header = "Matte",      params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "matte" } } },
        { header = "Metals",     params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "metals" } } },
        { header = "Util",       params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "util" } } },
        { header = "Chameleon",  params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "chameleon" } } },
        { header = "Back",       params = { event = "pf_mech:preview:openPaintJobs" } }
    }
    OpenQBMenu(menu)
end

-- Show color list for a GTA 5 paint category
local function openPaintColorListMenu(veh, which, paintType)
    local colors = GTA5PaintColors[paintType] or {}
    local menu = {
        { header = ("%s - %s Colors"):format(which:gsub("^%l", string.upper), paintType:gsub("^%l", string.upper)), isMenuHeader = true }
    }
    for _, color in ipairs(colors) do
        menu[#menu+1] = {
            header = color.name,
            params = { event = "pf_mech:preview:applyPaintColor", args = { which = which, paintType = paintType, index = color.index } }
        }
    end
    menu[#menu+1] = { header = "Back", params = { event = "pf_mech:preview:openPaintCategory", args = { which = which } } }
    OpenQBMenu(menu)
end

-- Apply selected color to vehicle
RegisterNetEvent("pf_mech:preview:applyPaintColor", function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    SetVehicleModKit(PreviewVeh, 0)
    if d.which == "primary" then
        ClearVehicleCustomPrimaryColour(PreviewVeh)
        SetVehicleColours(PreviewVeh, d.index, select(2, GetVehicleColours(PreviewVeh)))
    elseif d.which == "secondary" then
        ClearVehicleCustomSecondaryColour(PreviewVeh)
        SetVehicleColours(PreviewVeh, select(1, GetVehicleColours(PreviewVeh)), d.index)
    elseif d.which == "pearl" then
        local _, wheel = GetVehicleExtraColours(PreviewVeh)
        SetVehicleExtraColours(PreviewVeh, d.index, wheel)
    elseif d.which == "wheel" then
        local pearl, _ = GetVehicleExtraColours(PreviewVeh)
        SetVehicleExtraColours(PreviewVeh, pearl, d.index)
    end
    -- Reopen color list for further selection
    SetTimeout(40, function()
        openPaintColorListMenu(PreviewVeh, d.which, d.paintType)
    end)
end)

-- Event to open paint category menu
RegisterNetEvent("pf_mech:preview:openPaintCategory", function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    openPaintCategoryMenu(PreviewVeh, d.which)
end)

-- Event to open color list for a paint type
RegisterNetEvent("pf_mech:preview:openPaintColorList", function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    openPaintColorListMenu(PreviewVeh, d.which, d.paintType)
end)

-- Update openPaintJobs to use new color flow
RegisterNetEvent('pf_mech:preview:openPaintJobs', function()
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    local menu = {
        { header = 'Paint Jobs', isMenuHeader = true },
        { header = 'Primary Color',    params = { event = 'pf_mech:preview:openPaintCategory', args = { which = 'primary' } } },
        { header = 'Secondary Color',  params = { event = 'pf_mech:preview:openPaintCategory', args = { which = 'secondary' } } },
        { header = 'Pearlescent',      params = { event = 'pf_mech:preview:openPaintCategory', args = { which = 'pearl' } } },
        { header = 'Wheel Color',      params = { event = 'pf_mech:preview:openPaintCategory', args = { which = 'wheel' } } },
        { header = 'Back',             params = { event = 'pf_mech:preview:openMain' } }
    }
    OpenQBMenu(menu)
end)

-- Update openMain to keep Paint Jobs button
RegisterNetEvent('pf_mech:preview:openMain', function()
    local ped = PlayerPedId()
    local veh = PreviewVeh or GetVehiclePedIsIn(ped,false)
    if not veh or veh == 0 then return end
    if Config.MenuSystem ~= 'qb-menu' then
        QBCore.Functions.Notify('Preview requires qb-menu', 'error')
        return
    end
    local menu = {
        { header='Preview Cosmetics', isMenuHeader=true },
        { header='Spoiler',        txt='Preview spoilers',        params={ event='pf_mech:preview:openMod', args={ label='Spoiler', modType=0 } } },
        { header='Front Bumper',   txt='Preview front bumpers',   params={ event='pf_mech:preview:openMod', args={ label='Front Bumper', modType=1 } } },
        { header='Rear Bumper',    txt='Preview rear bumpers',    params={ event='pf_mech:preview:openMod', args={ label='Rear Bumper', modType=2 } } },
        { header='Side Skirts',    txt='Preview skirts',          params={ event='pf_mech:preview:openMod', args={ label='Side Skirts', modType=3 } } },
        { header='Exhaust',        txt='Preview exhausts',        params={ event='pf_mech:preview:openMod', args={ label='Exhaust', modType=4 } } },
        { header='Grille',         txt='Preview grilles',         params={ event='pf_mech:preview:openMod', args={ label='Grille', modType=6 } } },
        { header='Hood',           txt='Preview hoods',           params={ event='pf_mech:preview:openMod', args={ label='Hood', modType=7 } } },
        { header='Fenders',        txt='Preview fenders',         params={ event='pf_mech:preview:openMod', args={ label='Fenders', modType=8 } } },
        { header='Right Fender',   txt='Preview right fenders',   params={ event='pf_mech:preview:openMod', args={ label='Right Fender', modType=9 } } },
        { header='Roof',           txt='Preview roofs',           params={ event='pf_mech:preview:openMod', args={ label='Roof', modType=10 } } },
        { header='Livery',         txt='Preview livery',          params={ event='pf_mech:preview:openMod', args={ label='Livery', modType=48 } } },
        { header='Wheels',         txt='Preview wheels',          params={ event='pf_mech:preview:openMod', args={ label='Wheels', modType=23 } } },
        { header='Paint Jobs',     txt='Preview paint colors',    params={ event='pf_mech:preview:openPaintJobs' } },
        { header='Window Tint',     txt='Preview tint levels', params={ event='pf_mech:preview:openTint' } },
        { header='Close & Revert',  txt='Exit without saving', params={ event='pf_mech:preview:end' } },
    }
    OpenQBMenu(menu)
end)

-- Command
RegisterCommand('preview', function()
    if Config.MenuSystem ~= 'qb-menu' then QBCore.Functions.Notify('Preview requires qb-menu', 'error'); return end
    if not isMechanicJob() then QBCore.Functions.Notify('Not authorized', 'error'); return end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped,false) then QBCore.Functions.Notify('Enter a vehicle first', 'error'); return end
    local veh = GetVehiclePedIsIn(ped,false)
    if GetPedInVehicleSeat(veh,-1) ~= ped then QBCore.Functions.Notify('Driver seat required', 'error'); return end
    if not ensureControl or (ensureControl and not ensureControl(veh)) then
        -- fallback control attempt
        NetworkRequestControlOfEntity(veh)
    end
    if not ensurePreviewSession(veh) then QBCore.Functions.Notify('Preview init failed', 'error'); return end
    TriggerEvent('pf_mech:preview:openMain')
    QBCore.Functions.Notify('Preview started. Changes will not be saved.', 'primary')
end, false)
