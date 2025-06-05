-- Server/Services/GameModeService.luau
--!strict

local GameModeService = {}

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local GameTypes = require(Shared.GameTypes)
local Network = require(Shared.Network)
local Trove = require(Shared.Trove)
local MapService = require(script.Parent.MapService)

type GameMode = GameTypes.GameMode
type RoundInfo = GameTypes.RoundInfo
type TeamInfo = GameTypes.TeamInfo

-- Mode handlers storage
local ModeHandlers = {} :: {
    [GameMode]: {
        Init: (roundInfo: RoundInfo) -> (),
        Start: (roundInfo: RoundInfo) -> (),
        Update: (roundInfo: RoundInfo, dt: number) -> (),
        CheckEndConditions: (roundInfo: RoundInfo) -> (boolean, number?), -- Returns (shouldEnd, winnerId?)
        Cleanup: (roundInfo: RoundInfo) -> (),
        OnPlayerEliminated: (roundInfo: RoundInfo, userId: number) -> (),
        GetSpawnPosition: (roundInfo: RoundInfo, userId: number) -> CFrame,
    }
}

-- Network events
local TEAM_UPDATE = Network.Event("TeamUpdate", function(data: any)
    return data :: { UserId: number, Team: string? }
end)

local OBJECTIVE_UPDATE = Network.Event("ObjectiveUpdate", function(data: any)
    return data :: { Type: string, Progress: number, OwningTeam: string? }
end)

local SCORE_UPDATE = Network.Event("ScoreUpdate", function(data: any)
    return data :: { [string]: number }
end)

-- Initialize all game modes
function GameModeService.Init()
    -- Load all game mode modules
    ModeHandlers.FFA = require(script.FFA)
    ModeHandlers.TDM = require(script.TDM)
    ModeHandlers.KOTH = require(script.KOTH)
    ModeHandlers.CTF = require(script.CTF)
    ModeHandlers.Payload = require(script.Payload)
    ModeHandlers.Juggernaut = require(script.Juggernaut)
    ModeHandlers.Tournament = require(script.Tournament)
end

function GameModeService.Start()
    -- Start update loop for active modes
    task.spawn(function()
        while true do
            local dt = task.wait(0.1)
            -- Update loop handled by individual modes through RoundService
        end
    end)
end

function GameModeService.InitializeMode(mode: GameMode, roundInfo: RoundInfo)
    local handler = ModeHandlers[mode]
    if handler then
        handler.Init(roundInfo)
    end
end

function GameModeService.StartMode(mode: GameMode, roundInfo: RoundInfo)
    local handler = ModeHandlers[mode]
    if handler then
        handler.Start(roundInfo)
    end
end

function GameModeService.UpdateMode(mode: GameMode, roundInfo: RoundInfo, dt: number)
    local handler = ModeHandlers[mode]
    if handler then
        handler.Update(roundInfo, dt)
    end
end

function GameModeService.CheckEndConditions(mode: GameMode, roundInfo: RoundInfo): (boolean, number?)
    local handler = ModeHandlers[mode]
    if handler then
        return handler.CheckEndConditions(roundInfo)
    end
    return false, nil
end

function GameModeService.CleanupMode(mode: GameMode, roundInfo: RoundInfo)
    local handler = ModeHandlers[mode]
    if handler then
        handler.Cleanup(roundInfo)
    end
end

function GameModeService.OnPlayerEliminated(mode: GameMode, roundInfo: RoundInfo, userId: number)
    local handler = ModeHandlers[mode]
    if handler then
        handler.OnPlayerEliminated(roundInfo, userId)
    end
end

function GameModeService.GetSpawnPosition(mode: GameMode, roundInfo: RoundInfo, userId: number): CFrame
    local handler = ModeHandlers[mode]
    if handler then
        return handler.GetSpawnPosition(roundInfo, userId)
    end
    
    -- Fallback to any available spawn
    return MapService.GetSpawnPoint("FFA") or CFrame.new(0, 5, 0)
end

-- Utility functions for mode handlers
function GameModeService.AssignTeams(players: {number}, numTeams: number): {[string]: {number}}
    local teams = {}
    local teamNames = {"Red", "Blue", "Green", "Yellow"}
    
    -- Initialize teams
    for i = 1, numTeams do
        teams[teamNames[i]] = {}
    end
    
    -- Shuffle and distribute players
    local shuffled = table.clone(players)
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    -- Assign to teams
    for i, userId in ipairs(shuffled) do
        local teamIndex = ((i - 1) % numTeams) + 1
        table.insert(teams[teamNames[teamIndex]], userId)
    end
    
    return teams
end

function GameModeService.BroadcastTeamUpdate(userId: number, team: string?)
    local server = TEAM_UPDATE:Server()
    server:FireAll({ UserId = userId, Team = team })
end

function GameModeService.BroadcastObjectiveUpdate(objectiveType: string, progress: number, owningTeam: string?)
    local server = OBJECTIVE_UPDATE:Server()
    server:FireAll({ Type = objectiveType, Progress = progress, OwningTeam = owningTeam })
end

function GameModeService.BroadcastScoreUpdate(scores: {[string]: number})
    local server = SCORE_UPDATE:Server()
    server:FireAll(scores)
end

return GameModeService