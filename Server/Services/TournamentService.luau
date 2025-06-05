-- Server/Services/CombatService.luau
--!strict

local CombatService = {}

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local RoundService = require(script.Parent.RoundService)

function CombatService.Init()
    -- Set up player death handling
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            CombatService._SetupCharacter(character)
        end)
    end)
    
    -- Handle existing players
    for _, player in Players:GetPlayers() do
        if player.Character then
            CombatService._SetupCharacter(player.Character)
        end
        player.CharacterAdded:Connect(function(character)
            CombatService._SetupCharacter(character)
        end)
    end
end

function CombatService._SetupCharacter(character: Model)
    local humanoid = character:WaitForChild("Humanoid")
    local player = Players:GetPlayerFromCharacter(character)
    
    if not player then return end
    
    humanoid.Died:Connect(function()
        local currentRound = RoundService.GetCurrentRound()
        local playerState = RoundService.GetPlayerState(player.UserId)
        
        -- Only eliminate if they're currently fighting
        if currentRound.State == "Active" and playerState == "Fighting" then
            RoundService.EliminatePlayer(player.UserId)
        end
    end)
end

function CombatService.Start()
    print("CombatService started")
end

return CombatService