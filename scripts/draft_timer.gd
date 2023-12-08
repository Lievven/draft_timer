var script_class = "tool"

# Set to true to show debug buttons
const DEBUG_MODE = false

# Tool parameters
const TOOL_CATEGORY = "Settings"
const TOOL_ID = "draft_timer"
const TOOL_NAME = "Draft Timer"

# Icon paths
const TOOL_ICON_PATH = "icons/clock_icon.png"
const REWIND_ICON_PATH = "icons/rewind_icon.png"

# Texts & formatting for the timer labels
const SESSION_TIMER_LABEL = "Session Time: %02d:%02d:%02d"
const TOTAL_TIMER_LABEL = "Total %s Spent: %02d:%02d"
const TEXT_IDENTIFIER = "draft_timer mod data: "

# The path for storing the mod's settings.
const MOD_DATA_PATH = "user://draft_timer_mod_data.txt"

# Offset for the labels.
# Should be a large negative value to make sure the user can't see the DD Text nodes containing our Data.
# Set to (50, 50) for testing.
const LABEL_OFFSET = Vector2(-4000, -4000)

# The default node_id for Text nodes. DD should assign them randomly.
# However I changed it to a relatively high, random number to prevent potential conflicts.
const DEFAULT_NODE_ID = 9573

# Number of seconds between live updating the timers.
const TIMER_UPDATE_INTERVAL = 1

# The DD native sidebar where the tools are registered.
var tool_panel = null

# These time labels are currently buttons.
# The reason is simply lazyness.
var session_time_label = null
var total_time_label = null

# This button lets the user select whether the timers should pause while the DD window is unfocussed.
var afk_button = null
# This range lets the user select after how many minutes of inactivity the timer goes AFK.
var afk_timer_range = null

# The DD Text node in which the current session's time is being saved.
var session_text_node = null

# Trackers for all the different times.
var session_start_time = 0              # When the session started
var session_time_passed = 0             # How much time has passed this session
var total_time_passed = 0               # How much time has been spent on this map in total
var update_timer = 0                    # How long it's been since the last update
var afk_timer = 0                       # How long we've been AFK for

# If the mouse doesn't move within the DD window, the player will be treated as afk after this many minutes.
# If set to 0, the player will never afk.
var minutes_to_afk = 15
# If set true, the player will be flagged as AFK as soon as Dungeondraft is no longer focussed.
var afk_when_unfocussed = false
# The last known mouse position. If this doesn't change for a time, the player is flagged as afk.
var previous_mouse_position

# This is where we temporarily store the previous sessions' values.
var cache = []

    


# Vanilla start function called by Dungeondraft when the mod is first loaded
func start():

    load_user_settings()

    # Fetch tool panel for level selection.
    tool_panel = Global.Editor.Toolset.CreateModTool(self, TOOL_CATEGORY, TOOL_ID, TOOL_NAME, Global.Root + TOOL_ICON_PATH)

    tool_panel.BeginSection(true)

    # Add user interface labels for the timer.
    session_time_label = tool_panel.CreateButton("Session Time", Global.Root + TOOL_ICON_PATH)
    total_time_label = tool_panel.CreateButton("Total Time Wasted", Global.Root + TOOL_ICON_PATH)

    tool_panel.CreateSeparator()

    # =====================================
    # Add user interface for choosing under which conditions the timer should stop.

    # If checked, the timer should stop whenever DD is not in focus.
    # Uses the loaded user settings as default.
    afk_button = tool_panel.CreateCheckButton("Pause in Background", "", afk_when_unfocussed)
    afk_button.connect("pressed", self, "_on_afk_button_pressed")
    tool_panel.CreateNote("Stop the timer immediately upon interacting with a different window.")

    # If greater than 0, the timer should stop if the user does not move their mouse for this many minutes.
    # Uses the loaded user settings as default.
    tool_panel.CreateLabel("Minutes Until AFK")
    afk_timer_range = tool_panel.CreateSlider("AFK Range", minutes_to_afk, 0, 60, 1, false)
    afk_timer_range.connect("value_changed", self, "_on_afk_slider_changed")
    tool_panel.CreateNote("Stop the timer after not interacting with Dungeondraft for this many minutes. Set to 0 to disable this option.")



    # If in DEBUG_MODE, print buttons for:
    # Debug button that prints a lot of useful information
    # Print cache button that prints the currently cached session times
    if DEBUG_MODE:
        tool_panel.CreateSeparator()
        tool_panel.CreateLabel("Debug Tools")

        var debug_button = tool_panel.CreateButton("DEBUG", Global.Root + REWIND_ICON_PATH)
        debug_button.connect("pressed", self, "_on_debug_button")

        var print_cache_button = tool_panel.CreateButton("PRINT CACHE", Global.Root + REWIND_ICON_PATH)
        print_cache_button.connect("pressed", self, "_on_print_cache_button")

    
    
    tool_panel.EndSection()


    print("[Draft Timer] UI Layout: successful")
    
    # Populate the cache with any previous session times
    fetchData()
    # Print the current cache into a new Text node for next time.
    createDataText(JSON.print(cache))

    # Prepare the Text node that will store the current session's time.
    # We could store this in the same cache node as the previous sessions' time.
    # However I'm storing this in its own node just to deal with potential scaling issues.
    # Better limit any potential frequent copy interactions to a small string.
    # The mod will incorporate it into the larger array on the next load anyway.
    session_start_time = OS.get_unix_time()
    session_text_node = createDataText("[]")
    
    print("[Draft Timer] Loading session timer: successful")




