local QBCore = exports['qb-core']:GetCoreObject()

function DoWheelSteps()
  QBCore.Functions.Progressbar('pf_loosen_lugs','Loosening lugs', 3000, false, true, { disableMovement=true, disableCombat=true }, {}, {}, {}, function()
    QBCore.Functions.Progressbar('pf_remove_tire','Removing tire', 2500, false, true, {}, {}, {}, {}, function()
      TriggerEvent('QBCore:Notify','Wheel removed', 'success')
    end)
  end)
end

exports('DoWheelSteps', DoWheelSteps)
