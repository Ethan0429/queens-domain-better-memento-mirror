-- Decides when the proximity hint fires. Pure logic, no engine calls.
--
-- A ghost fires the hint once when it comes within range. It cannot fire again until the player
-- has moved past the release distance (a little farther than the trigger range, so hovering at
-- the edge does not flicker). After a hint, nothing fires until its sound and shimmer have
-- finished plus the backoff; a ghost that came into range during that time fires afterwards.
local Proximity={};Proximity.__index=Proximity

function Proximity.new(backoff)
    return setmetatable({backoff=backoff,latched={},readyAt=-math.huge},Proximity)
end

-- inRange: ids within the trigger radius; inRelease: ids within the release radius.
-- Returns the id that should fire, or nil.
function Proximity:update(now,inRange,inRelease)
    for id in pairs(self.latched) do
        if not inRelease[id] then self.latched[id]=nil end
    end
    if now<self.readyAt then return nil end
    local fresh
    for id in pairs(inRange) do
        if not self.latched[id] then fresh=id;break end
    end
    if fresh==nil then return nil end
    for id in pairs(inRange) do self.latched[id]=true end
    return fresh
end

-- Call when the hint starts; duration covers its sound and shimmer.
function Proximity:started(now,duration) self.readyAt=now+duration+self.backoff end

-- Forget everything, e.g. after a level change.
function Proximity:reset() self.latched={};self.readyAt=-math.huge end

return Proximity
