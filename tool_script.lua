--[[
    Sane Little Helper
    Developer: #samauelisdumbaf
    Version: 1.0.0
    Description: Advanced Roblox exploitation tool for remote event/function interception, logging, and replay.
]]

-- Ensure a clean environment for SLH or reuse if already loaded
if getgenv().SLH and getgenv().SLH.Info and getgenv().SLH.Info.Name == "Sane Little Helper" then
    if getgenv().SLH.UserInterface and getgenv().SLH.UserInterface.ToggleWindow then
        getgenv().SLH.UserInterface.ToggleWindow() -- If UI exists, just toggle it
    end
    return -- Avoid re-executing the whole script
end

local success, err = pcall(function()

    getgenv().SLH = {
        Info = {
            Name = "Sane Little Helper",
            Author = "#samauelisdumbaf",
            Version = "1.0.0"
        },
        Config = {
            MaxLogEntries = 250,
            TimestampFormat = "%H:%M:%S",
            AutoAttachOnLoad = true,
            DebugMode = false,
            UI_Lib_URL = "https://raw.githubusercontent.com/shlexware/Orion/main/source.lua", -- Popular choice
            ArgumentDisplayMaxLength = 100, -- Max length for displayed args in log list
            RemoteScanLocations = { -- Default locations to scan for remotes
                "ReplicatedStorage",
                "Workspace",
                "Lighting",
                "SoundService",
                -- Player specific services will be added when player is available
            },
            PlayerScanLocations = { -- To be scanned under LocalPlayer
                "PlayerGui",
                "Backpack"
            }
        },
        State = {
            Logs = {},
            HookedRemotes = {}, -- key: remote:GetFullName(), value: { remote, originalFireServer, originalInvokeServer, type }
            IsHookingActive = false,
            SelectedLogEntry = nil, -- Stores the actual log table entry
            UI = {
                Initialized = false,
                Visible = false,
                Window = nil,
                Tabs = {},
                Elements = {
                    LogList = nil,
                    ArgDisplay = nil,
                    ModArgsInput = nil,
                },
                LogListCache = {} -- Cache for UI log list items
            },
            Services = {}, -- Cached services
        },
        -- Placeholder for loaded UI Library
        UILib = nil,

        -- Core Modules (will be populated by functions)
        Utils = {},
        LogManager = {},
        RemoteInterceptor = {},
        RemoteActions = {},
        UserInterface = {},
    }

    local SLH = getgenv().SLH -- Local shorthand for easier access

    --[[----------------------------------------------------------------------------------
        SECTION: UTILITIES (SLH.Utils)
    ------------------------------------------------------------------------------------]]
    function SLH.Utils.PrintDebug(source, ...)
        if SLH.Config.DebugMode then
            local args = {...}
            local message = ""
            for i, v in ipairs(args) do
                message = message .. tostring(v) .. (i == #args and "" or "\t")
            end
            print("[SLH DEBUG | " .. tostring(source) .. "] " .. message)
        end
    end

    function SLH.Utils.PrintInfo(source, ...)
        local args = {...}
        local message = ""
        for i, v in ipairs(args) do
            message = message .. tostring(v) .. (i == #args and "" or "\t")
        end
        print("[SLH INFO | " .. tostring(source) .. "] " .. message)
    end
    
    function SLH.Utils.PrintError(source, ...)
        local args = {...}
        local message = ""
        for i, v in ipairs(args) do
            message = message .. tostring(v) .. (i == #args and "" or "\t")
        end
        warn("[SLH ERROR | " .. tostring(source) .. "] " .. message)
    end

    function SLH.Utils.GetService(serviceName)
        if not SLH.State.Services[serviceName] then
            local status, service = pcall(game.GetService, game, serviceName)
            if status and service then
                SLH.State.Services[serviceName] = service
            else
                SLH.Utils.PrintError("GetService", "Failed to get service:", serviceName, status and "" or service)
                return nil
            end
        end
        return SLH.State.Services[serviceName]
    end

    function SLH.Utils.RecursiveFindInstances(parent, className)
        local found = {}
        if typeof(parent) ~= "Instance" then return found end

        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA(className) then
                table.insert(found, child)
            end
            local childrenFound = SLH.Utils.RecursiveFindInstances(child, className)
            for _, subChild in ipairs(childrenFound) do
                table.insert(found, subChild)
            end
        end
        return found
    end
    
    function SLH.Utils.GetRemotePath(remote)
        if not remote or notราคาremote.Parent then return "UnknownPath" end
        local path = {}
        local current = remote
        while current ~= game and current.Parent do
            table.insert(path, 1, current.Name)
            current = current.Parent
        end
        if current ~= game then table.insert(path, 1, "[NonGameParent]") end
        return table.concat(path, ".")
    end

    function SLH.Utils.FindRemoteByPath(path)
        if type(path) ~= "string" then return nil end
        local parts = path:split(".")
        local current = game
        for _, partName in ipairs(parts) do
            if typeof(current) == "Instance" then
                current = current:FindFirstChild(partName)
                if not current then return nil end
            else
                return nil
            end
        end
        return current
    end

    function SLH.Utils.DeepSerialize(val, depth)
        depth = depth or 0
        if depth > 5 then return "{...max_depth...}" end -- Prevent infinite recursion / too large tables

        local t = type(val)
        if t == "string" then
            return string.format("%q", val)
        elseif t == "table" then
            local parts = {}
            local isArray = true
            local maxIndex = 0
            for k, _ in pairs(val) do
                if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                    isArray = false
                    break
                end
                maxIndex = math.max(maxIndex, k)
            end
            if isArray and maxIndex > #val then isArray = false end -- Sparse array is not treated as array

            if isArray then
                 for i = 1, #val do
                    table.insert(parts, SLH.Utils.DeepSerialize(val[i], depth + 1))
                end
            else -- dictionary style
                for k, v in pairs(val) do
                    local kStr = type(k) == "string" and string.match(k, "^[%a_][%w_]*$") and k or "[" .. SLH.Utils.DeepSerialize(k, depth + 1) .. "]"
                    table.insert(parts, kStr .. "=" .. SLH.Utils.DeepSerialize(v, depth + 1))
                end
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        elseif typeof(val) == "Instance" then
            return val:GetFullName() .. " (" .. val.ClassName .. ")"
        elseif t == "function" or t == "thread" or t == "userdata" then
            return "<" .. t .. ">"
        else
            return tostring(val)
        end
    end
    
    function SLH.Utils.TruncateString(str, maxLen)
        if #str > maxLen then
            return str:sub(1, maxLen - 3) .. "..."
        end
        return str
    end

    function SLH.Utils.ArgumentsToString(argsTable, maxLength)
        if not argsTable or #argsTable == 0 then return "()" end
        local serializedArgs = {}
        for _, arg_val in ipairs(argsTable) do
            table.insert(serializedArgs, SLH.Utils.DeepSerialize(arg_val))
        end
        local fullStr = table.concat(serializedArgs, ", ")
        if maxLength then
            return SLH.Utils.TruncateString(fullStr, maxLength)
        end
        return fullStr
    end

    -- Basic string to arguments parser (very simplified and potentially unsafe with loadstring)
    -- For UI: it's better to have separate input fields per argument or a structured editor.
    -- This is a simple approach for a single textbox.
    function SLH.Utils.ParseArgumentString(argString)
        if argString == nil or argString:match("^%s*$") then return {} end
        local funcStr = "return " .. argString
        local func, err = loadstring(funcStr)
        if not func then
            SLH.Utils.PrintError("ParseArgumentString", "Failed to parse arguments: " .. err)
            return nil, "Syntax error: " .. err
        end
        local success, result = pcall(func)
        if not success then
            SLH.Utils.PrintError("ParseArgumentString", "Error executing parsed arguments: " .. result)
            return nil, "Execution error: " .. result
        end
        if type(result) == "table" and not getmetatable(result) and #result == 0 and next(result) == nil then -- Check if it looks like a single empty table was intended as a list
             -- If user types `{}`, loadstring returns one table. If they type `{arg1}, {arg2}`, it also works.
             -- If they type `arg1, arg2`, loadstring returns multiple values. We pack them.
             -- This is tricky. The standard is that FireServer takes varargs.
             -- Let's assume `loadstring("return "..s)()` will return the values as they should be passed.
            local packedResults = {result} -- this seems to handle single table correctly but not multiple args.
            -- The `loadstring` approach is better for varargs:
            funcStr = "local function TempFunc(...) return {...} end return TempFunc(" .. argString .. ")"
            func, err = loadstring(funcStr)
            if not func then
                SLH.Utils.PrintError("ParseArgumentString", "Failed to parse arguments (vararg attempt): " .. err)
                return nil, "Syntax error (vararg attempt): " .. err
            end
            success, result = pcall(func)
            if not success then
                 SLH.Utils.PrintError("ParseArgumentString", "Error executing parsed arguments (vararg attempt): " .. result)
                return nil, "Execution error (vararg attempt): " .. result
            end
            return result -- result is now a table of arguments
        end
        return {result} -- If single non-table value returned, wrap it
    end


    --[[----------------------------------------------------------------------------------
        SECTION: LOG MANAGER (SLH.LogManager)
    ------------------------------------------------------------------------------------]]
    SLH.LogManager.Initialize = function()
        SLH.State.Logs = {}
        SLH.Utils.PrintDebug("LogManager", "Initialized.")
    end

    SLH.LogManager.AddLogEntry = function(remoteName, remotePath, remoteInstance, remoteType, originalArgs)
        if not SLH.State.IsHookingActive then return end

        if #SLH.State.Logs >= SLH.Config.MaxLogEntries then
            table.remove(SLH.State.Logs, 1)
            -- Update UI LogListCache if needed, or let UI refresh handle it
            if SLH.State.UI.Initialized then
                 table.remove(SLH.State.UI.LogListCache, 1)
            end
        end

        local entry = {
            Id = os.clock(), -- More unique ID
            Timestamp = os.date(SLH.Config.TimestampFormat),
            Name = remoteName,
            Path = remotePath,
            RemoteInstance = remoteInstance, -- Store weak reference if possible or rely on path
            Type = remoteType, -- "Event" or "Function"
            Arguments = originalArgs, -- Store the raw arguments for replay
            SerializedArgs = SLH.Utils.ArgumentsToString(originalArgs, SLH.Config.ArgumentDisplayMaxLength),
            FullSerializedArgs = SLH.Utils.ArgumentsToString(originalArgs), -- For display in details
        }
        table.insert(SLH.State.Logs, entry)
        SLH.Utils.PrintDebug("LogManager", "Logged:", entry.Type, entry.Name, entry.SerializedArgs)

        if SLH.State.UI.Initialized and SLH.UserInterface.IsVisible and SLH.UserInterface.IsVisible() then
            SLH.UserInterface.RefreshLogList()
        end
        return entry
    end

    SLH.LogManager.GetLogs = function()
        return SLH.State.Logs
    end

    SLH.LogManager.ClearLogs = function()
        SLH.State.Logs = {}
        SLH.State.SelectedLogEntry = nil
        SLH.Utils.PrintInfo("LogManager", "Logs cleared.")
        if SLH.State.UI.Initialized then
            SLH.UserInterface.RefreshLogList()
            SLH.UserInterface.UpdateReplayTab() -- Clear details
        end
    end

    SLH.LogManager.SetSelectedLog = function(logEntry)
        SLH.State.SelectedLogEntry = logEntry
        SLH.Utils.PrintDebug("LogManager", "Selected log:", logEntry and logEntry.Name)
        if SLH.State.UI.Initialized then
            SLH.UserInterface.UpdateReplayTab()
        end
    end

    --[[----------------------------------------------------------------------------------
        SECTION: REMOTE INTERCEPTOR (SLH.RemoteInterceptor)
    ------------------------------------------------------------------------------------]]
    SLH.RemoteInterceptor.HookRemote = function(remote)
        local remotePath = SLH.Utils.GetRemotePath(remote)
        if SLH.State.HookedRemotes[remotePath] then
            -- SLH.Utils.PrintDebug("RemoteInterceptor", "Already hooked:", remotePath)
            return -- Already hooked
        end

        local hookData = { remote = remote, type = remote:IsA("RemoteEvent") and "Event" or "Function" }

        if not is_hookable(remote) then
             SLH.Utils.PrintDebug("RemoteInterceptor", "Remote not hookable (no FireServer/InvokeServer):", remotePath)
             return
        end

        if remote:IsA("RemoteEvent") then
            if not remote.FireServer or typeof(remote.FireServer) ~= "function" then
                SLH.Utils.PrintDebug("RemoteInterceptor", "RemoteEvent has no FireServer method:", remotePath)
                return
            end
            hookData.originalFireServer = remote.FireServer
            local newFireServer = newcclosure(function(self, ...)
                local args = {...}
                -- Log before forwarding to capture original args
                SLH.LogManager.AddLogEntry(self.Name, remotePath, self, "Event", args)
                -- Forward the call to the original FireServer
                return hookData.originalFireServer(self, unpack(args))
            end)
            -- Some exploits might require hookfunction if direct assignment is sandboxed/ineffective
            local success_hook = pcall(function() remote.FireServer = newFireServer end)
            if not success_hook then
                SLH.Utils.PrintError("RemoteInterceptor", "Failed to assign hook for RemoteEvent:", remotePath)
                return
            end

        elseif remote:IsA("RemoteFunction") then
            if not remote.InvokeServer or typeof(remote.InvokeServer) ~= "function" then
                SLH.Utils.PrintDebug("RemoteInterceptor", "RemoteFunction has no InvokeServer method:", remotePath)
                return
            end
            hookData.originalInvokeServer = remote.InvokeServer
            local newInvokeServer = newcclosure(function(self, ...)
                local args = {...}
                -- Log before forwarding
                local logEntry = SLH.LogManager.AddLogEntry(self.Name, remotePath, self, "Function", args)
                -- Forward the call and capture result/error
                local success, results = pcall(hookData.originalInvokeServer, self, unpack(args))
                if success then
                    if logEntry then logEntry.ReturnValues = results end -- Store return values if needed for advanced logging
                    return results -- Must return all results from original function
                else
                    SLH.Utils.PrintError("RemoteInterceptor", "Error during original InvokeServer call for " .. self.Name .. ": " .. tostring(results))
                    if logEntry then logEntry.Error = tostring(results) end
                    -- Decide what to return on error. Roblox typically errors the script.
                    -- Depending on exploit, may need to return nil or error(results)
                    error(results) -- Propagate the error
                end
            end)
            local success_hook = pcall(function() remote.InvokeServer = newInvokeServer end)
             if not success_hook then
                SLH.Utils.PrintError("RemoteInterceptor", "Failed to assign hook for RemoteFunction:", remotePath)
                return
            end
        else
            return -- Not a remote event or function
        end
        
        SLH.State.HookedRemotes[remotePath] = hookData
        SLH.Utils.PrintDebug("RemoteInterceptor", "Hooked:", remotePath, "("..hookData.type..")")
    end
    
    function is_hookable(instance) -- Ensure the remote actually has the methods we expect. Some custom remote systems might not.
        return (instance:IsA("RemoteEvent") and rawget(instance, "FireServer")) or 
               (instance:IsA("RemoteFunction") and rawget(instance, "InvokeServer"))
    end

    SLH.RemoteInterceptor.UnhookRemote = function(remote)
        local remotePath = SLH.Utils.GetRemotePath(remote)
        local hookData = SLH.State.HookedRemotes[remotePath]

        if not hookData then return end

        if hookData.type == "Event" and hookData.originalFireServer then
            remote.FireServer = hookData.originalFireServer
        elseif hookData.type == "Function" and hookData.originalInvokeServer then
            remote.InvokeServer = hookData.originalInvokeServer
        end
        SLH.State.HookedRemotes[remotePath] = nil
        SLH.Utils.PrintDebug("RemoteInterceptor", "Unhooked:", remotePath)
    end

    SLH.RemoteInterceptor.ScanAndHookContainer = function(container)
        if typeof(container) ~= "Instance" then return end
        SLH.Utils.PrintDebug("RemoteInterceptor", "Scanning container:", container:GetFullName())

        local remotes = SLH.Utils.RecursiveFindInstances(container, "RemoteEvent")
        for _, remote in ipairs(remotes) do
            SLH.RemoteInterceptor.HookRemote(remote)
        end

        remotes = SLH.Utils.RecursiveFindInstances(container, "RemoteFunction")
        for _, remote in ipairs(remotes) do
            SLH.RemoteInterceptor.HookRemote(remote)
        end
    end

    SLH.RemoteInterceptor.StartGlobalHooking = function()
        if SLH.State.IsHookingActive then return end
        SLH.State.IsHookingActive = true
        SLH.Utils.PrintInfo("RemoteInterceptor", "Global hooking started.")

        -- Initial scan of default locations
        for _, serviceName in ipairs(SLH.Config.RemoteScanLocations) do
            local service = SLH.Utils.GetService(serviceName)
            if service then
                SLH.RemoteInterceptor.ScanAndHookContainer(service)
            end
        end
        
        -- Scan player specific locations if player exists
        local LocalPlayer = SLH.Utils.GetService("Players").LocalPlayer
        if LocalPlayer then
            for _, locName in ipairs(SLH.Config.PlayerScanLocations) do
                 local locInstance = LocalPlayer:FindFirstChild(locName)
                 if locInstance then
                    SLH.RemoteInterceptor.ScanAndHookContainer(locInstance)
                 end
            end
            -- Also scan Character if it exists
            if LocalPlayer.Character then
                SLH.RemoteInterceptor.ScanAndHookContainer(LocalPlayer.Character)
            end
        end


        -- Potentially hook Instance.new or :GetChildren(), :ChildAdded for dynamic hooking (more complex and intrusive)
        -- For now, manual re-scan or periodic scan is safer.
    end

    SLH.RemoteInterceptor.StopGlobalHooking = function()
        if not SLH.State.IsHookingActive then return end
        SLH.State.IsHookingActive = false
        for remotePath, hookData in pairs(SLH.State.HookedRemotes) do
            if hookData.remote and hookData.remote.Parent then -- Check if remote still exists
                SLH.RemoteInterceptor.UnhookRemote(hookData.remote)
            end
        end
        SLH.State.HookedRemotes = {} -- Clear all hooks
        SLH.Utils.PrintInfo("RemoteInterceptor", "Global hooking stopped. All remotes unhooked.")
    end

    --[[----------------------------------------------------------------------------------
        SECTION: REMOTE ACTIONS (SLH.RemoteActions) - For Replay
    ------------------------------------------------------------------------------------]]
    SLH.RemoteActions.ReplayCall = function(logEntry, argumentsToUse)
        if not logEntry then
            SLH.Utils.PrintError("RemoteActions", "No log entry provided for replay.")
            return false, "No log entry"
        end

        local remote = logEntry.RemoteInstance
        -- Try to find by path if instance is gone or not stored directly
        if not remote or not remote.Parent then
            SLH.Utils.PrintDebug("RemoteActions", "RemoteInstance invalid in log, finding by path:", logEntry.Path)
            remote = SLH.Utils.FindRemoteByPath(logEntry.Path)
        end

        if not remote or notราคาremote.Parent then -- Final check
            SLH.Utils.PrintError("RemoteActions", "Remote for replay not found or invalid:", logEntry.Name, logEntry.Path)
            if SLH.State.UI.Initialized then SLH.UserInterface.ShowToast("Error: Remote " .. logEntry.Name .. " not found.", 5, "Error") end
            return false, "Remote not found"
        end

        local args_to_send = argumentsToUse or logEntry.Arguments -- Use provided args or original logged args

        local success, resultOrError
        local returnedValues

        SLH.Utils.PrintInfo("RemoteActions", "Replaying", logEntry.Type, logEntry.Name, "with args:", SLH.Utils.ArgumentsToString(args_to_send, 200))

        if logEntry.Type == "Event" then
            if typeof(remote.FireServer) ~= "function" then
                 SLH.Utils.PrintError("RemoteActions", "FireServer is not a function on remote:", remote:GetFullName())
                 if SLH.State.UI.Initialized then SLH.UserInterface.ShowToast("Error: FireServer invalid on " .. remote.Name, 5, "Error") end
                 return false, "FireServer invalid"
            end
            success, resultOrError = pcall(remote.FireServer, remote, unpack(args_to_send))
        elseif logEntry.Type == "Function" then
             if typeof(remote.InvokeServer) ~= "function" then
                 SLH.Utils.PrintError("RemoteActions", "InvokeServer is not a function on remote:", remote:GetFullName())
                 if SLH.State.UI.Initialized then SLH.UserInterface.ShowToast("Error: InvokeServer invalid on " .. remote.Name, 5, "Error") end
                 return false, "InvokeServer invalid"
            end
            success, resultOrError = pcall(function() returnedValues = {remote:InvokeServer(unpack(args_to_send))} end)
            -- pcall for InvokeServer returns success status, and then the actual return values are in the first element of `results` from the main pcall.
            -- This needs to be handled correctly.
            -- The above wraps it so `returnedValues` table captures all returns.
        else
            SLH.Utils.PrintError("RemoteActions", "Unknown remote type for replay:", logEntry.Type)
            if SLH.State.UI.Initialized then SLH.UserInterface.ShowToast("Error: Unknown remote type " .. logEntry.Type, 5, "Error") end
            return false, "Unknown remote type"
        end

        if not success then
            SLH.Utils.PrintError("RemoteActions", "Error replaying call to", logEntry.Name .. ":", tostring(resultOrError))
            if SLH.State.UI.Initialized then SLH.UserInterface.ShowToast("Replay Error: " .. tostring(resultOrError), 8, "Error") end
            return false, tostring(resultOrError)
        end

        local resultString = ""
        if logEntry.Type == "Function" and returnedValues then
            resultString = SLH.Utils.ArgumentsToString(returnedValues, 200)
            SLH.Utils.PrintInfo("RemoteActions", logEntry.Name, "replayed successfully. Result:", resultString)
        else
            SLH.Utils.PrintInfo("RemoteActions", logEntry.Name, "replayed successfully.")
        end
        
        if SLH.State.UI.Initialized then SLH.UserInterface.ShowToast("Replayed: " .. logEntry.Name .. (resultString ~= "" and " -> " .. resultString or ""), 5, "Success") end
        return true, returnedValues
    end

    --[[----------------------------------------------------------------------------------
        SECTION: USER INTERFACE (SLH.UserInterface)
        This section defines the UI structure. It requires a UI Library to be loaded.
        Example using Orion-like syntax.
    ------------------------------------------------------------------------------------]]
    SLH.UserInterface.IsVisible = function()
        return SLH.State.UI.Window and SLH.State.UI.Window.Visible
    end
    
    SLH.UserInterface.ShowToast = function(message, duration, toastType) -- types: "Info", "Success", "Error"
        toastType = toastType or "Info"
        if SLH.UILib and SLH.UILib.Notify then
            SLH.UILib.Notify({
                Title = SLH.Info.Name .. " (" .. toastType .. ")",
                Content = message,
                Duration = duration or 5,
            })
        else
            print("[" .. SLH.Info.Name .. " Toast | " .. toastType .. "] " .. message)
        end
    end

    SLH.UserInterface.Setup = function()
        if not SLH.UILib then
            SLH.Utils.PrintError("UserInterface", "UI Library not loaded. Cannot setup UI.")
            SLH.UserInterface.ShowToast("UI Library not loaded! UI unavailable.", 10, "Error")
            return
        end
        
        if SLH.State.UI.Window then -- Destroy old window if any
            pcall(function() SLH.State.UI.Window:Destroy() end)
            SLH.State.UI.Window = nil
        end

        local OrionWindow = SLH.UILib.MakeWindow({
            Name = SLH.Info.Name .. " v" .. SLH.Info.Version .. " by " .. SLH.Info.Author,
            HidePremium = true, -- If lib supports
            SaveConfig = true, -- If lib supports
            ConfigFolder = "SaneLittleHelperConfig", -- If lib supports
            IntroText = SLH.Info.Name,
        })
        SLH.State.UI.Window = OrionWindow -- Store the window object itself

        -- MAIN TAB
        local mainTab = OrionWindow:MakeTab({ Name = "Main", Icon = "rbxassetid://4483345998" }) SLH.State.UI.Tabs.Main = mainTab
        mainTab:AddButton({
            Name = "Toggle Hooking (Currently: OFF)",
            Callback = function(button)
                if SLH.State.IsHookingActive then
                    SLH.RemoteInterceptor.StopGlobalHooking()
                    button.Name = "Toggle Hooking (Currently: OFF)"
                else
                    SLH.RemoteInterceptor.StartGlobalHooking()
                    button.Name = "Toggle Hooking (Currently: ON)"
                end
                if SLH.UILib.SetButtonText then SLH.UILib.SetButtonText(button, button.Name) else button:SetText(button.Name) end -- Adapt for actual lib
            end
        }):SetText(SLH.State.IsHookingActive and "Toggle Hooking (Currently: ON)" or "Toggle Hooking (Currently: OFF)") -- Initial text based on state

        mainTab:AddButton({ Name = "Manual Scan & Hook All Remotes", Callback = function()
                if not SLH.State.IsHookingActive then
                    SLH.UserInterface.ShowToast("Hooking is not active. Please enable it first.", 5, "Info")
                    return
                end
                SLH.Utils.PrintInfo("UserInterface", "Manual scan triggered.")
                SLH.RemoteInterceptor.StartGlobalHooking() -- This will re-scan and hook new ones
                SLH.UserInterface.ShowToast("Manual scan complete. Found " .. table.maxn(SLH.State.HookedRemotes or {}) .. " remotes.", 5, "Success")
            end
        })
        
        mainTab:AddToggle({ Name = "Debug Mode", Default = SLH.Config.DebugMode, Callback = function(val) SLH.Config.DebugMode = val end})

        -- LOGS TAB
        local logsTab = OrionWindow:MakeTab({ Name = "Logs", Icon = "rbxassetid://4483345998" }) SLH.State.UI.Tabs.Logs = logsTab
        SLH.State.UI.Elements.LogList = logsTab:AddSearchableList({
            Name = "Logged Remotes (Select to view details/replay)",
            MaxVisible = 10,
            Options = {}, -- Will be populated by RefreshLogList
            Callback = function(selectedItemText) -- The text of the selected item
                -- Find the actual log entry from the text
                local foundLog
                for _, log in ipairs(SLH.State.Logs) do
                    local displayText = string.format("[%s] %s: %s (%s)", log.Timestamp, log.Type, log.Name, log.SerializedArgs)
                    if displayText == selectedItemText then
                        foundLog = log
                        break
                    end
                end
                if foundLog then
                    SLH.LogManager.SetSelectedLog(foundLog)
                else
                    SLH.Utils.PrintError("UI", "Could not find log entry for text:", selectedItemText)
                end
            end,
        })
        logsTab:AddButton({ Name = "Clear All Logs", Callback = SLH.LogManager.ClearLogs })

        -- REPLAY TAB
        local replayTab = OrionWindow:MakeTab({ Name = "Replay / Modify", Icon = "rbxassetid://4483345998" }) SLH.State.UI.Tabs.Replay = replayTab
        SLH.State.UI.Elements.ArgDisplay = replayTab:AddParagraph("Selected Remote Info", "Select a call from the Logs tab.")
        SLH.State.UI.Elements.ModArgsInput = replayTab:AddTextBox({
            Name = "Arguments (Lua syntax, comma-separated)",
            PlaceholderText = "e.g., 123, \"hello\", true, {key=\"val\"}",
            ClearText = false, -- Don't clear on submit typically
            Callback = function(text)
                -- Could live-validate here if desired
            end
        })
        replayTab:AddButton({ Name = "Replay with Original Arguments", Callback = function()
                if SLH.State.SelectedLogEntry then
                    SLH.RemoteActions.ReplayCall(SLH.State.SelectedLogEntry, SLH.State.SelectedLogEntry.Arguments)
                else SLH.UserInterface.ShowToast("No log entry selected.", 3, "Info") end
            end
        })
        replayTab:AddButton({ Name = "Replay with Modified Arguments", Callback = function()
                if SLH.State.SelectedLogEntry then
                    local argString = SLH.State.UI.Elements.ModArgsInput:GetValue() -- Assuming GetValue() exists
                    local newArgs, err = SLH.Utils.ParseArgumentString(argString)
                    if newArgs then
                        SLH.RemoteActions.ReplayCall(SLH.State.SelectedLogEntry, newArgs)
                    else
                        SLH.UserInterface.ShowToast("Argument Parse Error: " .. (err or "Unknown error"), 5, "Error")
                    end
                else SLH.UserInterface.ShowToast("No log entry selected.", 3, "Info") end
            end
        })

        SLH.State.UI.Initialized = true
        SLH.UserInterface.RefreshLogList()
        SLH.UserInterface.UpdateReplayTab()
        SLH.Utils.PrintInfo("UserInterface", "UI Setup Complete.")
    end

    SLH.UserInterface.RefreshLogList = function()
        if not SLH.State.UI.Initialized or not SLH.State.UI.Elements.LogList then return end
        
        SLH.State.UI.LogListCache = {}
        for i = #SLH.State.Logs, 1, -1 do -- Iterate backwards to show newest first
            local log = SLH.State.Logs[i]
            local displayText = string.format("[%s] %s: %s (%s)", log.Timestamp, log.Type, log.Name, log.SerializedArgs)
            table.insert(SLH.State.UI.LogListCache, displayText)
        end
        
        -- Assuming the UI Lib's List element has a method to update its options
        SLH.State.UI.Elements.LogList:SetOptions(SLH.State.UI.LogListCache)
    end

    SLH.UserInterface.UpdateReplayTab = function()
        if not SLH.State.UI.Initialized or not SLH.State.UI.Elements.ArgDisplay or not SLH.State.UI.Elements.ModArgsInput then return end

        local logEntry = SLH.State.SelectedLogEntry
        if logEntry then
            local infoText = string.format(
                "Name: %s\nType: %s\nPath: %s\n\nOriginal Arguments:\n%s",
                logEntry.Name,
                logEntry.Type,
                logEntry.Path,
                logEntry.FullSerializedArgs
            )
            SLH.State.UI.Elements.ArgDisplay:SetText(infoText) -- Assuming SetText method
            
            -- Convert original arguments table to a comma-separated string for editing
            local argsAsText = ""
            if logEntry.Arguments and #logEntry.Arguments > 0 then
                local tempSerialized = {}
                for _, v_arg in ipairs(logEntry.Arguments) do
                    table.insert(tempSerialized, SLH.Utils.DeepSerialize(v_arg))
                end
                argsAsText = table.concat(tempSerialized, ", ")
            end
            SLH.State.UI.Elements.ModArgsInput:SetText(argsAsText) -- Assuming SetText method
        else
            SLH.State.UI.Elements.ArgDisplay:SetText("Select a call from the Logs tab.")
            SLH.State.UI.Elements.ModArgsInput:SetText("")
        end
    end
    
    SLH.UserInterface.ToggleWindow = function()
        if SLH.State.UI.Window and SLH.State.UI.Window.Toggle then
            SLH.State.UI.Window:Toggle()
            SLH.State.UI.Visible = SLH.State.UI.Window.Visible
        elseif SLH.State.UI.Window then -- Fallback if no Toggle method, try Visible prop
            SLH.State.UI.Window.Visible = not SLH.State.UI.Window.Visible
            SLH.State.UI.Visible = SLH.State.UI.Window.Visible
        else
            SLH.Utils.PrintError("UI", "Window not initialized, cannot toggle.")
        end
    end

    --[[----------------------------------------------------------------------------------
        SECTION: MAIN INITIALIZATION & EXECUTION
    ------------------------------------------------------------------------------------]]
    SLH.Initialize = function()
        SLH.Utils.PrintInfo("Main", "Initializing Sane Little Helper v" .. SLH.Info.Version)
        SLH.LogManager.Initialize()

        -- Load UI Library
        local uiLibLoaded = false
        if SLH.Config.UI_Lib_URL and type(SLH.Config.UI_Lib_URL) == "string" then
            local success, result = pcall(loadstring(game:HttpGet(SLH.Config.UI_Lib_URL, true)))
            if success and result and type(result) == "table" and result.MakeWindow then -- Check if it looks like Orion
                SLH.UILib = result
                uiLibLoaded = true
                SLH.Utils.PrintInfo("Main", "UI Library loaded successfully from URL.")
            else
                SLH.Utils.PrintError("Main", "Failed to load UI Library from URL or it's invalid. Result/Error:", result)
            end
        end
        
        -- Fallback or alternative UI libraries can be checked here
        if not uiLibLoaded then
            if syn and syn.protect_gui and syn. ชาวไร่ then -- Example check for Synapse X specific UI (conceptual)
                -- SLH.UILib = syn. ชาวไร่ -- Adapt to actual Synapse UI lib
                -- uiLibLoaded = true
                -- SLH.Utils.PrintInfo("Main", "Detected Synapse X, UI might integrate differently.")
            elseif gethui then -- For some free exploits
                -- SLH.UILib = -- Adapt to gethui based UI
                -- uiLibLoaded = true
            end
        end

        if not uiLibLoaded then
            SLH.Utils.PrintError("Main", "No suitable UI Library found or loaded. UI will be unavailable.")
            SLH.UserInterface.ShowToast("Critical: UI Library not found. Tool will run without GUI.", 10, "Error")
        else
             -- Setup UI in a protected call to prevent script death on UI errors
            local uiSetupOk, uiErr = pcall(SLH.UserInterface.Setup)
            if not uiSetupOk then
                SLH.Utils.PrintError("Main", "UI Setup failed:", uiErr)
                SLH.UserInterface.ShowToast("UI Setup Failed: " .. tostring(uiErr), 10, "Error")
                SLH.State.UI.Initialized = false -- Ensure it's marked as not initialized
            end
        end

        if SLH.Config.AutoAttachOnLoad then
            SLH.RemoteInterceptor.StartGlobalHooking()
            if SLH.State.UI.Initialized and SLH.State.UI.Tabs.Main then
                -- Try to update the button text if UI is already setup
                local mainTabButtons = SLH.State.UI.Tabs.Main:GetChildren() -- Assuming GetChildren or similar
                if mainTabButtons and mainTabButtons[1] then -- Assuming first button is toggle
                    mainTabButtons[1]:SetText("Toggle Hooking (Currently: ON)")
                end
            end
        end
        
        SLH.Utils.PrintInfo("Main", SLH.Info.Name .. " initialized. Type SLH.UserInterface.ToggleWindow() or use executor UI toggle if available.")
        if SLH.State.UI.Initialized and SLH.UserInterface.ToggleWindow then
             -- SLH.UserInterface.ToggleWindow() -- Optionally auto-show UI on load
        end
    end

    -- Execute Initialization in a protected call
    local initSuccess, initError = pcall(SLH.Initialize)
    if not initSuccess then
        warn("[SLH FATAL] Initialization Error: " .. tostring(initError))
        -- Attempt to show a basic print message if UI failed very early
        print(SLH.Info.Name .. " FATAL ERROR DURING INITIALIZATION: " .. tostring(initError))
        print("Stack trace: " .. debug.traceback())
    end

end) -- End of main pcall wrapper

if not success then
    warn("[SLH SCRIPT LOAD FAILED] Error: ", err)
    print("Stack trace: " .. debug.traceback())
end

-- To make it easy to toggle UI from executor if script is already run:
-- Example: getgenv().SLH.UserInterface.ToggleWindow()
