-- Server/Services/GameModeService/TeamTournament.luau
--!strict

-- This extends Tournament.luau for team-based tournaments
local Tournament = require(script.Parent.Tournament)
local TeamTournament = table.clone(Tournament)

local Players = game:GetService("Players")
local Shared = game.ReplicatedStorage.Shared
local GameTypes = require(Shared.GameTypes)

type RoundInfo = GameTypes.RoundInfo
type TournamentTeam = GameTypes.TournamentTeam

-- Team spawn configurations for 2v2 and 3v3
local TEAM_SPAWNS = {
    [2] = { -- 2v2 spawns
        Team1 = {
            CFrame.new(-15, 5, -5),
            CFrame.new(-15, 5, 5),
        },
        Team2 = {
            CFrame.new(15, 5, -5),
            CFrame.new(15, 5, 5),
        },
    },
    [3] = { -- 3v3 spawns
        Team1 = {
            CFrame.new(-20, 5, -8),
            CFrame.new(-20, 5, 0),
            CFrame.new(-20, 5, 8),
        },
        Team2 = {
            CFrame.new(20, 5, -8),
            CFrame.new(20, 5, 0),
            CFrame.new(20, 5, 8),
        },
    },
}

local function createTeamsFromPlayers(players: {number}, teamSize: number): {TournamentTeam}
    -- Shuffle players
    local shuffled = table.clone(players)
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    -- Create teams
    local teams: {TournamentTeam} = {}
    local currentTeam: {number} = {}
    
    for i, playerId in ipairs(shuffled) do
        table.insert(currentTeam, playerId)
        
        if #currentTeam == teamSize then
            table.insert(teams, {
                Players = currentTeam,
                Name = `Team {#teams + 1}`,
                Seed = #teams + 1,
            })
            currentTeam = {}
        end
    end
    
    -- Handle leftover players (incomplete team)
    if #currentTeam > 0 then
        -- Either fill with spectators or discard
        warn("Incomplete team in tournament, not enough players for even teams")
    end
    
    return teams
end

function TeamTournament.Init(roundInfo: RoundInfo)
    -- Determine team size (2v2 or 3v3)
    local config = GameTypes.GameModes.TeamTournament
    local teamSize = config.TeamSize or 2
    
    -- Ensure we have enough players
    local numPlayers = #roundInfo.PlayersTotal
    if numPlayers < teamSize * 2 then
        warn("Not enough players for team tournament")
        return
    end
    
    -- Create teams
    local teams = createTeamsFromPlayers(roundInfo.PlayersTotal, teamSize)
    
    -- Generate bracket with teams
    local bracket = Tournament.generateBracket(teams)
    bracket.TeamSize = teamSize
    roundInfo.TournamentBracket = bracket
    
    -- Set all as spectators initially
    Tournament.activePlayers = {}
    for _, playerId in ipairs(roundInfo.PlayersTotal) do
        Tournament.activePlayers[playerId] = "Spectator"
    end
    
    -- Broadcast bracket
    local server = Tournament.TOURNAMENT_UPDATE:Server()
    server:FireAll(bracket)
end

function TeamTournament.GetSpawnPosition(roundInfo: RoundInfo, userId: number): CFrame
    local role = Tournament.activePlayers[userId]
    
    if role == "Spectator" then
        return Tournament.SPECTATOR_SPAWN
    end
    
    -- Find which position in team
    local bracket = roundInfo.TournamentBracket
    local match = roundInfo.ActiveMatch
    
    if not (bracket and match) then
        return Tournament.SPECTATOR_SPAWN
    end
    
    local teamSize = bracket.TeamSize
    local spawns = TEAM_SPAWNS[teamSize]
    
    if not spawns then
        -- Fallback to default tournament spawns
        return Tournament.GetSpawnPosition(roundInfo, userId)
    end
    
    -- Find player's position in their team
    local team = role == "Team1" and match.Team1 or match.Team2
    if team then
        local position = table.find(team.Players, userId)
        if position and spawns[role][position] then
            return spawns[role][position]
        end
    end
    
    -- Fallback
    return role == "Team1" and spawns.Team1[1] or spawns.Team2[1]
end

return TeamTournament