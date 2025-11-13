local time = 10 -- how long the particle lasts
local SIZE = 1.0
local particleDict = "core"
local particleName = "ent_amb_generator_smoke"
local bone = "exhaust"
local key = 71
local maxSpeed = 40.0 -- max speed in MPH for rolling coal

-- [EFFECTS FROM CORE ONLY]
-- veh_exhaust_truck_rig [size = 3.0]
-- ent_amb_smoke_general [size = 1.0]
-- ent_amb_generator_smoke [size = 1.0]










local car_net = nil
local isRollingCoal = false
local currentParticles = {}

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        local ped = GetPlayerPed(PlayerId())
        
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            local speed = GetEntitySpeed(vehicle) * 2.23694 -- Convert m/s to MPH
            local isDiesel = IsDieselVehicle(vehicle)
            
            if IsPedTheDriver(vehicle, ped) and isDiesel then
                if IsControlPressed(1, key) and not isRollingCoal and speed <= maxSpeed then
                    -- Start rolling coal
                    isRollingCoal = true
                    RequestNamedPtfxAsset(particleDict)
                    
                    while not HasNamedPtfxAssetLoaded(particleDict) do
                        Citizen.Wait(10)
                    end
                    
                    local netid = VehToNet(vehicle)
                    SetNetworkIdExistsOnAllMachines(netid, 1)
                    NetworkSetNetworkIdDynamic(netid, 0)
                    SetNetworkIdCanMigrate(netid, 0)
                    
                    car_net = netid
                    TriggerServerEvent("Smoke:SyncStartParticles", car_net)
                elseif (not IsControlPressed(1, key) or speed > maxSpeed) and isRollingCoal then
                    -- Stop rolling coal
                    isRollingCoal = false
                    TriggerServerEvent("Smoke:SyncStopParticles", car_net)
                end
            elseif isRollingCoal then
                -- Stop if no longer in diesel vehicle or not driver
                isRollingCoal = false
                TriggerServerEvent("Smoke:SyncStopParticles", car_net)
            end
        else
            if isRollingCoal then
                isRollingCoal = false
                TriggerServerEvent("Smoke:SyncStopParticles", car_net)
            end
        end
    end
end)

RegisterNetEvent("Smoke:StartParticles")
AddEventHandler("Smoke:StartParticles", function(carid)
    local entity = NetToVeh(carid)
    local part = GetWorldPositionOfEntityBone(entity, bone)
    
    -- Clear any existing particles
    for _, particle in pairs(currentParticles) do
        StopParticleFxLooped(particle, true)
    end
    currentParticles = {}
    
    -- Start continuous particle emission
    Citizen.CreateThread(function()
        while isRollingCoal do
            UseParticleFxAssetNextCall(particleDict)
            local particle = StartParticleFxLoopedOnEntityBone(particleName, entity, part.x, part.y, part.z, 0.0, 0.0, 0.0, GetEntityBoneIndexByName(entity, bone), SIZE, false, false, false)
            SetParticleFxLoopedEvolution(particle, particleName, SIZE, 0)
            table.insert(currentParticles, particle)
            Citizen.Wait(0)
        end
    end)
end)

RegisterNetEvent("Smoke:StopParticles")
AddEventHandler("Smoke:StopParticles", function()
    for _, particle in pairs(currentParticles) do
        StopParticleFxLooped(particle, true)
    end
    currentParticles = {}
end)

function IsPedTheDriver(vehicle, ped)
    local driverPed = GetPedInVehicleSeat(vehicle, -1)
    if driverPed == ped then
        return true
    else
        return false
    end
end

function IsDieselVehicle(vehicle)
    -- Check if vehicle uses diesel fuel type (fuel type 2)
    local fuelType = GetVehicleFuelType(vehicle)
    return fuelType == 2
end

function GetVehicleFuelType(vehicle)
    -- Fuel types: 0 = None, 1 = Petrol, 2 = Diesel, 3 = Electric
    local model = GetEntityModel(vehicle)
    local vehicleClass = GetVehicleClass(vehicle)
    
    -- Trucks, Utility, Commercial, Industrial are typically diesel
    if vehicleClass == 11 or vehicleClass == 12 or vehicleClass == 15 or vehicleClass == 19 or vehicleClass == 20 then
        return 2 -- Diesel
    end
    
    return 1 -- Petrol (default)
end