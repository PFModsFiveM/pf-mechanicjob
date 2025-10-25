local QBCore = exports['qb-core']:GetCoreObject()

-- Helper: Get vehicle damage (same logic as damage.lua)
local function getVehicleDamage(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    local state = Entity(veh)
    if not state or not state.state then return nil end
    local damage = state.state.partDamage or {}
    damage.brakes = damage.brakes or 0
    return damage
end

-- Helper: Calculate pads needed (same logic as damage.lua)
local function calcPadsNeeded(brakeDmg)
    if brakeDmg >= 100 then return 4 end
    local pads = math.ceil((brakeDmg > 0 and brakeDmg or 0) / 25)
    return math.max(1, math.min(4, pads))
end

-- Helper: Get nearest vehicle
local function getRepairVehicle()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and DoesEntityExist(veh) then return veh end
    end
    local coords = GetEntityCoords(ped)
    local veh = GetClosestVehicle(coords.x, coords.y, coords.z, 6.0, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then return veh end
    return nil
end

-- Open Mechanic Tools menu (includes Brake Pads repair)
RegisterNetEvent('pf-mechanicjob:client:openToolsMenu', function()
    local veh = getRepairVehicle()
    local damage = veh and getVehicleDamage(veh) or nil
    local brakeDmg = damage and (tonumber(damage.brakes) or 0) or 0
    local brakeHealth = math.max(0, 100 - brakeDmg)
    local padsNeeded = calcPadsNeeded(brakeDmg)

    local menu = {
        { header = 'Mechanic Tools', isMenuHeader = true },
        {
            header = 'Brake Pads',
            txt = ('Health: %d%% • Needs: %d • Use brake pads item near vehicle'):format(brakeHealth, padsNeeded),
            isMenuHeader = true
        },
        -- ...add your other existing tool actions here if needed...
        { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    }
    if exports['qb-menu'] and exports['qb-menu'].openMenu then
        exports['qb-menu']:openMenu(menu)
    else
        QBCore.Functions.Notify('qb-menu not found.', 'error')
    end
end)
