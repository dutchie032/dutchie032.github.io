--[[
        Spearhead Compile Time: 2024-10-11T22:31:43.136828
    ]]
do --spearhead_base.lua
--- DEFAULT Values
if Spearhead == nil then Spearhead = {} end

local UTIL = {}
do -- INIT UTIL
    ---splits a string in sub parts by seperator
    ---@param input string
    ---@param seperator string
    ---@return table result list of strings
    function UTIL.split_string(input, seperator)
        if seperator == nil then
            seperator = " "
        end

        local result = {}
        if input == nil then
            return result
        end

        for str in string.gmatch(input, "[^" .. seperator .. "]+") do
            table.insert(result, str)
        end
        return result
    end

    ---comment
    ---@param table any
    ---@return number
    function UTIL.tableLength(table)
        if table == nil then return 0 end

        local count = 0
        for _ in pairs(table) do count = count + 1 end
        return count
    end

    ---Gets a random from the list
    ---@param list table
    function UTIL.randomFromList(list)
        local max = #list

        if max == 0 or max == nil then
            return nil
        end

        local random = math.random(0, max)
        if random == 0 then random = 1 end

        return list[random]
    end

    local function table_print(tt, indent, done)
        done = done or {}
        indent = indent or 0
        if type(tt) == "table" then
            local sb = {}
            for key, value in pairs(tt) do
                table.insert(sb, string.rep(" ", indent)) -- indent it
                if type(value) == "table" and not done[value] then
                    done[value] = true
                    table.insert(sb, key .. " = {\n");
                    table.insert(sb, table_print(value, indent + 2, done))
                    table.insert(sb, string.rep(" ", indent)) -- indent it
                    table.insert(sb, "}\n");
                elseif "number" == type(key) then
                    table.insert(sb, string.format("\"%s\"\n", tostring(value)))
                else
                    table.insert(sb, string.format(
                        "%s = \"%s\"\n", tostring(key), tostring(value)))
                end
            end
            return table.concat(sb)
        else
            return tt .. "\n"
        end
    end

    ---comment
    ---@param str string
    ---@param findable string
    ---@return boolean
    UTIL.startswith = function(str, findable)
        return str:find('^' .. findable) ~= nil
    end

    ---comment
    ---@param str string
    ---@param findable string
    ---@return boolean
    UTIL.strContains = function(str, findable)
        return str:find(findable) ~= nil
    end

    ---comment
    ---@param str string
    ---@param findableTable table
    ---@return boolean
    UTIL.startswithAny = function(str, findableTable)
        for key, value in pairs(findableTable) do
            if type(value) == "string" and UTIL.startswith(str, value) then return true end
        end
        return false
    end

    function UTIL.toString(something)
        if something == nil then
            return "nil"
        elseif "table" == type(something) then
            return table_print(something)
        elseif "string" == type(something) then
            return something
        else
            return tostring(something)
        end
    end
end
Spearhead.Util = UTIL