# Vanilla update called by Godot every frame.
# Used to update the timers^^
func update(delta):

    # Update or reset the AFK timer based on whether the mouse has been used since the previous update.
    if Global.WorldUI.get_global_mouse_position() != previous_mouse_position:
        previous_mouse_position = Global.WorldUI.get_global_mouse_position()
        afk_timer = 0
    else:
        afk_timer += delta
    
    # If we have been AFK for longer than the user-defined amount in minutes, we skip the timer updates.
    # If AFK is 0 or less, that means the user does not want AFK tracking.
    if minutes_to_afk > 0 and afk_timer > minutes_to_afk * 60:
        return
    
    # If the windowow is not focussed, we skip the timer updates.
    # However we continue as normal if the user has declared that they do not want to AFK when unfocussing.
    if afk_when_unfocussed and not OS.is_window_focused():
        return


    # If we pass the AFK checks, we begin updating our timers.
    # We do this in steps of TIMER_UPDATE_INTERVAL seconds.
    # This should save resources and we don't want floats anyway.
    update_timer += delta
    if update_timer < TIMER_UPDATE_INTERVAL:
        return
    session_time_passed += TIMER_UPDATE_INTERVAL
    total_time_passed += TIMER_UPDATE_INTERVAL
    update_timer -= TIMER_UPDATE_INTERVAL

    # Apply the updated session time to the session text node.
    # Important: the JSON requires a 2D array as the times given are only the first tuple in said array.
    var json_payload = JSON.print([[session_start_time, session_time_passed]])
    session_text_node.text = TEXT_IDENTIFIER + json_payload

    # Update the times for the current session.
    var seconds = session_time_passed % 60
    var minutes = (session_time_passed / 60) % 60
    var hours = session_time_passed / 3600
    var session_label = SESSION_TIMER_LABEL % [hours, minutes, seconds]
    session_time_label.set_text(session_label)
    
    # Update the total time.
    seconds = total_time_passed % 60
    minutes = total_time_passed / 60
    hours = total_time_passed / 3600
    var days = total_time_passed / (3600 * 24)

    # Since we reasonably expect projects to last for many hours or days, we accept a certain amount of inaccuracy.
    # So we only display time with an accuracy of 99%
    var total_label = TOTAL_TIMER_LABEL % ["Minutes", minutes, seconds]
    if hours >= 100:
        total_label = TOTAL_TIMER_LABEL % ["Days", days, hours % 24]
    elif minutes >= 100:
        total_label = TOTAL_TIMER_LABEL % ["Hours", hours, minutes % 60]
    
    total_time_label.set_text(total_label)




# Should be called only when the map is loaded.
# Searches all Text nodes for the mod's identifier and adds any elements to the cache.
# Only non-duplicate elements are being added.
# All found Text nodes are then being deleted.
func fetchData():
    for levels in Global.World.levels:
        for text in levels.Texts.get_children():
            if not text.text.begins_with(TEXT_IDENTIFIER):
                continue
            var raw_json = text.text.trim_prefix(TEXT_IDENTIFIER)
            appendToCache(JSON.parse(raw_json).result)
            text.queue_free()




