require "TimedActions/ISBaseTimedAction"
require "PZLectures/PL_Config"

ISLectureAction = ISBaseTimedAction:derive("ISLectureAction")

function ISLectureAction:isValid()
    return self.character ~= nil and not self.character:isDead()
end

-- Keep the configured lecture duration deterministic. Vanilla's implementation
-- otherwise changes it based on unhappiness, drunkenness, wounds and temperature.
function ISLectureAction:adjustMaxTime(maxTime)
    return maxTime
end

function ISLectureAction:start()
    self:setAnimVariable("ReadType", "book")
    self:setActionAnim(CharacterActionAnims.Read)
    self.character:setReading(true)
    self.character:reportEvent("EventRead")

    if isClient() then
        sendClientCommand(self.character, PZLectures.MODULE, "actionStarted", {
            sessionId = self.sessionId,
            role = self.role,
        })
    end
end

function ISLectureAction:update()
end

function ISLectureAction:stop()
    self.character:setReading(false)

    if isClient() and not self.suppressNetwork then
        sendClientCommand(self.character, PZLectures.MODULE, "actionCancelled", {
            sessionId = self.sessionId,
            role = self.role,
            reason = "interrupted",
        })
    end

    if PZLecturesClient and PZLecturesClient.onLocalActionFinished then
        PZLecturesClient.onLocalActionFinished(self)
    end

    ISBaseTimedAction.stop(self)
end

function ISLectureAction:forceCancel()
    if isClient() and not self.suppressNetwork then
        sendClientCommand(self.character, PZLectures.MODULE, "actionCancelled", {
            sessionId = self.sessionId,
            role = self.role,
            reason = "queue-cancelled",
        })
    end
end

function ISLectureAction:perform()
    self.character:setReading(false)

    if isClient() and not self.suppressNetwork then
        sendClientCommand(self.character, PZLectures.MODULE, "actionCompleted", {
            sessionId = self.sessionId,
            role = self.role,
        })
    end

    if PZLecturesClient and PZLecturesClient.onLocalActionFinished then
        PZLecturesClient.onLocalActionFinished(self)
    end

    ISBaseTimedAction.perform(self)
end

-- Build 42 networked timed actions call complete() on the authoritative side.
-- The lecture reward itself is handled by PL_Server's session clock.
function ISLectureAction:complete()
    return true
end

function ISLectureAction:new(character, sessionId, role, durationSeconds)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.sessionId = sessionId
    o.role = role
    o.maxTime = math.max(1, math.floor((durationSeconds or 30) * 60))
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.ignoreHandsWounds = true
    o.forceProgressBar = true
    o.caloriesModifier = 0.5
    o.suppressNetwork = false
    return o
end
