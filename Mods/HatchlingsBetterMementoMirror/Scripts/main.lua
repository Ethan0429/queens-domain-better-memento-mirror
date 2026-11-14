local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local ROOT=assert(source:match('^(.*)/Scripts/main.lua$'),'Cannot locate mod folder')
local Proximity=dofile(ROOT..'/Scripts/proximity.lua')
local Shimmer=dofile(ROOT..'/Scripts/shimmer.lua')
local UE=require('UEHelpers')
local VERSION='0.1.0'
local TAG='[HatchlingsBetterMementoMirror] '
local DATA=(os.getenv('LOCALAPPDATA') or '.')..'/QueensDomain/Saved/BetterMementoMirror/'

-- Tuning. Distances are in Unreal units (centimeters).
local RADIUS=1500             -- about 49 ft: the mirror's own reveal range, so every hint is actionable
local RELEASE=RADIUS*1.25     -- walk this far from a ghost before it can hint again
local BACKOFF=5               -- seconds of quiet after the sound and shimmer finish
local VOLUME=.3               -- the real mirror plays at 1.0
local SCAN_TICKS=15           -- distance checks every ~0.25 s
local REFRESH_TICKS=120       -- re-list the level's ghosts every ~2 s

local GHOST_CLASS='NPC_Ghost_Base_C'
local MIRROR_ITEM='/Game/Items/Consumables/MementoMirror/MementoMirror.MementoMirror'
local MIRROR_SOUND='/Game/Items/Consumables/MementoMirror/GhostMirrorUse.GhostMirrorUse'
local SOUND_SECONDS=6.31      -- GhostMirrorUse length, used if the asset cannot be read

os.execute('mkdir "'..DATA:gsub('/','\\')..'" >NUL 2>NUL')

local function log(s) print(TAG..tostring(s)..'\n') end
local function valid(o) return o~=nil and o:IsValid() end
local warned={}
local function warnOnce(key,msg) if not warned[key] then warned[key]=true;log(msg) end end

local proximity=Proximity.new(BACKOFF)
local shimmer=Shimmer.new(ROOT)
local frame,world,ghosts,ghostsAt=0,nil,{},-math.huge
local lastError,lastStatus,lastHint=nil,'',nil

local function context()
    local pc=UE.GetPlayerController()
    if not valid(pc) then return nil end
    local pawn=pc.Pawn
    if not valid(pawn) or not pawn:GetClass():GetFName():ToString():find('PlayerChar',1,true) then return nil end
    local gi=FindFirstOf('FS_GameInstance_C')
    if not valid(gi) or not valid(gi.ActiveSaveSlot) then return nil end
    return {pc=pc,pawn=pawn,gi=gi,save=gi.ActiveSaveSlot,world=pawn:GetWorld():GetFName():ToString()}
end
local function realTime(c) return UE.GetGameplayStatics():GetRealTimeSeconds(c.pawn) end
local function busy(c)
    return UE.GetGameplayStatics():IsGamePaused(c.pawn) or c.gi.InCutscene or c.pawn.Health<=0
end

local function ownsMirror(c)
    local item=StaticFindObject(MIRROR_ITEM)
    if not valid(item) then return false end
    local ok,count=pcall(function() return c.save:GetInventoryCount(item) end)
    return ok and type(count)=='number' and count>0
end

