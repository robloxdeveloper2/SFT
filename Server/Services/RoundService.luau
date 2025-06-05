-- Server/Services/RoundService.luau
--!strict

local RoundService = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local GameTypes = require(Shared.GameTypes)
local Network = require(Shared.Network)
local Signal = require(Shared.Signal)
local Trove = require(Shared.Trove)

type RoundInfo = GameTypes.RoundInfo
type GameMode = GameTypes.GameMode
type RoundState = GameTypes.RoundState
type PlayerState = GameTypes.PlayerState

-- Round state
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
local roundTimer: thread?

-- Cleanup management
local roundTrove = Trove.new() -- Cleans up when round ends
local playerTroves: { [number]: any } = {} -- Individual player cleanup

-- Network events
local ROUND_UPDATE = Network.Event("RoundUpdate", function(roundInfo: any): RoundInfo
	return roundInfo :: RoundInfo
end)

local PLAYER_STATE_UPDATE = Network.Event("PlayerStateUpdate", function(data: any)
	assert(type(data) == "table")
	return data :: { UserId: number, State: PlayerState }
end)

-- Signals
RoundService.RoundChanged = Signal.new()
RoundService.PlayerStateChanged = Signal.new()

-- Lobby and arena locations
local LOBBY_SPAWN = CFrame.new(0, 10, 0)
local ARENA_SPAWNS = {
	CFrame.new(-20, 5, 0),
	CFrame.new(20, 5, 0),
	CFrame.new(0, 5, -20),
	CFrame.new(0, 5, 20),
	CFrame.new(-15, 5, -15),
	CFrame.new(15, 5, -15),
	CFrame.new(-15, 5, 15),
	CFrame.new(15, 5, 15),
}

function RoundService.Init()
	-- Set up round timer
	task.spawn(function()
		while true do
			task.wait(1)
			RoundService._UpdateTimer()
		end
	end)
end

function RoundService.Start()
	-- Initialize all connected players
	for _, player in Players:GetPlayers() do
		RoundService._OnPlayerAdded(player)
	end

	Players.PlayerAdded:Connect(RoundService._OnPlayerAdded)
	Players.PlayerRemoving:Connect(RoundService._OnPlayerRemoving)

	-- Start the round cycle
	RoundService._StartWaiting()
end

function RoundService._OnPlayerAdded(player: Player)
	-- Create individual player trove for cleanup
	playerTroves[player.UserId] = Trove.new()

	-- Set up character cleanup
	local function setupCharacter(character)
		RoundService._SetupCharacterCleanup(player, character)
	end

	if player.Character then
		setupCharacter(player.Character)
	end

	playerTroves[player.UserId]:Connect(player.CharacterAdded, setupCharacter)

	playerStates[player.UserId] = "Lobby"
	RoundService._SpawnPlayerInLobby(player)
	RoundService._BroadcastPlayerState(player.UserId, "Lobby")
	RoundService._CheckStartConditions()
end

function RoundService._OnPlayerRemoving(player: Player)
	-- Clean up player-specific items
	if playerTroves[player.UserId] then
		playerTroves[player.UserId]:Destroy()
		playerTroves[player.UserId] = nil
	end

	playerStates[player.UserId] = nil

	-- Remove from round if they were participating
	local aliveIndex = table.find(currentRound.PlayersAlive, player.UserId)
	if aliveIndex then
		table.remove(currentRound.PlayersAlive, aliveIndex)
	end

	local totalIndex = table.find(currentRound.PlayersTotal, player.UserId)
	if totalIndex then
		table.remove(currentRound.PlayersTotal, totalIndex)
	end

	RoundService._CheckEndConditions()
	RoundService._BroadcastRoundUpdate()
end

function RoundService._SetupCharacterCleanup(player: Player, character: Model)
	local playerTrove = playerTroves[player.UserId]
	if not playerTrove then return end

	-- Clean up any existing character items for this player
	playerTrove:Clean()

	-- Track character for cleanup
	playerTrove:Add(function()
		-- Remove any tools when character is cleaned up
		for _, tool in character:GetChildren() do
			if tool:IsA("Tool") then
				tool:Destroy()
			end
		end
	end)
end

