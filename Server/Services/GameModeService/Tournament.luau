-- Server/Services/GameModeService/Tournament.luau
--!strict

local Players = game:GetService("Players")
local Shared = game.ReplicatedStorage.Shared
local GameTypes = require(Shared.GameTypes)
local Network = require(Shared.Network)

type RoundInfo = GameTypes.RoundInfo
type TournamentMatch = GameTypes.TournamentMatch
type TournamentBracket = GameTypes.TournamentBracket
type TournamentTeam = GameTypes.TournamentTeam

local Tournament = {}

-- Tournament arena spawn points (for the active match)
local ARENA_SPAWNS = {
    Team1 = CFrame.new(-15, 5, 0),
    Team2 = CFrame.new(15, 5, 0),
}

-- Spectator area
local SPECTATOR_SPAWN = CFrame.new(0, 20, -30) -- Elevated view of arena

local activePlayers = {} :: {[number]: "Team1" | "Team2" | "Spectator"}

-- Network events
local TOURNAMENT_UPDATE = Network.Event("TournamentUpdate", function(data: any)
    return data :: TournamentBracket
end)

local MATCH_START = Network.Event("MatchStart", function(data: any)
    return data :: TournamentMatch
end)

local MATCH_END = Network.Event("MatchEnd", function(data: any)
    return data :: { Match: TournamentMatch, Winner: TournamentTeam }
end)

local function createTeam(players: {number}, seed: number): TournamentTeam
    return {
        Players = players,
        Name = #players == 1 and Players:GetPlayerByUserId(players[1]).DisplayName or nil,
        Seed = seed,
    }
end

local function generateBracket(players: {number}): TournamentBracket
    -- Shuffle players for random seeding
    local shuffled = table.clone(players)
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    -- Create teams (solo for this mode)
    local teams: {TournamentTeam} = {}
    for i, playerId in ipairs(shuffled) do
        table.insert(teams, createTeam({playerId}, i))
    end
    
    -- Calculate bracket size (next power of 2)
    local bracketSize = 1
    while bracketSize < #teams do
        bracketSize = bracketSize * 2
    end
    
    -- Create first round with byes
    local firstRound: {TournamentMatch} = {}
    local matchNumber = 1
    
    -- Place teams in bracket positions
    for i = 1, bracketSize, 2 do
        local team1 = teams[i]
        local team2 = teams[i + 1]
        
        local match: TournamentMatch = {
            Team1 = team1,
            Team2 = team2,
            Winner = nil,
            MatchNumber = matchNumber,
            RoundNumber = 1,
            IsBye = team1 == nil or team2 == nil,
        }
        
        -- Auto-advance bye matches
        if match.IsBye then
            match.Winner = team1 or team2
        end
        
        table.insert(firstRound, match)
        matchNumber += 1
    end
    
    -- Create empty subsequent rounds
    local rounds = {firstRound}
    local currentRoundSize = #firstRound
    local roundNumber = 2
    
    while currentRoundSize > 1 do
        currentRoundSize = currentRoundSize / 2
        local round: {TournamentMatch} = {}
        
        for i = 1, currentRoundSize do
            table.insert(round, {
                Team1 = nil,
                Team2 = nil,
                Winner = nil,
                MatchNumber = matchNumber,
                RoundNumber = roundNumber,
                IsBye = false,
            })
            matchNumber += 1
        end
        
        table.insert(rounds, round)
        roundNumber += 1
    end
    
    return {
        Rounds = rounds,
        CurrentRound = 1,
        CurrentMatch = 1,
        Champion = nil,
        TeamSize = 1,
        AllTeams = teams,
    }
end

local function findNextMatch(bracket: TournamentBracket): TournamentMatch?
    -- Find first non-bye match in current round that hasn't been played
    local round = bracket.Rounds[bracket.CurrentRound]
    
    for i, match in ipairs(round) do
        if not match.IsBye and not match.Winner then
            return match
        end
    end
    
    -- Check if we need to advance to next round
    if bracket.CurrentRound < #bracket.Rounds then
        -- Advance winners to next round
        local nextRound = bracket.Rounds[bracket.CurrentRound + 1]
        local currentRound = bracket.Rounds[bracket.CurrentRound]
        
        for i = 1, #currentRound, 2 do
            local match1 = currentRound[i]
            local match2 = currentRound[i + 1]
            local nextMatch = nextRound[math.ceil(i / 2)]
            
            if match1.Winner then
                nextMatch.Team1 = match1.Winner
            end
            if match2 and match2.Winner then
                nextMatch.Team2 = match2.Winner
            end
        end
        
        bracket.CurrentRound += 1
        return findNextMatch(bracket)
    end
    
    return nil
end

function Tournament.Init(roundInfo: RoundInfo)
    -- Generate tournament bracket
    local bracket = generateBracket(roundInfo.PlayersTotal)
    roundInfo.TournamentBracket = bracket
    
    -- All players start as spectators
    activePlayers = {}
    for _, playerId in ipairs(roundInfo.PlayersTotal) do
        activePlayers[playerId] = "Spectator"
    end
    
    -- Broadcast bracket
    local server = TOURNAMENT_UPDATE:Server()
    server:FireAll(bracket)
end

