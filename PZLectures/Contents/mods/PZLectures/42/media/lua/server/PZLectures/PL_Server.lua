require "PZLectures/PL_Config"
require "PZLectures/PL_Topics"

if isClient() then return end

local Sessions = {}
local SessionByParticipant = {}
local Sequence = 0
local LastUpdateMs = 0

local function nowMs()
    return getTimestampMs()
end

local function getPlayerById(onlineId)
    if onlineId == nil then return nil end
    return getPlayerByOnlineID(onlineId)
end

local function isUsablePlayer(player)
    return player ~= nil and not player:isDead()
end

local function sendTo(player, command, args)
    if not player then return end
    args = args or {}
    args.participantOnlineId = player:getOnlineID()
    sendServerCommand(player, PZLectures.MODULE, command, args)
end

local function countMap(values)
    local count = 0
    for _, enabled in pairs(values or {}) do
        if enabled then count = count + 1 end
    end
    return count
end

local function makeSessionId(teacher)
    Sequence = Sequence + 1
    return tostring(nowMs()) .. "-" .. tostring(teacher:getOnlineID()) .. "-" .. tostring(Sequence)
end

local function removeParticipantIndex(session)
    if not session then return end
    SessionByParticipant[session.teacherOnlineId] = nil
    for onlineId, _ in pairs(session.accepted or {}) do
        if SessionByParticipant[onlineId] == session.id then
            SessionByParticipant[onlineId] = nil
        end
    end
end

local function deleteSession(session)
    if not session then return end
    removeParticipantIndex(session)
    Sessions[session.id] = nil
end

local function notifySession(session, command, args)
    local teacher = getPlayerById(session.teacherOnlineId)
    sendTo(teacher, command, args)
    for onlineId, active in pairs(session.activeListeners or {}) do
        if active then sendTo(getPlayerById(onlineId), command, args) end
    end
end

local function cancelSession(session, messageKey)
    if not session or session.state == "CANCELLED" or session.state == "COMPLETED" then return end
    session.state = "CANCELLED"
    local message = {
        sessionId = session.id,
        messageKey = messageKey or "IGUI_PZLectures_Cancelled",
    }
    notifySession(session, "lectureCancelled", message)

    local alreadyNotified = { [session.teacherOnlineId] = true }
    for onlineId, _ in pairs(session.activeListeners or {}) do
        alreadyNotified[onlineId] = true
    end
    for onlineId, _ in pairs(session.invited or {}) do
        if not alreadyNotified[onlineId] then
            sendTo(getPlayerById(onlineId), "lectureCancelled", message)
            alreadyNotified[onlineId] = true
        end
    end
    for onlineId, _ in pairs(session.accepted or {}) do
        if not alreadyNotified[onlineId] then
            sendTo(getPlayerById(onlineId), "lectureCancelled", message)
        end
    end
    PZLectures.debug("Cancelled session " .. session.id .. ": " .. tostring(messageKey))
    deleteSession(session)
end

local function findCandidates(teacher, radius)
    local candidates = {}
    local onlinePlayers = getOnlinePlayers()

    for index = 0, onlinePlayers:size() - 1 do
        local candidate = onlinePlayers:get(index)
        local candidateId = candidate and candidate:getOnlineID() or nil
        if candidate and candidate ~= teacher and isUsablePlayer(candidate) and
           not SessionByParticipant[candidateId] and
           PZLectures.isInRange(teacher, candidate, radius) then
            candidates[candidateId] = true
        end
    end

    return candidates
end

local function validateTeacher(teacher, settings, topic)
    if not isUsablePlayer(teacher) then
        return false, "IGUI_PZLectures_ErrorInvalidTeacher"
    end
    if not topic or teacher:getPerkLevel(topic.perk) < settings.minimumTeacherLevel then
        return false, "IGUI_PZLectures_ErrorTeacherLevel"
    end
    if SessionByParticipant[teacher:getOnlineID()] then
        return false, "IGUI_PZLectures_ErrorAlreadyBusy"
    end
    if teacher:isAsleep() then
        return false, "IGUI_PZLectures_ErrorInvalidState"
    end
    local vehicle = teacher:getVehicle()
    if vehicle and vehicle:isDriver(teacher) and (vehicle:isEngineRunning() or vehicle:getSpeed2D() ~= 0) then
        return false, "IGUI_PZLectures_ErrorInvalidState"
    end
    return true
