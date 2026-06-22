require "ISUI/ISModalDialog"
require "TimedActions/ISTimedActionQueue"
require "PZLectures/PL_Config"
require "PZLectures/PL_Topics"
require "PZLectures/TimedActions/ISLectureAction"

if isServer() then return end

PZLecturesClient = PZLecturesClient or {
    inviteModal = nil,
    inviteSessionId = nil,
    activeAction = nil,
}

local function findLocalPlayerByOnlineId(onlineId)
    if onlineId == nil then return getPlayer() end

    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player and player:getOnlineID() == onlineId then
            return player
        end
    end
    return getPlayer()
end

local function closeInvite(sessionId)
    if PZLecturesClient.inviteModal and
       (sessionId == nil or PZLecturesClient.inviteSessionId == sessionId) then
        PZLecturesClient.inviteModal:destroy()
        PZLecturesClient.inviteModal = nil
        PZLecturesClient.inviteSessionId = nil
    end
end

local function showGood(player, text)
    if player then HaloTextHelper.addGoodText(player, text) end
end

local function showBad(player, text)
    if player then HaloTextHelper.addBadText(player, text) end
end

local function getTopicName(args)
    return PZLectures.getTopicDisplayName(args and args.topic)
end

local function stopActiveAction(sessionId, complete)
    local action = PZLecturesClient.activeAction
    if not action or action.sessionId ~= sessionId then return end

    action.suppressNetwork = true
    if action.action then
        if complete then
            action:forceComplete()
        else
            action:forceStop()
        end
    else
        ISTimedActionQueue.clear(action.character)
    end
    PZLecturesClient.activeAction = nil
end

function PZLecturesClient.onLocalActionFinished(action)
    if PZLecturesClient.activeAction == action then
        PZLecturesClient.activeAction = nil
    end
end

local function onInviteAnswer(_, button, sessionId)
    local player = getSpecificPlayer(button.player or 0) or getPlayer()
    local accepted = button.internal == "YES"

    PZLecturesClient.inviteModal = nil
    PZLecturesClient.inviteSessionId = nil

    if player then
        sendClientCommand(player, PZLectures.MODULE, "answerInvite", {
            sessionId = sessionId,
            accepted = accepted,
        })
    end
end

local function showInvite(args)
    closeInvite()

    local player = findLocalPlayerByOnlineId(args.participantOnlineId)
    if not player then return end

    local text = getText(
        "IGUI_PZLectures_Invite",
        tostring(args.teacherName),
        getTopicName(args),
        tostring(args.inviteSeconds)
    )
    local playerNum = player:getPlayerNum()
    local modal = ISModalDialog:new(
        0,
        0,
        420,
        150,
        text,
        true,
        nil,
        onInviteAnswer,
        playerNum,
        args.sessionId
    )
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
    modal:bringToTop()

    PZLecturesClient.inviteModal = modal
    PZLecturesClient.inviteSessionId = args.sessionId
end

local function startLecture(args)
    closeInvite(args.sessionId)

    local player = findLocalPlayerByOnlineId(args.participantOnlineId)
    if not player then return end

    if PZLecturesClient.activeAction then
        stopActiveAction(PZLecturesClient.activeAction.sessionId, false)
    end

    -- A lecture is an exclusive action. Accepted participants leave whatever
    -- they were doing and start the synchronized lecture immediately.
    ISTimedActionQueue.clear(player)

    local action = ISLectureAction:new(
        player,
        args.sessionId,
        args.role,
        tonumber(args.durationSeconds) or 30
    )
    PZLecturesClient.activeAction = action
    ISTimedActionQueue.add(action)

    if args.role == "teacher" then
        showGood(player, getText("IGUI_PZLectures_LectureStartedTeacher", getTopicName(args)))
    else
        showGood(player, getText("IGUI_PZLectures_LectureStartedListener", getTopicName(args)))
    end
end

local function onServerCommand(module, command, args)
    if module ~= PZLectures.MODULE then return end
    args = args or {}

    local player = findLocalPlayerByOnlineId(args.participantOnlineId)

    if command == "invite" then
        showInvite(args)
    elseif command == "inviteExpired" then
        closeInvite(args.sessionId)
    elseif command == "lectureStarting" then
        startLecture(args)
    elseif command == "participantRemoved" then
        stopActiveAction(args.sessionId, false)
        showBad(player, getText("IGUI_PZLectures_RemovedFromLecture"))
    elseif command == "lectureCancelled" then
        closeInvite(args.sessionId)
        stopActiveAction(args.sessionId, false)
        showBad(player, getText(args.messageKey or "IGUI_PZLectures_Cancelled"))
    elseif command == "lectureCompleted" then
        closeInvite(args.sessionId)
        stopActiveAction(args.sessionId, true)
        showGood(player, getText("IGUI_PZLectures_Completed", getTopicName(args)))
    elseif command == "rewardResult" then
        if args.changed then
            showGood(player, getText("IGUI_PZLectures_Rewarded", getTopicName(args), tostring(args.targetDescription)))
        else
            showGood(player, getText("IGUI_PZLectures_AlreadyAtCap", getTopicName(args), tostring(args.targetDescription)))
        end
    elseif command == "invitationsSent" then
        showGood(player, getText("IGUI_PZLectures_InvitationsSent", tostring(args.count or 0)))
    elseif command == "error" then
        showBad(player, getText(args.messageKey or "IGUI_PZLectures_Error"))
    end
end

local function onDisconnect()
    closeInvite()
    if PZLecturesClient.activeAction then
        PZLecturesClient.activeAction.suppressNetwork = true
        PZLecturesClient.activeAction = nil
    end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnDisconnect.Add(onDisconnect)
