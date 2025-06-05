-- Client/Controllers/RoundController.luau
--!strict

local RoundController = {}

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local Shared = game.ReplicatedStorage.Shared
local GameTypes = require(Shared.GameTypes)
local Network = require(Shared.Network)

type RoundInfo = GameTypes.RoundInfo
type PlayerState = GameTypes.PlayerState

local currentRound: RoundInfo = {
    State = "Waiting",
    Mode = "FFA",
    TimeRemaining = 0,
    MaxTime = 0,
    PlayersAlive = {},
    PlayersTotal = {},
    Winner = nil,
    Map = nil,
}

local playerStates: { [number]: PlayerState } = {}
local player = Players.LocalPlayer

-- Network events
local ROUND_UPDATE = Network.Event("RoundUpdate", function(roundInfo: any): RoundInfo
    return roundInfo :: RoundInfo
end)

local PLAYER_STATE_UPDATE = Network.Event("PlayerStateUpdate", function(data: any)
    return data :: { UserId: number, State: PlayerState }
end)

function RoundController.Init()
    local roundClient = ROUND_UPDATE:Client()
    local stateClient = PLAYER_STATE_UPDATE:Client()
    
    roundClient:On(function(roundInfo: RoundInfo)
        currentRound = roundInfo
        RoundController._UpdateUI()
    end)
    
    stateClient:On(function(data: { UserId: number, State: PlayerState })
        playerStates[data.UserId] = data.State
        RoundController._UpdateUI()
    end)
end

function RoundController.Start()
    RoundController._CreateUI()
end

function RoundController._CreateUI()
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Create main round UI
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RoundUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    screenGui.IgnoreGuiInset = true
    
    -- Round status frame
    local statusFrame = Instance.new("Frame")
    statusFrame.Name = "StatusFrame"
    statusFrame.Size = UDim2.new(0.3, 0, 0.15, 0)
    statusFrame.Position = UDim2.new(0.35, 0, 0.02, 0)
    statusFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    statusFrame.BorderSizePixel = 0
    statusFrame.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = statusFrame
    
    -- Round state label
    local stateLabel = Instance.new("TextLabel")
    stateLabel.Name = "StateLabel"
    stateLabel.Size = UDim2.new(1, 0, 0.4, 0)
    stateLabel.Position = UDim2.new(0, 0, 0, 0)
    stateLabel.BackgroundTransparency = 1
    stateLabel.Text = "Waiting for players..."
    stateLabel.TextColor3 = Color3.new(1, 1, 1)
    stateLabel.TextScaled = true
    stateLabel.Font = Enum.Font.SourceSansBold
    stateLabel.Parent = statusFrame
    
    -- Timer label
    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "TimerLabel"
    timerLabel.Size = UDim2.new(1, 0, 0.3, 0)
    timerLabel.Position = UDim2.new(0, 0, 0.4, 0)
    timerLabel.BackgroundTransparency = 1
    timerLabel.Text = ""
    timerLabel.TextColor3 = Color3.new(0.8, 0.8, 1)
    timerLabel.TextScaled = true
    timerLabel.Font = Enum.Font.SourceSans
    timerLabel.Parent = statusFrame
    
    -- Players alive label
    local playersLabel = Instance.new("TextLabel")
    playersLabel.Name = "PlayersLabel"
    playersLabel.Size = UDim2.new(1, 0, 0.3, 0)
    playersLabel.Position = UDim2.new(0, 0, 0.7, 0)
    playersLabel.BackgroundTransparency = 1
    playersLabel.Text = ""
    playersLabel.TextColor3 = Color3.new(1, 0.8, 0.8)
    playersLabel.TextScaled = true
    playersLabel.Font = Enum.Font.SourceSans
    playersLabel.Parent = statusFrame
end

function RoundController._UpdateUI()
    local playerGui = player:WaitForChild("PlayerGui")
    local roundUI = playerGui:FindFirstChild("RoundUI")
    if not roundUI then return end
    
    local statusFrame = roundUI:FindFirstChild("StatusFrame")
    if not statusFrame then return end
    
    local stateLabel = statusFrame:FindFirstChild("StateLabel")
    local timerLabel = statusFrame:FindFirstChild("TimerLabel")
    local playersLabel = statusFrame:FindFirstChild("PlayersLabel")
    
    if stateLabel then
        if currentRound.State == "Waiting" then
            stateLabel.Text = "Waiting for players..."
        elseif currentRound.State == "Starting" then
            stateLabel.Text = "Round starting..."
        elseif currentRound.State == "Active" then
            stateLabel.Text = `{GameTypes.GameModes[currentRound.Mode].Name} - FIGHT!`
        elseif currentRound.State == "Ending" then
            if currentRound.Winner then
                local winner = Players:GetPlayerByUserId(currentRound.Winner)
                stateLabel.Text = winner and `{winner.DisplayName} wins!` or "Round ended!"
            else
                stateLabel.Text = "Round ended!"
            end
        end
    end
    
    if timerLabel then
        if currentRound.TimeRemaining > 0 then
            local minutes = math.floor(currentRound.TimeRemaining / 60)
            local seconds = currentRound.TimeRemaining % 60
            timerLabel.Text = string.format("%d:%02d", minutes, seconds)
        else
            timerLabel.Text = ""
        end
    end
    
    if playersLabel then
        if currentRound.State == "Active" or currentRound.State == "Starting" then
            playersLabel.Text = `Players alive: {#currentRound.PlayersAlive}`
        else
            playersLabel.Text = ""
        end
    end
end

function RoundController.GetCurrentRound(): RoundInfo
    return currentRound
end

function RoundController.GetPlayerState(userId: number?): PlayerState?
    return playerStates[userId or player.UserId]
end

return RoundController