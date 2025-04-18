# readeck.koplugin

A [KOReader](https://koreader.rocks/) plugin to add integration with your
[Readeck](https://readeck.org/en/) instance's API.

> [!WARNING]  
> THIS IS NOT YET IN A DECENTLY USABLE STATE.  
> Progress tracked in [TODO.md](./TODO.md)

## Installation

Simply put this repo (without the [koreader submodule](./koreader), as it's
only there for better Lua development integration) in your KOReader's plugin
folder (koreader/plugins).

## Usage

#TODO

## Configuration

#TODO

For now, the only way to configure is to create a readeck.lua file on your
koreader/settings folder:

```koreader/settings/readeck.lua
return {
  data_dir = nil -- default: require("datastorage"):getDataDir() .. "/readeck",
  server_url = "http(s)://[yourreadeckserver]/", -- mandatory
  -- Authentication
  api_token = "abcdefg123", -- mandatory for now
  username = nil, -- useless for now
  password = nil, -- useless for now
}
```

You can create your API token at https://\[yourreadeckserver]/profile/tokens.
Don't forget to set both the "Bookmarks: Read Only" and "Bookmarks: Write Only"
roles.

