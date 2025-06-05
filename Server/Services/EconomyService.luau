-- Server/Services/EconomyService.luau
local EconomyService = {}

local POINT_REWARDS = {
    TournamentWin = 150,
    TournamentParticipation = 20,
    FillerWin = 50,
    FillerParticipation = 10,
    Kill = 5,
    Objective = 10,
    -- etc...
}

function EconomyService.AwardPoints(userId: number, reason: string, amount: number?)
    local points = amount or POINT_REWARDS[reason] or 0
    
    PlayerData.Patch(userId, function(data)
        data.Wallet.Credits += points
    end)
    
    -- Fire event to client for UI notification
end