# Appends all non-duplicate elements of the given array to the cache.
# Adds the value in position [1] of each tuple to time_passed_previously.
# Ultimately those should sum to the total time spent on the map.
func appendToCache(array):
    for elem in array:
        if not cache.has(elem):
            cache.append(elem)
            total_time_passed += int(elem[1])




# Creates the DD Text node in which our data will be stored on the map.
# The Text node is preceded by a TEXT_IDENTIFIER.
# This is to make sure that we only access Text nodes we created ourselves.
# The Text node is returned for potential future editing.
func createDataText(text_content = "[]"): 
    var level = Global.World.levels[Global.World.CurrentLevelId]
    var data_text = level.Texts.CreateText()
    data_text.text = TEXT_IDENTIFIER + text_content
    data_text.SetFontColor(Color.black)                             # replace with Color.transparent to hide from user. I think I'll leave it for now. Better for users to see an issue.
    # Note that we must set a node_id of a positive value and a valid font.
    # Otherwise DD may fail saving correctly and can even crash upon loading.
    data_text.set_meta("node_id", DEFAULT_NODE_ID)
    data_text.SetFont("Libre Baskerville", 8)
    data_text.rect_global_position = LABEL_OFFSET
    return data_text



# Saves the user settings as JSON in the MOD_DATA_PATH
func save_user_settings():
    var data = {
        "afk_when_unfocussed": afk_when_unfocussed,
        "minutes_to_afk": minutes_to_afk
    }
    var file = File.new()
    file.open(MOD_DATA_PATH, File.WRITE)
    file.store_line(JSON.print(data, "\t"))
    file.close()


# Loads the user settings from the MOD_DATA_PATH
# If there is no file in the specified location, we stop the attempt and leave the default values as they are.
func load_user_settings():
    var file = File.new()
    var error = file.open(MOD_DATA_PATH, File.READ)
    
    # If we cannot read the file, stop this attempt and leave the respective values at their default.
    if error != 0:
        print("[Draft Timer] Loading user settings: no user settings found")
        return

    var line = file.get_as_text()
    var data = JSON.parse(line).result
    file.close()
    minutes_to_afk = data["minutes_to_afk"]
    afk_when_unfocussed = data["afk_when_unfocussed"]

    print("[Draft Timer] Loading user settings: successful")



# Called when the AFK checkbox is toggled and updates the corresponding flag to match.
func _on_afk_button_pressed():
    afk_when_unfocussed = afk_button.pressed
    save_user_settings()


# Called when the AFK slider is changed and updates the corresponding value to match.
func _on_afk_slider_changed(new_value):
    minutes_to_afk = new_value
    save_user_settings()




# =========================================================
# ANYTHING BEYOND THIS POINT IS FOR DEBUGGING PURPOSES ONLY
# =========================================================



# Debug function, very important. Prints whatever stuff I need to know at the moment.
func _on_debug_button():
    print("========== DEBUG BUTTON ==========")
    load_user_settings()
#    fetchData()
#    createDataText()
#    print_levels()
#    print_methods()
#    print_properties(Global.World)
#    print_signals(Global.World)
#    Global.World.print_tree_pretty()


func _on_print_cache_button():
    print("========== PRINT CACHE ==========")
    print(cache)


# Debug function, prints out the info for every level
func print_levels():
    for level in Global.World.levels:
        print("==== Level %s ====" % level.name)
        print("Z Index: %s" % level.z_index)
        print("Z Relative: %s" % level.z_as_relative)



# Debug function, prints properties of the given node
func print_properties(node):
    print("========= PRINTING PROPERTIES OF %s ==========" % node.name)
    var properties_list = node.get_property_list()
    for property in properties_list:
        print(property.name)


# Debug function, prints methods of the given node
func print_methods(node):
    print("========= PRINTING METHODS OF %s ==========" % node.name)
    var method_list = node.get_method_list()
    for method in method_list:
        print(method.name)


# Debug function, prints signals of the given node
func print_signals(node):
    print("========= PRINTING SIGNALS OF %s ==========" % node.name)
    var signal_list = node.get_signal_list()
    for sig in signal_list:
        print(sig.name)