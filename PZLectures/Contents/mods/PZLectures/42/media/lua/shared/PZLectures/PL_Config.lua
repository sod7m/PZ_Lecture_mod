PZLectures = PZLectures or {}

PZLectures.MODULE = "PZLectures"
PZLectures.Defaults = {
    MinimumTeacherLevel = 6,
    TargetLevel = 4,
    TargetProgressPercent = 50,
    LectureRadius = 5,
    InviteDurationSeconds = 10,
    LectureDurationSeconds = 30,
    MinimumListeners = 1,
    DebugLogging = false,
}

local function getSandboxValue(key)
    if SandboxVars and SandboxVars.PZLectures then
        local value = SandboxVars.PZLectures[key]
        if value ~= nil then
            return value
        end
    end
    return PZLectures.Defaults[key]
end

function PZLectures.getSetting(key)
    return getSandboxValue(key)
end

function PZLectures.getSettingsSnapshot()
    return {
        minimumTeacherLevel = tonumber(getSandboxValue("MinimumTeacherLevel")) or 6,
        targetLevel = tonumber(getSandboxValue("TargetLevel")) or 4,
        targetProgressPercent = tonumber(getSandboxValue("TargetProgressPercent")) or 50,
        lectureRadius = tonumber(getSandboxValue("LectureRadius")) or 5,
        inviteDurationSeconds = tonumber(getSandboxValue("InviteDurationSeconds")) or 10,
        lectureDurationSeconds = tonumber(getSandboxValue("LectureDurationSeconds")) or 30,
        minimumListeners = tonumber(getSandboxValue("MinimumListeners")) or 1,
        debugLogging = getSandboxValue("DebugLogging") == true,
    }
end

function PZLectures.debug(message)
    if getSandboxValue("DebugLogging") == true then
        print("[PZLectures] " .. tostring(message))
    end
end

function PZLectures.isInRange(firstPlayer, secondPlayer, radius)
    if not firstPlayer or not secondPlayer then return false end
    if firstPlayer:getZ() ~= secondPlayer:getZ() then return false end

    local dx = firstPlayer:getX() - secondPlayer:getX()
    local dy = firstPlayer:getY() - secondPlayer:getY()
    return (dx * dx + dy * dy) <= (radius * radius)
end
