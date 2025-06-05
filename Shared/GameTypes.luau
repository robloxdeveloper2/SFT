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
    | "TeamTournament"
    | "CTF"
    | "Payload"
    | "Juggernaut"

export type RoundState = 
    | "Waiting"
    | "Starting"
    | "Active"
    | "Ending"
    | "Intermission"

export type TeamInfo = {
    Name: string,
    Color: Color3,
    Players: { number },
    Score: number,
    SpawnPoints: { CFrame },
}

export type ObjectiveInfo = {
    Type: "Hill" | "Flag" | "Payload",
    Position: CFrame,
    OwningTeam: string?,
    Progress: number,
    CaptureRadius: number,
}

-- Tournament specific types
export type TournamentTeam = {
    Players: { number }, -- 1 player for solo, 2+ for teams
    Name: string?, -- Optional team name
    Seed: number, -- Tournament seeding
}

export type TournamentMatch = {
    Team1: TournamentTeam?,
    Team2: TournamentTeam?,
    Winner: TournamentTeam?,
    MatchNumber: number,
    RoundNumber: number,
    IsBye: boolean, -- For handling odd numbers
}

export type TournamentBracket = {
    Rounds: { { TournamentMatch } },
    CurrentRound: number,
    CurrentMatch: number,
    Champion: TournamentTeam?,
    TeamSize: number, -- 1 for 1v1, 2 for 2v2, 3 for 3v3
    AllTeams: { TournamentTeam },
}

export type RoundInfo = {
    State: RoundState,
    Mode: GameMode,
    TimeRemaining: number,
    MaxTime: number,
    PlayersAlive: { number },
    PlayersTotal: { number },
    Winner: number?,
    Map: string?,
    Teams: { [string]: TeamInfo }?,
    Objectives: { [string]: ObjectiveInfo }?,
    Scores: { [string]: number }?, -- For TDM, CTF scoring
    TournamentBracket: TournamentBracket?,
    ActiveMatch: TournamentMatch?, -- Current tournament match
}

export type GameConfig = {
    Name: string,
    Description: string,
    MinPlayers: number,
    MaxPlayers: number,
    RoundTime: number,
    IntermissionTime: number,
    StartCountdown: number,
    TeamSize: number?, -- For team-based modes
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
        StartCountdown = 3,
    },

    TDM = {
        Name = "Team Deathmatch",
        Description = "Two teams clash for the most kills!",
        MinPlayers = 4,
        MaxPlayers = 36,
        RoundTime = 240,
        IntermissionTime = 10,
        StartCountdown = 3,
    },

    KOTH = {
        Name = "King of the Hill",
        Description = "Control the hill to earn points!",
        MinPlayers = 4,
        MaxPlayers = 36,
        RoundTime = 210,
        IntermissionTime = 10,
        StartCountdown = 3,
    },

    CTF = {
        Name = "Capture the Flag",
        Description = "Steal the enemy flag and return it to win!",
        MinPlayers = 4,
        MaxPlayers = 36,
        RoundTime = 300,
        IntermissionTime = 10,
        StartCountdown = 3,
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
        StartCountdown = 3,
    },

    Tournament = {
        Name = "Tournament",
        Description = "Bracket-style 1v1 elimination. Be the last standing!",
        MinPlayers = 2,
        MaxPlayers = 32,
        RoundTime = 90, -- Per match
        IntermissionTime = 10,
        StartCountdown = 5,
        TeamSize = 1,
    },

    TeamTournament = {
        Name = "Team Tournament",
        Description = "Bracket-style team elimination! 2v2 or 3v3 battles.",
        MinPlayers = 4, -- At least 2 teams of 2
        MaxPlayers = 36,
        RoundTime = 120, -- Per match
        IntermissionTime = 10,
        StartCountdown = 5,
        TeamSize = 2, -- Default to 2v2, can be changed
    },
}

GameTypes.GameModes = table.freeze(gameModes)

return table.freeze(GameTypes)