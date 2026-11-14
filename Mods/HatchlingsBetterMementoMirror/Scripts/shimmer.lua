-- Full-screen spectral border that fades in, shimmers, and fades out.
-- Textures in Assets/ come from tools/generate_assets.py.
local Shimmer={};Shimmer.__index=Shimmer
Shimmer.DURATION=3.6
local FRAMES=4                -- edge-shimmer-0..3; must match FRAMES in tools/generate_assets.py
local FADE_IN,FADE_OUT=.6,1.4
local GLOW,SHINE=.5,.7        -- peak opacity of the base glow and of the moving shimmer
local SPEED=.55               -- shimmer cycles per second
local HIT_TEST_INVISIBLE,COLLAPSED=3,1
local ZORDER=-10              -- below the game's HUD and menus

local function valid(o) return o~=nil and o:IsValid() end
local function smooth(a,b,t)
    local x=math.max(0,math.min(1,(t-a)/(b-a)))
    return x*x*(3-2*x)
end

function Shimmer.new(root) return setmetatable({root=root,textures={}},Shimmer) end

function Shimmer:texture(pc,name)
    local tex=self.textures[name]
    if not valid(tex) then
        tex=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(pc,self.root..'/Assets/'..name..'.png')
        assert(valid(tex),'Could not load '..name..'.png')
        self.textures[name]=tex
    end
    return tex
end

function Shimmer:build(pc)
    -- Any small user widget class works as a host; its tree is replaced with our canvas.
    local host=StaticFindObject('/Game/UI/Title/CreditLinkText.CreditLinkText_C')
    if not valid(host) then LoadAsset('/Game/UI/Title/CreditLinkText');host=StaticFindObject('/Game/UI/Title/CreditLinkText.CreditLinkText_C') end
    local widget=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,host,pc)
    assert(valid(widget),'Could not create the shimmer overlay')
    local tree=widget.WidgetTree
    local canvas=StaticConstructObject(StaticFindObject('/Script/UMG.CanvasPanel'),tree)
    tree.RootWidget=canvas
    self.layers={}
    local names={'edge-glow'}
    for k=0,FRAMES-1 do names[#names+1]='edge-shimmer-'..k end
    for i,name in ipairs(names) do
        local image=StaticConstructObject(StaticFindObject('/Script/UMG.Image'),tree)
        image:SetBrushFromTexture(self:texture(pc,name),false)
        image:SetRenderOpacity(0)
        local slot=canvas:AddChildToCanvas(image)
        slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}})
        slot:SetOffsets({Left=0,Top=0,Right=0,Bottom=0})
        self.layers[i]=image
    end
    pcall(function() widget.bIsFocusable=false end)
    widget:SetVisibility(COLLAPSED)
    widget:AddToViewport(ZORDER)
    self.widget,self.pc=widget,pc
end

function Shimmer:play(pc,now)
    if not valid(self.widget) or not (valid(self.pc) and self.pc:GetAddress()==pc:GetAddress()) then
        self:destroy();self:build(pc)
    end
    self.start=now
    self:update(now)
    self.widget:SetVisibility(HIT_TEST_INVISIBLE)
end

-- Advances the animation; returns true while it is playing.
function Shimmer:update(now)
    if not self.start then return false end
    local t=now-self.start
    if t>=Shimmer.DURATION or t<0 or not valid(self.widget) then self:stop();return false end
    local env=smooth(0,FADE_IN,t)*(1-smooth(Shimmer.DURATION-FADE_OUT,Shimmer.DURATION,t))
    local breathe=.88+.12*math.sin(t*2*math.pi*1.1)
    self.layers[1]:SetRenderOpacity(GLOW*env*breathe)
    -- Adjacent phases cross-fade, so the light bands appear to drift around the border.
    local phase=t*SPEED*2*math.pi
    for k=0,FRAMES-1 do
        local w=math.max(0,math.cos(phase-k*math.pi/2))
        self.layers[k+2]:SetRenderOpacity(SHINE*env*w*w)
    end
    return true
end

function Shimmer:stop()
    self.start=nil
    if valid(self.widget) then self.widget:SetVisibility(COLLAPSED) end
end

function Shimmer:destroy()
    self.start=nil
    if valid(self.widget) then pcall(function() self.widget:RemoveFromParent() end) end
    self.widget=nil
end

return Shimmer
