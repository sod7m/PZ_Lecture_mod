require "PZLectures/PL_Config"

-- Ordered exactly like the Build 42 Crafting skill group.
PZLectures.Topics = {
    { key = "carving", perk = Perks.Carving },
    { key = "glassmaking", perk = Perks.Glassmaking },
    { key = "flintKnapping", perk = Perks.FlintKnapping },
    { key = "masonry", perk = Perks.Masonry },
    { key = "pottery", perk = Perks.Pottery },
    { key = "mechanics", perk = Perks.Mechanics },
    { key = "woodwork", perk = Perks.Woodwork },
    { key = "metalWelding", perk = Perks.MetalWelding },
    { key = "electricity", perk = Perks.Electricity },
    { key = "blacksmith", perk = Perks.Blacksmith },
    { key = "cooking", perk = Perks.Cooking },
    { key = "tailoring", perk = Perks.Tailoring },
}

PZLectures.TopicsByKey = {}
for _, topic in ipairs(PZLectures.Topics) do
    PZLectures.TopicsByKey[topic.key] = topic
end

function PZLectures.getTopic(topicKey)
    return PZLectures.TopicsByKey[topicKey]
end

function PZLectures.getTopicDisplayName(topicOrKey)
    local topic = type(topicOrKey) == "table" and topicOrKey or PZLectures.getTopic(topicOrKey)
    if not topic then return tostring(topicOrKey or "") end
    return PerkFactory.getPerkName(topic.perk)
end

