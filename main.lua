-- Created By: OneMoreZerg

local myMod = RegisterMod( "Chain Chomp", 1 )
local chainchomp_item = Isaac.GetItemIdByName( "Chain Chomp" )
local chainchomp_sound = Isaac.GetSoundIdByName("chainchomp")
local chase_sound = Isaac.GetSoundIdByName("chase")
EntityType.HEAD = Isaac.GetEntityTypeByName("ChainChomp")
EntityType.BASE = Isaac.GetEntityTypeByName("ChainChompBase")
EntityType.RING = Isaac.GetEntityTypeByName("ChainChompRing")

local attackVector;
local soundCountdown = 100;

-- Chain Chomp state enumerations
ChainChomp = {
	IDLE = 0,
	ATTACK = 4,
	WITHDRAW = 2,
	CHASE = 3
}

function myMod:use_chainchomp( )
	local player = Isaac.GetPlayer(0)
	local ents = Isaac.GetRoomEntities()
	local baseEntity
	local head
	local pos

	-- Check if there is a base present
	for i=1,#ents do
		if ents[i].Type == EntityType.BASE then
			baseEntity = ents[i]
		end
	end

	-- Only ever have 1 base at a time
	if baseEntity == nil then
		pos = Isaac.GetFreeNearPosition(player.Position,0)
		baseEntity = Isaac.Spawn(EntityType.BASE, 0, 0, pos, Vector(0,0), player)
		baseEntity:GetSprite():Play("Idle",true)

		pos = Isaac.GetFreeNearPosition(baseEntity.Position, 0)
		head = Isaac.Spawn(EntityType.HEAD, 0, 0, pos, Vector(0,0), player)
		head:GetSprite():Play("Idle",true)
	else
		pos = Isaac.GetFreeNearPosition(baseEntity.Position, 0)
		head = Isaac.Spawn(EntityType.HEAD, 0, 0, pos, Vector(0,0), player)
		head:GetSprite():Play("Idle",true)
	end
	
	-- Spawn the rings that make up the chain
	local midway = (head.Position + baseEntity.Position)/2
	local ring1 = Isaac.Spawn(EntityType.RING, 0, 0, (midway + head.Position)/2, Vector(0,0), player)
	local ring2 = Isaac.Spawn(EntityType.RING, 0, 0, midway, Vector(0,0), player)
	local ring3 = Isaac.Spawn(EntityType.RING, 0, 0, (midway + baseEntity.Position)/2, Vector(0,0), player)
	
	-- Make sure rings don't collide with anything
	ring1.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
	ring2.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
	ring3.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
	
	-- Useful for accessing them later
	head.Child = ring1
	ring1.Child = ring2
	ring2.Child = ring3
end

