-- Shared/GameTypes.luau
--!strict

local GameTypes = {}

export type PlayerState = 
    | "Lobby"
    | "Fighting"
    | "Spectating"
    | "Eliminated"

export type GameMode = 
    | "FFA"
    | "TDM"
    | "KOTH"
    | "Tournament"
    | "CTF"
    | "Payload"
    | "Juggernaut"

export type RoundState = 
    | "Waiting"
    | "Starting"
    | "Active"
    | "Ending"
    | "Intermission"

export type RoundInfo = {
    State: RoundState,
    Mode: GameMode,
    TimeRemaining: number,
    MaxTime: number,
    PlayersAlive: { number },
    PlayersTotal: { number },
    Winner: number?,
    Map: string?,
}

export type GameConfig = {
    Name: string,
    Description: string,
    MinPlayers: number,
    MaxPlayers: number,
    RoundTime: number,
    IntermissionTime: number,
    StartCountdown: number,
}

-- Type the GameModes as a record that maps GameMode to GameConfig
export type GameModes = {
    [GameMode]: GameConfig
}

local gameModes: GameModes = {
    FFA = {
        Name = "Free For All",
        Description = "Last player standing wins!",
        MinPlayers = 2,
        MaxPlayers = 36,
        RoundTime = 180,
        IntermissionTime = 10,
        StartCountdown = 0,
    },

    TDM = {
        Name = "Team Deathmatch",
        Description = "Two teams clash for the most kills!",
        MinPlayers = 4,
        MaxPlayers = 36,
        RoundTime = 240,
        IntermissionTime = 10,
        StartCountdown = 0,
    },

    KOTH = {
        Name = "King of the Hill",
        Description = "Control the hill to earn points!",
        MinPlayers = 4,
        MaxPlayers = 36,
        RoundTime = 210,
        IntermissionTime = 10,
        StartCountdown = 0,
    },

    CTF = {
        Name = "Capture the Flag",
        Description = "Steal the enemy flag and return it to win!",
        MinPlayers = 4,
        MaxPlayers = 36,
        RoundTime = 300,
        IntermissionTime = 10,
        StartCountdown = 0,
    },

    Payload = {
        Name = "Payload",
        Description = "Escort the cart or stop the attackers!",
        MinPlayers = 4,
        MaxPlayers = 16,
        RoundTime = 300,
        IntermissionTime = 10,
        StartCountdown = 5,
    },

    Juggernaut = {
        Name = "Juggernaut",
        Description = "One super-powered player fights off the rest!",
        MinPlayers = 11,
        MaxPlayers = 36,
        RoundTime = 180,
        IntermissionTime = 10,
        StartCountdown = 0,
    },

    Tournament = {
        Name = "Tournament",
        Description = "Bracket-style 1v1 elimination. Be the last standing!",
        MinPlayers = 6,
        MaxPlayers = 36,
        RoundTime = 60, -- Per match
        IntermissionTime = 10,
        StartCountdown = 3,
    },
}

GameTypes.GameModes = table.freeze(gameModes)

return table.freeze(GameTypes)