function Tournament.Start(roundInfo: RoundInfo)
    local bracket = roundInfo.TournamentBracket
    if not bracket then return end
    
    -- Find and start first match
    local match = findNextMatch(bracket)
    if match then
        Tournament._StartMatch(roundInfo, match)
    end
end

function Tournament._StartMatch(roundInfo: RoundInfo, match: TournamentMatch)
    roundInfo.ActiveMatch = match
    
    -- Clear active players
    for playerId in pairs(activePlayers) do
        activePlayers[playerId] = "Spectator"
    end
    
    -- Set active players for this match
    if match.Team1 then
        for _, playerId in ipairs(match.Team1.Players) do
            activePlayers[playerId] = "Team1"
            table.insert(roundInfo.PlayersAlive, playerId)
        end
    end
    
    if match.Team2 then
        for _, playerId in ipairs(match.Team2.Players) do
            activePlayers[playerId] = "Team2"
            table.insert(roundInfo.PlayersAlive, playerId)
        end
    end
    
    -- Broadcast match start
    local server = MATCH_START:Server()
    server:FireAll(match)
    
    -- Teleport players to positions
    local RoundService = require(game.ServerStorage.Services.RoundService)
    for _, player in Players:GetPlayers() do
        if activePlayers[player.UserId] == "Spectator" then
            RoundService._SpawnPlayerAt(player, SPECTATOR_SPAWN)
        else
            -- Fighting players spawn at arena
            RoundService._SpawnPlayerInArena(player)
        end
    end
    
    -- Set match timer
    roundInfo.TimeRemaining = GameTypes.GameModes.Tournament.RoundTime
end

function Tournament.Update(roundInfo: RoundInfo, dt: number)
    -- Tournament timer handled by RoundService
end

function Tournament.CheckEndConditions(roundInfo: RoundInfo): (boolean, number?)
    local match = roundInfo.ActiveMatch
    if not match then
        -- No active match, tournament might be over
        local bracket = roundInfo.TournamentBracket
        if bracket and bracket.Champion then
            -- Tournament complete, return champion
            return true, bracket.Champion.Players[1]
        end
        return true, nil
    end
    
    -- Check if one team is eliminated
    local team1Alive = 0
    local team2Alive = 0
    
    if match.Team1 then
        for _, playerId in ipairs(match.Team1.Players) do
            if table.find(roundInfo.PlayersAlive, playerId) then
                team1Alive += 1
            end
        end
    end
    
    if match.Team2 then
        for _, playerId in ipairs(match.Team2.Players) do
            if table.find(roundInfo.PlayersAlive, playerId) then
                team2Alive += 1
            end
        end
    end
    
    -- Match over if one team is eliminated
    if team1Alive == 0 or team2Alive == 0 then
        local winner = team1Alive > 0 and match.Team1 or match.Team2
        match.Winner = winner
        
        -- Broadcast match end
        local server = MATCH_END:Server()
        server:FireAll({ Match = match, Winner = winner })
        
        -- Clear active match
        roundInfo.ActiveMatch = nil
        roundInfo.PlayersAlive = {}
        
        -- Find next match
        local bracket = roundInfo.TournamentBracket
        if bracket then
            local nextMatch = findNextMatch(bracket)
            if nextMatch then
                -- Start next match after delay
                task.wait(5)
                Tournament._StartMatch(roundInfo, nextMatch)
                return false, nil -- Tournament continues
            else
                -- Tournament complete
                bracket.Champion = winner
                return true, winner and winner.Players[1] or nil
            end
        end
    end
    
    -- Check timeout
    if roundInfo.TimeRemaining <= 0 then
        -- Sudden death or random winner
        local winner = team1Alive > team2Alive and match.Team1 or match.Team2
        match.Winner = winner
        
        -- Same as above
        local server = MATCH_END:Server()
        server:FireAll({ Match = match, Winner = winner })
        
        roundInfo.ActiveMatch = nil
        roundInfo.PlayersAlive = {}
        
        local bracket = roundInfo.TournamentBracket
        if bracket then
            local nextMatch = findNextMatch(bracket)
            if nextMatch then
                task.wait(5)
                Tournament._StartMatch(roundInfo, nextMatch)
                return false, nil
            else
                bracket.Champion = winner
                return true, winner and winner.Players[1] or nil
            end
        end
    end
    
    return false, nil
end

function Tournament.Cleanup(roundInfo: RoundInfo)
    activePlayers = {}
    roundInfo.TournamentBracket = nil
    roundInfo.ActiveMatch = nil
end

function Tournament.OnPlayerEliminated(roundInfo: RoundInfo, userId: number)
    -- In tournament, eliminated players become spectators for this match
    activePlayers[userId] = "Spectator"
    
    -- Teleport to spectator area
    local player = Players:GetPlayerByUserId(userId)
    if player then
        local RoundService = require(game.ServerStorage.Services.RoundService)
        RoundService._SpawnPlayerAt(player, SPECTATOR_SPAWN)
    end
end

function Tournament.GetSpawnPosition(roundInfo: RoundInfo, userId: number): CFrame
    local role = activePlayers[userId]
    
    if role == "Team1" then
        return ARENA_SPAWNS.Team1
    elseif role == "Team2" then
        return ARENA_SPAWNS.Team2
    else
        return SPECTATOR_SPAWN
    end
end

return Tournament