end

local function createLecture(teacher, args)
    local settings = PZLectures.getSettingsSnapshot()
    local topic = args and PZLectures.getTopic(args.topic) or nil
    if not topic then
        sendTo(teacher, "error", { messageKey = "IGUI_PZLectures_ErrorUnknownTopic" })
        return
    end

    local valid, messageKey = validateTeacher(teacher, settings, topic)
    if not valid then
        sendTo(teacher, "error", { messageKey = messageKey })
        return
    end

    local clickedPlayer = getPlayerById(tonumber(args.clickedPlayerOnlineId))
    if not clickedPlayer or clickedPlayer == teacher or not isUsablePlayer(clickedPlayer) or
       not PZLectures.isInRange(teacher, clickedPlayer, settings.lectureRadius) then
        sendTo(teacher, "error", { messageKey = "IGUI_PZLectures_ErrorNoCandidates" })
        return
    end

    local candidates = findCandidates(teacher, settings.lectureRadius)
    if not candidates or countMap(candidates) == 0 then
        sendTo(teacher, "error", { messageKey = "IGUI_PZLectures_ErrorNoCandidates" })
        return
    end

    local sessionId = makeSessionId(teacher)
    local session = {
        id = sessionId,
        topic = topic.key,
        state = "INVITING",
        teacherOnlineId = teacher:getOnlineID(),
        teacherName = teacher:getDisplayName(),
        teacherOriginX = teacher:getX(),
        teacherOriginY = teacher:getY(),
        teacherOriginZ = teacher:getZ(),
        invited = candidates,
        accepted = {},
        activeListeners = {},
        rewarded = {},
        settings = settings,
        inviteDeadlineMs = nowMs() + settings.inviteDurationSeconds * 1000,
    }

    Sessions[sessionId] = session
    SessionByParticipant[teacher:getOnlineID()] = sessionId

    local invitationCount = 0
    for onlineId, _ in pairs(candidates) do
        local candidate = getPlayerById(onlineId)
        if candidate then
            invitationCount = invitationCount + 1
            sendTo(candidate, "invite", {
                sessionId = sessionId,
                teacherName = session.teacherName,
                topic = session.topic,
                inviteSeconds = settings.inviteDurationSeconds,
            })
        end
    end

    sendTo(teacher, "invitationsSent", {
        sessionId = sessionId,
        count = invitationCount,
    })
    PZLectures.debug("Created session " .. sessionId .. " with " .. invitationCount .. " invitations")
end

local function answerInvite(player, args)
    if not args or not args.sessionId then return end
    local session = Sessions[args.sessionId]
    if not session or session.state ~= "INVITING" then
        sendTo(player, "error", { messageKey = "IGUI_PZLectures_ErrorInviteExpired" })
        return
    end

    local onlineId = player:getOnlineID()
    if not session.invited[onlineId] then return end

    if args.accepted ~= true then
        session.invited[onlineId] = nil
        return
    end

    if SessionByParticipant[onlineId] then
        sendTo(player, "error", { messageKey = "IGUI_PZLectures_ErrorAlreadyBusy" })
        return
    end

    local teacher = getPlayerById(session.teacherOnlineId)
    if not isUsablePlayer(teacher) or not isUsablePlayer(player) or
       not PZLectures.isInRange(teacher, player, session.settings.lectureRadius) then
        sendTo(player, "error", { messageKey = "IGUI_PZLectures_ErrorTooFar" })
        return
    end

    session.accepted[onlineId] = true
    SessionByParticipant[onlineId] = session.id
    sendTo(player, "inviteExpired", { sessionId = session.id })
end

local function removeListener(session, onlineId, notify)
    if not session.activeListeners[onlineId] then return end
    session.activeListeners[onlineId] = nil
    session.accepted[onlineId] = nil
    session.invited[onlineId] = nil
    if SessionByParticipant[onlineId] == session.id then
        SessionByParticipant[onlineId] = nil
    end
    if notify then
        sendTo(getPlayerById(onlineId), "participantRemoved", { sessionId = session.id })
    end
