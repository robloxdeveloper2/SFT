-- Server/Services/GameModeService/FFA.luau
--!strict

local Players = game:GetService("Players")
local Shared = game.ReplicatedStorage.Shared
local GameTypes = require(Shared.GameTypes)

type RoundInfo = GameTypes.RoundInfo

local FFA = {}

-- Arena spawn points for FFA
local ARENA_SPAWNS = {
    CFrame.new(-20, 5, 0),
    CFrame.new(20, 5, 0),
    CFrame.new(0, 5, -20),
    CFrame.new(0, 5, 20),
    CFrame.new(-15, 5, -15),
    CFrame.new(15, 5, -15),
    CFrame.new(-15, 5, 15),
    CFrame.new(15, 5, 15),
}

function FFA.Init(roundInfo: RoundInfo)
    -- FFA doesn't need special initialization
end

function FFA.Start(roundInfo: RoundInfo)
    -- All players start as enemies
    -- No team assignment needed for FFA
end

function FFA.Update(roundInfo: RoundInfo, dt: number)
    -- FFA doesn't need special updates
end

function FFA.CheckEndConditions(roundInfo: RoundInfo): (boolean, number?)
    -- End when only one player remains
    if #roundInfo.PlayersAlive <= 1 then
        local winner = roundInfo.PlayersAlive[1]
        return true, winner
    end
    
    -- Or when time runs out
    if roundInfo.TimeRemaining <= 0 then
        -- Random winner from remaining players
        if #roundInfo.PlayersAlive > 0 then
            local winner = roundInfo.PlayersAlive[math.random(1, #roundInfo.PlayersAlive)]
            return true, winner
        end
        return true, nil
    end
    
    return false, nil
end

function FFA.Cleanup(roundInfo: RoundInfo)
    -- No special cleanup needed
end

function FFA.OnPlayerEliminated(roundInfo: RoundInfo, userId: number)
    -- Remove from alive list (handled by RoundService)
end

function FFA.GetSpawnPosition(roundInfo: RoundInfo, userId: number): CFrame
    -- Random spawn point
    return ARENA_SPAWNS[math.random(1, #ARENA_SPAWNS)]
end

return FFA