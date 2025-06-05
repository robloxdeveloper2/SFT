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
local Tags = require(Shared.Tags)

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

-- Team assignments for team modes
local playerTeams: { [number]: number } = {} -- UserId -> Team (1 or 2)

-- Mode rotation
local modeRotation: { GameMode } = {"FFA", "TDM", "KOTH", "CTF", "Payload", "Juggernaut"}
local currentModeIndex = 1

-- Special mode data
local tournamentBracket: { { number } } = {} -- For Tournament mode
local juggernautPlayer: number? = nil -- For Juggernaut mode

-- Cleanup management
local roundTrove = Trove.new()
local playerTroves: { [number]: any } = {}

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

-- Spawn Tags
local SPAWN_TAGS = {
	Lobby = "LobbyTeam",
	FFA = "FFATeamspawn", 
	Team1 = "Team1",
	Team2 = "Team2",
	Winner = "WinnerSpawn",
	KOTH = "KOTHSpawn", -- For KOTH hill area
	CTF_Flag1 = "CTFFlag1", -- Team 1 flag area
	CTF_Flag2 = "CTFFlag2", -- Team 2 flag area
	Payload = "PayloadSpawn", -- Payload cart area
	Tournament = "TournamentSpawn", -- 1v1 tournament area
}

-- Fallback spawns if no tagged spawns found
local FALLBACK_SPAWNS = {
	Lobby = CFrame.new(0, 10, 0),
	Arena = CFrame.new(0, 5, 0),
	Winner = CFrame.new(0, 15, 0)
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

-- MODE ROTATION FUNCTIONS

function RoundService._GetNextMode(): GameMode
	-- Skip Tournament mode for now (needs special implementation)
	repeat
		currentModeIndex = (currentModeIndex % #modeRotation) + 1
		local mode = modeRotation[currentModeIndex]

		-- Skip modes that don't have enough players
		local config = GameTypes.GameModes[mode]
		local lobbyPlayers = RoundService._GetLobbyPlayers()

		if #lobbyPlayers >= config.MinPlayers and mode ~= "Tournament" then
			return mode
		end
	until currentModeIndex == 1 -- Prevent infinite loop

	-- Fallback to FFA if no suitable mode found
	return "FFA"
end

function RoundService._IsTeamMode(mode: GameMode): boolean
	return mode == "TDM" or mode == "KOTH" or mode == "CTF" or mode == "Payload"
end

-- TELEPORTATION FUNCTIONS

function RoundService._GetSpawnsByTag(tag: string): { CFrame }
	local taggedSpawns = Tags.GetTagged(tag)
	local spawns = {}

	for _, spawn in taggedSpawns do
		if spawn:IsA("Part") or spawn:IsA("SpawnLocation") then
			table.insert(spawns, spawn.CFrame + Vector3.new(0, 3, 0))
		elseif spawn:IsA("Model") and spawn.PrimaryPart then
			table.insert(spawns, spawn.PrimaryPart.CFrame + Vector3.new(0, 3, 0))
		end
	end

	return spawns
end

function RoundService._GetRandomSpawn(tag: string): CFrame
	local spawns = RoundService._GetSpawnsByTag(tag)

	if #spawns > 0 then
		return spawns[math.random(1, #spawns)]
	end

	-- Fallback spawns
	warn(`No spawns found for tag: {tag}, using fallback`)
	if tag == SPAWN_TAGS.Lobby then
		return FALLBACK_SPAWNS.Lobby
	elseif tag == SPAWN_TAGS.Winner then
		return FALLBACK_SPAWNS.Winner
	else
		return FALLBACK_SPAWNS.Arena
	end
end

function RoundService._TeleportPlayer(player: Player, cframe: CFrame)
	local character = player.Character
	if not character then return false end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return false end

	humanoidRootPart.CFrame = cframe
	return true
end

function RoundService._TeleportPlayerToTag(player: Player, tag: string): boolean
	local spawn = RoundService._GetRandomSpawn(tag)
	return RoundService._TeleportPlayer(player, spawn)
end

function RoundService._TeleportToLobby(player: Player)
	RoundService._TeleportPlayerToTag(player, SPAWN_TAGS.Lobby)
end

function RoundService._TeleportToWinner(player: Player)
	RoundService._TeleportPlayerToTag(player, SPAWN_TAGS.Winner)
end

function RoundService._TeleportToGameModeSpawn(player: Player)
	local mode = currentRound.Mode

	if mode == "FFA" then
		RoundService._TeleportPlayerToTag(player, SPAWN_TAGS.FFA)
	elseif mode == "Tournament" then
		RoundService._TeleportPlayerToTag(player, SPAWN_TAGS.Tournament)
	elseif mode == "Juggernaut" then
		-- Juggernaut uses Team2 spawn, others use Team1 spawn
		if player.UserId == juggernautPlayer then
			RoundService._TeleportPlayerToTag(player, SPAWN_TAGS.Team2)
		else
			RoundService._TeleportPlayerToTag(player, SPAWN_TAGS.Team1)
		end
	elseif RoundService._IsTeamMode(mode) then
		local team = RoundService._GetPlayerTeam(player.UserId)
		if team then
			RoundService._TeleportToTeamSpawn(player, team)
		else
			warn(`Player {player.Name} has no team assignment, using FFA spawn`)
			RoundService._TeleportPlayerToTag(player, SPAWN_TAGS.FFA)
		end
	else
		-- Default to FFA spawn for unknown modes
		RoundService._TeleportPlayerToTag(player, SPAWN_TAGS.FFA)
	end
end

function RoundService._TeleportToTeamSpawn(player: Player, team: number)
	local tag = team == 1 and SPAWN_TAGS.Team1 or SPAWN_TAGS.Team2
	RoundService._TeleportPlayerToTag(player, tag)
end

-- TEAM MANAGEMENT

function RoundService._AssignPlayerToTeam(userId: number, team: number)
	playerTeams[userId] = team
end

function RoundService._GetPlayerTeam(userId: number): number?
	return playerTeams[userId]
end

function RoundService._AssignTeams(players: { Player })
	table.clear(playerTeams)

	-- Assign teams alternately for balance
	for i, player in players do
		local team = ((i - 1) % 2) + 1
		RoundService._AssignPlayerToTeam(player.UserId, team)
	end
end

function RoundService._AssignJuggernaut(players: { Player })
	if #players > 0 then
		juggernautPlayer = players[math.random(1, #players)].UserId
	end
end

-- PLAYER MANAGEMENT

function RoundService._OnPlayerAdded(player: Player)
	playerTroves[player.UserId] = Trove.new()

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
	if playerTroves[player.UserId] then
		playerTroves[player.UserId]:Destroy()
		playerTroves[player.UserId] = nil
	end

	playerStates[player.UserId] = nil
	playerTeams[player.UserId] = nil

	-- Clear juggernaut if they leave
	if juggernautPlayer == player.UserId then
		juggernautPlayer = nil
	end

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

	playerTrove:Clean()

	playerTrove:Add(function()
		for _, tool in character:GetChildren() do
			if tool:IsA("Tool") then
				tool:Destroy()
			end
		end
	end)
end

function RoundService._SpawnPlayerInLobby(player: Player)
	if not player.Character then
		player.CharacterAdded:Wait()
		task.wait(0.1)
	end

	RoundService._TeleportToLobby(player)
end

function RoundService._SpawnPlayerInArena(player: Player)
	if not player.Character then
		player.CharacterAdded:Wait()
		task.wait(0.1)
	end

	RoundService._TeleportToGameModeSpawn(player)
	RoundService._GivePlayerSword(player)

	-- Special equipment for Juggernaut mode
	if currentRound.Mode == "Juggernaut" and player.UserId == juggernautPlayer then
		RoundService._GiveJuggernautPowers(player)
	end
end

function RoundService._GivePlayerSword(player: Player)
	local character = player.Character
	if not character then return end

	for _, tool in character:GetChildren() do
		if tool:IsA("Tool") then
			tool:Destroy()
		end
	end

	local swordTemplate = Shared.Parent:WaitForChild("ClassicSword")
	local sword = swordTemplate:Clone()
	sword.Parent = character
end

function RoundService._GiveJuggernautPowers(player: Player)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- Count non-juggernaut players in the round
	local nonJuggernautCount = 0
	for _, userId in currentRound.PlayersAlive do
		if userId ~= juggernautPlayer then
			nonJuggernautCount += 1
		end
	end

	-- Calculate health based on opposition count
	-- Formula: 100 health per opponent, minimum 200
	local juggernautHealth = math.max(150, nonJuggernautCount * 50)

	-- Apply juggernaut stats
	humanoid.MaxHealth = juggernautHealth
	humanoid.Health = juggernautHealth
	humanoid.WalkSpeed = 17.5

	print(`Juggernaut {player.Name} has {juggernautHealth} health against {nonJuggernautCount} opponents`)
end


function RoundService._ClearPlayerTools(player: Player)
	local character = player.Character
	if not character then return end

	for _, tool in character:GetChildren() do
		if tool:IsA("Tool") then
			tool:Destroy()
		end
	end
end

function RoundService._ClearAllPlayerTools()
	for _, player in Players:GetPlayers() do
		RoundService._ClearPlayerTools(player)
	end
end

-- ROUND MANAGEMENT

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
	RoundService._CleanupRound()

	-- Get next mode in rotation
	local nextMode = RoundService._GetNextMode()

	currentRound.State = "Waiting"
	currentRound.Mode = nextMode
	currentRound.TimeRemaining = 0
	currentRound.PlayersAlive = {}
	currentRound.PlayersTotal = {}
	currentRound.Winner = nil

	-- Clear special mode data
	table.clear(playerTeams)
	table.clear(tournamentBracket)
	juggernautPlayer = nil

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
	roundTrove:Clean()
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
	local lobbyPlayers = RoundService._GetLobbyPlayers()

	-- If StartCountdown is 0, skip countdown and start immediately
	if config.StartCountdown == 0 then
		RoundService._SetupRoundPlayers(lobbyPlayers)
		RoundService._StartRound()
		return
	end

	currentRound.State = "Starting"
	currentRound.TimeRemaining = config.StartCountdown
	currentRound.MaxTime = config.StartCountdown

	RoundService._SetupRoundPlayers(lobbyPlayers)
	RoundService._BroadcastRoundUpdate()
end

function RoundService._SetupRoundPlayers(lobbyPlayers: { Player })
	-- Assign teams for team-based modes
	if RoundService._IsTeamMode(currentRound.Mode) then
		RoundService._AssignTeams(lobbyPlayers)
	elseif currentRound.Mode == "Juggernaut" then
		RoundService._AssignJuggernaut(lobbyPlayers)
	end

	-- Set up players for round
	for _, player in lobbyPlayers do
		table.insert(currentRound.PlayersTotal, player.UserId)
		table.insert(currentRound.PlayersAlive, player.UserId)
		playerStates[player.UserId] = "Fighting"
		RoundService._BroadcastPlayerState(player.UserId, "Fighting")
	end
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
	currentRound.TimeRemaining = 5

	-- Determine winner based on game mode
	RoundService._DetermineWinner(reason)

	-- Teleport winner to winner area
	if currentRound.Winner then
		local winner = Players:GetPlayerByUserId(currentRound.Winner)
		if winner then
			playerStates[currentRound.Winner] = "Spectating"
			RoundService._TeleportToWinner(winner)
			RoundService._BroadcastPlayerState(currentRound.Winner, "Spectating")
		end
	end

	RoundService._ClearAllPlayerTools()
	RoundService._BroadcastRoundUpdate()
end

function RoundService._DetermineWinner(reason: string)
	if currentRound.Mode == "FFA" or currentRound.Mode == "Tournament" or currentRound.Mode == "Juggernaut" then
		-- Last player standing wins
		if #currentRound.PlayersAlive == 1 then
			currentRound.Winner = currentRound.PlayersAlive[1]
		elseif #currentRound.PlayersAlive > 1 and reason == "Time" then
			currentRound.Winner = currentRound.PlayersAlive[math.random(1, #currentRound.PlayersAlive)]
		end
	else
		-- Team-based modes - TODO: Implement team scoring
		-- For now, just pick a random alive player
		if #currentRound.PlayersAlive > 0 then
			currentRound.Winner = currentRound.PlayersAlive[math.random(1, #currentRound.PlayersAlive)]
		end
	end
end

function RoundService._CheckEndConditions()
	if currentRound.State ~= "Active" then return end

	if currentRound.Mode == "FFA" or currentRound.Mode == "Tournament" then
		-- End when only one player remains
		if #currentRound.PlayersAlive <= 1 then
			RoundService._EndRound("Elimination")
		end
	elseif currentRound.Mode == "Juggernaut" then
		-- End when juggernaut dies or all others die
		local juggernautAlive = juggernautPlayer and table.find(currentRound.PlayersAlive, juggernautPlayer)
		if not juggernautAlive or #currentRound.PlayersAlive <= 1 then
			RoundService._EndRound("Elimination")
		end
	else
		-- Team-based modes - TODO: Implement proper win conditions
		-- For now, end when too few players remain
		if #currentRound.PlayersAlive <= 1 then
			RoundService._EndRound("Elimination")
		end
	end
end

function RoundService.EliminatePlayer(userId: number)
	local aliveIndex = table.find(currentRound.PlayersAlive, userId)
	if not aliveIndex then return end

	table.remove(currentRound.PlayersAlive, aliveIndex)
	playerStates[userId] = "Eliminated"

	local player = Players:GetPlayerByUserId(userId)
	if player then
		RoundService._ClearPlayerTools(player)
		RoundService._BroadcastPlayerState(userId, "Eliminated")
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

function RoundService.Cleanup()
	roundTrove:Destroy()

	for userId, trove in pairs(playerTroves) do
		trove:Destroy()
	end

	table.clear(playerTroves)
	table.clear(playerTeams)
end

return RoundService