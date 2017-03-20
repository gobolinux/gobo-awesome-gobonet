
local gobonet = {}

local gears = require("gears")
local timer = gears.timer or timer
local mouse = mouse
local awful = require("awful")
local wibox = require("wibox")
local beautiful = require("beautiful")
local spawn = require("awful.spawn")
local core = require("gobo.awesome.gobonet.core")

local wlan_interface
local wired_interface

local function pread(cmd)
   local pd = io.popen(cmd, "r")
   if not pd then
      return ""
   end
   local data = pd:read("*a")
   pd:close()
   return data
end

local function read_wifi_level()
   local fd = io.open("/proc/net/wireless", "r")
   if fd then
      fd:read("*l")
      fd:read("*l")
      local data = fd:read("*l")
      fd:close()
      if data then
         local value = data:match("^%s*[^%s]+:%s+[^%s]+%s*(%d+)")
         if value then
            return tonumber(value)
         end
      end
   end
end

local function quality_icon(quality)
   if quality >= 75 then
      return beautiful.wifi_3_icon
   elseif quality >= 50 then
      return beautiful.wifi_2_icon
   elseif quality >= 25 then
      return beautiful.wifi_1_icon
   else
      return beautiful.wifi_0_icon
   end
end

local run = awful.spawn and awful.spawn.with_shell or awful.util.spawn_with_shell

local function disconnect()
   run("gobonet disconnect")
end

local function forget(essid)
   run("gobonet forget '"..essid:gsub("'", "'\\''").."'")
end

local function compact_entries(entries)
   local limit = 20
   if #entries > limit then
      local submenu = {}
      for i = limit + 1, #entries do
         table.insert(submenu, entries[i])
         entries[i] = nil
      end
      compact_entries(submenu)
      table.insert(entries, { "More...", submenu } )
   end
end

