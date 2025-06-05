-- Server/Services/TournamentService.luau
export type TournamentBracket = {
    Rounds: { { Match } },
    CurrentRound: number,
    Champion: number?,
}

export type Match = {
    Player1: number?,
    Player2: number?,
    Winner: number?,
    Arena: string, -- Which sub-arena for 1v1
}

function TournamentService.GenerateBracket(players: {Player}): TournamentBracket
    -- Create single-elimination bracket
    -- Handle byes for non-power-of-2 player counts
end

function TournamentService.StartMatch(match: Match)
    -- Teleport players to isolated 1v1 arena
    -- Track match results
end