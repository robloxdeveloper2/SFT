-- Server/Services/MapService.luau
local MapService = {}

local Maps = {
    {
        Name = "Arena Classic",
        GameModes = {"FFA", "TDM", "Tournament"},
        SpawnPoints = {
            Lobby = CFrame.new(0, 10, 0),
            Arena = { --[[ multiple spawn points ]] },
            Spectator = { --[[ spectator positions ]] }
        },
        Objectives = {
            Hill = CFrame.new(0, 5, 0),
            -- etc...
        }
    },
    -- More maps...
}

function MapService.LoadMap(mapName: string)
    -- Load map from ServerStorage/Maps
    -- Set up spawn points, objectives, etc.
end

function MapService.VoteForMap(player: Player, mapName: string)
    -- Handle map voting logic
end