end

local function startSession(session)
    local teacher = getPlayerById(session.teacherOnlineId)
    local settings = session.settings
    local topic = PZLectures.getTopic(session.topic)
    if not isUsablePlayer(teacher) or
       not topic or teacher:getPerkLevel(topic.perk) < settings.minimumTeacherLevel then
        cancelSession(session, "IGUI_PZLectures_CancelledTeacher")
        return
    end

    for onlineId, _ in pairs(session.accepted) do
        local listener = getPlayerById(onlineId)
        if isUsablePlayer(listener) and PZLectures.isInRange(teacher, listener, settings.lectureRadius) then
            session.activeListeners[onlineId] = true
        else
            session.accepted[onlineId] = nil
            if listener then
                sendTo(listener, "error", { messageKey = "IGUI_PZLectures_ErrorTooFar" })
            end
            if SessionByParticipant[onlineId] == session.id then
                SessionByParticipant[onlineId] = nil
            end
        end
    end

    if countMap(session.activeListeners) < settings.minimumListeners then
        cancelSession(session, "IGUI_PZLectures_CancelledNoListeners")
        return
    end

    session.state = "ACTIVE"
    session.teacherOriginX = teacher:getX()
    session.teacherOriginY = teacher:getY()
    session.teacherOriginZ = teacher:getZ()
    session.startedAtMs = nowMs()
    session.endsAtMs = session.startedAtMs + settings.lectureDurationSeconds * 1000

    sendTo(teacher, "lectureStarting", {
        sessionId = session.id,
        topic = session.topic,
        role = "teacher",
        durationSeconds = settings.lectureDurationSeconds,
    })
    for onlineId, _ in pairs(session.activeListeners) do
        sendTo(getPlayerById(onlineId), "lectureStarting", {
            sessionId = session.id,
            topic = session.topic,
            role = "listener",
            durationSeconds = settings.lectureDurationSeconds,
        })
    end
    PZLectures.debug("Started session " .. session.id)
end

local function targetXp(settings, perkType)
    local perk = PerkFactory.getPerk(perkType)
    local baseLevel = math.max(0, math.min(9, settings.targetLevel))
    local fraction = math.max(0, math.min(99, settings.targetProgressPercent)) / 100
    local xpAtBase = perk:getTotalXpForLevel(baseLevel)
    local xpAtNext = perk:getTotalXpForLevel(baseLevel + 1)
    local percent = math.max(0, math.min(99, settings.targetProgressPercent))
    local description = tostring(baseLevel)
    if percent > 0 then
        local decimals = string.format("%02d", percent)
        decimals = string.gsub(decimals, "0$", "")
        description = description .. "." .. decimals
    end

    return xpAtBase + (xpAtNext - xpAtBase) * fraction, description
end

local function rewardListener(session, listener)
    local onlineId = listener:getOnlineID()
    if session.rewarded[onlineId] then return end
    session.rewarded[onlineId] = true

    local topic = PZLectures.getTopic(session.topic)
    if not topic then return end

    local target, targetDescription = targetXp(session.settings, topic.perk)
    local current = listener:getXp():getXP(topic.perk)
    local changed = false

    if current < target then
        local delta = target - current
        listener:getXp():AddXP(topic.perk, delta, false, false, false, false)
        changed = true
        PZLectures.debug("Rewarded " .. tostring(listener:getUsername()) .. " with " .. tostring(delta) .. " " .. topic.key .. " XP")
    end

    sendTo(listener, "rewardResult", {
        sessionId = session.id,
        changed = changed,
        topic = session.topic,
        targetDescription = targetDescription,
    })
end

