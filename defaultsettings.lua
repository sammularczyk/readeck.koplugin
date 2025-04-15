local DataStorage = require("datastorage")

return {
  data_dir = DataStorage:getDataDir() .. "/readeck",
  server_url = nil,
  -- Authentication
  api_token = nil, --will be set automatically if username and password are set
  username = nil, --optional, if api_token is set
  password = nil, --optional, if api_token is set
}