---DCS UTIL Takes inspiration from MIST but only takes the things it needs, changes for DCS updates and different vision for advanced mission scripting stuff.
---It also adds functions that make the other TDCS scripts easier without taking too much "control" away like MOOSE can sometimes.
local DCS_UTIL = {}
do     -- INIT DCS_UTIL
    do -- local databases
        --[[
            groupdata = {
                category,
                country_id,
                group_template
            }
        ]] --
        DCS_UTIL.__miz_groups = {}
        DCS_UTIL.__groupNames = {}
        DCS_UTIL.__blueGroupNames = {}
        DCS_UTIL.__redGroupNames = {}
        --[[
            zone = {
                name,

                zone_type,
                x,
                z,
                radius
                verts,

            }
        ]] --
        DCS_UTIL.__trigger_zones = {}
    end

    DCS_UTIL.Coalition =
    {
        NEUTRAL = 0,
        RED = 1,
        BLUE = 2
    }

    DCS_UTIL.ZoneType = {
        Cilinder = 0,
        Polygon = 2
    }

    DCS_UTIL.GroupCategory = {
        AIRPLANE   = 0,
        HELICOPTER = 1,
        GROUND     = 2,
        SHIP       = 3,
        TRAIN      = 4,
        STATIC     = 5 --CUSTOM CATEGORY
    }

    DCS_UTIL.__airbaseNamesById = {}

    DCS_UTIL.__airportsStartingCoalition = {}
    DCS_UTIL.__warehouseStartingCoalition = {}
    function DCS_UTIL.__INIT()
        do     -- INITS ALL TABLES WITH DATA THAT's from the MIZ environment
            do -- init group tables
                for coalition_name, coalition_data in pairs(env.mission.coalition) do
                    local coalition_nr = DCS_UTIL.stringToCoalition(coalition_name)
                    if coalition_data.country then
                        for country_index, country_data in pairs(coalition_data.country) do
                            for category_name, categorydata in pairs(country_data) do
                                local category_id = DCS_UTIL.stringToGroupCategory(category_name)
                                if category_id ~= nil and type(categorydata) == "table" and categorydata.group ~= nil and type(categorydata.group) == "table" then
                                    for group_index, group in pairs(categorydata.group) do
                                        local name = group.name
                                        if category_id == DCS_UTIL.GroupCategory.STATIC then
                                            local unit = group.units[1]
                                            name = unit.name
                                            local staticObj = {
                                                heading = unit.heading,
                                                name = unit.name,
                                                x = unit.x,
                                                y = unit.y,
                                                type = unit.type,
                                                dead = group.dead
                                            }

                                            if string.lower(unit.category) == "planes" then
                                                staticObj.livery_id = unit.livery_id
                                            end

                                            group = staticObj
                                        end

                                        table.insert(DCS_UTIL.__groupNames, name)
                                        DCS_UTIL.__miz_groups[name] =
                                        {
                                            category = category_id,
                                            country_id = country_data.id,
                                            group_template = group
                                        }

                                        if coalition_nr == 1 then
                                            table.insert(DCS_UTIL.__redGroupNames, name)
                                        elseif coalition_nr == 2 then
                                            table.insert(DCS_UTIL.__blueGroupNames, name)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            do --init trigger zones
                for i, trigger_zone in pairs(env.mission.triggers.zones) do
                    local verticies = {}
                    if trigger_zone.verticies and type(trigger_zone.verticies) == "table" then
                        for ii, vert in pairs(trigger_zone.verticies) do
                            table.insert(verticies, { x = vert.x, z = vert.y })
                        end
                    end

                    --see if this works. Swap 3 and 4 to make sure points are ordered and edges can be created
                    local p4 = verticies[4]
                    local p3 = verticies[3]
                    verticies[3] = p4
                    verticies[4] = p3

                    local zone = {
                        name = trigger_zone.name,
                        zone_type = trigger_zone.type,
                        x = trigger_zone.x,
                        z = trigger_zone.y,
                        radius = trigger_zone.radius,
                        verts = verticies
                    }

                    DCS_UTIL.__trigger_zones[zone.name] = zone
                end
            end

            do -- init airports and warehouses
                if env.warehouses.airports then
                    for warehouse_id, value in pairs(env.warehouses.airports) do
                        if warehouse_id ~= nil then
                            warehouse_id = tostring(warehouse_id) or "nil"
                            local coalitionNumber = DCS_UTIL.stringToCoalition(value.coalition)
                            DCS_UTIL.__airportsStartingCoalition[warehouse_id] = coalitionNumber
                        end
                    end
                end

                if env.warehouses.warehouses then
                    DCS_UTIL.__warehouseStartingCoalition[-1] = "placeholder"
                    for warehouse_id, value in pairs(env.warehouses.warehouses) do
                        if warehouse_id ~= nil then
                            warehouse_id = tostring(warehouse_id) or "nil"
                            local coalitionNumber = DCS_UTIL.stringToCoalition(value.coalition)
                            DCS_UTIL.__warehouseStartingCoalition[warehouse_id] = coalitionNumber
                        end
                    end
                end
            end

            do -- fill airbaseNames
                local airbases = world.getAirbases()
                if airbases then
                    for _, airbase in pairs(airbases) do
                        local name = airbase:getName()
                        local id = tostring(airbase:getID())

                        if name and id then
                            DCS_UTIL.__airbaseNamesById[id] = name
                        end
                    end
                end
            end
        end
    end

    ---maps the coalition name to the DCS coalition integer
    ---@param input string the name
    ---@return integer
    function DCS_UTIL.stringToCoalition(input)
        --[[
            coalition.side = {
                NEUTRAL = 0
                RED = 1
                BLUE = 2
            }
        ]] --
        local input = string.lower(input)
        if input == 'neutrals' or input == "neutral" or input == "0" then
            return DCS_UTIL.Coalition.NEUTRAL
        end

        if input == 'red' or input == "1" then
            return DCS_UTIL.Coalition.RED
        end

        if input == 'blue' or input == "2" then
            return DCS_UTIL.Coalition.BLUE
        end

        return -1
    end

    ---checks if the groupname is a static group
    ---@param groupName any
    function DCS_UTIL.IsGroupStatic(groupName)
        return DCS_UTIL.__miz_groups[groupName].category == 5;
    end

    ---comment
    ---@param groupName string destroy the given group
    function DCS_UTIL.DestroyGroup(groupName)
        if DCS_UTIL.IsGroupStatic(groupName) then
            local object = StaticObject.getByName(groupName)
            if object ~= nil then
                object:destroy()
            end
        else
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                group:destroy()
            end
        end
    end

    ---comment
    ---@param polygon table of pairs { x, z }
    ---@param x number X location
    ---@param z number Y location
    ---@return boolean
    function DCS_UTIL.IsPointInPolygon(polygon, x, z)
        local function isInComplexPolygon(polygon, x, z)
            local function getEdges(poly)
                local moved = {}
                moved[#poly] = poly[1]
                for i = 2, #poly do
                    moved[i - 1] = poly[i]
                end

                local result = {}
                for i = 1, #poly do
                    local point1 = moved[i]
                    local point2 = poly[i]
                    local edge = { x1 = point1.x, z1 = point1.z, x2 = point2.x, z2 = point2.z }
                    table.insert(result, edge)
                end
                return result
            end

            local edges = getEdges(polygon)
            local count = 0;
            for _, edge in pairs(edges) do
                if (x < edge.x1) ~= (x < edge.x2) and z < edge.z1 + ((x - edge.x1) / (edge.x2 - edge.x1)) * (edge.z2 - edge.z1) then
                    count = count + 1
                    -- if (yp < y1) != (yp < y2) and xp < x1 + ((yp-y1)/(y2-y1))*(x2-x1) then
                    --     count = count + 1
                end
            end
            return count % 2 == 1
        end
        return isInComplexPolygon(polygon, x, z)
    end

    --- takes a list of units and returns all the units that are in any of the zones
    ---@param unit_names table unit names
    ---@param zone_names table zone names
    ---@return table unit list of objects { unit = UNIT, zone_name = zoneName}
    function DCS_UTIL.getUnitsInZones(unit_names, zone_names)
        local units = {}
        local zones = {}

        for k = 1, #unit_names do
            local unit = Unit.getByName(unit_names[k]) or StaticObject.getByName(unit_names[k])
            if unit and unit:isExist() == true then
                units[#units + 1] = unit
            end
        end

        for index, zone_name in pairs(zone_names) do
            local zone = DCS_UTIL.__trigger_zones[zone_name]
            if zone then
                zones[#zones + 1] = zone
            end
        end

        local in_zone_units = {}
        for units_ind = 1, #units do
            local lUnit = units[units_ind]
            local unit_pos = lUnit:getPosition().p
            local lCat = Object.getCategory(lUnit)
            for zone_name, zone in pairs(zones) do
                if unit_pos and ((lCat == 1 and lUnit:isActive() == true) or lCat ~= 1) then -- it is a unit and is active or it is not a unit
                    if zone.zone_type == DCS_UTIL.ZoneType.Polygon and zone.verts then
                        if DCS_UTIL.IsPointInPolygon(zone.verts, unit_pos.x, unit_pos.z) == true then
                            in_zone_units[#in_zone_units + 1] = { unit = lUnit, zone_name = zone.name }
                        end
                    else
                        if (((unit_pos.x - zone.x) ^ 2 + (unit_pos.z - zone.z) ^ 2) ^ 0.5 <= zone.radius) then
                            in_zone_units[#in_zone_units + 1] = { unit = lUnit, zone_name = zone.name }
                        end
                    end
                end
            end
        end
        return in_zone_units
    end

    --- takes a list of groups and returns all the group leaders that are in any of the zones
    ---@param group_names table unit names
    ---@param zone_name string zone names
    ---@return table groupnames list of group names
    function DCS_UTIL.getGroupsInZone(group_names, zone_name)
        local zone = DCS_UTIL.__trigger_zones[zone_name]
        if zone == nil then
            return {}
        end

        -- MAP Just for mapping sake
        local custom_zone = {
            x = zone.x,
            z = zone.z,
            zone_type = zone.zone_type,
            radius = zone.radius,
            verts = zone.verts
        }

        return DCS_UTIL.areGroupsInCustomZone(group_names, custom_zone)
    end

    --- takes a x, y poistion and checks if it is inside any of the zones
    ---@param group_names table North South position
    ---@param zone table { x, z, zonetype,  radius, verts }
    ---@return table groupnames list of groups that are in the zone
    function DCS_UTIL.areGroupsInCustomZone(group_names, zone)
        local units = {}
        if Spearhead.Util.tableLength(group_names) < 1 then return {} end

        for k = 1, #group_names do
            local entry = nil
            local group = Group.getByName(group_names[k])
            if group ~= nil then
                entry = { unit = group:getUnit(1), groupname = group_names[k] }
            else
                entry = { unit = StaticObject.getByName(group_names[k]), groupname = group_names[k] }
            end

            if entry and entry.unit and entry.unit:isExist() == true then
                units[#units + 1] = entry
            end
        end

        local result_groups = {}
        for _, entry in pairs(units) do
            local pos = entry.unit:getPoint()
            if zone.zone_type == DCS_UTIL.ZoneType.Polygon and zone.verts then
                if DCS_UTIL.IsPointInPolygon(zone.verts, pos.x, pos.z) == true then
                    table.insert(result_groups, entry.groupname)
                end
            else
                if (((pos.x - zone.x) ^ 2 + (pos.z - zone.z) ^ 2) ^ 0.5 <= zone.radius) then
                    table.insert(result_groups, entry.groupname)
                end
            end
        end
        return result_groups
    end

    --- takes a x, y poistion and checks if it is inside any of the zones
    ---@param x number North South position
    ---@param z number West East position
    ---@param zone_names table zone names
    ---@return table zones list of objects { zone_name = zoneName}
    function DCS_UTIL.isPositionInZones(x, z, zone_names)
        local zones = {}
        for index, zone_name in pairs(zone_names) do
            local zone = DCS_UTIL.__trigger_zones[zone_name]
            if zone then
                zones[#zones + 1] = zone
            end
        end

        local result_zones = {}
        for zone_name, zone in pairs(zones) do
            if zone.zone_type == DCS_UTIL.ZoneType.Polygon and zone.verts then
                if DCS_UTIL.IsPointInPolygon(zone.verts, x, z) == true then
                    result_zones[#result_zones + 1] = zone.name
                end
            else
                if (((x - zone.x) ^ 2 + (z - zone.z) ^ 2) ^ 0.5 <= zone.radius) then
                    result_zones[#result_zones + 1] = zone.name
                end
            end
        end
        return result_zones
    end

    --- takes a x, y poistion and checks if it is inside any of the zones
    ---@param x number North South position
    ---@param z number West East position
    ---@param zone_name table zone names
    ---@return boolean result
    function DCS_UTIL.isPositionInZone(x, z, zone_name)
        local zone = DCS_UTIL.__trigger_zones[zone_name]
        if zone.zone_type == DCS_UTIL.ZoneType.Polygon and zone.verts then
            if DCS_UTIL.IsPointInPolygon(zone.verts, x, z) == true then
                return true
            end
        else
            if (((x - zone.x) ^ 2 + (z - zone.z) ^ 2) ^ 0.5 <= zone.radius) then
                return true
            end
        end
        return false
    end

    --- takes a x, y poistion and checks if it is inside any of the zones
    ---@param zone_name string
    ---@param parent_zone_name string
    ---@return boolean result
    function DCS_UTIL.isZoneInZone(zone_name, parent_zone_name)
        local zoneA = DCS_UTIL.__trigger_zones[zone_name]
        local zoneB = DCS_UTIL.__trigger_zones[parent_zone_name]

        if zoneB.zone_type == DCS_UTIL.ZoneType.Polygon and zoneB.verts then
            if DCS_UTIL.IsPointInPolygon(zoneB.verts, zoneA.x, zoneA.z) == true then
                return true
            end
        else
            if (((zoneA.x - zoneB.x) ^ 2 + (zoneA.z - zoneB.z) ^ 2) ^ 0.5 <= zoneB.radius) then
                return true
            end
        end
        return false
    end

    --- takes a x, y poistion and checks if it is inside any of the zones
    ---@param x number North South position
    ---@param z number West East position
    ---@param zone table { x, z, zonetype,  radius }
    ---@return boolean result
    function DCS_UTIL.isPositionInCustomZone(x, z, zone)
        if zone.zone_type == DCS_UTIL.ZoneType.Polygon and zone.verts then
            if DCS_UTIL.IsPointInPolygon(zone.verts, x, z) == true then
                return true
            end
        else
            if (((x - zone.x) ^ 2 + (z - zone.z) ^ 2) ^ 0.5 <= zone.radius) then
                return true
            end
        end
        return false
    end

    ---comment
    ---@param zone_name any
    ---@return table? zone { name,b zone_type, x, z, radius, verts }
    function DCS_UTIL.getZoneByName(zone_name)
        if zone_name == nil then return nil end
        return DCS_UTIL.__trigger_zones[zone_name]
    end

    ---maps the category name to the DCS group category
    ---@param input string the name
    ---@return integer?
    function DCS_UTIL.stringToGroupCategory(input)
        input = string.lower(input)
        if input == 'airplane' or input == 'plane' then
            return DCS_UTIL.GroupCategory.AIRPLANE
        end
        if input == 'helicopter' then
            return DCS_UTIL.GroupCategory.HELICOPTER
        end
        if input == 'ground' or input == 'vehicle' then
            return DCS_UTIL.GroupCategory.GROUND
        end
        if input == 'ship' then
            return DCS_UTIL.GroupCategory.SHIP
        end
        if input == 'train' then
            return DCS_UTIL.GroupCategory.TRAIN
        end
        if input == "static" then
            return DCS_UTIL.GroupCategory.STATIC
        end
        return nil;
    end

    --- get the group config as per start of the mission
    --- group = {
    ---     category,
    ---     country_id,
    ---     group_template
    --- }
    ---@param groupname string groupName you're looking for
    function DCS_UTIL.GetMizGroupOrDefault(groupname, default)
        local group = DCS_UTIL.__miz_groups[groupname]
        if group == nil then
            return default
        end
        return group
    end

    ---comment Get all group names. Can be a LOT
    ---Includes statics
    ---@return table groups
    function DCS_UTIL.getAllGroupNames()
        return DCS_UTIL.__groupNames
    end

    ---comment Get all BLUE group names. Can be a LOT
    ---Includes statics
    ---@return table groups
    function DCS_UTIL.getAllBlueGroupNames()
        return DCS_UTIL.__blueGroupNames
    end

    ---comment Get all RED group names. Can be a LOT
    ---Includes statics
    ---@return table groups
    function DCS_UTIL.getAllRedGroupNames()
        return DCS_UTIL.__redGroupNames
    end

    ---comment Get all units that are players
    ---@return table units
    function DCS_UTIL.getAllPlayerUnits()
        local units = {}
        for key, value in pairs({ 1, 2, 3 }) do
            local players = coalition.getPlayers(value)
            for key, unit in pairs(players) do
                units[#units + 1] = unit
            end
        end
        return units
    end

    ---get base name from ID
    ---@param baseId number
    ---@return string? name
    function DCS_UTIL.getAirbaseName(baseId)
        local stringified = tostring(baseId)
        return DCS_UTIL.__airbaseNamesById[stringified]
    end

    ---get base from id
    ---@param baseId number
    ---@return table? table
    function DCS_UTIL.getAirbaseById(baseId)
        local name = DCS_UTIL.getAirbaseName(baseId)
        if name == nil then return nil end
        return Airbase.getByName(name)
    end

    ---Get the starting coalition of a farp or airbase
    ---@return number? coalition
    function DCS_UTIL.getStartingCoalition(baseId)
        if baseId == nil then
            return nil
        end

        --STRING based dictionary otherwise it'll be a string/collapsed array
        baseId = tostring(baseId) or "nil"

        local result = DCS_UTIL.__airportsStartingCoalition[baseId]
        if result == nil then
            result = DCS_UTIL.__warehouseStartingCoalition[baseId]
        end
        return result
    end

    ---Gets all groups that have players
    ---@return table groups
    function DCS_UTIL.getAllPlayerGroups()
        local groupNames = {}
        local result = {}
        for key, value in pairs({ 1, 2, 3 }) do
            local players = coalition.getPlayers(value)
            for key, unit in pairs(players) do
                local group = unit:getGroup()
                if group ~= nil then
                    local name = group:getName()
                    if name ~= nil then
                        if groupNames[name] ~= nil then
                            groupNames[name] = 1
                            table.insert(result, group)
                        end
                    end
                end
            end
        end
        return result
    end

    --- spawns the units as specified in the mission file itself
    --- location and route can be nil and will then use default route
    ---@param groupName string
    ---@param location table? vector 3 data. { x , z, alt }
    ---@param route table? route of the group. If nil wil be the default route.
    ---@param uncontrolled boolean? Sets the group to be uncontrolled on spawn
    ---@return table? new_group the Group class that was spawned
    function DCS_UTIL.SpawnGroupTemplate(groupName, location, route, uncontrolled)
        if groupName == nil then
            return
        end

        local template = DCS_UTIL.GetMizGroupOrDefault(groupName, nil)
        if template == nil then
            return nil
        end
        if template.category == DCS_UTIL.GroupCategory.STATIC then
            --TODO: Implement location and route stuff
            local spawn_template = template.group_template
            coalition.addStaticObject(template.country_id, spawn_template)
        else
            local spawn_template = template.group_template
            if location ~= nil then
                local x_offset
                if location.x ~= nil then x_offset = spawn_template.x - location.x end

                local y_offset
                if location.z ~= nil then y_offset = spawn_template.y - location.z end

                spawn_template.x = location.x
                spawn_template.y = location.z

                for i, unit in pairs(spawn_template.units) do
                    unit.x = unit.x - x_offset
                    unit.y = unit.y - y_offset
                    unit.alt = location.alt
                end
            end

            if route ~= nil then
                spawn_template.route = route
            end

            if uncontrolled ~= nil then
                spawn_template.uncontrolled = uncontrolled
            end
            local new_group = coalition.addGroup(template.country_id, template.category, spawn_template)
            return new_group
        end
    end

    function DCS_UTIL.IsBingoFuel(groupName, offset)
        if offset == nil then offset = 0 end
        local bingoSetting = 0.20
        bingoSetting = bingoSetting + offset

        local group = Group.getByName(groupName)
        for _, unit in pairs(group:getUnits()) do
            if unit and unit:isExist() == true and unit:inAir() == true and unit:getFuel() < bingoSetting then
                return true
            end
        end
        return false
    end

    DCS_UTIL.__INIT();
end
Spearhead.DcsUtil = DCS_UTIL

local LOGGER = {}
do
    LOGGER.LogLevelOptions = {
        DEBUG = 0,
        INFO = 1,
        WARN = 2,
        ERROR = 3,
        NONE = 4
    }

    local PreFix = "Spearhead"

    function LOGGER:new(logger_name, logLevel, liveLoggingLevel)
        local o = {}
        setmetatable(o, { __index = self })
        o.LoggerName = logger_name or "(loggername not set)"
        o.LogLevel = logLevel or LOGGER.LogLevelOptions.INFO
        o.LiveLoggingLevel = liveLoggingLevel or LOGGER.LogLevelOptions.NONE

        ---comment
        ---@param self table self logger
        ---@param message any the message
        o.info = function(self, message)
            if message == nil then
                return
            end
            message = UTIL.toString(message)

            if self.LogLevel <= LOGGER.LogLevelOptions.INFO then
                env.info("[" .. PreFix .. "]" .. "[" .. self.LoggerName .. "] " .. message)
            end

            if self.LiveLoggingLevel <= LOGGER.LogLevelOptions.INFO then
                trigger.action.outText(message, 20)
            end
        end

        ---comment
        ---@param message string
        o.warn = function(self, message)
            if message == nil then
                return
            end
            message = UTIL.toString(message)

            if self.LogLevel <= LOGGER.LogLevelOptions.WARN then
                env.warning("[" .. PreFix .. "]" .. "[" .. self.LoggerName .. "] " .. message)
            end

            if self.LiveLoggingLevel <= LOGGER.LogLevelOptions.WARN then
                trigger.action.outText(message, 20)
            end
        end

        ---comment
        ---@param self table -- logger
        ---@param message any -- the message
        o.error = function(self, message)
            if message == nil then
                return
            end

            message = UTIL.toString(message)

            if self.LogLevel <= LOGGER.LogLevelOptions.ERROR then
                env.error("[" .. PreFix .. "]" .. "[" .. self.LoggerName .. "] " .. message)
            end

            if self.LiveLoggingLevel <= LOGGER.LogLevelOptions.ERROR then
                trigger.action.outText(message, 20)
            end
        end

        ---write debug
        ---@param self table
        ---@param message any the message
        o.debug = function(self, message)
            if message == nil then
                return
            end

            message = UTIL.toString(message)
            if self.LogLevel <= LOGGER.LogLevelOptions.DEBUG then
                env.info("[" .. PreFix .. "]" .. "[" .. self.LoggerName .. "][DEBUG] " .. message)
            end

            if self.LiveLoggingLevel <= LOGGER.LogLevelOptions.DEBUG then
                trigger.action.outText(message, 20)
            end
        end


        return o
    end
end
Spearhead.LoggerTemplate = LOGGER

local ROUTE_UTIL = {}
do --setup route util
    ---comment
    ---@param attackHelos boolean
    ---@return table
    local function GetCAPTargetTypes(attackHelos)
        local targetTypes = {
            [1] = "Planes",
        }

        if attackHelos then
            targetTypes[2] = "Helicopters"
        end

        return targetTypes
    end

    ---comment
    ---@param airdromeId number
    ---@param basePoint table { x, z, y } (y == alt)
    ---@param speed number the speed
    ---@return table task
    local RtbTask = function(airdromeId, basePoint, speed)
        if basePoint == nil then
            basePoint = Spearhead.Util.getAirbaseById(airdromeId):getPoint()
        end

        return {
            alt = basePoint.y,
            action = "Landing",
            alt_type = "BARO",
            speed = speed,
            ETA = 0,
            ETA_locked = false,
            x = basePoint.x,
            y = basePoint.z,
            speed_locked = true,
            formation_template = "",
            airdromeId = airdromeId,
            type = "Land",
            task = {
                id = "ComboTask",
                params = {
                    tasks = {}
                }
            }
        }
    end

    ---comment
    ---@param groupName string
    ---@param position table { x, y}
    ---@param altitude number
    ---@param speed number
    ---@param duration number
    ---@param engageHelos boolean
    ---@param pattern string ["Race-Track"|"Circle"]
    ---@return table
    local CapTask = function(groupName, position, altitude, speed, duration, engageHelos, deviationdistance, pattern)
        local durationBefore10 = duration - 600
        if durationBefore10 < 0 then durationBefore10 = 0 end
        local durationAfter10 = 600
        if duration < 600 then
            durationAfter10 = duration
        end

        return {
            alt = altitude,
            action = "Turning Point",
            alt_type = "BARO",
            speed = speed,
            ETA = 0,
            ETA_locked = false,
            x = position.x,
            y = position.z,
            speed_locked = true,
            formation_template = "",
            task = {
                id = "ComboTask",
                params = {
                    tasks = {
                        [1] = {
                            number = 1,
                            auto = false,
                            id = "WrappedAction",
                            enabled = "true",
                            params = {
                                action = {
                                    id = "Script",
                                    params = {
                                        command = "pcall(Spearhead.Events.PublishOnStation, \"" .. groupName .. "\")"
                                    }
                                }
                            }
                        },
                        [2] = {
                            id = 'EngageTargets',
                            params = {
                                maxDist = deviationdistance,
                                maxDistEnabled = deviationdistance >= 0, -- required to check maxDist
                                targetTypes = GetCAPTargetTypes(engageHelos),
                                priority = 0
                            }
                        },
                        [3] = {
                            number = 3,
                            auto = false,
                            id = "ControlledTask",
                            enabled = true,
                            params = {
                                task = {
                                    id = "Orbit",
                                    params = {
                                        altitude = altitude,
                                        pattern = pattern,
                                        speed = speed,
                                    }
                                },
                                stopCondition = {
                                    duration = durationBefore10,
                                    condition = "return Spearhead.DcsUtil.IsBingoFuel(\"" .. groupName .. "\", 0.10)",
                                }
                            }
                        },
                        [4] = {
                            number = 4,
                            auto = false,
                            id = "WrappedAction",
                            enabled = "true",
                            params = {
                                action = {
                                    id = "Script",
                                    params = {
                                        command = "pcall(Spearhead.Events.PublishRTBInTen, \"" .. groupName .. "\")"
                                    }
                                }
                            }
                        },
                        [5] = {
                            number = 5,
                            auto = false,
                            id = "ControlledTask",
                            enabled = true,
                            params = {
                                task = {
                                    id = "Orbit",
                                    params = {
                                        altitude = altitude,
                                        pattern = pattern,
                                        speed = speed,
                                    }
                                },
                                stopCondition = {
                                    duration = durationAfter10,
                                    condition = "return Spearhead.DcsUtil.IsBingoFuel(\"" .. groupName .. "\")",
                                }
                            }
                        },
                        [6] = {
                            number = 6,
                            auto = false,
                            id = "WrappedAction",
                            enabled = "true",
                            params = {
                                action = {
                                    id = "Script",
                                    params = {
                                        command = "pcall(Spearhead.Events.PublishRTB, \"" .. groupName .. "\")"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    end

    ---comment
    ---@param position table { x, y}
    ---@param altitude number
    ---@param speed number
    ---@param childTasks table
    ---@return table
    local FlyToPointTask = function(position, altitude, speed, childTasks)
        return {
            alt = altitude,
            action = "Turning Point",
            alt_type = "BARO",
            speed = speed,
            ETA = 0,
            ETA_locked = false,
            x = position.x,
            y = position.z,
            speed_locked = true,
            formation_template = "",
            task = {
                id = "ComboTask",
                params = {
                    tasks = childTasks or {}
                }
            }
        }
    end

    ---comment
    ---@param groupName string groupName you're creating this route for
    ---@param airdromeId number airdromeId
    ---@param capPoint table { x, z }
    ---@param altitude number
    ---@param speed number
    ---@param durationOnStation number
    ---@param attackHelos boolean
    ---@param deviationDistance number
    ---@return table route
    ROUTE_UTIL.createCapMission = function(groupName, airdromeId, capPoint, racetrackSecondPoint, altitude, speed,
                                           durationOnStation, attackHelos, deviationDistance)
        local baseName = Spearhead.DcsUtil.getAirbaseName(airdromeId)
        if baseName == nil then
            return {}
        end

        durationOnStation = durationOnStation or 1800
        altitude = altitude or 3000
        speed = speed or 130
        attackHelos = attackHelos or false
        deviationDistance = deviationDistance or 32186

        local base = Airbase.getByName(baseName)
        if base == nil then
            return {}
        end

        local additionalFlyOverTasks = {
            {
                enabled = true,
                auto = false,
                id = "WrappedAction",
                number = 1,
                params = {
                    action = {
                        id = "Option",
                        params = {
                            variantIndex = 2,
                            name = AI.Option.Air.id.FORMATION,
                            formationIndex = 2,
                            value = 131074
                        }
                    }
                }
            }
        }

        local orbitType = "Circle"
        if racetrackSecondPoint then orbitType = "Race-Track" end

        local basePoint = base:getPoint()
        local points = {}
        if racetrackSecondPoint == nil then
            points = {
                [1] = FlyToPointTask(capPoint, altitude, speed, additionalFlyOverTasks),
                [2] = CapTask(groupName, capPoint, altitude, speed, durationOnStation, attackHelos, deviationDistance,
                    orbitType),
                [3] = RtbTask(airdromeId, basePoint, speed)
            }
        else
            points = {
                [1] = FlyToPointTask(capPoint, altitude, speed, additionalFlyOverTasks),
                [2] = CapTask(groupName, capPoint, altitude, speed, durationOnStation, attackHelos, deviationDistance,
                    orbitType),
                [3] = FlyToPointTask(racetrackSecondPoint, altitude, speed, {}),
                [4] = RtbTask(airdromeId, basePoint, speed)
            }
        end

        return {
            id = 'Mission',
            params = {
                airborne = true,
                route = {
                    points = points
                }
            }
        }
    end

    ---Creates an RTB task. The first point is to trigger the TDCS OnRTB Event, the second task will be the actual RTB point
    ---If any of the values are not met it will return nil
    ---@param groupName string
    ---@param airdromeId number
    ---@param speed number
    ---@return table?, string ComboTask
    ROUTE_UTIL.CreateRTBMission = function(groupName, airdromeId, speed)
        --[[
            TODO: Test the creation and pubishing of event and the timing of said event
        ]] --

        local base = Spearhead.DcsUtil.getAirbaseById(airdromeId)
        if base == nil then
            return nil, "No airbase found for ID " .. tostring(airdromeId)
        end

        local group = Group.getByName(groupName)
        local pos;
        local i = 1
        local units = group:getUnits()
        while pos == nil and i <= Spearhead.Util.tableLength(units) do
            local unit = units[i]
            if unit and unit:isExist() == true and unit:inAir() == true then
                pos = unit:getPoint()
            end
            i = i + 1
        end

        speed = speed or 130
        if pos == nil then
            return nil, "Could not find any unit in the air to set the RTB task"
        end

        local additionalFlyOverTasks = {
            {
                enabled = true,
                auto = false,
                id = "WrappedAction",
                number = 1,
                params = {
                    action = {
                        id = "Option",
                        params = {
                            variantIndex = 2,
                            name = AI.Option.Air.id.FORMATION,
                            formationIndex = 2,
                            value = 131074
                        }
                    }
                }
            }
        }

        return {
            id = "Mission",
            params = {
                airborne = true, -- RTB mission generally are given to airborne units
                route = {
                    points = {

                        [1] = {
                            alt = pos.y,
                            action = "Turning Point",
                            alt_type = "BARO",
                            speed = speed,
                            ETA = 0,
                            ETA_locked = false,
                            x = pos.x,
                            y = pos.z,
                            speed_locked = true,
                            formation_template = "",
                            task = {
                                id = "ComboTask",
                                params = {
                                    tasks = {
                                        [1] = {
                                            number = 1,
                                            auto = false,
                                            id = "WrappedAction",
                                            enabled = "true",
                                            params = {
                                                action = {
                                                    id = "Script",
                                                    params = {
                                                        command = "pcall(Spearhead.Events.PublishRTB, \"" ..
                                                            groupName .. "\")"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        },
                        [2] = FlyToPointTask(base:getPoint(), 600, speed, additionalFlyOverTasks),
                        [3] = RtbTask(airdromeId, base:getPoint(), speed)
                    }
                }
            }
        }, ""
    end

    ROUTE_UTIL.CreateCarrierRacetrack = function(pointA, pointB)
        return {
            id = "Mission",
            params = {
                airborne = false,
                route = {
                    points = {
                        [1] =
                        {
                            ["alt"] = -0,
                            ["type"] = "Turning Point",
                            ["ETA"] = 0,
                            ["alt_type"] = "BARO",
                            ["formation_template"] = "",
                            ["y"] = pointA.z,
                            ["x"] = pointA.x,
                            ["ETA_locked"] = false,
                            ["speed"] = 13.88888,
                            ["action"] = "Turning Point",
                            ["task"] =
                            {
                                ["id"] = "ComboTask",
                                ["params"] =
                                {
                                    ["tasks"] = {},
                                }, -- end of ["params"]
                            }, -- end of ["task"]
                            ["speed_locked"] = true,
                        },
                        [2] =
                        {
                            ["alt"] = -0,
                            ["type"] = "Turning Point",
                            ["ETA"] = -0,
                            ["alt_type"] = "BARO",
                            ["formation_template"] = "",
                            ["y"] = pointB.z,
                            ["x"] = pointB.x,
                            ["ETA_locked"] = false,
                            ["speed"] = 13.88888,
                            ["action"] = "Turning Point",
                            ["task"] =
                            {
                                ["id"] = "ComboTask",
                                ["params"] =
                                {
                                    ["tasks"] =
                                    {
                                        [1] =
                                        {
                                            ["enabled"] = true,
                                            ["auto"] = false,
                                            ["id"] = "GoToWaypoint",
                                            ["number"] = 1,
                                            ["params"] =
                                            {
                                                ["fromWaypointIndex"] = 2,
                                                ["nWaypointIndx"] = 1,
                                            },
                                        },
                                    },
                                },
                            },
                            ["speed_locked"] = true,
                        }
                    }
                }
            }
        }, ""
    end
end

Spearhead.RouteUtil = ROUTE_UTIL

local SpearheadEvents = {}
do
    local SpearheadLogger = Spearhead.LoggerTemplate:new("Spearhead Events",
        Spearhead.LoggerTemplate.LogLevelOptions.INFO)

    do -- STAGE NUMBER CHANGED
        local OnStageNumberChangedListeners = {}
        local OnStageNumberChangedHandlers = {}

        ---Add a stage zone number changed listener
        ---@param listener table object with function OnStageNumberChanged(self, number)
        SpearheadEvents.AddStageNumberChangedListener = function(listener)
            if type(listener) ~= "table" then
                SpearheadLogger:warn("Event listener not of type table, did you mean to use handler?")
                return
            end
            table.insert(OnStageNumberChangedListeners, listener)
        end

        ---Add a stage zone number changed listener
        ---@param handler function function(number)
        SpearheadEvents.AddStageNumberChangedHandler = function(handler)
            if type(handler) ~= "function" then
                SpearheadLogger:warn("Event handler not of type function, did you mean to use listener?")
                return
            end
            table.insert(OnStageNumberChangedHandlers, handler)
        end

        ---@param newStageNumber number
        SpearheadEvents.PublishStageNumberChanged = function(newStageNumber)
            for _, callable in pairs(OnStageNumberChangedListeners) do
                local succ, err = pcall(function()
                    callable:OnStageNumberChanged(newStageNumber)
                end)
                if err then
                    SpearheadLogger:error(err)
                end
            end

            for _, callable in pairs(OnStageNumberChangedHandlers) do
                local succ, err = pcall(callable, newStageNumber)
                if err then
                    SpearheadLogger:error(err)
                end
            end
        end
    end

    local onLandEventListeners = {}
    ---Add an event listener to a specific unit
    ---@param unitName string to call when the unit lands
    ---@param landListener table table with function OnUnitLanded(self, initiatorUnit, airbase)
    SpearheadEvents.addOnUnitLandEventListener = function(unitName, landListener)
        if type(landListener) ~= "table" then
            SpearheadLogger:warn("Event handler not of type table/object")
            return
        end

        SpearheadLogger:debug("Added Land event handler for unit: " .. unitName)

        if onLandEventListeners[unitName] == nil then
            onLandEventListeners[unitName] = {}
        end
        table.insert(onLandEventListeners[unitName], landListener)
    end

    local OnUnitLostListeners = {}
    ---This listener gets fired for any event that can indicate a loss of a unit.
    ---Such as: Eject, Crash, Dead, Unit_Lost,
    ---@param unitName any
    ---@param unitLostListener table Object with function: OnUnitLost(initiatorUnit)
    SpearheadEvents.addOnUnitLostEventListener = function(unitName, unitLostListener)
        if type(unitLostListener) ~= "table" then
            SpearheadLogger:warn("Unit lost Event listener not of type table/object")
            return
        end

        if OnUnitLostListeners[unitName] == nil then
            OnUnitLostListeners[unitName] = {}
        end

        table.insert(OnUnitLostListeners[unitName], unitLostListener)
    end

    do -- ON RTB
        local OnGroupRTBListeners = {}
        ---Adds a function to the events listener that triggers when a group publishes themselves RTB.
        ---This is only available when a ROUTE is created via the Spearhead.RouteUtil
        ---@param groupName string the groupname to expect
        ---@param handlingObject table object with OnGroupRTB(self, groupName)
        SpearheadEvents.addOnGroupRTBListener = function(groupName, handlingObject)
            if type(handlingObject) ~= "table" then
                SpearheadLogger:warn("Event handler not of type table/object")
                return
            end

            if OnGroupRTBListeners[groupName] == nil then
                OnGroupRTBListeners[groupName] = {}
            end

            table.insert(OnGroupRTBListeners[groupName], handlingObject)
        end

        ---Publish the Group to RTB
        ---@param groupName string
        SpearheadEvents.PublishRTB = function(groupName)
            SpearheadLogger:debug("Publishing RTB event for group " .. groupName)
            if groupName ~= nil then
                if OnGroupRTBListeners[groupName] then
                    for _, callable in pairs(OnGroupRTBListeners[groupName]) do
                        local succ, err = pcall(function()
                            callable:OnGroupRTB(groupName)
                        end)
                        if err then
                            SpearheadLogger:error(err)
                        end
                    end
                end
            end
        end

        local OnGroupRTBInTenListeners = {}
        ---Adds a function to the events listener that triggers when a group publishes themselves RTB.
        ---This is only available when a ROUTE is created via the Spearhead.RouteUtil
        ---@param groupName string the groupname to expect
        ---@param handlingObject table object with OnGroupRTBInTen(self, groupName)
        SpearheadEvents.addOnGroupRTBInTenListener = function(groupName, handlingObject)
            if type(handlingObject) ~= "table" then
                SpearheadLogger:warn("Event handler not of type table/object")
                return
            end

            if OnGroupRTBInTenListeners[groupName] == nil then
                OnGroupRTBInTenListeners[groupName] = {}
            end

            table.insert(OnGroupRTBInTenListeners[groupName], handlingObject)
        end

        ---Publish the Group is RTB
        ---@param groupName string
        SpearheadEvents.PublishRTBInTen = function(groupName)
            SpearheadLogger:debug("Publishing RTB in TEN event for group " .. groupName)
            if groupName ~= nil then
                if OnGroupRTBInTenListeners[groupName] then
                    for _, callable in pairs(OnGroupRTBInTenListeners[groupName]) do
                        local succ, err = pcall(function()
                            callable:OnGroupRTBInTen(groupName)
                        end)
                        if err then
                            SpearheadLogger:error(err)
                        end
                    end
                end
            end
        end
    end

    do -- ON Station
        local OnGroupOnStationListeners = {}
        ---Adds a function to the events listener that triggers when a group publishes themselves RTB.
        ---This is only available when a ROUTE is created via the Spearhead.RouteUtil
        ---@param groupName string the groupname to expect
        SpearheadEvents.addOnGroupOnStationListener = function(groupName, handlingObject)
            if type(handlingObject) ~= "table" then
                SpearheadLogger:warn("Event handler not of type table/object")
                return
            end

            if OnGroupOnStationListeners[groupName] == nil then
                OnGroupOnStationListeners[groupName] = {}
            end

            table.insert(OnGroupOnStationListeners[groupName], handlingObject)
        end

        ---Publish the Group to RTB
        ---@param groupName string
        SpearheadEvents.PublishOnStation = function(groupName)
            SpearheadLogger:debug("Publishing onStation event for group " .. groupName)
            if groupName ~= nil then
                if OnGroupOnStationListeners[groupName] then
                    for _, callable in pairs(OnGroupOnStationListeners[groupName]) do
                        local succ, err = pcall(function()
                            callable:OnGroupOnStation(groupName)
                        end)
                        if err then
                            SpearheadLogger:error(err)
                        end
                    end
                end
            end
        end
    end

    do     --COMMANDS
        do -- status updates
            local onStatusRequestReceivedListeners = {}
            ---comment
            ---@param listener table object with OnStatusRequestReceived(self, groupId)
            SpearheadEvents.AddOnStatusRequestReceivedListener = function(listener)
                if type(listener) ~= "table" then
                    SpearheadLogger:warn("Unit lost Event listener not of type table/object")
                    return
                end

                table.insert(onStatusRequestReceivedListeners, listener)
            end

            local triggerStatusRequestReceived = function(groupId)
                for _, callable in pairs(onStatusRequestReceivedListeners) do
                    local succ, err = pcall(function()
                        callable:OnStatusRequestReceived(groupId)
                    end)
                end
            end

            SpearheadEvents.AddCommandsToGroup = function(groupId)
                local base = "MISSIONS"
                if groupId then
                    missionCommands.addCommandForGroup(groupId, "Stage Status", nil, triggerStatusRequestReceived,
                        groupId)
                end
            end

            --Single player purpose
            local id = net.get_my_player_id()
            if id == 0 then
                SpearheadLogger:info("Single Player detected")

                local unit = world.getPlayer()
                if unit then
                    local groupId = unit:getGroup():getID()
                    SpearheadEvents.AddCommandsToGroup(groupId)

                    --DEBUG COMMANDS
                    do
                        local activateStage = function(number)
                            SpearheadEvents.PublishStageNumberChanged(number)
                        end

                        missionCommands.addSubMenuForGroup(groupId, "debug", nil)
                        missionCommands.addSubMenuForGroup(groupId, "Set Stage", { "debug" })

                        for i = 0, 9 do
                            local menuName = tostring(i) .. ".."
                            missionCommands.addSubMenuForGroup(groupId, menuName, { "debug", "Set Stage" })
                            for ii = 0, 9 do
                                local number = tonumber(tostring(i) .. tostring(ii))
                                missionCommands.addCommandForGroup(groupId, "Stage " .. tostring(number),
                                { "debug", "Set Stage", menuName }, activateStage, number)
                            end
                        end
                    end
                end
            end
        end
    end

    do -- PLAYER ENTER UNIT
        local playerEnterUnitListeners = {}
        ---comment
        ---@param listener table object with OnPlayerEnterUnit(self, unit)
        SpearheadEvents.AddOnPlayerEnterUnitListener = function(listener)
            if type(listener) ~= "table" then
                SpearheadLogger:warn("Unit lost Event listener not of type table/object")
                return
            end

            table.insert(playerEnterUnitListeners, listener)
        end

        SpearheadEvents.TriggerPlayerEntersUnit = function(unit)
            if unit ~= nil then
                if playerEnterUnitListeners then
                    for _, callable in pairs(playerEnterUnitListeners) do
                        local succ, err = pcall(function()
                            callable:OnPlayerEnterUnit(unit)
                        end)
                        if err then
                            SpearheadLogger:error(err)
                        end
                    end
                end
            end
        end
    end

    local e = {}
    function e:onEvent(event)
        if event.id == world.event.S_EVENT_LAND or event.id == world.event.S_EVENT_RUNWAY_TOUCH then
            local unit = event.initiator
            local airbase = event.place
            if unit ~= nil then
                local name = unit:getName()
                if onLandEventListeners[name] then
                    for _, callable in pairs(onLandEventListeners[name]) do
                        local succ, err = pcall(function()
                            callable:OnUnitLanded(unit, airbase)
                        end)
                        if err then
                            SpearheadLogger:error(err)
                        end
                    end
                end
            end
        end

        if event.id == world.event.S_EVENT_DEAD or
            event.id == world.event.S_EVENT_CRASH or
            event.id == world.event.S_EVENT_EJECTION or
            event.id == world.event.S_EVENT_UNIT_LOST then
            local object = event.initiator
            if object and object.getName and OnUnitLostListeners[object:getName()] then
                for _, callable in pairs(OnUnitLostListeners[object:getName()]) do
                    local succ, err = pcall(function()
                        callable:OnUnitLost(object)
                    end)

                    if err then
                        SpearheadLogger:error(err)
                    end
                end
            end
        end

        if event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
            env.info("blaat player entering unit")
            local groupId = event.initiator:getGroup():getID()
            SpearheadEvents.AddCommandsToGroup(groupId)
        end
    end

    world.addEventHandler(e)
end
Spearhead.Events = SpearheadEvents

Spearhead.MissionEditingWarnings = {}
function Spearhead.AddMissionEditorWarning(warningMessage)
    table.insert(Spearhead.MissionEditingWarnings, warningMessage or "skip")
end

missionCommands.addSubMenu("Missions")

local loadDone = false
Spearhead.LoadingDone = function()
    if loadDone == true then
        return
    end

    local warningLogger = Spearhead.LoggerTemplate:new("MISSIONPARSER", Spearhead.LoggerTemplate.LogLevelOptions.INFO, 4)
    if Spearhead.Util.tableLength(Spearhead.MissionEditingWarnings) > 0 then
        for key, message in pairs(Spearhead.MissionEditingWarnings) do
            warningLogger:warn(message)
        end
    else
        warningLogger:info("No issues detected")
    end

    loadDone = true
end

end --spearhead_base.lua
do --spearhead_db.lua
-- 3

local SpearheadDB = {}
do -- DB

    local singleton = nil

    ---comment
    ---@param Logger table
    ---@return table
    function SpearheadDB:new(Logger)
        if singleton ~= nil then
            Logger:info("Returning an already initiated instance of SpearheadDB")
            return singleton
        end

        local o = {}
        setmetatable(o, { __index = self })

        o.Logger = Logger
        o.tables = {}
        do --INIT ALL TABLES
            Logger:debug("Initiating tables")
        
            o.tables.all_zones = {}
            o.tables.stage_zones = {}
            o.tables.mission_zones = {}
            o.tables.random_mission_zones = {}
            o.tables.farp_zones = {}
            o.tables.cap_route_zones = {}
            o.tables.carrier_route_zones = {}

            o.tables.stage_zonesByNumer = {}
            o.tables.stage_numberPerzone = {}

            do -- INIT ZONE TABLES
                if env.mission.triggers and env.mission.triggers.zones then
                    for zone_ind, zone_data in pairs(env.mission.triggers.zones) do
                        local zone_name = zone_data.name
                        local split_string = Spearhead.Util.split_string(zone_name, "_")
                        table.insert(o.tables.all_zones, zone_name)

                        if string.lower(split_string[1]) == "missionstage" then
                            table.insert(o.tables.stage_zones, zone_name)
                            if split_string[2] then
                                local stringified = tostring(split_string[2]) or "unknown"
                                if o.tables.stage_zonesByNumer[stringified] == nil then
                                    o.tables.stage_zonesByNumer[stringified] = {}
                                end
                                table.insert(o.tables.stage_zonesByNumer[stringified], zone_name)
                                o.tables.stage_numberPerzone[zone_name] = stringified
                            end
                        end

                        if string.lower(split_string[1]) == "mission" then
                            table.insert(o.tables.mission_zones, zone_name)
                        end

                        if string.lower(split_string[1]) == "randommission" then
                            table.insert(o.tables.random_mission_zones, zone_name)
                        end

                        if string.lower(split_string[1]) == "farp" then
                            table.insert(o.tables.farp_zones, zone_name)
                        end

                        if string.lower(split_string[1]) == "caproute" then
                            table.insert(o.tables.cap_route_zones, zone_name)
                        end

                        if string.lower(split_string[1]) == "carrierroute" then
                            table.insert(o.tables.carrier_route_zones, zone_name)
                        end
                    end
                end
            end

            Logger:debug("initiated zone tables, continuing with descriptions")
            o.tables.descriptions = {}
            do --load markers
                if env.mission.drawings and env.mission.drawings.layers then
                    for i, layer in pairs(env.mission.drawings.layers) do
                        if string.lower(layer.name) == "author" then
                            for key, layer_object in pairs(layer.objects) do
                                local inZone = Spearhead.DcsUtil.isPositionInZones(layer_object.mapX, layer_object.mapY, o.tables.mission_zones)
                                if Spearhead.Util.tableLength(inZone) >= 1 then
                                    local name = inZone[1]
                                    if name ~= nil then
                                        o.tables.descriptions[name] = layer_object.text
                                    end
                                end

                                local inZone = Spearhead.DcsUtil.isPositionInZones(layer_object.mapX, layer_object.mapY, o.tables.random_mission_zones)
                                if Spearhead.Util.tableLength(inZone) >= 1 then
                                    local name = inZone[1]
                                    if name ~= nil then
                                        o.tables.descriptions[name] = layer_object.text
                                    end
                                end
                            end
                        end
                    end
                end
            end

            o.tables.missionZonesPerStage = {}
            for key, missionZone in pairs(o.tables.mission_zones) do
                local found = false
                local i = 1
                while found == false and i <= Spearhead.Util.tableLength(o.tables.stage_zones) do
                    local stageZone = o.tables.stage_zones[i]
                    if Spearhead.DcsUtil.isZoneInZone(missionZone, stageZone) == true then
                        if o.tables.missionZonesPerStage[stageZone] == nil then
                            o.tables.missionZonesPerStage[stageZone] = {}
                        end
                        table.insert(o.tables.missionZonesPerStage[stageZone], missionZone)
                    end
                    i = i + 1
                end
            end

            o.tables.randomMissionZonesPerStage = {}
            for key, missionZone in pairs(o.tables.random_mission_zones) do
                local found = false
                local i = 1
                while found == false and i <= Spearhead.Util.tableLength(o.tables.stage_zones) do
                    local stageZone = o.tables.stage_zones[i]
                    if Spearhead.DcsUtil.isZoneInZone(missionZone, stageZone) == true then
                        if o.tables.randomMissionZonesPerStage[stageZone] == nil then
                            o.tables.randomMissionZonesPerStage[stageZone] = {}
                        end
                        table.insert(o.tables.randomMissionZonesPerStage[stageZone], missionZone)
                    end
                    i = i + 1
                end
            end

            local isAirbaseInZone = {}
            o.tables.airbasesPerStage = {}
            o.tables.farpIdsInFarpZones = {}
            local airbases = world.getAirbases()
            for _, airbase in pairs(airbases) do
                local baseId = airbase:getID()
                local point = airbase:getPoint()
                local found = false
                for _, zoneName in pairs(o.tables.stage_zones) do
                    if found == false then
                        if Spearhead.DcsUtil.isPositionInZone(point.x, point.z, zoneName) == true then
                            found = true
                            local baseIdString = tostring(baseId) or "nil"
                            isAirbaseInZone[baseIdString] = true

                            if airbase:getDesc().category == 0 then
                                --Airbase 
                                if Spearhead.DcsUtil.getStartingCoalition(baseId) == 2 then
                                    airbase:setCoalition(1)
                                    airbase:autoCapture(false)
                                end

                                if o.tables.airbasesPerStage[zoneName] == nil then
                                    o.tables.airbasesPerStage[zoneName] = {}
                                end

                                table.insert(o.tables.airbasesPerStage[zoneName], baseId)
                            else
                                -- farp
                                local i = 1
                                local farpFound = false
                                while farpFound == false and i <= Spearhead.Util.tableLength(o.tables.farp_zones) do
                                    local farpZoneName = o.tables.farp_zones[i]
                                    if Spearhead.DcsUtil.isPositionInZone(point.x, point.z, farpZoneName) == true then
                                        farpFound = true

                                        if o.tables.farpIdsInFarpZones[farpZoneName] == nil then
                                            o.tables.farpIdsInFarpZones[farpZoneName] = {}
                                        end

                                        airbase:setCoalition(1)
                                        airbase:autoCapture(false)
                                        table.insert(o.tables.farpIdsInFarpZones[farpZoneName], baseIdString)
                                    end
                                    i = i +1
                                end
                            end
                        end
                    end
                end
            end
        
           

            o.tables.farpZonesPerStage = {}
            for _, farpZoneName in pairs(o.tables.farp_zones) do
                local findFirst = function (farpZoneName)
                    for _, stage_zone in pairs(o.tables.stage_zones) do
                        if Spearhead.DcsUtil.isZoneInZone(farpZoneName, stage_zone) then
                            return stage_zone
                        end
                    end
                    return nil
                end

                local found = findFirst(farpZoneName)
                if found then
                    
                    if o.tables.farpZonesPerStage[found] == nil then
                        o.tables.farpZonesPerStage[found] = {}
                    end

                    table.insert(o.tables.farpZonesPerStage[found], farpZoneName)
                end
            end


            local is_group_taken = {}
            do
                local all_groups = Spearhead.DcsUtil.getAllGroupNames()
                for _, value in pairs(all_groups) do
                    is_group_taken[value] = false
                end
            end

            local getAvailableGroups = function()
                local result = {}
                for name, value in pairs(is_group_taken) do
                    if value == false then
                        table.insert(result, name)
                    end
                end
                return result
            end

            local getAvailableCAPGroups = function()
                local result = {}
                for name, value in pairs(is_group_taken) do
                    if value == false and Spearhead.Util.startswith(name, "CAP") then
                        table.insert(result, name)
                    end
                end
                return result
            end

            --- airbaseId <> groupname[]
            o.tables.capGroupsOnAirbase = {}
            local loadCapUnits = function()
                local all_groups = getAvailableCAPGroups()
                local airbases = world.getAirbases()
                for _, airbase in pairs(airbases) do
                    local baseId = airbase:getID()
                    local point = airbase:getPoint()

                    o.tables.capGroupsOnAirbase[baseId] = {}
                    local groups = Spearhead.DcsUtil.areGroupsInCustomZone(all_groups,
                        { x = point.x, z = point.z, radius = 2048 })
                    for _, groupName in pairs(groups) do
                        is_group_taken[groupName] = true
                        table.insert(o.tables.capGroupsOnAirbase[baseId], groupName)
                    end
                end
            end

            --- missionZoneName <> groupname[]
            o.tables.groupsInMissionZone = {}
            local loadMissionzoneUnits = function()
                local all_groups = getAvailableGroups()
                for _, missionZoneName in pairs(o.tables.mission_zones) do
                    o.tables.groupsInMissionZone[missionZoneName] = {}
                    local groups = Spearhead.DcsUtil.getGroupsInZone(all_groups, missionZoneName)
                    for _, groupName in pairs(groups) do
                        is_group_taken[groupName] = true
                        table.insert(o.tables.groupsInMissionZone[missionZoneName], groupName)
                    end
                end
            end

           --- missionZoneName <> groupname[]
           o.tables.groupsInRandomMissions = {}
           local loadRandomMissionzoneUnits = function()
               local all_groups = getAvailableGroups()
               for _, missionZoneName in pairs(o.tables.random_mission_zones) do
                   o.tables.groupsInRandomMissions[missionZoneName] = {}
                   local groups = Spearhead.DcsUtil.getGroupsInZone(all_groups, missionZoneName)
                   for _, groupName in pairs(groups) do
                       is_group_taken[groupName] = true
                       table.insert(o.tables.groupsInRandomMissions[missionZoneName], groupName)
                   end
               end
           end

            --- farpZoneName <> groupname[]
            o.tables.groupsInFarpZone = {}
            local loadFarpGroups = function()
                local all_groups = getAvailableGroups()
                for _, farpZone in pairs(o.tables.farp_zones) do
                    o.tables.groupsInFarpZone[farpZone] = {}
                    local groups = Spearhead.DcsUtil.getGroupsInZone(all_groups, farpZone)
                    for _, groupName in pairs(groups) do
                        is_group_taken[groupName] = true
                        table.insert(o.tables.groupsInFarpZone[farpZone], groupName)
                    end
                end
            end

            --- farpZoneName <> groupname[]
            o.tables.redAirbaseGroupsPerAirbase = {}
            o.tables.blueAirbaseGroupsPerAirbase = {}
            local loadAirbaseGroups = function()
                local all_groups = getAvailableGroups()
                local airbases = world.getAirbases()
                for _, airbase in pairs(airbases) do
                    local baseId = tostring(airbase:getID())
                    local point = airbase:getPoint()

                    if isAirbaseInZone[tostring(baseId) or "something" ] == true and airbase:getDesc().category == Airbase.Category.AIRDROME then
                        o.tables.redAirbaseGroupsPerAirbase[baseId] = {}
                        o.tables.blueAirbaseGroupsPerAirbase[baseId] = {}
                        local groups = Spearhead.DcsUtil.areGroupsInCustomZone(all_groups, { x = point.x, z = point.z, radius = 2048 })
                        for _, groupName in pairs(groups) do

                            if Spearhead.DcsUtil.IsGroupStatic(groupName) == true then
                                local object = StaticObject.getByName(groupName)
                                if object then
                                    if object:getCoalition() == coalition.side.RED then
                                        table.insert(o.tables.redAirbaseGroupsPerAirbase[baseId], groupName)
                                        is_group_taken[groupName] = true
                                    elseif object:getCoalition() == coalition.side.BLUE then
                                        table.insert(o.tables.blueAirbaseGroupsPerAirbase[baseId], groupName)
                                        is_group_taken[groupName] = true
                                    end
                                end
                            else
                                local group = Group.getByName(groupName)
                                if group then
                                    if group:getCoalition() == coalition.side.RED then
                                        table.insert(o.tables.redAirbaseGroupsPerAirbase[baseId], groupName)
                                        is_group_taken[groupName] = true
                                    elseif group:getCoalition() == coalition.side.BLUE then
                                        table.insert(o.tables.blueAirbaseGroupsPerAirbase[baseId], groupName)
                                        is_group_taken[groupName] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end

            o.tables.miscGroupsInStages = {}
            local loadMiscGroupsInStages = function ()
                local all_groups = getAvailableGroups()
                for _, stage_zone in pairs(o.tables.stage_zones) do
                    o.tables.miscGroupsInStages[stage_zone] = {}
                    local groups = Spearhead.DcsUtil.getGroupsInZone(all_groups, stage_zone)
                    for _, groupName in pairs(groups) do
                        if Spearhead.DcsUtil.IsGroupStatic(groupName) == true then
                            local object = StaticObject.getByName(groupName)
                            if object and object:getCoalition() ~= coalition.side.NEUTRAL then
                                is_group_taken[groupName] = true
                                table.insert(o.tables.miscGroupsInStages[stage_zone], groupName)
                            end
                        else
                            local group = Group.getByName(groupName)
                            if group and group:getCoalition() ~= coalition.side.NEUTRAL then
                                is_group_taken[groupName] = true
                                table.insert(o.tables.miscGroupsInStages[stage_zone], groupName)
                            end
                        end
                    end
                end
            end

            loadCapUnits()
            loadMissionzoneUnits()
            loadRandomMissionzoneUnits()
            loadFarpGroups()
            loadAirbaseGroups()
            loadMiscGroupsInStages()

            local cleanup = function () --CLean up all groups that are now managed inside zones by spearhead 
                
                local count = 0
                for name, taken in pairs(is_group_taken) do
                    if taken == true then
                        Spearhead.DcsUtil.DestroyGroup(name)
                        count = count + 1
                    end
                end
                Logger:info("Destroyed " .. count .. " units that are now managed in zones by Spearhead")
            end
            cleanup()

            --- key: zoneName value: { current, routes = [ { point1, point2 } ] }
            o.tables.capRoutesPerStageNumber = {}
            for _, zoneName in pairs(o.tables.stage_zones) do
                local number = tostring(o.tables.stage_numberPerzone[zoneName] or "unknown")

                if o.tables.capRoutesPerStageNumber[number] == nil then
                    o.tables.capRoutesPerStageNumber[number] = {
                        current = 0,
                        routes = {}
                    }
                end

                for _, cap_route_zone in pairs(o.tables.cap_route_zones) do
                    if Spearhead.DcsUtil.isZoneInZone(cap_route_zone, zoneName) == true then
                        local zone = Spearhead.DcsUtil.getZoneByName(cap_route_zone)
                        if zone then
                            if zone.zone_type == Spearhead.DcsUtil.ZoneType.Cilinder then
                                table.insert(o.tables.capRoutesPerStageNumber[number].routes, { point1 = { x = zone.x , z = zone.z }, point2 = nil } )
                            else
                                local function getDist(a, b)
                                    return math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
                                end

                                local biggest = nil
                                local biggestA = nil
                                local biggestB = nil

                                for i=1, 3 do
                                    for ii = i + 1, 4 do
                                        
                                        local a = zone.verts[i]
                                        local b = zone.verts[ii]
                                        local dist = getDist(a,b)

                                        if biggest == nil or dist > biggest then
                                            biggestA = a
                                            biggestB = b
                                            biggest = dist
                                        end
                                    end
                                end

                                if biggestA and biggestB then
                                    table.insert(o.tables.capRoutesPerStageNumber[number].routes, 
                                    {
                                        point1 = { x = biggestA.x , z = biggestA.z },
                                        point2 = { x = biggestB.x , z = biggestB.z }
                                    })
                                end
                            end
                        end
                    end
                end
            end

            o.Logger:debug(o.tables.capRoutesPerStageNumber)
            
            o.tables.missionCodes = {}
        end

        o.GetDescriptionForMission = function(self, missionZoneName)
            return self.tables.descriptions[missionZoneName]
        end

        o.getCapRouteInZone = function(self, stageNumber, baseId)
            local stageNumber = tostring(stageNumber) or "nothing"
            local routeData = self.tables.capRoutesPerStageNumber[stageNumber]
            if routeData  then
                local count = Spearhead.Util.tableLength(routeData.routes)
                if count > 0 then
                    routeData.current = routeData.current + 1
                    if count < routeData.current then
                        routeData.current = 1
                    end
                    return routeData.routes[routeData.current]
                end
            end
            do
                local function GetClosestPointOnCircle(pC, radius, p)
                    local vX = p.x - pC.x;
                    local vY = p.z - pC.z;
                    local magV = math.sqrt(vX*vX + vY*vY);
                    local aX = pC.x + vX / magV * radius;
                    local aY = pC.z + vY / magV * radius;
                    return { x = aX, z = aY }
                end
                local stageZoneName = Spearhead.Util.randomFromList(self.tables.stage_zonesByNumer[stageNumber]) or "none"
                local stagezone = Spearhead.DcsUtil.getZoneByName(stageZoneName)
                if stagezone then
                    local base = Spearhead.DcsUtil.getAirbaseById(baseId)
                    if base then
                        local closest = nil
                        if stagezone.zone_type == Spearhead.DcsUtil.ZoneType.Cilinder then
                            closest = GetClosestPointOnCircle({x = stagezone.x, z = stagezone.z}, stagezone.radius, base:getPoint())
                        else
                            local function getDist(a, b)
                                return math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
                            end
    
                            local closestDistance = -1
                            for _, vert in pairs(stagezone.verts) do
                                local distance = getDist(vert, base:getPoint())
                                if closestDistance == -1 or distance < closestDistance then
                                   closestDistance = distance
                                   closest = vert
                                end
                            end
                        end
                        
                        if math.random(1,2)%2 == 0 then
                            return { point1 = closest, point2 = {x = stagezone.x, z = stagezone.z} }
                        else
                            return { point1 = {x = stagezone.x, z = stagezone.z}, point2 = closest }
                        end
                    end
                end
            end
            
        end
        ---comment
        ---@param self table
        ---@param number number
        ---@return string zoneName
        o.getStageZonesByStageNumber = function (self, number)
            local numberString = tostring(number)
            return self.tables.stage_zonesByNumer[numberString]
        end

        ---comment
        ---@param self table
        ---@return table result a  list of stage zone names
        o.getStagezoneNames = function (self)
            return self.tables.stage_zones
        end

        o.getCarrierRouteZones = function (self)
            return self.tables.carrier_route_zones
        end

        o.getMissionsForStage = function (self, stagename)
            return self.tables.missionZonesPerStage[stagename] or {}
        end

        o.getRandomMissionsForStage = function(self, stagename)
            return self.tables.randomMissionZonesPerStage[stagename] or {}
        end

        o.getGroupsForMissionZone = function (self, missionZoneName)
            if Spearhead.Util.startswith(missionZoneName, "RANDOMMISSION") == true then
                return self.tables.groupsInRandomMissions[missionZoneName] or  {}
            end
            return self.tables.groupsInMissionZone[missionZoneName] or {}
        end

        o.getMissionBriefingForMissionZone = function (self, missionZoneName)
            return self.tables.descriptions[missionZoneName] or ""
        end

        ---comment
        ---@param self table
        ---@param stageName string
        ---@return table result airbase IDs. Use Spearhead.DcsUtil.getAirbaseById
        o.getAirbaseIdsInStage = function (self, stageName)
            return self.tables.airbasesPerStage[stageName] or {}
        end
        
        o.getFarpZonesInStage = function (self, stageName)
            return self.tables.farpZonesPerStage[stageName]
        end

        ---comment
        ---@param self table
        ---@param airbaseId number
        ---@return table
        o.getCapGroupsAtAirbase = function(self, airbaseId)
            return self.tables.capGroupsOnAirbase[airbaseId] or {}
        end
        
        o.getRedGroupsAtAirbase = function (self, airbaseId)
            local baseId = tostring(airbaseId)
            return self.tables.redAirbaseGroupsPerAirbase[baseId] or {}
        end

        o.getBlueGroupsAtAirbase = function (self, airbaseId)
            local baseId = tostring(airbaseId)
            return self.tables.blueAirbaseGroupsPerAirbase[baseId] or {}
        end

        o.getMiscGroupsAtStage = function(self, stageName)
            return self.tables.miscGroupsInStages[stageName] or {}
        end

        o.GetNewMissionCode = function (self)
            local code = nil
            local tries = 0
            while code == nil and tries < 10 do
                local random = math.random(1000, 9999)
                if self.tables.missionCodes[random] == nil then
                    code = random
                end
                tries = tries + 1
            end
            return code

            --[[
                TODO: What to do when there's no random possible
            ]]
        end

        do -- LOG STATE
            Logger:info("initiated the database with amount of zones: ")
            Logger:info("Stages:            " .. Spearhead.Util.tableLength(o.tables.stage_zones))
            Logger:info("Missions:          " .. Spearhead.Util.tableLength(o.tables.mission_zones))
            Logger:info("Random Missions:   " .. Spearhead.Util.tableLength(o.tables.random_mission_zones))
            Logger:info("Farps:             " .. Spearhead.Util.tableLength(o.tables.farp_zones))
            Logger:info("Airbases:          " .. Spearhead.Util.tableLength(o.tables.airbasesPerStage))
            Logger:info("RedAirbase Groups: " .. Spearhead.Util.tableLength(o.tables.redAirbaseGroupsPerAirbase["21"]))


            for _, missionZone in pairs(o.tables.mission_zones) do
                if o.tables.descriptions[missionZone] == nil then
                    Spearhead.AddMissionEditorWarning("Mission with zonename: " .. missionZone .. " does not have a briefing")
                end
            end

            for _, randomMission in pairs(o.tables.random_mission_zones) do
                if o.tables.descriptions[randomMission] == nil then
                    Spearhead.AddMissionEditorWarning("Mission with zonename: " .. randomMission .. " does not have a briefing")
                end
            end

        end
        singleton = o
        return o
    end
end

Spearhead.DB = SpearheadDB

end --spearhead_db.lua
do --Stage.lua

local Stage = {}
do --init STAGE DIRECTOR


    local stageDrawingId = 0

    ---comment
    ---@param stagezone_name string
    ---@param database table
    ---@param logger table
    ---@return table?
    function Stage:new(stagezone_name, database, logger, stageConfig)
        local o = {}
        setmetatable(o, { __index = self })

        o.zoneName = stagezone_name

        local split = Spearhead.Util.split_string(stagezone_name, "_")
        if Spearhead.Util.tableLength(split) < 2 then
            Spearhead.AddMissionEditorWarning("Stage zone with name " .. stagezone_name .. " does not have a order number or valid format")
            return nil
        end

        local orderNumber = tonumber(split[2])
        if orderNumber == nil then
            Spearhead.AddMissionEditorWarning("Stage zone with name " .. stagezone_name .. " does not have a valid order number : " .. split[2])
            return nil
        end

        o.stageNumber = orderNumber
        o.database = database
        o.logger = logger
        o.db = {}
        o.db.missionsByCode = {}
        o.db.missions = {}
        o.db.sams = {}
        o.db.redAirbasegroups = {}
        o.db.blueAirbasegroups = {}
        o.db.airbaseIds = {}
        o.db.farps = {}
        o.activeStage = 0
        o.preActivated = false
        o.stageConfig = stageConfig or {}
        o.stageDrawingId = stageDrawingId + 1

        stageDrawingId = stageDrawingId + 1

        do --Init Stage
            logger:info("Initiating new Stage with name: " .. stagezone_name)

            local missionZones = database:getMissionsForStage(stagezone_name)
            for _, missionZone in pairs(missionZones) do
                local mission = Spearhead.internal.Mission:new(missionZone, database, logger)
                if mission then
                    o.db.missionsByCode[mission.code] = mission
                    if mission.missionType == Spearhead.internal.Mission.MissionType.SAM then
                        table.insert(o.db.sams, mission)
                    else
                        table.insert(o.db.missions, mission)
                    end
                end
            end

            local randomMissionNames = database:getRandomMissionsForStage(stagezone_name)

            local randomMissionByName = {}
            for _, missionZoneName in pairs(randomMissionNames) do
                local mission = Spearhead.internal.Mission:new(missionZoneName, database, logger)
                if mission then
                    if randomMissionByName[mission.name] == nil then
                        randomMissionByName[mission.name] = {}
                    end
                    table.insert(randomMissionByName[mission.name], mission)
                end
            end

            for _, missions in pairs(randomMissionByName) do
                local mission = Spearhead.Util.randomFromList(missions)
                if mission then
                    o.db.missionsByCode[mission.code] = mission
                    if mission.missionType == Spearhead.internal.Mission.MissionType.SAM then
                        table.insert(o.db.sams, mission)
                    else
                        table.insert(o.db.missions, mission)
                    end
                end
            end

            local airbaseIds = database:getAirbaseIdsInStage(o.zoneName)
            if airbaseIds ~= nil and type(airbaseIds) == "table" then
                o.db.airbaseIds = airbaseIds
                for _, airbaseId in pairs(airbaseIds) do
                    
                    for _, groupName in pairs(database:getRedGroupsAtAirbase(airbaseId)) do 
                        table.insert(o.db.redAirbasegroups, groupName)
                    end

                    for _, groupName in pairs(database:getBlueGroupsAtAirbase(airbaseId)) do 
                        table.insert(o.db.blueAirbasegroups, groupName)
                    end
                end
            end

            local farps = database:getFarpZonesInStage(o.zoneName)
            if farps ~= nil and type(farps) == "table" then o.db.farps = farps end
        end

        o.IsComplete = function(self)
            for i, mission in pairs(self.db.missions) do
                local state = mission:GetState()
                if state == Spearhead.Mission.MissionState.ACTIVE or state == Spearhead.Mission.MissionState.NEW then
                    return false
                end
            end
            return true
        end

        ---Activates all SAMS, Airbase units etc all at once.
        ---@param self table
        o.PreActivate = function(self)
            if self.preActivated == false then
                self.preActivated = true
                for key, mission in pairs(self.db.sams) do
                    if mission and mission.Activate then
                        mission:Activate()
                    end
                end
                self.logger:debug("Pre-activating stage with airbase groups amount: " .. Spearhead.Util.tableLength(self.db.redAirbasegroups))

                for _ , groupName in pairs(self.db.redAirbasegroups) do
                    Spearhead.DcsUtil.SpawnGroupTemplate(groupName)
                end
            end

            if self.activeStage == self.stageNumber then
                for _, mission in pairs(self.db.sams) do
                    self:AddCommmandsForMissionToAllPlayers(mission)
                end
            end
        end

        local activateMissionsIfApplicableAsync = function(self)
            self:ActivateMissionsIfApplicable(self)
        end

        o.MarkStage = function(self, blue)
            local fillColor = {1, 0, 0, 0.1}
            local line ={ 1, 0,0, 1 }
            if blue == true then
                fillColor = {0, 0, 1, 0.1}
                line ={ 0, 0,1, 1 }
            end

            local zone = Spearhead.DcsUtil.getZoneByName(self.zoneName)
            if zone then
                self.logger:debug("drawing stage")
                if zone.zone_type == Spearhead.DcsUtil.ZoneType.Cilinder then
                    trigger.action.circleToAll(-1, self.stageDrawingId, {x = zone.x, y = 0 , z = zone.z}, zone.radius, {0,0,0,0}, {0,0,0,0},4, true)
                else
                    --trigger.action.circleToAll(-1, self.stageDrawingId, {x = zone.x, y = 0 , z = zone.z}, zone.radius, { 1, 0,0, 1 }, {1,0,0,1},4, true)
                    trigger.action.quadToAll( -1, self.stageDrawingId,  zone.verts[2], zone.verts[1], zone.verts[4],  zone.verts[3], {0,0,0,0}, {0,0,0,0}, 4, true)
                end

                trigger.action.setMarkupColorFill(self.stageDrawingId, fillColor)
                trigger.action.setMarkupColor(self.stageDrawingId, line)
            end
        end
        
        o.ActivateStage = function(self)
            pcall(function()
                self:MarkStage()
            end)

            self:PreActivate()
            
            local miscGroups = self.database:getMiscGroupsAtStage(self.zoneName)
            self.logger:debug("Activating Misc groups for zone: " .. Spearhead.Util.tableLength(miscGroups))
            for _, groupName in pairs(miscGroups) do
                Spearhead.DcsUtil.SpawnGroupTemplate(groupName)
            end

            for _, mission in pairs(self.db.missions) do
                if mission.missionType == Spearhead.internal.Mission.MissionType.DEAD then
                    mission:Activate()
                    self:AddCommmandsForMissionToAllPlayers(mission)
                end
            end
            timer.scheduleFunction(activateMissionsIfApplicableAsync, self, timer.getTime() + 5)
        end

        o.ActivateMissionsIfApplicable = function (self)
            local activeCount = 0

            local availableMissions = {}
            for _, mission in pairs(self.db.missionsByCode) do
                if mission.missionState == Spearhead.internal.Mission.MissionState.ACTIVE then
                    activeCount = activeCount + 1
                end

                if mission.missionState == Spearhead.internal.Mission.MissionState.NEW then
                    table.insert(availableMissions, mission)
                end
            end

            local max = self.stageConfig.maxMissionsInStage or 10

            local availableMissionsCount = Spearhead.Util.tableLength(availableMissions)
            if activeCount < max and availableMissionsCount > 0  then
                for i = activeCount+1, max do
                    if availableMissionsCount == 0 then
                        i = max+1 --exits this loop
                    else
                        local index = math.random(1, availableMissionsCount)
                        local mission = table.remove(availableMissions, index)
                        if mission then
                            mission:Activate()
                            self:AddCommmandsForMissionToAllPlayers(mission)
                            activeCount = activeCount + 1;
                        end
                        availableMissionsCount = availableMissionsCount - 1
                    end
                end
            end
        end

        ---Cleans up all missions
        ---@param self table
        o.Clean = function(self)
            for key, mission in pairs(self.db.missions) do
                mission:Cleanup()
            end

            for key, samMission in pairs(self.db.sams) do
                samMission:Cleanup()
            end

            for _, airbase in pairs(self.db.airbases) do
                for _, redGroupName in pairs(airbase.redAirbaseGroupNames) do
                    Spearhead.DcsUtil.DcsUtil.DestroyGroup(redGroupName)
                end
            end

            logger:debug("'" .. Spearhead.Util.toString(self.zoneName) .. "' cleaned")
        end

        local ActivateBlueAsync = function(self)
            pcall(function()
                self:MarkStage(true)
            end)

            for key, airbaseId in pairs(self.db.airbaseIds) do
                local airbase = Spearhead.DcsUtil.getAirbaseById(airbaseId)

                if airbase then
                    local startingCoalition = Spearhead.DcsUtil.getStartingCoalition(airbaseId)
                    if startingCoalition == coalition.side.BLUE then
                        airbase:setCoalition(2)
                        for _, blueGroupName in pairs(self.db.blueAirbasegroups) do
                            Spearhead.DcsUtil.SpawnGroupTemplate(blueGroupName)
                        end
                    else
                        airbase:setCoalition(0)
                    end
                end
            end
        end

        ---Sets airfields to blue and spawns friendly farps
        o.ActivateBlueStage = function(self)
            logger:debug("Setting stage '" .. Spearhead.Util.toString(self.zoneName) .. "' to blue")
            
            for _, groupName in pairs(self.db.redAirbasegroups) do
                Spearhead.DcsUtil.DestroyGroup(groupName)
            end

            for _, mission in pairs(self.db.missions) do
                mission:Cleanup()
            end

            for _, mission in pairs(self.db.sams) do
                mission:Cleanup()
            end

            timer.scheduleFunction(ActivateBlueAsync, self, timer.getTime() + 3)

        end

        o.OnStatusRequestReceived = function(self, groupId)
            if self.activeStage ~= self.stageNumber then
                return
            end

            trigger.action.outTextForGroup(groupId, "Status Update incoming... ", 3)

            local text = "Mission Status: \n"

            local  totalmissions = 0
            local completedMissions = 0
            for _, mission in pairs(self.db.missionsByCode) do
                totalmissions = totalmissions + 1
                if mission.missionState == Spearhead.internal.Mission.MissionState.ACTIVE then

                    text = text .. "\n [" .. mission.code .. "] " .. mission.name .. 
                    " ("  ..  mission.missionTypeDisplayName .. ") \n"
                end
               
                if mission.missionState == Spearhead.internal.Mission.MissionState.COMPLETED then
                    completedMissions = completedMissions + 1
                end
            end

            local completionPercentage = math.floor((completedMissions / totalmissions) * 100)
            text = text .. " \n Missions Complete: " .. completionPercentage .. "%" 

            self.logger:debug(text)
            trigger.action.outTextForGroup(groupId, text, 20)
        end

        o.OnStageNumberChanged = function (self, number)

            if self.activeStage == number then --only activate once for a stage
                return
            end

            local previousActive = self.activeStage
            self.activeStage = number
            if Spearhead.capInfo.IsCapActiveWhenZoneIsActive(self.zoneName, number) == true then
                self:PreActivate()
            end

            if number == self.stageNumber then
                self:ActivateStage()
            end

            if previousActive <= self.stageNumber then
                if number > self.stageNumber then
                    self:ActivateBlueStage()
                    self:RemoveAllMissionCommands()
                end
            end
        end

        --- input = { self, groupId, missionCode }
        local ShowBriefingClicked = function (input)
            
            local self = input.self
            local groupId = input.groupId
            local missionCode = input.missionCode

            local mission  = self.db.missionsByCode[missionCode]
            if mission then
                mission:ShowBriefing(groupId)
            end
        end
        
        o.RemoveMissionCommands = function (self, mission)

            self.logger:debug("Removing commands for: " .. mission.name)

            local folderName = mission.name .. "(" .. mission.missionTypeDisplayName .. ")"
            for i = 0, 2 do
                local players = coalition.getPlayers(i)
                for _, playerUnit in pairs(players) do
                    local groupId = playerUnit:getGroup():getID()
                    missionCommands.removeItemForGroup(groupId, { "Missions", folderName })
                end
            end
        end

        o.RemoveAllMissionCommands = function (self)
            for _, mission in pairs(self.db.missionsByCode) do
                self:RemoveMissionCommands(mission)
            end
        end

        o.AddCommandsForMissionToGroup = function (self, groupId, mission)
            local folderName = mission.name .. "(" .. mission.missionTypeDisplayName .. ")"
            missionCommands.addSubMenuForGroup(groupId, folderName, { "Missions"} )
            missionCommands.addCommandForGroup(groupId, "Show Briefing", { "Missions", folderName }, ShowBriefingClicked, { self = self, groupId = groupId, missionCode = mission.code })
        end

        o.AddCommmandsForMissionToAllPlayers = function(self, mission)
            for i = 0, 2 do
                local players = coalition.getPlayers(i)
                for _, playerUnit in pairs(players) do
                    local groupId = playerUnit:getGroup():getID()
                    self:AddCommandsForMissionToGroup(groupId, mission)
                end
            end
        end
        
        o.OnPlayerEntersUnit = function (self, unit)
            if self.activeStage == self.stageNumber then
                local groupId = unit:getGroup():getID()
                for _, mission in pairs(self.db.missionsByCode) do
                    if mission.missionState == Spearhead.internal.Mission.MissionState.ACTIVE then
                        self:AddCommandsForMissionToGroup(groupId, mission)
                    end
                end
            end
        end

        local removeMissionCommandsDelayed = function(input)
            local self = input.self
            local mission = input.mission
            self:RemoveMissionCommands(mission)
        end
        
        o.OnMissionComplete = function(self, mission)
            timer.scheduleFunction(removeMissionCommandsDelayed, { self = self, mission = mission}, timer.getTime() + 20)

            if(self:IsComplete()) then
                
            else
                timer.scheduleFunction(activateMissionsIfApplicableAsync, self, timer.getTime() + 10)
            end
        end

        for _, mission in pairs(o.db.missionsByCode) do
            mission:AddMissionCompleteListener(o)
        end

        o.StageCompleteListeners = {}
        ---comment
        ---@param self table
        ---@param StageCompleteListener table a Object with tage
        o.AddStageCompleteListener = function(self, StageCompleteListener)

            if type(StageCompleteListener) ~= "table" then
                return
            end
            table.insert(self.MissionCompleteListeners, StageCompleteListener)
        end
        

        Spearhead.Events.AddOnStatusRequestReceivedListener(o)
        Spearhead.Events.AddStageNumberChangedListener(o)
        return o
    end
end

if not Spearhead.internal then Spearhead.internal = {} end
Spearhead.internal.Stage = Stage
end --Stage.lua
do --GlobalStageManager.lua


local StagesByName = {}


GlobalStageManager = {}
GlobalStageManager.start = function (database, stageConfig)

    for _, stageName in pairs(database:getStagezoneNames()) do

        local logger = Spearhead.LoggerTemplate:new(stageName, stageConfig.logLevel)
        local stage = Spearhead.internal.Stage:new(stageName, database, logger)

        StagesByName[stageName]  = stage

        local logger = Spearhead.LoggerTemplate:new("StageManager", stageConfig.logLevel)
        logger:info("Initiated " .. Spearhead.Util.tableLength(StagesByName) .. " airbases for cap")

    end
end

if not Spearhead.internal then Spearhead.internal = {} end
Spearhead.internal.GlobalStageManager = GlobalStageManager

end --GlobalStageManager.lua
do --Mission.lua

--- A mission Object.
local Mission = {}
do -- INIT Mission Class

    local MINIMAL_UNITS_ALIVE_RATIO = 0.20

    local Defaults = {}
    Defaults.MainMenu = "Missions"
    Defaults.SelectMenuSubMenus = { Defaults.MainMenu, "Select Mission" }
    Defaults.ShowMissionSubs = { Defaults.MainMenu }

    local PlayersInMission = {}
    local MissionType = {
        UNKNOWN = 0,
        STRIKE = 1,
        BAI = 2,
        DEAD = 3,
        SAM = 4,
    }

    do --INIT MISSION TYPE FUNCTIONS
        ---Parse string to mission type
        ---@param input string
        MissionType.Parse = function(input)
            if input == nil then
                return Mission.MissionType.UNKNOWN
            end

            input = string.lower(input)
            if input == "dead" then return MissionType.DEAD end
            if input == "strike" then return MissionType.STRIKE end
            if input == "bai" then return MissionType.BAI end
            if input == "sam" then return MissionType.SAM end
            return Mission.MissionType.UNKNOWN
        end

        ---comment
        ---@param input number missionType
        ---@return string text
        MissionType.toString = function(input)
            if input == MissionType.DEAD then return "DEAD" end
            if input == MissionType.STRIKE then return "STRIKE" end
            if input == MissionType.BAI then return "BAI" end
            if input == MissionType.SAM then return "SAM" end
            return "?"
        end
    end
    Mission.MissionType = MissionType

    Mission.MissionState = {
        NEW = 0,
        ACTIVE = 1,
        COMPLETED = 2,
    }

    ---comment
    ---@param missionZoneName string missionZoneName
    ---@param database table db dependency injection
    ---@return table?
    function Mission:new(missionZoneName, database, logger)
        local o = {}
        setmetatable(o, { __index = self })

        local function ParseGroupName(input)
            local split_name = Spearhead.Util.split_string(input, "_")
            local split_length = Spearhead.Util.tableLength(split_name)
            if Spearhead.Util.startswith(input, "RANDOMMISSION") == true and split_length < 4 then
                Spearhead.AddMissionEditorWarning("Random Mission with zonename " .. input .. " not in right format")
                return nil
            elseif split_length < 3 then
                Spearhead.AddMissionEditorWarning("Mission with zonename" .. input .. " not in right format")
                return nil
            end
            local type = split_name[2]
            local parsedType = Mission.MissionType.Parse(type)
    
            if parsedType == nil then
                Spearhead.AddMissionEditorWarning("Mission with zonename '" .. input .. "' has an unsupported type '" .. (type or "nil" ))
                return nil
            end
            local name = split_name[3]
            return {
                missionName = name,
                type = parsedType
            }
        end

        local parsed = ParseGroupName(missionZoneName)
        if parsed == nil then return nil end

        o.missionZoneName = missionZoneName
        o.database = database
        o.groupNames = database:getGroupsForMissionZone(missionZoneName)
        o.name = parsed.missionName
        o.missionType = parsed.type
        o.missionTypeDisplayName = Mission.MissionType.toString(o.missionType)
        o.startingGroups = Spearhead.Util.tableLength(o.groupNames)
        o.missionState = Mission.MissionState.NEW
        o.missionbriefing = database:GetDescriptionForMission(missionZoneName)
        o.startingUnits = 0
        o.logger = logger
        o.code = database:GetNewMissionCode()

        o.groupNamesPerUnit = {}

        o.groupUnitAliveDict = {}
        o.targetAliveStates = {}
        o.hasSpecificTargets = false

        local CheckStateAsync = function (self, time)
            self:CheckAndUpdateSelf()
            return nil
        end

        o.OnUnitLost = function(self, object)
            --[[
                OnUnit lost event
            ]]--
            self.logger:debug("Getting on unit lost event")

            local category = Object.getCategory(object)
            if category == Object.Category.UNIT then
                local unitName = object:getName()
                self.logger:debug("UnitName:" .. unitName)
                local groupName = self.groupNamesPerUnit[unitName]
                self.groupUnitAliveDict[groupName][unitName] = false

                if self.targetAliveStates[groupName][unitName] then
                    self.targetAliveStates[groupName][unitName] = false
                end
            elseif category == Object.Category.STATIC  then
                local name = object:getName()
                self.groupUnitAliveDict[name][name] = false

                self.logger:debug("Name " .. name)

                if self.targetAliveStates[name][name] then
                    self.targetAliveStates[name][name] = false
                end
            end
            timer.scheduleFunction(CheckStateAsync, self, timer.getTime() + 3)
        end

        o.MissionCompleteListeners = {}
        ---comment
        ---@param self table
        ---@param listener table Object that implements "OnMissionComplete(self, mission)"
        o.AddMissionCompleteListener = function(self, listener)
            if type(listener) ~= "table" then
                return
            end
            
            table.insert(self.MissionCompleteListeners, listener)
        end

        local TriggerMissionComplete = function(self)
            for _, callable in pairs(self.MissionCompleteListeners) do
                local succ, err = pcall( function() 
                    callable:OnMissionComplete(self)
                end)
                if err then
                    self.logger:warn("Error in misstion complete listener:" .. err)
                end
            end
        end


        local StartCheckingAndUpdateSelfContinuous = function (self)
            local CheckAndUpdate = function(self, time)
                self:CheckAndUpdateSelf(true)
                if self.missionState == Mission.MissionState.COMPLETED or self.missionState == Mission.MissionState.NEW then
                    return nil
                else
                    return time + 60
                end
            end

            timer.scheduleFunction(CheckAndUpdate, self, timer.getTime() + 300)
        end

        local CleanupDelayedAsync = function (self, time)
            self:Cleanup()
            return nil
        end

        ---comment
        ---@param self table
        ---@param checkUnitHealth boolean?
        o.CheckAndUpdateSelf = function(self, checkUnitHealth)
            if not checkUnitHealth then checkUnitHealth = false end

            if self.missionState == Mission.MissionState.COMPLETED then
                return
            end

            if self.hasSpecificTargets == true then
                local specificTargetsAlive = false
                for groupName, unitNameDict in pairs(self.targetAliveStates) do
                    for unitName, isAlive in pairs(unitNameDict) do
                        if isAlive == true then
                            specificTargetsAlive = true
                        end
                    end
                end
                if specificTargetsAlive == false then
                    self.missionState = Mission.MissionState.COMPLETED
                end
            else
                local function CountAliveGroups()
                    local aliveGroups = 0

                    for _, group in pairs(self.groupUnitAliveDict) do
                        local groupTotal = 0
                        local groupDeath = 0
                        for _, isAlive in pairs(group) do
                            if isAlive ~= true then
                                groupDeath = groupDeath + 1
                            end
                            groupTotal = groupTotal + 1
                        end

                        local aliveRatio = (groupTotal - groupDeath) / groupTotal
                        if aliveRatio >= MINIMAL_UNITS_ALIVE_RATIO then
                            aliveGroups = aliveGroups + 1
                        end
                    end

                    return aliveGroups
                end
                
                if self.missionType == Mission.MissionType.STRIKE then --strike targets should normally have TGT targets
                    if CountAliveGroups() == 0 then
                        self.missionState = Mission.MissionState.COMPLETED
                    end
                elseif self.missionType == Mission.MissionType.BAI then
                    if CountAliveGroups() == 0 then
                        self.missionState = Mission.MissionState.COMPLETED
                    end
                end
                --[[
                    TODO: Other checks for mission complete 
                ]]
            end

            if self.missionState == Mission.MissionState.COMPLETED then
                self.logger:debug("Mission complete " .. self.name)
                trigger.action.outText("Mission " .. self.name .. " (" .. self.code .. ") was completed succesfully!", 20)

                TriggerMissionComplete(self)
                --Schedule cleanup after 5 minutes of mission complete
                --timer.scheduleFunction(CleanupDelayedAsync, self, timer.getTime() + 300)
            end
        end

        ---Activates groups for this mission
        ---@param self table
        o.Activate = function(self)
            if self.missionState == Mission.MissionState.ACTIVE then
                return
            end

            self.missionState = Mission.MissionState.ACTIVE
            do --spawn groups
                for key, groupname in pairs(self.groupNames) do
                    Spearhead.DcsUtil.SpawnGroupTemplate(groupname)
                end
            end

            StartCheckingAndUpdateSelfContinuous(self)
        end

        local ToStateString = function(self)
            if self.hasSpecificTargets then
                local dead = 0
                local total = 0
                for _, group in pairs(self.targetAliveStates) do
                    for _, isAlive in pairs(group) do
                        total = total + 1
                        if isAlive == false then
                            dead = dead + 1
                        end
                    end
                end
                local completionPercentage = math.floor((dead / total) * 100)
                return "Targets Destroyed: " .. completionPercentage .. "%"
            else
                local dead = 0
                local total = 0
                for _, group in pairs(self.targetAliveStates) do
                    for _, isAlive in pairs(group) do
                        total = total + 1
                        if isAlive == false then
                            dead = dead + 1
                        end
                    end
                end

                local completionPercentage = math.floor((dead / total) * 100)
                return "Targets Destroyed: " .. completionPercentage .. "%"
            end
        end

        o.ShowBriefing = function(self, groupId)
            local stateString = ToStateString(self)

            if self.missionbriefing == nil then self.missionbriefing = "No briefing available" end
            local text = "Mission [" .. self.code .. "] ".. self.name .. "\n \n" .. self.missionbriefing .. " \n \n" .. stateString
            trigger.action.outTextForGroup(groupId, text, 30);
        end

        o.Cleanup = function(self)
            for key, groupName in pairs(self.groupNames) do
                Spearhead.DcsUtil.DestroyGroup(groupName)
            end
        end

        local Init = function(self)
            for key, group_name in pairs(self.groupNames) do

                self.groupUnitAliveDict[group_name] = {}
                self.targetAliveStates[group_name] = {}

                if Spearhead.DcsUtil.IsGroupStatic(group_name) then
                    Spearhead.Events.addOnUnitLostEventListener(group_name, self)

                    if Spearhead.Util.startswith(group_name, "TGT_") == true then
                        self.targetAliveStates[group_name][group_name] = true
                    end
                else
                    local group = Group.getByName(group_name)
                    local isGroupTarget = Spearhead.Util.startswith(group_name, "TGT_")

                    self.startingUnits = self.startingUnits + group:getInitialSize()
                    for _, unit in pairs(group:getUnits()) do
                        local unitName = unit:getName()

                        self.groupNamesPerUnit[unitName] = group_name

                        Spearhead.Events.addOnUnitLostEventListener(unitName, self)
                        self.groupUnitAliveDict[group_name][unitName] = true

                        if isGroupTarget == true or Spearhead.Util.startswith(unitName, "TGT_") == true then
                            self.targetAliveStates[group_name][unitName] = true
                        end

                        if self.missionType == MissionType.DEAD or self.missionType == MissionType.SAM then
                            local desc = unit:getDesc()
                            local attributes = desc.attributes
                            if attributes["SAM"] == true or attributes["SAM TR"] or attributes["AAA"] then
                                self.targetAliveStates[group_name][unitName] = true
                            end
                        end
                    end
                end
            end

            if Spearhead.Util.tableLength(self.targetAliveStates) > 0 then
                self.hasSpecificTargets = true
            end
        end

        Init(o)
        return o;
    end
end

if not Spearhead.internal then Spearhead.internal = {} end
Spearhead.internal.Mission = Mission
end --Mission.lua
do --FleetGroup.lua
local FleetGroup = {}

function FleetGroup:new(fleetGroupName, database, logger)
    local o = {}

    setmetatable(o, { __index = self })

    o.fleetGroupName = fleetGroupName
    o.logger = logger

    local split_name = Spearhead.Util.split_string(fleetGroupName, "_")
    if Spearhead.Util.tableLength(split_name) < 2 then
        Spearhead.AddMissionEditorWarning("CARRIERGROUP should have at least 2 parts. CARRIERGROUP_<fleetname>")
        return nil
    end
    o.fleetNameIdentifier = split_name[2]

    o.targetZonePerStage = {}
    o.currentTargetZone = nil
    o.pointsPerZone = {}

    do --INIT
        local carrierRouteZones = database:getCarrierRouteZones()
        for _, zoneName in pairs(carrierRouteZones) do
            if Spearhead.Util.strContains(string.lower(zoneName), "_".. string.lower(o.fleetNameIdentifier) .. "_" ) == true then
                local zone = Spearhead.DcsUtil.getZoneByName(zoneName)
                if zone and zone.zone_type == Spearhead.DcsUtil.ZoneType.Polygon then
                    local split_string = Spearhead.Util.split_string(zoneName, "_")
                    if Spearhead.Util.tableLength(split_string) < 3 then
                        Spearhead.AddMissionEditorWarning(
                            "CARRIERROUTE should at least have 3 parts. Check the documentation for: " .. zoneName)
                    else
                        local function GetTwoFurthestPoints(zone)
                            local function getDist(a, b)
                                return math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
                            end

                            local biggest = nil
                            local biggestA = nil
                            local biggestB = nil

                            for i = 1, 3 do
                                for ii = i + 1, 4 do
                                    local a = zone.verts[i]
                                    local b = zone.verts[ii]
                                    local dist = getDist(a, b)

                                    if biggest == nil or dist > biggest then
                                        biggestA = a
                                        biggestB = b
                                        biggest = dist
                                    end
                                end
                            end
                            return { x = biggestA.x, z = biggestA.z }, { x = biggestB.x, z = biggestB.z }
                        end

                        local function getMinMaxStage(namePart)
                            if namePart == nil then
                                return nil, nil
                            end

                            if Spearhead.Util.startswith(namePart, "%[") == true then
                                namePart = Spearhead.Util.split_string(namePart, "[")[1]
                            end

                            if Spearhead.Util.strContains(namePart, "%]") == true then
                                namePart = Spearhead.Util.split_string(namePart, "]")[1]
                            end

                            local split_numbers = Spearhead.Util.split_string(namePart, "-")
                            if Spearhead.Util.tableLength(split_numbers) < 2  then
                                Spearhead.AddMissionEditorWarning("CARRIERROUTE zone stage numbers not in the format _[<number>-<number>]: " .. zoneName)
                                return nil, nil
                            end

                            local first = tonumber(split_numbers[1])
                            local second = tonumber(split_numbers[2])

                            if first == nil or second == nil  then
                                Spearhead.AddMissionEditorWarning("CARRIERROUTE zone stage numbers not in the format _[<number>-<number>]: " .. zoneName)
                                return nil, nil
                            end
                            return first, second
                        end

                        local pointA, pointB = GetTwoFurthestPoints(zone)
                        local first, second = getMinMaxStage(split_string[3])
                        if first ~= nil and second ~= nil then
                            for i = first, second do
                                o.targetZonePerStage[tostring(i)] = zoneName
                            end
                            o.pointsPerZone[zoneName] = { pointA = pointA, pointB = pointB }
                        else
                            Spearhead.AddMissionEditorWarning("CARRIERROUTE zone stage numbers not in the format _[<number>-<number>]: " .. zoneName)
                        end
                    end
                else
                    Spearhead.AddMissionEditorWarning("CARRIERROUTE cannot be a cilinder: " .. zoneName)
                end
            end
        end
    end

    local SetTaskAsync = function(input, time)
        local targetZone = input.targetZone
        local task = input.task
        local groupName = input.groupName
        local logger = input.logger

        local group = Group.getByName(groupName)
        if group then
            logger:info("Sending " .. fleetGroupName .. " to " .. targetZone)
            group:getController():setTask(task)
        end
    end

    o.OnStageNumberChanged = function(self, number)
        local targetZone = self.targetZonePerStage[tostring(number)]
        if targetZone and targetZone ~= self.currentTargetZone then
            local points = self.pointsPerZone[targetZone]
            local task  = Spearhead.RouteUtil.CreateCarrierRacetrack(points.pointA, points.pointB)
            timer.scheduleFunction(SetTaskAsync, { task = task, targetZone = targetZone,  groupName = self.fleetGroupName, logger = self.logger }, timer.getTime() + 5)
        end
    end

    Spearhead.Events.AddStageNumberChangedListener(o)
    return o
end

if not Spearhead.internal then Spearhead.internal = {} end
Spearhead.internal.FleetGroup = FleetGroup

end --FleetGroup.lua
do --GlobalFleetManager.lua


local GlobalFleetManager = {}

local fleetGroups = {}

GlobalFleetManager.start = function(database)

    local logger = Spearhead.LoggerTemplate:new("CARRIERFLEET", Spearhead.LoggerTemplate.LogLevelOptions.DEBUG)

    local all_groups = Spearhead.DcsUtil.getAllGroupNames()
    for _, groupName in pairs(all_groups) do
        if Spearhead.Util.startswith(string.lower(groupName), "carriergroup" ) == true then
            logger:info("Registering " .. groupName .. " as a managed fleet")
            local carrierGroup = Spearhead.internal.FleetGroup:new(groupName, database, logger)
            table.insert(fleetGroups, carrierGroup)
        end
    end
end

Spearhead.internal.GlobalFleetManager = GlobalFleetManager
end --GlobalFleetManager.lua
do --GlobalCapManager.lua
local GlobalCapManager = {}
do
    local airbasesPerStage = {}
    local allAirbasesByName = {}
    local activeAirbasesPerActiveStage = {}
    local unitsPerzonePerStage = {}

    local initiated = false

    function GlobalCapManager.start(database, capConfig, stageConfig)
        if initiated == true then return end

        local logger = Spearhead.LoggerTemplate:new("AirbaseManager", capConfig.logLevel)

        local zones = database:getStagezoneNames()
        if zones then
            for key, stageName in pairs(zones) do
                if airbasesPerStage[stageName] == nil then
                    airbasesPerStage[stageName] = {}
                end

                local airbaseIds = database:getAirbaseIdsInStage(stageName)
                if airbaseIds then
                    for _, id in pairs(airbaseIds) do
                        local airbaseName = Spearhead.DcsUtil.getAirbaseName(id)
                        if airbaseName then
                            local airbaseSpecificLogger = Spearhead.LoggerTemplate:new("CAP_" .. airbaseName, capConfig.logLevel)
                            local airbase = Spearhead.internal.CapAirbase:new(id, database, airbaseSpecificLogger, capConfig, stageConfig)
                            if airbase then
                                table.insert(airbasesPerStage[stageName], airbase)
                                allAirbasesByName[airbaseName] = airbase
                            end
                        end
                    end
                end
            end
        end

        logger:info("Initiated " .. Spearhead.Util.tableLength(allAirbasesByName) .. " airbases for cap")
        initiated = true

        local InfoFunctions = {}

        ---returns if there is CAP active 
        ---@param zoneName any
        ---@param activeZoneNumber number
        ---@return boolean
        InfoFunctions.IsCapActiveWhenZoneIsActive = function(zoneName, activeZoneNumber)
            for _, airbase in pairs(airbasesPerStage[zoneName]) do
                if airbase:IsBaseActiveWhenStageIsActive(activeZoneNumber) == true then
                    return true
                end
            end
            return false
        end

        Spearhead.capInfo = InfoFunctions
    end
end

if not Spearhead.internal then Spearhead.internal = {} end
Spearhead.internal.GlobalCapManager = GlobalCapManager

end --GlobalCapManager.lua
do --CapGroup.lua


local CapHelper = {}
do
    ---comment
    ---@param groupName string
    ---@return table?
    CapHelper.ParseGroupName = function(groupName)
        local split_string = Spearhead.Util.split_string(groupName, "_")
        local partCount = Spearhead.Util.tableLength(split_string)
        if partCount >= 3 then
            local result = {}
            result.zonesConfig = {}

            -- CAP_[1-5]5|[6]6|[7]7_Sukhoi
            -- CAP_[1-5,7]A|[6]7_Sukhoi

            local configPart = split_string[2]
            local first = configPart:sub(1, 1)
            if first == "A" then
                result.isBackup = false
                configPart = string.sub(configPart, 2, #configPart)
            elseif first == "B" then
                configPart = string.sub(configPart, 2, #configPart)
                result.isBackup = true
            elseif first == "[" then
                result.isBackup = false
            else
                Spearhead.AddMissionEditorWarning("Could not parse the CAP config for group: " .. groupName)
                return nil
            end

            local subsplit = Spearhead.Util.split_string(configPart, "|")
            if subsplit then
                for key, value in pairs(subsplit) do
                    local keySplit = Spearhead.Util.split_string(value, "]")
                    local targetZone = keySplit[2]
                    local allActives = string.sub(keySplit[1], 2, #keySplit[1])
                    local commaSeperated = Spearhead.Util.split_string(allActives, ",")
                    for _, value in pairs(commaSeperated) do
                        local dashSeperated = Spearhead.Util.split_string(value, "-")
                        if Spearhead.Util.tableLength(dashSeperated) > 1 then
                            local from = tonumber(dashSeperated[1])
                            local till = tonumber(dashSeperated[2])

                            for i = from, till do
                                if targetZone == "A" then
                                    result.zonesConfig[tostring(i)] = tostring(i)
                                else
                                    result.zonesConfig[tostring(i)] = tostring(targetZone)
                                end
                            end
                        else
                            if targetZone == "A" then
                                result.zonesConfig[tostring(dashSeperated[1])] = tostring(dashSeperated[1])
                            else
                                result.zonesConfig[tostring(dashSeperated[1])] = tostring(targetZone)
                            end
                        end
                    end
                end
            end
            return result
        else
            Spearhead.AddMissionEditorWarning("CAP Group with name: " .. groupName .. "should have at least 3 parts, but has " .. partCount)
            return nil
        end
    end
end

---comment
---@param input table { groupName, task, logger }
---@param time number
---@return nil
local function setTaskAsync(input, time)
    local task = input.task
    local groupName = input.groupName
    local group = Group.getByName(groupName)

    if task then
        group:getController():setTask(task)
        if input.logger ~= nil then
            input.logger:debug("task set succesfully to group " .. groupName)
        end
    end
    return nil
end

local CapGroup = {}

CapGroup.GroupState = {
    UNSPAWNED = 0,
    READYONRAMP = 1,
    INTRANSIT = 2,
    ONSTATION = 3,
    RTBINTEN = 4,
    RTB = 5,
    DEAD = 6,
    REARMING = 7
}

local function SetReadyOnRampAsync(self, time)
    self:SetState(CapGroup.GroupState.READYONRAMP)
end

---comment
---@param groupName string
---@param airbaseId number
---@param logger table logger dependency injection
---@param database table database  dependency injection
---@param capConfig table config dependency injection
---@return table? o
function CapGroup:new(groupName, airbaseId, logger, database, capConfig)
    local o = {}
    setmetatable(o, { __index = self })

    local RESPAWN_AFTER_TOUCHDOWN_SECONDS = 180

    -- initials
    o.groupName = groupName
    o.airbaseId = airbaseId
    o.logger = logger
    o.database = database

    local parsed = CapHelper.ParseGroupName(groupName)
    if parsed == nil then return nil end
    o.capZonesConfig = parsed.zonesConfig
    o.isBackup = parsed.isBackup

    --vars
    o.assignedStageNumber = nil
    
    o.state = CapGroup.GroupState.UNSPAWNED
    o.aliveUnits = {}
    o.landedUnits = {}
    o.unitCount = 0
    o.onStationSince = 0
    o.currentCapTaskingDuration = 0
    o.markedForDespawn = false

    --config
    o.capConfig = {}

    if not capConfig then capConfig = {} end
    o.capConfig.maxDeviationRange = capConfig.maxDeviationRange
    o.capConfig.minSpeed = (capConfig.minSpeed or 400) * 0.514444
    o.capConfig.maxSpeed = (capConfig.maxSpeed or 500) * 0.514444
    o.capConfig.minAlt = (capConfig.minAlt or 8000) * 0.3048
    o.capConfig.maxAlt = (capConfig.maxAlt or 27000) * 0.3048
    o.capConfig.minDurationOnStation = capConfig.minDurationOnStation or 600
    o.capConfig.maxDurationOnstation = capConfig.maxDurationOnStation or 1800
    o.capConfig.rearmDelay = capConfig.rearmDelay or 300

    ---comment
    ---@param self table
    ---@param currentActive number
    ---@return table
    o.GetTargetZone = function (self, currentActive)
        return self.capZonesConfig[tostring(currentActive)]
    end

    o.SetState = function(self, state)
        self.state = state
        self:PublishUnitUpdatedEvent()
    end

    o.StartRearm = function(self)
        self:SpawnOnTheRamp()
        self:SetState(CapGroup.GroupState.REARMING)
        timer.scheduleFunction(SetReadyOnRampAsync, self, timer.getTime() + self.capConfig.rearmDelay - RESPAWN_AFTER_TOUCHDOWN_SECONDS)
    end

    o.SpawnOnTheRamp = function(self)
        self.markedForDespawn = false
        self.logger:debug("Spawning group " .. self.groupName)
        self.aliveUnits = {}
        self.landedUnits = {}
        self.onStationSince = 0

        local group = Spearhead.DcsUtil.SpawnGroupTemplate(self.groupName, nil, nil, true)
        if group then
            self.unitCount = group:getInitialSize()

            if self.state == CapGroup.GroupState.UNSPAWNED then
                self:SetState(CapGroup.GroupState.READYONRAMP)
            end

            for _, unit in pairs(group:getUnits()) do
                local name = unit:getName()
                self.aliveUnits[name] = true
                self.landedUnits[name] = false
            end
        end
    end

    o.Despawn = function(self)
        self.logger:debug("Despawning group " .. self.groupName)
        Spearhead.DcsUtil.DestroyGroup(self.groupName)
        self:SetState(CapGroup.GroupState.UNSPAWNED)
    end

    o.SendRTB = function(self)
        local group = Group.getByName(self.groupName)
        if group and group:isExist() then
            local speed = math.random(self.capConfig.minSpeed, self.capConfig.maxSpeed)
            local rtbTask, errormessage = Spearhead.RouteUtil.CreateRTBMission(self.groupName, self.airbaseId, speed)
            if rtbTask then
                timer.scheduleFunction(setTaskAsync, { task = rtbTask, groupName = self.groupName, logger = self.logger }, timer.getTime() + 3)
            else
                self.logger:error("No RTB task could be created for group: " .. self.groupName .. " due to " .. errormessage)
                if self.markedForDespawn == true then
                    self:Despawn()
                end
            end
        end
    end

    o.SendRTBAndDespawn = function(self)
        self.markedForDespawn = true
        o.SendRTB(self)
    end

    ---Starts and send this group to perform CAP at a stage
    ---@param self any
    ---@param stageZoneNumber string
    o.SendToStage = function(self, stageZoneNumber)
        if self.state == CapGroup.GroupState.DEAD or self.state == CapGroup.GroupState.RTB then
            return --Can't task a unit that's dead or RTB
        end

        self.assignedStageNumber = stageZoneNumber
        local group = Group.getByName(self.groupName)
        if group and group:isExist() then
            self.logger:debug("Sending group out " .. self.groupName)
            local controller = group:getController()
            local capPoints = database:getCapRouteInZone(stageZoneNumber, self.airbaseId)

            local altitude = math.random(self.capConfig.minAlt, self.capConfig.maxAlt)
            local speed = math.random(self.capConfig.minSpeed, self.capConfig.maxSpeed)
            local attackHelos = false
            local deviationDistance = self.capConfig.maxDeviationRange
            local capTask
            if self.state == CapGroup.GroupState.ONRAMP or self.onStationSince == 0 then
                controller:setCommand({
                    id = 'Start',
                    params = {}
                })
                local duration = math.random(self.capConfig.minDurationOnStation, self.capConfig
                .maxDurationOnstation)
                self.logger:debug("random schedule min: " ..
                tostring(self.capConfig.minDurationOnStation or "nil") ..
                " max: " .. tostring(self.capConfig.maxDurationOnstation or "nil") .. " actual " .. duration)
                self.currentCapTaskingDuration = duration

                
                capTask = Spearhead.RouteUtil.createCapMission(self.groupName, self.airbaseId, capPoints.point1, capPoints.point2, altitude, speed, duration, attackHelos, deviationDistance)
            else
                local duration = self.currentCapTaskingDuration - (timer.getTime() - o.onStationSince)
                capTask = Spearhead.RouteUtil.createCapMission(self.groupName, self.airbaseId, capPoints.point1, capPoints.point2, altitude, speed, duration, attackHelos, deviationDistance)
            end

            if capTask then
                timer.scheduleFunction(setTaskAsync,
                    { task = capTask, groupName = self.groupName, logger = self.logger }, timer.getTime() + 3)
            end
            self:SetState(CapGroup.GroupState.INTRANSIT)
        end
    end

    ---Starts and send a unit to another airbase
    ---@param self table
    ---@param airdomeId any
    o.SendToAirbase = function(self, airdomeId)
        self.airbaseId = airdomeId
        local speed = math.random(self.capConfig.minSpeed, self.capConfig.maxSpeed)
        local rtbTask = Spearhead.RouteUtil.CreateRTBMission(self.groupName, airdomeId, speed)
        local group = Group.getByName(self.groupName)
        local controller = group:getController()
        controller:setCommand({
            id = 'Start',
            params = {}
        })
        timer.scheduleFunction(setTaskAsync, { task = rtbTask, groupName = self.groupName, logger = self.logger },
            timer.getTime() + 5)
    end

    o.OnGroupRTB = function(self, groupName)
        if groupName == self.groupName then
            self.logger:debug("Setting group " ..
            groupName ..
            " to state RTB after a total of " ..
            timer.getTime() - self.onStationSince .. "s of the " .. self.currentCapTaskingDuration .. "s")
            self:SetState(CapGroup.GroupState.RTB)
        end
    end

    o.OnGroupRTBInTen = function(self, groupName)
        if groupName == self.groupName then
            self:SetState(CapGroup.GroupState.RTBINTEN)
        end
    end

    o.OnGroupOnStation = function(self, groupName)
        if groupName == self.groupName then
            self.onStationSince = timer.getTime()
            self.logger:debug("Setting group " .. groupName .. " to state Onstation")
            self:SetState(CapGroup.GroupState.ONSTATION)
        end
    end

    ---comment
    ---@param self table
    ---@param proActive boolean Will check all units in group for aliveness
    o.UpdateState = function(self, proActive)
        local landed = false
        local landedCount = 0
        for name, landedBool in pairs(self.landedUnits) do
            if landedBool == true then
                landedCount = landedCount + 1
                landed = true
            end
        end

        local deadCount = 0
        for name, isAlive in pairs(self.aliveUnits) do
            if isAlive == false then
                deadCount = deadCount + 1
            end
        end

        local function DelayedStartRearm(input, time)
            local capGroup = input.self
            capGroup:StartRearm()
        end

        if landedCount + deadCount == self.unitCount then
            if landed then
                if self.markedForDespawn == true then
                    self:Despawn()
                else
                    timer.scheduleFunction(DelayedStartRearm, { self = self }, timer.getTime() + RESPAWN_AFTER_TOUCHDOWN_SECONDS)
                end
            else
                if self.markedForDespawn == true then
                    self:Despawn()
                else
                    local delay = self.capConfig.deathDelay - self.capConfig.rearmDelay + RESPAWN_AFTER_TOUCHDOWN_SECONDS
                    timer.scheduleFunction(DelayedStartRearm, { self = self }, timer.getTime() + delay)
                end
            end
        end
    end

    o.eventListeners = {}
    ---comment
    ---@param self table
    ---@param listener table object with  function OnGroupStateUpdated(capGroupTable)
    o.AddOnStateUpdatedListener = function(self, listener)
        if type(listener) ~= "table" then
            self.logger:error("Listener not of type table for AddOnStateUpdatedListener")
            return
        end

        if listener.OnGroupStateUpdated == nil then
            self.logger:error("Listener does not implement OnGroupStateUpdated")
            return
        end
        table.insert(self.eventListeners, listener)
    end

    o.PublishUnitUpdatedEvent = function(self)
        for _, callable in pairs(self.eventListeners) do
            local _, error = pcall(function()
                callable:OnGroupStateUpdated(self)
            end)
            if error then
                self.logger:error(error)
            end
        end
    end

    o.OnUnitLanded = function(self, initiatorUnit, airbase)
        if airbase then
            local airdomeId = airbase:getID()
            self.airbaseId = airdomeId
        end
        local name = initiatorUnit:getName()
        self.logger:debug("Received unit land event for unit " .. name .. " of group " .. self.groupName)

        self.landedUnits[name] = true
        self:UpdateState(false)
    end

    o.OnUnitLost = function(self, initiatorUnit)
        self.logger:debug("Received unit lost event for group " .. self.groupName)
        if initiatorUnit then
            self.aliveUnits[initiatorUnit:getName()] = false
        end
        self:UpdateState(false)
    end

    Spearhead.Events.addOnGroupRTBListener(o.groupName, o)
    Spearhead.Events.addOnGroupRTBInTenListener(o.groupName, o)
    Spearhead.Events.addOnGroupOnStationListener(o.groupName, o)
    local units = Group.getByName(groupName):getUnits()
    for key, unit in pairs(units) do
        Spearhead.Events.addOnUnitLandEventListener(unit:getName(), o)
        Spearhead.Events.addOnUnitLostEventListener(unit:getName(), o)
    end
    return o
end

if not Spearhead.internal then Spearhead.internal = {} end
Spearhead.internal.CapGroup = CapGroup

end --CapGroup.lua
do --CapAirbase.lua

local CapBase = {}

---comment
---@param airbaseId number
---@param database table
---@param logger table
---@param capConfig table
---@param stageConfig table
---@return table
function CapBase:new(airbaseId, database, logger, capConfig, stageConfig)
    local o  = {}
    setmetatable(o, { __index = self })

    o.groupNames = database:getCapGroupsAtAirbase(airbaseId)
    o.database  = database
    o.airbaseId = airbaseId
    o.logger = logger
    o.activeStage = 0
    o.capConfig = capConfig

    if capConfig == nil then
        capConfig = {}
        Spearhead.AddMissionEditorWarning("CapConfig is nil")
    else
        if capConfig.minSpeed == nil then Spearhead.AddMissionEditorWarning("CapConfig.minSpeed is nil") end
        if capConfig.maxSpeed == nil then Spearhead.AddMissionEditorWarning("CapConfig.maxSpeed is nil") end
        if capConfig.minAlt == nil then Spearhead.AddMissionEditorWarning("CapConfig.minAlt is nil") end
        if capConfig.maxAlt == nil then Spearhead.AddMissionEditorWarning("CapConfig.maxAlt is nil") end
        if capConfig.minDurationOnStation == nil then Spearhead.AddMissionEditorWarning("CapConfig.minDurationOnStation is nil") end
        if capConfig.maxDurationOnStation == nil then Spearhead.AddMissionEditorWarning("CapConfig.maxDurationOnStation is nil") end
        if capConfig.rearmDelay == nil then Spearhead.AddMissionEditorWarning("CapConfig.rearmDelay is nil") end
        if capConfig.deathDelay == nil then Spearhead.AddMissionEditorWarning("CapConfig.deathDelay is nil") end
    end

    o.activeCapStages = (stageConfig or {}).capActiveStages or 10

    o.lastStatesByName = {}
    o.groupsByName = {}
    o.PrimaryGroups = {}
    o.BackupGroups = {}

    local CheckReschedulingAsync = function(self, time)
        self:CheckAndScheduleCAP()
    end

    o.OnGroupStateUpdated = function (self, capGroup)
        --[[
            There is no update needed for INTRANSIT, ONSTATION or REARMING as the PREVIOUS state already was checked and nothing changes in the actual overal state.
        ]]--
        if  capGroup.state == Spearhead.internal.CapGroup.GroupState.INTRANSIT 
            or capGroup.state == Spearhead.internal.CapGroup.GroupState.ONSTATION 
            or capGroup.state == Spearhead.internal.CapGroup.GroupState.REARMING
        then
            return
        end
        timer.scheduleFunction(CheckReschedulingAsync, self, timer.getTime() + 1)
    end

    for key, name in pairs(o.groupNames) do
        local capGroup = Spearhead.internal.CapGroup:new(name, airbaseId, logger, database, capConfig)
        if capGroup then
            o.groupsByName[name] = capGroup

            if capGroup.isBackup ==true then
                table.insert(o.BackupGroups, capGroup)
            else
                table.insert(o.PrimaryGroups, capGroup)
            end

            capGroup:AddOnStateUpdatedListener(o)
        end
    end
    logger:info("Airbase with Id '" .. airbaseId .. "' has a total of " .. Spearhead.Util.tableLength(o.groupsByName) .. "cap flights registered")

    o.SpawnIfApplicable = function(self)
        self.logger:debug("Check spawns for airbase " .. self.airbaseId )
        for groupName, capGroup in pairs(self.groupsByName) do
            
            local activeStage = tostring(self.activeStage)
            local targetStage = capGroup:GetTargetZone(activeStage)

            if targetStage ~= nil and capGroup.state == Spearhead.internal.CapGroup.GroupState.UNSPAWNED then
                capGroup:SpawnOnTheRamp()
            end
        end
    end

    o.CheckAndScheduleCAP = function (self)

        self.logger:debug("Check taskings for airbase " .. self.airbaseId )
        
        local countPerStage = {}
        local requiredPerStage = {}

        --Count back up groups that are active or reassign to the new zone if that's needed
        for _, backupGroup in pairs(self.BackupGroups) do
            if backupGroup.state == Spearhead.internal.CapGroup.GroupState.INTRANSIT or backupGroup.state == Spearhead.internal.CapGroup.GroupState.ONSTATION then
                local supposedTargetStage = backupGroup:GetTargetZone(self.activeStage)
                if supposedTargetStage then
                    if supposedTargetStage ~= backupGroup.assignedStageNumber then
                        backupGroup:SendToStage(supposedTargetStage)
                    end
    
                    if countPerStage[supposedTargetStage] == nil then
                        countPerStage[supposedTargetStage] = 0
                    end
                    countPerStage[supposedTargetStage] = countPerStage[supposedTargetStage] + 1
                else
                    backupGroup:SendRTBAndDespawn()
                end
            elseif backupGroup.state == Spearhead.internal.CapGroup.GroupState.RTBINTEN and backupGroup:GetTargetZone(self.activeStage) ~= backupGroup.assignedStageNumber then
                backupGroup:SendRTB()
            end
        end

        --Schedule or reassign primary units if applicable
        for _, primaryGroup in pairs(self.PrimaryGroups) do
            local supposedTargetStage = primaryGroup:GetTargetZone(self.activeStage)
            if supposedTargetStage then
                if requiredPerStage[supposedTargetStage] == nil then
                    requiredPerStage[supposedTargetStage] = 0
                end

                if countPerStage[supposedTargetStage] == nil
                 then
                    countPerStage[supposedTargetStage] = 0
                end

                requiredPerStage[supposedTargetStage] =  requiredPerStage[supposedTargetStage] + 1

                if primaryGroup.state == Spearhead.internal.CapGroup.GroupState.READYONRAMP then
                    if countPerStage[supposedTargetStage] < requiredPerStage[supposedTargetStage] then
                        primaryGroup:SendToStage(supposedTargetStage)
                        countPerStage[supposedTargetStage] = countPerStage[supposedTargetStage] + 1
                    end
                elseif primaryGroup.state == Spearhead.internal.CapGroup.GroupState.INTRANSIT or primaryGroup.state == Spearhead.internal.CapGroup.GroupState.ONSTATION then
                    if supposedTargetStage ~= primaryGroup.assignedStageNumber then
                        if countPerStage[supposedTargetStage] < requiredPerStage[supposedTargetStage] then
                            primaryGroup:SendToStage(supposedTargetStage)
                        else
                            countPerStage[supposedTargetStage] = countPerStage[supposedTargetStage] + 1
                            primaryGroup:SendRTB()
                        end
                    end
                    countPerStage[supposedTargetStage] = countPerStage[supposedTargetStage] + 1
                elseif primaryGroup.state == Spearhead.internal.CapGroup.GroupState.RTBINTEN and primaryGroup:GetTargetZone(self.activeStage) ~= primaryGroup.assignedStageNumber then
                    primaryGroup:SendRTB()
                end
            else
                primaryGroup:SendRTBAndDespawn()
            end
        end

        for _, backupGroup in pairs(self.BackupGroups) do
            if backupGroup.state == Spearhead.internal.CapGroup.GroupState.READYONRAMP then
                local supposedTargetStage = backupGroup:GetTargetZone(self.activeStage)
                if supposedTargetStage then
                    if countPerStage[supposedTargetStage] == nil then
                        countPerStage[supposedTargetStage] = 0
                    end
    
                    if countPerStage[supposedTargetStage] < requiredPerStage[supposedTargetStage] then
                        backupGroup:SendToStage(supposedTargetStage)
                        countPerStage[supposedTargetStage] = countPerStage[supposedTargetStage] + 1
                    end
                else
                    backupGroup:SendRTBAndDespawn()
                end
            end
        end
    end

    o.OnStageNumberChanged = function (self, number)
        self.activeStage = number
        self:SpawnIfApplicable()
        timer.scheduleFunction(CheckReschedulingAsync, self, timer.getTime() + 5)
    end

    ---Check if any CAP is active when a certain stage is active
    ---@param self table
    ---@param stageNumber number
    ---@return boolean
    o.IsBaseActiveWhenStageIsActive = function (self, stageNumber)
        for _, group in pairs(self.PrimaryGroups) do
            local target = group:GetTargetZone(stageNumber)
            if target ~= nil then
                return true
            end
        end
        return false
    end

    Spearhead.Events.AddStageNumberChangedListener(o)
    return o
end

if not Spearhead.internal then Spearhead.internal = {} end
Spearhead.internal.CapAirbase = CapBase
end --CapAirbase.lua

local dbLogger = Spearhead.LoggerTemplate:new("database", Spearhead.LoggerTemplate.LogLevelOptions.INFO)
local databaseManager = Spearhead.DB:new(dbLogger)

local capConfig = {
    maxDeviationRange = 46300, --25NM -- max engagement distance
    maxSpeed = 500,
    minAlt = 18000,
    maxAlt = 28000,
    minDurationOnStation = 1800,
    maxDurationOnStation = 2700,
    rearmDelay = 600,
    deathDelay = 1800,
    logLevel  = Spearhead.LoggerTemplate.LogLevelOptions.INFO
}

local stageConfig = {
    logLevel = Spearhead.LoggerTemplate.LogLevelOptions.INFO
}

Spearhead.internal.GlobalCapManager.start(databaseManager, capConfig, stageConfig)
Spearhead.internal.GlobalStageManager.start(databaseManager, stageConfig)
Spearhead.internal.GlobalFleetManager.start(databaseManager)

local SetStageDelayed = function(number, time)
    Spearhead.Events.PublishStageNumberChanged(number)
    return nil
end

timer.scheduleFunction(SetStageDelayed, 1, timer.getTime() + 3)

Spearhead.LoadingDone()
--Check lines of code in directory per file: 
-- Get-ChildItem . -Include *.lua -Recurse | foreach {""+(Get-Content $_).Count + " => " + $_.name }; && GCI . -Include *.lua* -Recurse | foreach{(GC $_).Count} | measure-object -sum |  % Sum  
-- find . -name '*.lua' | xargs wc -l