local function completeSession(session)
    local teacher = getPlayerById(session.teacherOnlineId)
    if not isUsablePlayer(teacher) then
        cancelSession(session, "IGUI_PZLectures_CancelledTeacher")
        return
    end

    local validListeners = {}
    for onlineId, active in pairs(session.activeListeners) do
        local listener = active and getPlayerById(onlineId) or nil
        if listener and isUsablePlayer(listener) and
           PZLectures.isInRange(teacher, listener, session.settings.lectureRadius) then
            validListeners[onlineId] = listener
        end
    end

    if countMap(validListeners) < session.settings.minimumListeners then
        cancelSession(session, "IGUI_PZLectures_CancelledNoListeners")
        return
    end

    session.state = "COMPLETED"
    sendTo(teacher, "lectureCompleted", { sessionId = session.id, topic = session.topic })
    for onlineId, listener in pairs(validListeners) do
        sendTo(listener, "lectureCompleted", { sessionId = session.id, topic = session.topic })
        rewardListener(session, listener)
    end

    PZLectures.debug("Completed session " .. session.id)
    deleteSession(session)
end

local function teacherStayedInPlace(session, teacher)
    if teacher:getZ() ~= session.teacherOriginZ then return false end
    return math.floor(teacher:getX()) == math.floor(session.teacherOriginX) and
           math.floor(teacher:getY()) == math.floor(session.teacherOriginY)
end

local function updateActiveSession(session, currentMs)
    local teacher = getPlayerById(session.teacherOnlineId)
    local topic = PZLectures.getTopic(session.topic)
    if not isUsablePlayer(teacher) or
       not topic or teacher:getPerkLevel(topic.perk) < session.settings.minimumTeacherLevel or
       not teacherStayedInPlace(session, teacher) then
        cancelSession(session, "IGUI_PZLectures_CancelledTeacher")
        return
    end

    local toRemove = {}
    for onlineId, active in pairs(session.activeListeners) do
        local listener = active and getPlayerById(onlineId) or nil
        if not listener or not isUsablePlayer(listener) or
           not PZLectures.isInRange(teacher, listener, session.settings.lectureRadius) then
            table.insert(toRemove, onlineId)
        end
    end
    for _, onlineId in ipairs(toRemove) do
        removeListener(session, onlineId, true)
    end

    if countMap(session.activeListeners) < session.settings.minimumListeners then
        cancelSession(session, "IGUI_PZLectures_CancelledNoListeners")
        return
    end

    if currentMs >= session.endsAtMs then
        completeSession(session)
    end
end

local function onTick()
    local currentMs = nowMs()
    if currentMs - LastUpdateMs < 250 then return end
    LastUpdateMs = currentMs

    local sessionIds = {}
    for sessionId, _ in pairs(Sessions) do table.insert(sessionIds, sessionId) end

    for _, sessionId in ipairs(sessionIds) do
        local session = Sessions[sessionId]
        if session then
            if session.state == "INVITING" and currentMs >= session.inviteDeadlineMs then
                for onlineId, _ in pairs(session.invited) do
                    sendTo(getPlayerById(onlineId), "inviteExpired", { sessionId = session.id })
                end
                session.invited = {}
                if countMap(session.accepted) >= session.settings.minimumListeners then
                    startSession(session)
                else
                    cancelSession(session, "IGUI_PZLectures_CancelledNoListeners")
                end
            elseif session.state == "ACTIVE" then
                updateActiveSession(session, currentMs)
            end
        end
    end
end

local function onActionCancelled(player, args)
    if not args or not args.sessionId then return end
    local session = Sessions[args.sessionId]
    if not session or session.state ~= "ACTIVE" then return end

    local onlineId = player:getOnlineID()
    if onlineId == session.teacherOnlineId then
        cancelSession(session, "IGUI_PZLectures_CancelledTeacher")
    elseif session.activeListeners[onlineId] then
        removeListener(session, onlineId, true)
        if countMap(session.activeListeners) < session.settings.minimumListeners then
            cancelSession(session, "IGUI_PZLectures_CancelledNoListeners")
        end
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= PZLectures.MODULE then return end

    if command == "requestLecture" then
        createLecture(player, args)
    elseif command == "answerInvite" then
        answerInvite(player, args)
    elseif command == "actionCancelled" then
        onActionCancelled(player, args)
    elseif command == "actionStarted" or command == "actionCompleted" then
        -- These acknowledgements are intentionally informational. The server's
        -- clock, positions and session state remain authoritative.
        PZLectures.debug(command .. " from " .. tostring(player:getUsername()))
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)
