local http = require("socket.http")
local url = require("socket.url")
local ltn12 = require("ltn12")
-- Apparently https://github.com/harningt/luajson
local rapidjson = require("rapidjson")
local logger = require("logger")

local function log_return_error(err_msg)
    err_msg = "Readeck API error: " .. err_msg
    logger.warn(err_msg)
    return nil, err_msg
end

local Api = {
    url = nil,
    token = nil,
    proxy = nil,
}

function Api:new(o)
    if not o
        or not o.url
        or not o.token then
        return nil
    end

    setmetatable(o, self)
    self.__index = self

    if not o.url:match("/api$") then
        o.url = o.url .. "/api"
    end

    return o
end

function Api:buildUrl(path, query)
    local target_url = self.url .. "/" .. path .. "?"
    for q, val in pairs(query or {}) do
        if val ~= rapidjson.null then
            if type(val) == "table" then
                -- If an array, add the query several times
                for i, elt in pairs(val) do
                    if elt ~= rapidjson.null then
                        target_url = target_url .. url.escape(q) .. "=" .. url.escape(tostring(elt)) .. "&"
                    end
                end
            else
                target_url = target_url .. url.escape(q) .. "=" .. url.escape(tostring(val)) .. "&"
            end
        end
    end
    return target_url
end

---
-- @param sink
-- @param method GET, POST, DELETE, PATCH, etc…
-- @param path URL endpoint on Readeck server, without "<hostname>/api"
-- @query[opt] query Query to include in the url, if needed
-- @param[opt] body Body to include in the request, if needed
-- @param[opt] headers Defaults to Authorization for API endpoints, none for external
-- @return header, or nil
-- @return nil, or error message
function Api:callApi(sink, method, path, query, body, headers)
    local target_url = self:buildUrl(path, query)
    logger.dbg("Readeck API: Sending " .. method .. " " .. target_url)

    headers = headers or {}
    if not headers.Authorization then
        headers.Authorization = "Bearer " .. self.token
    end

    local source = body
    if type(body) == "table" then
        -- Convert body to JSON
        -- TODO check if this is still compatible with rapidjson (was maed for "luajson")
        local bodyJson = rapidjson.encode(body)
        logger.dbg("JSON: ", bodyJson)
        source = ltn12.source.string(bodyJson)

        headers["Content-type"] = "application/json"
        headers["Content-Length"] = tostring(#bodyJson)
    end

    local _, code, header = http.request {
        url = target_url,
        method = method,
        headers = headers,
        proxy = self.proxy,
        sink = sink,
        source = source,
    }

    if code >= 400 then
        return log_return_error("API call failed with status code " .. code)
    else
        return header
    end
end

function Api:callDownloadApi(file, method, path, query, body, headers)
    local sink = ltn12.sink.file(io.open(file, "wb"))
    return self:callApi(sink, method, path, query, body, headers)
end

---
-- @return Lua table parsed from response JSON, or nil
-- @return The response headers, or error message
function Api:callJsonApi(method, path, query, body, headers)
    headers = headers or {}
    headers["Accept"] = "application/json"

    local response_data = {}
    local sink = ltn12.sink.table(response_data)

    local resp_headers, err = self:callApi(sink, method, path, query, body, headers)
    if not resp_headers then
        return nil, err
    end

    local content = table.concat(response_data, "")
    logger.dbg("Readeck API response: " .. content)

    -- TODO check if this is still compatible with rapidjson (was maed for "luajson")
    local ok, result = pcall(rapidjson.decode, content, { null = "BABEU" })
    if ok then
        -- Empty JSON responses return nil, but we'd want an empty table
        return result or {}, resp_headers
    else
        return log_return_error("Failed to parse JSON in response: " .. tostring(result))
    end
end

--- See https://your.readeck/docs/api#get-/bookmarks
function Api:bookmarkList(query)
    return self:callJsonApi("GET", "/bookmarks", query)
end

--- See https://your.readeck/docs/api#post-/bookmarks
-- @return The new bookmark's id, or nil
-- @return nil, or error message
function Api:bookmarkCreate(bookmark_url, title, labels)
    local response, headers = self:callJsonApi("POST", "/bookmarks", {}, {
        url = bookmark_url,
        title = #title ~= 0 and title or nil,
        labels = #labels ~= 0 and labels or nil,
    })
    if not response or not headers then
        return response, headers
    end

    logger.dbg("Readeck: Bookmark created: " .. tostring(headers["bookmark-id"]))
    return headers["bookmark-id"]
end

--- See http://your.readeck/docs/api#get-/bookmarks/-id-
-- @return A table with the bookmark's details
function Api:bookmarkDetails(id)
    return self:callJsonApi("GET", "/bookmarks/" .. id)
end

-- TODO bookmarkDelete
-- TODO bookmarkUpdate

-- TODO bookmarkArticle?

--- See https://your.readeck/docs/api#get-/bookmarks/-id-/article.-format-
-- @return Response header, or nil
-- @return nil, or error message
function Api:bookmarkExport(file, id)
    return self:callDownloadApi(file, "GET", "/bookmarks/" .. id .. "/article.epub", nil, nil, { ["Accept"] = "application/epub+zip" })
end

--- See https://your.readeck/docs/api#get-/bookmarks/labels
function Api:labelList()
    return self:callJsonApi("GET", "/bookmarks/labels")
end

-- TODO labelInfo
-- TODO labelDelete
-- TODO labelUpdate

-- TODO highlightList
-- TODO bookmarkHighlights
-- TODO highlightCreate
-- TODO highlightDelete
-- TODO highlightUpdate

--- See https://your.readeck/docs/api#get-/bookmarks/collections
function Api:collectionList()
    -- TODO define limits and pagination?
    return self:callJsonApi("GET", "/bookmarks/collections")
end

-- TODO collectionCreate

--- See https://your.readeck/docs/api#get-/bookmarks/collections/-id-
function Api:collectionDetails(id)
    return self:callJsonApi("GET", "/bookmarks/collections/" .. id)
end

-- TODO collectionDelete
-- TODO collectionUpdate

return Api