function myMod:chase(entity)
	local headPos = entity.Position
	local sprite = entity:GetSprite()
	local data = entity:GetData()

	local room = Game():GetRoom()
	local gridSize = room:GetGridSize()

	local minDistance = 999999
	local currTarget
	local targetDirection

	local base
	local ents = Isaac.GetRoomEntities()

	-- Check if there is a base still alive and get the nearest enemy
	for i=1,#ents do
		if ents[i].Type == EntityType.BASE then
			base = ents[i]
		end
		if ents[i]:IsVulnerableEnemy() and (ents[i].Position - headPos):Length() < minDistance and ents[i].Type ~= EntityType.HEAD and ents[i].Type ~= EntityType.BASE and ents[i].Type ~= EntityType.RING then
			currTarget = i
			minDistance = (ents[i].Position - headPos):Length()
		end
		-- Damage enemies if attacking or chasing
		if (ents[i].Position - headPos):Length() < 44 and ents[i]:IsVulnerableEnemy() and ents[i].Type ~= EntityType.HEAD and ents[i].Type ~= EntityType.BASE then
			if entity.State == ChainChomp.CHASE then
				ents[i]:TakeDamage(1.5,0,EntityRef(entity),0)
			elseif entity.State == ChainChomp.ATTACK then
				ents[i]:TakeDamage(5,0,EntityRef(entity),0)
			end
		end
	end
	
	if base ~= nil then
		-- Update the position of the rings
		midway = (entity.Position + base.Position)/2
		entity.Child.Position = (midway + entity.Position)/2
		entity.Child.Child.Position = midway
		entity.Child.Child.Child.Position = (midway + base.Position)/2
	else
		entity.State = ChainChomp.CHASE
	end

	-- Target the player if there are no enemies
	if currTarget == nil then
		entity.Target = entity:GetPlayerTarget()
	else
		entity.Target = ents[currTarget]
	end

	targetDirection = (entity.Target.Position - headPos):GetAngleDegrees()
	if data.GridCountdown == nil then data.GridCountdown = 0 end

	-- Transition to an attack
	if sprite:IsFinished("Idle") then
		entity.State = ChainChomp.ATTACK
		attackVector = entity.Target.Position - headPos
		local sfx = SFXManager()
		sfx:Play(chainchomp_sound,1,0,false,1)
		entity.CollisionDamage = 0.5
	end
	
	-- Chase state
	if entity.State == ChainChomp.CHASE then
		
		local sfx = SFXManager()
		if not sfx:IsPlaying(chase_sound) then
			local playSound = math.random(soundCountdown)
			
			if playSound == 1 then
				local sfx = SFXManager()
				sfx:Play(chase_sound,0.5,0,false,1)
				soundCountdown = 100
			else
				soundCountdown = soundCountdown - 1
			end
		end
		
		animationName = getAnimation("Chase", targetDirection)
		
		if not sprite:IsPlaying(animationName) then
			sprite:Play(animationName, true)
		end

		if entity.Target == nil then
			-- If there are no targets just sit still
			entity.Velocity = Vector(0,0)
		elseif entity:CollidesWithGrid() or data.GridCountdown > 0 then
			entity.Pathfinder:FindGridPath(entity.Target.Position, 4/6, 1, true)
			if data.GridCountdown <= 0 then
				data.GridCountdown = 30
			else
				data.GridCountdown = data.GridCountdown - 1
			end
		else
			entity.Velocity = (entity.Target.Position - headPos):Normalized() * 6
		end

	-- Attack state
	elseif entity.State == ChainChomp.ATTACK then
		-- Transition to the withdraw
		if sprite:IsFinished("AttackSouth") or sprite:IsFinished("AttackNorth") or sprite:IsFinished("AttackEast") or sprite:IsFinished("AttackWest") then
			entity.State = ChainChomp.WITHDRAW
		else
			-- Play animation
			animationName = getAnimation("Attack", attackVector:GetAngleDegrees())
			if not sprite:IsPlaying(animationName) then
				sprite:Play(animationName,true)
			end
		end
		-- Don't go too far from base
		if (base.Position - headPos):Length() < 100 then
			entity.Velocity = attackVector:Normalized() * 13
			
			-- Destroy rocks when in attack mode
			if entity:CollidesWithGrid() then
				for i=0,gridSize-1 do
					local grid_ent = room:GetGridEntity(i)
					if grid_ent ~= nil then
						if (headPos - grid_ent.Position):Length() < 50 then
							grid_ent:Destroy(true)
						end
					end
				end
			end
		else
			entity.Velocity = Vector(0,0)
		end

	-- Withdraw state
	elseif entity.State == ChainChomp.WITHDRAW then
		targetDirection = (headPos - base.Position):GetAngleDegrees()
		-- Transition to the attack
		if sprite:IsFinished("WithdrawSouth") or sprite:IsFinished("WithdrawNorth") or sprite:IsFinished("WithdrawEast") or sprite:IsFinished("WithdrawWest") then
			entity.State = ChainChomp.ATTACK
			attackVector = entity.Target.Position - headPos
			local sfx = SFXManager()
			sfx:Play(chainchomp_sound,1,0,false,1)
		else
			-- Play animation
			animationName = getAnimation("Withdraw", targetDirection)
			if not sprite:IsPlaying(animationName) then
				sprite:Play(animationName,true)
			end
		end
		entity.Velocity = (base.Position - headPos):Normalized() * 1
	end
end

-- Get rid of the appropriate rings when the head dies
function myMod:removeHeadRings(entity, dmgAmount, dmgFlag, source, dmgCountDownFrames)
	if(entity.HitPoints - dmgAmount <= 0) then
		entity.Child.Visible = false
		entity.Child.Child.Visible = false
		entity.Child.Child.Child.Visible = false
	end
end

-- Get rid of all rings when the base dies
function myMod:removeBaseRings(entity, dmgAmount, dmgFlag, source, dmgCountDownFrames)
	if(entity.HitPoints - dmgAmount <= 0) then
		local ents = Isaac.GetRoomEntities()
		for i=1, #ents do
			if ents[i].Type == EntityType.RING then
				ents[i].Visible = false
			end
		end
	end
end

-- Helper function to get the direction we should be facing
function getAnimation(animation_type, direction)
	local direction_name
	if direction > 45 and direction < 135 then
		direction_name = "South"
	elseif direction >= 135 or direction < -135 then
		direction_name = "West"
	elseif direction >= -135 and direction <= -45 then
		direction_name = "North"
	else
		direction_name = "East"
	end
	return animation_type .. direction_name
end

-- Callbacks
myMod:AddCallback( ModCallbacks.MC_NPC_UPDATE, myMod.chase, EntityType.HEAD)
myMod:AddCallback( ModCallbacks.MC_USE_ITEM, myMod.use_chainchomp, chainchomp_item)
myMod:AddCallback( ModCallbacks.MC_ENTITY_TAKE_DMG, myMod.removeHeadRings, EntityType.HEAD)
myMod:AddCallback( ModCallbacks.MC_ENTITY_TAKE_DMG, myMod.removeBaseRings, EntityType.BASE)
