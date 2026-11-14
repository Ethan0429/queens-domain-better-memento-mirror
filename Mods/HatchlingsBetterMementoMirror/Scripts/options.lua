-- Adds an On/Off row to the game's own Options > Game list, built from the game's row widgets.
--
-- The game's toggle normally reads and writes a property on its system save by name. With
-- SkipSavingOption set it does neither and only flips CurrentValue (and animates) when clicked,
-- so the mod owns the value: it sets CurrentValue when the row appears and watches it for
-- changes. DisableRevert keeps the list's "Revert to default" button from switching it off.
local Options={};Options.__index=Options
local LIST_CLASS='Game_OptionsList_C'
local ENTRY_CLASS='/Game/UI/Menus/OptionsMenu/OptionsMenu_Entry.OptionsMenu_Entry_C'
local TOGGLE_CLASS='/Game/UI/Menus/OptionsMenu/OptionsMenu_ToggleControl.OptionsMenu_ToggleControl_C'
local PROPERTY='BetterMementoMirrorHints' -- marks our row; deliberately not a real save property

local function valid(o) return o~=nil and o:IsValid() end
local function className(o) return o:GetClass():GetFName():ToString() end
local function isOurs(widget)
    local ok,name=pcall(function() return widget.Property:ToString() end)
    return ok and name==PROPERTY
end

function Options.new(label,log)
    return setmetatable({label=label,log=log,rows={}},Options)
end

local function findRow(scroll)
    for i=0,scroll:GetChildrenCount()-1 do
        local child=scroll:GetChildAt(i)
        if valid(child) and isOurs(child) then return child end
    end
end

function Options:inject(list,pc)
    local scroll=list.OptionsList
    if not valid(scroll) or scroll:GetChildrenCount()==0 then return end
    local entry=findRow(scroll)
    if entry then
        -- Left over from a previous load of this script: adopt it.
        local toggle=entry.MyControl
        if valid(toggle) then self.rows[list:GetAddress()]={list=list,entry=entry,toggle=toggle} end
        return
    end
    local entryClass,toggleClass=StaticFindObject(ENTRY_CLASS),StaticFindObject(TOGGLE_CLASS)
    if not valid(entryClass) or not valid(toggleClass) then return end
    local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local owner=valid(pc) and pc or CreateInvalidObject()
    entry=lib:Create(list,entryClass,owner)
    local toggle=lib:Create(list,toggleClass,owner)
    assert(valid(entry) and valid(toggle),'Could not create the options row')
    toggle.SkipSavingOption=true
    entry.Name=FText(self.label)
    entry.Property=FName(PROPERTY)
    entry.TextSizeCap=400
    entry.DisableRevert=true
    entry:SetContentForSlot(FName('ControlWidget'),toggle)
    -- The list ends with its "Revert to default" button; keep that last.
    local last=scroll:GetChildAt(scroll:GetChildrenCount()-1)
    if valid(last) and className(last)=='SizeBox' then
        scroll:RemoveChild(last);scroll:AddChild(entry);scroll:AddChild(last)
    else
        scroll:AddChild(entry)
    end
    -- The list initializes its rows when it is constructed; if that already happened, do it here.
    pcall(function() entry:Init(list) end)
    self.rows[list:GetAddress()]={list=list,entry=entry,toggle=toggle}
    if not self.announced then self.announced=true;self.log('Added "'..self.label..'" to Options > Game') end
end

-- Looks for option lists that do not have the row yet.
function Options:scan(pc)
    for _,list in ipairs(FindAllOf(LIST_CLASS) or {}) do
        if valid(list) and not self.rows[list:GetAddress()] then self:inject(list,pc) end
    end
end

-- Keeps rows in step with `enabled`. Returns the new value if the player flipped a row.
function Options:update(enabled)
    local changed
    for address,row in pairs(self.rows) do
        if not (valid(row.list) and valid(row.entry) and valid(row.toggle)) then
            self.rows[address]=nil
        elseif not row.synced then
            -- The entry wires up its control when it is constructed; show our value after that.
            if valid(row.entry.MyControl) then self:show(row,enabled);row.synced=true end
        elseif row.toggle.CurrentValue~=enabled and changed==nil then
            changed=row.toggle.CurrentValue
        end
    end
    return changed
end

function Options:show(row,value)
    row.toggle.CurrentValue=value
    pcall(function() row.toggle:PlayRelevantToggleAnim() end)
end

-- Applies a value to every row (after one of them was flipped).
function Options:sync(enabled)
    for _,row in pairs(self.rows) do
        if row.synced and valid(row.toggle) and row.toggle.CurrentValue~=enabled then self:show(row,enabled) end
    end
end

return Options
