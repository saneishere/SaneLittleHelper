# Sane Little Helper

**Developed by: #samauelisdumbaf**

## Description

Sane Little Helper is an advanced, complex tool designed for Roblox exploitation. It provides robust capabilities for intercepting, logging, modifying, and replaying RemoteEvent and RemoteFunction communications between the client and server. This tool is intended for users who require granular control and insight into game networking for automation, analysis, or other advanced purposes.

## Key Features

*   **Comprehensive Remote Interception:** Hooks into `RemoteEvent:FireServer` and `RemoteFunction:InvokeServer` calls game-wide.
*   **Detailed Logging:** Logs remote call names, a serialization of their arguments, and timestamps.
*   **Undetected Forwarding:** Forwards original calls to the server seamlessly to maintain normal game functionality and avoid detection.
*   **Call Replay & Modification:** Allows users to select logged calls and replay them, either with original or user-modified arguments.
*   **Stealth Operations:** Utilizes techniques like `newcclosure` for hooks to minimize detection by anti-cheat mechanisms.
*   **User-Friendly Interface:** Provides a clean interface (requires a separate UI library like Orion, Kavo, etc.) to view logs, manage settings, and interact with replay functionality.
*   **Modular Design:** Internally structured for clarity and potential future expansions.

## Requirements

*   A Roblox exploit that supports:
    *   `getgenv()`
    *   `hookfunction()` (or similar for robust hooking)
    *   `newcclosure()`
    *   Execution of multi-thousand line scripts.
    *   A UI Library (e.g., Orion, Rayfield, Kavo) for the GUI. The script is designed to integrate with one. A default URL for Orion is provided but can be changed.

## Installation

1.  **Obtain a compatible Roblox exploit.**
2.  **Acquire a UI Library script:**
    *   The tool is pre-configured to attempt loading Orion UI Library from: `https://raw.githubusercontent.com/shlexware/Orion/main/source.lua`
    *   You can change this URL in the `SLH.Config.UI_Lib_URL` variable within the script if you use a different library or source.
3.  **Copy the entire `SaneLittleHelper.lua` script.**
4.  **Paste the script into your exploit's execution area and execute.**

## Usage

Once executed, the Sane Little Helper UI should appear (if the UI library loads correctly).

*   **Main Tab:**
    *   **Enable/Disable Hooking:** Toggle button to start or stop intercepting remote calls.
    *   **Scan Remotes:** Manually trigger a scan for new remotes in predefined game services.
*   **Logs Tab:**
    *   Displays a list of intercepted remote calls with Timestamp, Type (Event/Function), Name, and Arguments.
    *   Click on a log entry to select it for details and replay.
    *   **Clear Logs:** Button to clear all current log entries.
*   **Replay Tab:**
    *   Displays details of the selected log entry.
    *   **Remote Name & Type:** Shows the name and type of the selected remote.
    *   **Original Arguments:** Shows the arguments as they were originally captured.
    *   **Modified Arguments (Text Area):** Allows you to edit the arguments.
        *   Arguments should be entered as a comma-separated list, e.g., `123, "hello", true, {key = "value"}`.
        *   For tables, use Lua table syntax. Be careful with complex nested tables; direct string input has limitations.
    *   **Replay Original:** Button to fire the remote with its original arguments.
    *   **Replay Modified:** Button to fire the remote with the arguments from the text area.
*   **Settings Tab:** (Conceptual - can be expanded)
    *   Adjust `MaxLogEntries`, `DebugMode`, etc.

## Disclaimer

This tool is provided for educational and technical exploration purposes only. Misuse of this tool in games may violate their Terms of Service. The developer (#samauelisdumbaf) is not responsible for any actions taken using this tool or any consequences thereof. Use responsibly.
