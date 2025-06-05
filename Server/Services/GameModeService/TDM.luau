-- Server/Services/GameModeService/TDM.luau
--!strict

local Players = game:GetService("Players")
local Shared = game.ReplicatedStorage.Shared
local GameTypes = require(Shared.GameTypes)

type RoundInfo = GameTypes.RoundInfo

local TDM = {}

-- Team spawn points
local TEAM_SPAWNS = {
    Red = {
        CFrame.new(-30, 5, 0),
        CFrame.new(-30, 5, -10),
        CFrame.new(-30, 5, 10),
    },
    Blue = {
        CFrame.new(30, 5, 0),
        CFrame.new(30, 5, -10),
        CFrame.new(30, 5, 10),
    }
}

local teamScores = {}
local playerTeams = {} :: {[number]: string}

function TDM.Init(roundInfo: RoundInfo)
    teamScores = { Red = 0, Blue = 0 }
    playerTeams = {}
    
    -- Assign teams
    local GameModeService = require(script.Parent.Parent)
    local teams = GameModeService.AssignTeams(roundInfo.PlayersTotal, 2)
    
    -- Store team assignments
    for teamName, members in pairs(teams) do
        for _, userId in ipairs(members) do
            playerTeams[userId] = teamName
            GameModeService.BroadcastTeamUpdate(userId, teamName)
        end
    end
    
    -- Store in round info
    roundInfo.Teams = teams
    roundInfo.Scores = teamScores
end

function TDM.Start(roundInfo: RoundInfo)
    -- Broadcast initial scores
    local GameModeService = require(script.Parent.Parent)
    GameModeService.BroadcastScoreUpdate(teamScores)
end

function TDM.Update(roundInfo: RoundInfo, dt: number)
    -- TDM updates handled by elimination events
end

function TDM.CheckEndConditions(roundInfo: RoundInfo): (boolean, number?)
    local config = GameTypes.GameModes.TDM
    local targetKills = 50 -- First team to 50 kills wins
    
    -- Check if any team reached target kills
    for team, score in pairs(teamScores) do
        if score >= targetKills then
            -- Find a player from winning team to declare as winner
            if roundInfo.Teams and roundInfo.Teams[team] then
                return true, roundInfo.Teams[team][1]
            end
            return true, nil
        end
    end
    
    -- Check if time ran out
    if roundInfo.TimeRemaining <= 0 then
        -- Find winning team
        local winningTeam = nil
        local highestScore = 0
        
        for team, score in pairs(teamScores) do
            if score > highestScore then
                highestScore = score
                winningTeam = team
            end
        end
        
        if winningTeam and roundInfo.Teams and roundInfo.Teams[winningTeam] then
            return true, roundInfo.Teams[winningTeam][1]
        end
        
        return true, nil
    end
    
    return false, nil
end

function TDM.Cleanup(roundInfo: RoundInfo)
    teamScores = {}
    playerTeams = {}
end

function TDM.OnPlayerEliminated(roundInfo: RoundInfo, userId: number)
    -- Award point to opposing team
    local eliminatedTeam = playerTeams[userId]
    if eliminatedTeam then
        local opposingTeam = eliminatedTeam == "Red" and "Blue" or "Red"
        teamScores[opposingTeam] = teamScores[opposingTeam] + 1
        
        local GameModeService = require(script.Parent.Parent)
        GameModeService.BroadcastScoreUpdate(teamScores)
    end
    
    -- Respawn player after delay
    task.wait(3)
    
    local player = Players:GetPlayerByUserId(userId)
    if player and player.Character then
        -- Respawn at team spawn
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:LoadCharacter()
        end
    end
end

function TDM.GetSpawnPosition(roundInfo: RoundInfo, userId: number): CFrame
    local team = playerTeams[userId]
    if team and TEAM_SPAWNS[team] then
        local spawns = TEAM_SPAWNS[team]
        return spawns[math.random(1, #spawns)]
    end
    
    -- Default spawn
    return CFrame.new(0, 5, 0)
end

return TDM