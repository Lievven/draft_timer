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

# Offset for the labels.
# Should be a large negative value to make sure the user can't see the DD Text nodes containing our Data.
# Set to (50, 50) for testing.
const LABEL_OFFSET = Vector2(-4000, -4000)

# The default node_id for Text nodes. DD should assign them randomly.
# However I changed it to a relatively high, random number to prevent potential conflicts.
const DEFAULT_NODE_ID = 9573

# Number of seconds between live updating the timers.
const TIMER_UPDATE_INTERVAL = 1

var tool_panel = null

# These time labels are currently buttons.
# The reason is simply lazyness.
var session_time_label = null
var total_time_label = null

# The DD Text node in which the current session's time is being saved.
var session_text_node = null

# Trackers for all the different times.
var session_start_time = 0
var session_time_passed = 0
var total_time_passed = 0
var update_timer = 0

# This is where we temporarily store the previous sessions' values.
var cache = []




# Vanilla start function called by Dungeondraft when the mod is first loaded
func start():

    # Fetch tool panel for level selection.
    tool_panel = Global.Editor.Toolset.CreateModTool(self, TOOL_CATEGORY, TOOL_ID, TOOL_NAME, Global.Root + TOOL_ICON_PATH)

    tool_panel.BeginSection(true)

    # Add user interface labels for the timer.
    session_time_label = tool_panel.CreateButton("Session Time", Global.Root + TOOL_ICON_PATH)
    total_time_label = tool_panel.CreateButton("Total Time Wasted", Global.Root + TOOL_ICON_PATH)

    # If in DEBUG_MODE, print buttons for:
    # Debug button that prints a lot of useful information
    # Print cache button that prints the currently cached session times
    if DEBUG_MODE:
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








# =========================================================
# ANYTHING BEYOND THIS POINT IS FOR DEBUGGING PURPOSES ONLY
# =========================================================



# Debug function, very important. Prints whatever stuff I need to know at the moment.
func _on_debug_button():
    print("========== DEBUG BUTTON ==========")
#    fetchData()
#    createDataText()
#    print_levels()
#    print_methods(Global.World)
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