-- The mirror reveals a ghost when its quest condition passes and its reward has not been
-- claimed (NPC_Ghost_Base.TryToReveal). These mirror those checks without revealing anything.
local scripting,saveUtils
local function conditionMet(c,ghost)
    if not valid(scripting) then scripting=StaticFindObject('/Script/QueensDomain.Default__FS_GameScriptingUtils') end
    if not valid(scripting) then return nil end
    local condition=ghost.QuestConditionName
    local ok,result=pcall(function() return scripting:EvaluateSingleCondition(condition,c.gi) end)
    if ok and type(result)=='boolean' then return result end
    ok,result=pcall(function()
        local items={}
        pcall(function() condition.ItemsToCheck:ForEach(function(_,item) items[#items+1]=item:get() end) end)
        return scripting:EvaluateSingleCondition({Type=condition.Type,DataToCheck=condition.DataToCheck,ItemsToCheck=items,
            Comparison=condition.Comparison,ValueToCompare=condition.ValueToCompare,Behaviour=condition.Behaviour},c.gi)
    end)
    if ok and type(result)=='boolean' then return result end
    warnOnce('condition','Could not check ghost quest conditions ('..tostring(result)..'); hinting without them')
    return nil
end
local function rewardClaimed(ghost)
    if not valid(saveUtils) then saveUtils=StaticFindObject('/Script/QueensDomain.Default__FS_SaveGameUtils') end
    if not valid(saveUtils) then return nil end
    local name=ghost.RewardCountNamedData
    for _,exists in ipairs({{},false}) do
        local ok,count=pcall(function() return saveUtils:GetNamedSaveData(ghost,name,exists) end)
        if ok and type(count)=='number' then return count>0 end
    end
    warnOnce('reward','Could not read ghost reward state; hinting without it')
    return nil
end
local function revealable(c,ghost)
    if ghost.Revealed then return false end
    local ok,value=pcall(function() return ghost.QuestStateHidden end)
    if ok and value==true then return false end
    ok,value=pcall(function() return ghost:HasMovedOn() end)
    if ok and value==true then return false end
    if conditionMet(c,ghost)==false then return false end
    if rewardClaimed(ghost)==true then return false end
    return true
end

local function playHint(c,now,ghost,distance)
    local sound=StaticFindObject(MIRROR_SOUND)
    if not valid(sound) then
        pcall(LoadAsset,'/Game/Items/Consumables/MementoMirror/GhostMirrorUse')
        sound=StaticFindObject(MIRROR_SOUND)
    end
    local seconds=SOUND_SECONDS
    if valid(sound) then
        local ok,err=pcall(function()
            UE.GetGameplayStatics():PlaySound2D(c.pawn,sound,VOLUME,1.0,0.0,CreateInvalidObject(),CreateInvalidObject(),false)
        end)
        if not ok then warnOnce('sound','Could not play the mirror sound: '..tostring(err)) end
        local okDuration,duration=pcall(function() return sound.Duration end)
        if okDuration and type(duration)=='number' and duration>0 then seconds=duration end
    else
        warnOnce('sound','Could not load the mirror sound')
    end
    local ok,err=pcall(function() shimmer:play(c.pc,now) end)
    if not ok then warnOnce('shimmer','Could not show the shimmer: '..tostring(err)) end
    proximity:started(now,math.max(seconds,Shimmer.DURATION))
    lastHint=string.format('%s at %.0f units (%.0f ft)',ghost:GetClass():GetFName():ToString(),distance,distance/30.48)
    log('Hint: '..lastHint)
end

local nearest
local function scan(c,now)
    nearest=nil
    if not ownsMirror(c) then proximity:reset();return end
    local inRange,inRelease,first={},{},{}
    for _,ghost in ipairs(ghosts) do
        if valid(ghost) then
            local distance=c.pawn:GetDistanceTo(ghost)
            if distance<=RELEASE and revealable(c,ghost) then
                local id=ghost:GetAddress()
                inRelease[id]=true
                if distance<=RADIUS then inRange[id]=true;first[id]={ghost,distance} end
                if not nearest or distance<nearest then nearest=distance end
            end
        end
    end
    local id=proximity:update(now,inRange,inRelease)
    if id then playHint(c,now,first[id][1],first[id][2]) end
end

local function status(c)
    local line=string.format('owns_mirror=%s\nworld=%s\nghosts=%d\nnearest_revealable=%s\nlast_hint=%s\nerror=%s\n',
        tostring(c and ownsMirror(c) or false),world or '',#ghosts,
        nearest and string.format('%.0f',nearest) or '',lastHint or '',lastError or '')
    if line~=lastStatus then
        local f=io.open(DATA..'status.txt','wb');if f then f:write(line);f:close() end
        lastStatus=line
    end
end

local function tick()
    frame=frame+1
    local c=context()
    if not c then shimmer:stop();return end
    local now=realTime(c)
    shimmer:update(now)
    if c.world~=world then
        world=c.world;proximity:reset();shimmer:stop();ghosts={};ghostsAt=-math.huge
    end
    if frame-ghostsAt>=REFRESH_TICKS then
        local before=#ghosts
        ghosts=FindAllOf(GHOST_CLASS) or {};ghostsAt=frame
        if #ghosts~=before then log('Ghosts in '..world..': '..#ghosts) end
    end
    if frame%SCAN_TICKS==0 and not busy(c) then scan(c,now) end
    if frame%60==0 then status(c) end
end

local function protectedTick()
    local ok,err=pcall(tick)
    if not ok then
        pcall(function() shimmer:stop() end)
        if tostring(err)~=lastError then lastError=tostring(err);log('ERROR '..lastError) end
    end
end
ModRef.OnUnload=function() pcall(function() shimmer:destroy() end) end
local queued=false
LoopAsync(16,function()
    if not queued then queued=true;ExecuteInGameThread(function() protectedTick();queued=false end) end
    return false
end)
log('Loaded v'..VERSION..'.')
