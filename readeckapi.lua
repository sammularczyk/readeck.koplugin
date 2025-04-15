local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("json")
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
    local url = self.url .. path .. "?"
    for q, v in pairs(query) do
        url = url .. q .. "=" .. v .. "&"
    end

    headers = headers or {}
    if not headers.Authorization then
        headers.Authorization = "Bearer " .. self.token
    end

    local _, code, header = http.request {
        url = self.url .. path,
        method = method,
        headers = headers,
        body = body,
        proxy = self.proxy,
        sink = sink
    }

    if code ~= 200 then
        return log_return_error("API call failed with status code " .. code)
    else
        return header
    end
end

function Api:callDownloadApi(file, method, path, query, body, headers)
    local sink = ltn12.sink.file(io.open(file, "wb"))
    return self:callApi(sink, method, path, query, body, headers)
end

function Api:callJsonApi(method, path, query, body, headers)
    local response_data = {}
    local sink = ltn12.sink.table(response_data)

    local code, header = self:callApi(sink, method, path, query, body, headers)
    if not code then
        return nil, header
    end

    local content = table.concat(response_data, "")
    local ok, result = pcall(json.decode, content)
    if ok then
        return result
    else
        return log_return_error("Failed to parse JSON in response: " .. tostring(result))
    end
end

function Api:bookmarkList()
    return self:callJsonApi("GET", "/bookmarks", {})
end

return Api