function gobonet.new()
   local widget = wibox.widget.imagebox()
   local menu
   local wifi_menu_fn
   
   if not wlan_interface then
      wlan_interface = pread("gobonet interface")
   end

   if not wired_interface then
      wired_interface = pread("gobonet wired_interface")
      -- Outdated GoboNet
      if wired_interface:match("^GoboNet") then
         wired_interface = nil
      end
      wired_interface = wired_interface:gsub("\n", "")
      -- No wired interface
      if wired_interface == "" then
         wired_interface = nil
      end
   end

   if not (wlan_interface or wired_interface) then
      return widget
   end
   
   local is_scanning = function() return false end
   local is_connecting = function() return false end

   local function animated_operation(args)
      local cmd = args.command
      local popup_menu = args.popup_menu_when_done or false
      if not cmd then return end
      local waiting
      local is_waiting = function()
         if not waiting then return false end
         if waiting() ~= true then
            return true
         end
         waiting = nil
         return false
      end
      return function()
         if is_waiting() then
            return is_waiting
         end
         do
            local done = false
            waiting = function()
               return done
            end
            spawn.easy_async(cmd, function()
               done = true
            end)
         end
         local frames = args.frames or {
            beautiful.wifi_0_icon,
            beautiful.wifi_1_icon,
            beautiful.wifi_2_icon,
            beautiful.wifi_3_icon,
         }
         local step = 1
         local animation_timer = timer({timeout=0.25})
         local function animate()
            if is_waiting() then
               widget:set_image(frames[step])
               step = step + 1
               if step == #frames + 1 then step = 1 end
            else
               animation_timer:stop()
               if popup_menu then
                  if menu then
                     menu:hide()
                     menu = nil
                  end
                  wifi_menu_fn(true)
               end
            end
         end
         animation_timer:connect_signal("timeout", animate)
         animation_timer:start()
         return is_waiting
      end
   end
   
   local function is_external_scanning()
      local pidfilename = os.getenv("HOME").."/.cache/GoboNet/wifi/.connecting.pid"
      local pidfd = io.open(pidfilename, "r")
      if not pidfd then return false end
      local pid = pidfd:read("*l")
      pidfd:close()
      local statfilename = "/proc/"..pid.."/stat"
      local statfd = io.open(statfilename, "r")
      if not statfd then
         os.remove(pidfilename)
         return false
      end
      statfd:close()
      is_scanning = animated_operation { command = "bash -c 'while grep -q gobonet \""..statfilename.."\"; do sleep 0.5; done; rm \""..pidfilename.."\"'" } ()
      return true
   end

   local rescan = animated_operation { command = "gobonet_backend full-scan "..wlan_interface, popup_menu_when_done = true }

   local function connect(essid)
      return animated_operation { command = "gobonet connect '"..essid:gsub("'", "'\\''").."'" } ()
   end

   local function autoconnect()
      return animated_operation { command = "gobonet autoconnect" } ()
   end

   local function connect_wired()
      return animated_operation { command = "gobonet connect_wired", frames = { beautiful.wired_up_icon, beautiful.wired_down_icon } } ()
   end
   
   local last_update = os.time()
   local function update()
      local prev_update = last_update
      last_update = os.time()
      if is_scanning() or is_connecting() or is_external_scanning() then
         return
      end
      if wired_interface then
         local pok, up, running = pcall(core.up_and_running, wired_interface)
         if pok and up and running then
            widget:set_image(beautiful.wired_up_icon)
            return
         end
      end
      local wifi_level = read_wifi_level()
      if not wifi_level then
         if wlan_interface then
            widget:set_image(beautiful.wifi_down_icon)
         else
            widget:set_image(beautiful.wired_down_icon)
         end
         -- A long time elapsed between updates probably means
         -- the computer went asleep. Let's try to autoconnect.
         if last_update - prev_update > 10 then
            is_connecting = autoconnect()
         end
      else
         local quality = (tonumber(wifi_level) / 70) * 100
         widget:set_image(quality_icon(quality))
      end
   end
   
   local coords
   wifi_menu_fn = function(auto_popped)
      if not auto_popped then
         coords = mouse.coords()
      end
      if menu then
         if menu.wibox.visible then
            menu:hide()
            menu = nil
            return
         else
            menu = nil
         end
      end
      local iwconfig = pread("iwconfig")
      local my_essid = iwconfig:match('ESSID:"([^\n]*)"%s*\n')
      local scan = ""
      if not is_scanning() then
         scan = pread("gobonet_backend quick-scan "..wlan_interface)
      end
      local entries = {}
      local curr_entry
      for key, value in scan:gmatch("%s*([^:=]+)[:=]([^\n]*)\n") do
         if key:match("^Cell ") then
            if curr_entry then
               table.insert(entries, curr_entry)
            end
            curr_entry = { [1] = " " .. value:gsub(" ", "") }
         elseif key == "ESSID" then
            local essid = value:match('^"(.*)"$')
            if essid ~= "" then
               local label = " " .. essid
               curr_entry[1] = label
               curr_entry[2] = function() is_connecting = connect(essid) end
            end
         elseif key == "Quality" then
            local cur, max = value:match("^(%d+)/(%d+)")
            local quality = (tonumber(cur) / tonumber(max)) * 100
            curr_entry.quality = quality
            curr_entry[3] = quality_icon(quality)
         end
      end
      if curr_entry then
         table.insert(entries, curr_entry)
      end
      table.sort(entries, function(a,b) 
         return (a.quality or 0) > (b.quality or 0)
      end)
      if my_essid then
         local disconnect_msg = is_connecting() and " Cancel connecting to " or " Disconnect "
         table.insert(entries, 1, { disconnect_msg .. my_essid, function() disconnect() end })
         table.insert(entries, 2, { " Forget " .. my_essid, function() forget(my_essid) end })
      end
      if is_scanning() then
         table.insert(entries, { " Scanning..." })
      elseif #entries == 0 and not auto_popped then
         table.insert(entries, { " Scanning..." })
         is_scanning = rescan()
      else
         table.insert(entries, { " Rescan", function() is_scanning = rescan() end } )
      end
      if wired_interface then
         table.insert(entries, 1, { " Wired network ("..wired_interface..") ", function() connect_wired() end, beautiful.wired_up_icon })
      end
      local len = 10
      for _, entry in ipairs(entries) do
         len = math.max(len, (#entry[1] + 1) * 10 )
      end
      entries.theme = { height = 24, width = len }
      compact_entries(entries)
      menu = awful.menu.new(entries)
      menu:show({ coords = coords })
   end
   
   widget:buttons(awful.util.table.join(
      awful.button({ }, 1, function() wifi_menu_fn() end ),
      awful.button({ }, 3, function() wifi_menu_fn() end )
   ))
   
   local wifi_timer = timer({timeout=2})
   wifi_timer:connect_signal("timeout", update)
   update()
   wifi_timer:start()
   
   return widget
end

return gobonet

