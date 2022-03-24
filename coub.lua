dofile("table_show.lua")
dofile("urlcode.lua")
local urlparse = require("socket.url")
local http = require("socket.http")
JSON = (loadfile "JSON.lua")()

local item_dir = os.getenv("item_dir")
local warc_file_base = os.getenv("warc_file_base")
local item_type = nil
local item_name = nil
local item_value = nil

local selftext = nil

if urlparse == nil or http == nil then
  io.stdout:write("socket not corrently installed.\n")
  io.stdout:flush()
  abortgrab = true
end

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local discovered_items = {}
local discovered_audio = {}
local bad_items = {}
local ids = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

abort_item = function(item)
  abortgrab = true
  if not item then
    item = item_name
  end
  if not bad_items[item] then
    io.stdout:write("Aborting item " .. item .. ".\n")
    io.stdout:flush()
    bad_items[item] = true
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

processed = function(url)
  if downloaded[url] or addedtolist[url] then
    return true
  end
  return false
end

discover_item = function(item)
if string.match(item, "^user:") then return nil end
  discovered_items[item] = true
end

allowed = function(url, parenturl)
  return true
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local parenturl = parent["url"]
  local html = urlpos["link_expect_html"]

  --[[if not processed(url) and allowed(url, parent["url"]) then
    addedtolist[url] = true
    return true
  end]]
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function decode_codepoint(newurl)
    newurl = string.gsub(
      newurl, "\\[uU]([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])",
      function (s)
        return unicode_codepoint_as_utf8(tonumber(s, 16))
      end
    )
    return newurl
  end

  local function check(newurl)
    newurl = decode_codepoint(newurl)
    local origurl = url
    local url = string.match(newurl, "^([^#]+)")
    local url_ = string.match(url, "^(.-)[%.\\]*$")
    while string.find(url_, "&amp;") do
      url_ = string.gsub(url_, "&amp;", "&")
    end
    if not processed(url_)
      and string.match(url_, "^https?://[^/%.]+%..+")
      and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    newurl = decode_codepoint(newurl)
    if string.match(newurl, "['\"><]") then
      return nil
    end
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./") then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    newurl = decode_codepoint(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (
      string.match(newurl, "^https?:\\?/\\?//?/?")
      or string.match(newurl, "^[/\\]")
      or string.match(newurl, "^%./")
      or string.match(newurl, "^[jJ]ava[sS]cript:")
      or string.match(newurl, "^[mM]ail[tT]o:")
      or string.match(newurl, "^vine:")
      or string.match(newurl, "^android%-app:")
      or string.match(newurl, "^ios%-app:")
      or string.match(newurl, "^data:")
      or string.match(newurl, "^irc:")
      or string.match(newurl, "^%${")
    ) then
      check(urlparse.absolute(url, newurl))
    end
  end

  if allowed(url) and status_code < 300 then
    html = read_file(file)
    if string.match(url, "^https?://[^/]*coub%.com/api/v2/coubs/[^/]+$") then
      local json = JSON:decode(html)
      local permalink = json["permalink"]
      if not permalink then
        io.stdout:write("Bad video.\n")
        io.stdout:flush()
        abort_item()
      end
      ids[permalink] = true
      check("https://coub.com/view/" .. permalink)
      --check("https://coub.com/api/v2/coubs/" .. permalink .. "/category_suggestions?count=40")
      --check("https://coub.com/api/v2/coubs/" .. permalink)
      --check("https://coub.com/api/v2/coubs/" .. permalink .. ".json")
      for _, muted in pairs({"true", "false"}) do
        for _, autostart in pairs({"true", "false"}) do
          for _, originalSize in pairs({"true", "false"}) do
            for _, startWithHD in pairs({"true", "false"}) do
              --check("https://coub.com/embed/18rpdy?muted=" .. muted .. "&autostart=" .. autostart .. "&originalSize=" .. originalSize .. "&startWithHD=" .. startWithHD)
            end
          end
        end
      end
      local id = tostring(json["id"])
      --check("https://coub.com/api/v2/coubs/" .. id)
      --check("https://coub.com/api/v2/coubs/" .. id .. "/segments")
      --check("https://coub.com/api/v2/coubs/" .. id .. ".json")
      discovered_items["c:" .. tostring(json["channel_id"])] = true
      for _, tag in pairs(json["tags"]) do
        discovered_items["t:" .. tostring(tag["id"]) .. ":" .. tag["value"]] = true
      end
    end
    if string.match(url, "^https?://[^/]*coub%.com/view/") then
      local json = JSON:decode(string.match(html, "<script%s+id='coubPageCoubJson'%s+type='text/json'>%s*({.-})%s*</script>"))
      local image_url = json["first_frame_versions"]["template"]
      for _, version in pairs(json["first_frame_versions"]["versions"]) do
        check(string.gsub(image_url, "%%{version}", version))
      end
      image_url = json["image_versions"]["template"]
      check(string.gsub(image_url, "%%{version}", "med"))
      local html5_data = json["file_versions"]["html5"]
      local found_data = {}
      for _, type_ in pairs({"video", "audio"}) do
        local current_url = nil
        local current_size = 0
        for quality, data in pairs(html5_data[type_]) do
          if quality ~= "sample_duration" and data["size"] ~= nil and data["size"] > current_size then
            current_url = data["url"]
            current_size = data["size"]
          end
        end
        if current_url then
          check(current_url)
          found_data[type_] = true
        end
      end
      if not found_data["video"] then
        io.stdout:write("Could not find video.\n")
        io.stdout:flush()
        abort_item()
      end
      local download_url = json["file_versions"]["share"]["default"]
      if download_url then
        check(download_url)
        check(download_url .. "?dl=1")
      end
    end
    if string.match(url, "^https?://[^/]*coub%.com/api/v2/coubs/[^/]+/segments") then
      local json = JSON:decode(html)
      local found_cutter = false
      for _, data in pairs(json["segments"]) do
        local cutter_ios = data["cutter_ios"]
        if string.match(cutter_ios, "^https?://") then
          found_cutter = true
          check(cutter_ios)
        end
      end
      if not found_cutter then
        io.stdout:write("Could not find cutter_ios video.\n")
        io.stdout:flush()
        os.execute("sleep 10")
        abort_item()
      end
      if json["audio_track"] then
        if json["audio_track"]["file"] then
          discovered_audio[json["audio_track"]["file"]] = true
        end
        if json["audio_track"]["image"] then
          discovered_audio[json["audio_track"]["image"]] = true
        end
      end
    end
    --[[for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end]]
  end

  return urls
