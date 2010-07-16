Plugins are loaded in plugins.lua.

This directory contains plugins in folders. They can only be loaded 
using plugins.lua.

Each plugin gets its own directory. Each plugin typically has at least two files:
 1) plugin_NAME.lua - The plugin's code
 2) config_NAME.lua - The plugin's configuration, which you may want/need to edit
Note that "NAME" is the name of the plugin. By convention, it should match the 
folder name under which its scripts are located.
 
The plugin's directory may be used for other things. For example, a plugin might 
output its own log file there, or have configuration that extends beyond just
its regular configuration Lua script.

Please note that there are standard (mandatory) plugins. They are:
- server
- administration
They are implicitly loaded and you cannot change that. Do not remove the plugins
or ironmod will not start.