function RoundService._SpawnPlayerInLobby(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	humanoidRootPart.CFrame = LOBBY_SPAWN

	-- Give default sword
	RoundService._GivePlayerSword(player)
end

function RoundService._SpawnPlayerInArena(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

	-- Find available spawn
	local spawnIndex = math.random(1, #ARENA_SPAWNS)
	humanoidRootPart.CFrame = ARENA_SPAWNS[spawnIndex]

	-- Give sword
	RoundService._GivePlayerSword(player)
end

function RoundService._GivePlayerSword(player: Player)
	local character = player.Character
	if not character then return end

	-- Remove existing tools
	for _, tool in character:GetChildren() do
		if tool:IsA("Tool") then
			tool:Destroy()
		end
	end

	-- Give linked sword (clone it so the original stays in Shared)
	local swordTemplate = Shared.Parent:WaitForChild("ClassicSword")
	local sword = swordTemplate:Clone()

	sword.Parent = character
end

function RoundService._ClearPlayerTools(player: Player)
	local character = player.Character
	if not character then return end

	-- Remove existing tools
	for _, tool in character:GetChildren() do
		if tool:IsA("Tool") then
			tool:Destroy()
		end
	end
end

function RoundService._ClearAllPlayerTools()
	-- Remove tools from all players
	for _, player in Players:GetPlayers() do
		RoundService._ClearPlayerTools(player)
	end
end

function RoundService._UpdateTimer()
	if currentRound.TimeRemaining <= 0 then
		return
	end

	currentRound.TimeRemaining -= 1

	if currentRound.TimeRemaining <= 0 then
		if currentRound.State == "Starting" then
			RoundService._StartRound()
		elseif currentRound.State == "Active" then
			RoundService._EndRound("Time")
		elseif currentRound.State == "Ending" or currentRound.State == "Intermission" then
			RoundService._StartWaiting()
		end
	end

	RoundService._BroadcastRoundUpdate()
end

function RoundService._StartWaiting()
	-- Clean up everything from the previous round
	RoundService._CleanupRound()
	RoundService._ClearAllPlayerTools()

	currentRound.State = "Waiting"
	currentRound.Mode = "FFA" -- For now, always FFA
	currentRound.TimeRemaining = 0
	currentRound.PlayersAlive = {}
	currentRound.PlayersTotal = {}
	currentRound.Winner = nil

	-- Move all players to lobby
	for _, player in Players:GetPlayers() do
		playerStates[player.UserId] = "Lobby"
		RoundService._SpawnPlayerInLobby(player)
		RoundService._BroadcastPlayerState(player.UserId, "Lobby")
	end

	RoundService._CheckStartConditions()
	RoundService._BroadcastRoundUpdate()
end

function RoundService._CleanupRound()
	-- Clean up all round-specific items
	roundTrove:Clean()

	-- Clear all tools from all players
	RoundService._ClearAllPlayerTools()

	print("Round cleanup completed")
end

function RoundService._CheckStartConditions()
	if currentRound.State ~= "Waiting" then return end

	local config = GameTypes.GameModes[currentRound.Mode]
	local lobbyPlayers = RoundService._GetLobbyPlayers()

	if #lobbyPlayers >= config.MinPlayers then
		RoundService._StartCountdown()
	end
end

function RoundService._GetLobbyPlayers(): { Player }
	local lobbyPlayers = {}
	for _, player in Players:GetPlayers() do
		if playerStates[player.UserId] == "Lobby" then
			table.insert(lobbyPlayers, player)
		end
	end
	return lobbyPlayers
end

function RoundService._StartCountdown()
	local config = GameTypes.GameModes[currentRound.Mode]

	currentRound.State = "Starting"
	currentRound.TimeRemaining = config.StartCountdown
	currentRound.MaxTime = config.StartCountdown

	-- Set up players for round
	local lobbyPlayers = RoundService._GetLobbyPlayers()
	for _, player in lobbyPlayers do
		table.insert(currentRound.PlayersTotal, player.UserId)
		table.insert(currentRound.PlayersAlive, player.UserId)
		playerStates[player.UserId] = "Fighting"
		RoundService._BroadcastPlayerState(player.UserId, "Fighting")
	end

	RoundService._BroadcastRoundUpdate()
end

function RoundService._StartRound()
	local config = GameTypes.GameModes[currentRound.Mode]

	currentRound.State = "Active"
	currentRound.TimeRemaining = config.RoundTime
	currentRound.MaxTime = config.RoundTime

	-- Teleport players to arena
	for _, userId in currentRound.PlayersAlive do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			RoundService._SpawnPlayerInArena(player)
		end
	end

	RoundService._BroadcastRoundUpdate()
end

function RoundService._EndRound(reason: string)
	currentRound.State = "Ending"
	currentRound.TimeRemaining = 5 -- Show results for 5 seconds

	-- Determine winner
	if #currentRound.PlayersAlive == 1 then
		currentRound.Winner = currentRound.PlayersAlive[1]
	elseif #currentRound.PlayersAlive > 1 and reason == "Time" then
		-- Random winner if time ran out
		currentRound.Winner = currentRound.PlayersAlive[math.random(1, #currentRound.PlayersAlive)]
	end

	-- Start cleaning up round items (but don't move players yet)
	RoundService._ClearAllPlayerTools()

	RoundService._BroadcastRoundUpdate()
end

function RoundService._CheckEndConditions()
	if currentRound.State ~= "Active" then return end

	if #currentRound.PlayersAlive <= 1 then
		RoundService._EndRound("Elimination")
	end
end

function RoundService.EliminatePlayer(userId: number)
	local aliveIndex = table.find(currentRound.PlayersAlive, userId)
	if not aliveIndex then return end

	table.remove(currentRound.PlayersAlive, aliveIndex)
	playerStates[userId] = "Spectating"

	local player = Players:GetPlayerByUserId(userId)
	if player then
		-- Clear tools from eliminated player
		RoundService._ClearPlayerTools(player)
		RoundService._SpawnPlayerInLobby(player)
		RoundService._BroadcastPlayerState(userId, "Spectating")
	end

	RoundService._CheckEndConditions()
	RoundService._BroadcastRoundUpdate()
end

function RoundService._BroadcastRoundUpdate()
	local server = ROUND_UPDATE:Server()
	server:FireAll(currentRound)
end

function RoundService._BroadcastPlayerState(userId: number, state: PlayerState)
	local server = PLAYER_STATE_UPDATE:Server()
	server:FireAll({ UserId = userId, State = state })
end

function RoundService.GetCurrentRound(): RoundInfo
	return currentRound
end

function RoundService.GetPlayerState(userId: number): PlayerState?
	return playerStates[userId]
end

-- Cleanup function for when the service shuts down
function RoundService.Cleanup()
	roundTrove:Destroy()

	for userId, trove in pairs(playerTroves) do
		trove:Destroy()
	end

	table.clear(playerTroves)
end

return RoundService