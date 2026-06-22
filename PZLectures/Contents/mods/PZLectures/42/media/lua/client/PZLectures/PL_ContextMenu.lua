require "PZLectures/PL_Config"
require "PZLectures/PL_Topics"

print("[PZLectures] Client context-menu module loaded")

local function findClickedPlayer(localPlayer, worldObjects, playerNum, context)
    worldObjects = worldObjects or {}

    for _, object in ipairs(worldObjects) do
        if instanceof(object, "IsoPlayer") and object ~= localPlayer then
            return object
        end
    end

    -- Reuse the player already detected by the vanilla context-menu builder.
    -- B42 stores fetched targets here before firing OnFillWorldObjectContextMenu.
    local fetchVars = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars or nil
    if fetchVars then
        if fetchVars.otherPlayer and instanceof(fetchVars.otherPlayer, "IsoPlayer") and
           fetchVars.otherPlayer ~= localPlayer then
            return fetchVars.otherPlayer
        end
        for _, value in pairs(fetchVars) do
            if type(value) == "userdata" and instanceof(value, "IsoPlayer") and value ~= localPlayer then
                return value
            end
        end
    end

    -- B42 may give mods only the static object from the clicked square even
    -- though the vanilla menu has already detected the moving player there.
    -- Mirror vanilla's fallback and inspect moving objects on those squares.
    for _, object in ipairs(worldObjects) do
        local square = object and object:getSquare() or nil
        local movingObjects = square and square:getMovingObjects() or nil
        if movingObjects then
            for index = 0, movingObjects:size() - 1 do
                local movingObject = movingObjects:get(index)
                if instanceof(movingObject, "IsoPlayer") and movingObject ~= localPlayer then
                    return movingObject
                end
            end
        end
    end

    -- The vanilla B42 Java context builder can offer Trade/Medical Check even
    -- when the target IsoPlayer isn't present in worldObjects. Resolve the
    -- closest online player to the actual right-click world coordinate.
    if context and context.x and context.y then
        local clickedX = screenToIsoX(playerNum, context.x, context.y, localPlayer:getZ())
        local clickedY = screenToIsoY(playerNum, context.x, context.y, localPlayer:getZ())
        local onlinePlayers = getOnlinePlayers()
        local closestPlayer = nil
        local closestDistanceSquared = 4.0 -- two-tile click tolerance

        if onlinePlayers then
            for index = 0, onlinePlayers:size() - 1 do
                local candidate = onlinePlayers:get(index)
                if candidate and candidate ~= localPlayer and
                   candidate:getZ() == localPlayer:getZ() then
                    local dx = candidate:getX() - clickedX
                    local dy = candidate:getY() - clickedY
                    local distanceSquared = dx * dx + dy * dy
                    if distanceSquared <= closestDistanceSquared then
                        closestDistanceSquared = distanceSquared
                        closestPlayer = candidate
                    end
                end
            end
        end
        if closestPlayer then return closestPlayer end
    end

    return nil
end

local function requestLecture(localPlayer, clickedPlayer, topicKey)
    if not localPlayer or not clickedPlayer then return end

    sendClientCommand(localPlayer, PZLectures.MODULE, "requestLecture", {
        topic = topicKey,
        clickedPlayerOnlineId = clickedPlayer:getOnlineID(),
    })
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    if not isClient() then return end

    if not PZLectures._contextEventSeen then
        PZLectures._contextEventSeen = true
        print("[PZLectures] OnFillWorldObjectContextMenu received")
    end

    local localPlayer = getSpecificPlayer(playerNum)
    if not localPlayer or localPlayer:isDead() then return end

    local clickedPlayer = findClickedPlayer(localPlayer, worldObjects, playerNum, context)
    if not clickedPlayer then
        PZLectures.debug("No player target found for context menu")
        return
    end

    local requiredLevel = tonumber(PZLectures.getSetting("MinimumTeacherLevel")) or 6

    local parentOption = context:addOption(
        getText("ContextMenu_PZLectures_ConductLecture"),
        worldObjects,
        nil
    )

    local availableTopics = {}
    for _, topic in ipairs(PZLectures.Topics) do
        if localPlayer:getPerkLevel(topic.perk) >= requiredLevel then
            table.insert(availableTopics, topic)
        end
    end

    if #availableTopics == 0 then
        parentOption.notAvailable = true
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = getText(
            "IGUI_PZLectures_RequiresCraftingSkill",
            tostring(requiredLevel)
        )
        parentOption.toolTip = tooltip
        return
    end

    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(parentOption, subMenu)

    for _, topic in ipairs(availableTopics) do
        subMenu:addOption(
            PZLectures.getTopicDisplayName(topic),
            localPlayer,
            requestLecture,
            clickedPlayer,
            topic.key
        )
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