end

wget.callbacks.write_to_warc = function(url, http_stat)
  if http_stat["statcode"] >= 500 then
    return false
  end
  return true
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. " \n")
  io.stdout:flush()

  local value = string.match(url["url"], "^https?://coub%.com/api/v2/coubs/([0-9]+)$")
  local type_ = "v"
  if value then
    abortgrab = false
    item_type = type_
    item_value = value
    item_name = item_type .. ":" .. item_value
    ids[item_value] = true
    print("Archiving item " .. item_name)
  end

  if status_code >= 300 and status_code <= 399 then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if processed(newloc) or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab then
    abort_item()
    return wget.actions.ABORT
  end
  
  if status_code >= 500
    or (status_code >= 400 and status_code ~= 404)
    or status_code  == 0 then
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 3
    if not allowed(url["url"]) then
        maxtries = 2
    end
    if tries >= maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.ABORT
    end
    os.execute("sleep " .. math.floor(math.pow(2, tries)))
    tries = tries + 1
    return wget.actions.CONTINUE
  end

  tries = 0

  local sleep_time = 0

  if string.match(url["url"], "^https?://coub%.com/") then
    sleep_time = 2
  end

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local function submit_backfeed(newurls, key)
    local tries = 0
    local maxtries = 4
    while tries < maxtries do
      local body, code, headers, status = http.request(
        "https://legacy-api.arpa.li/backfeed/legacy/" .. key,
        newurls .. "\0"
      )
      print(body)
      if code == 200 then
        io.stdout:write("Submitted discovered URLs.\n")
        io.stdout:flush()
        break
      end
      io.stdout:write("Failed to submit discovered URLs." .. tostring(code) .. tostring(body) .. "\n")
      io.stdout:flush()
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
    end
    if tries == maxtries then
      abortgrab = true
    end
  end

  local file = io.open(item_dir .. "/" .. warc_file_base .. "_bad-items.txt", "w")
  for url, _ in pairs(bad_items) do
    file:write(url .. "\n")
  end
  file:close()
  for key, data in pairs({
    ["coub-0q4i22xyiuzecha"] = discovered_items,
    ["coub-tracks-n713kvf8dhuc9x0"] = discovered_audio
  }) do
    local newurls = nil
    local count = 0
    for newurl, _ in pairs(data) do
      print("found item", newurl)
      if items == nil then
        newurls = newurl
      else
        newurls = newurls .. "\0" .. newurl
      end
      count = count + 1
      if count == 100 then
        submit_backfeed(newurls, key)
        newurls = nil
        count = 0
      end
    end
    if newurls ~= nil then
      submit_backfeed(newurls, key)
    end
  end
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab then
    abort_item()
  end
  return exit_status
end
