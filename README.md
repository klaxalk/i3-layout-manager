# i3-layout-manager
Saving, loading and managing layouts for i3wm.

## Preamble - dont worry, I solved all of this

i3 window manager supports saving and loading of window layouts, however, the features are bare-bone and partially missing.
According to the [manual](https://i3wm.org/docs/layout-saving.html), the layout tree can be exported into a json file.
The file contains a description of the containers of a workspace with prefilled (and commented) potential matching rules for the windows.
User is supposed to uncomment the desierd one (and/or modify it) and delete the unsused ones.
Moreover, user should add a surrouding root container which is missing in the file (this baffles me, why cant they save it too?).

So doing it manually (which I dont want) consists of following steps, as described at [i3wm.org](https://i3wm.org/docs/layout-saving.html):
1. export the workspace into jason using ```i3-save-tree --workspace ...```
2. edit the json to match your desired matching rules for the windows
3. wrap the file in a root node, which defines the root split.
4. when needed, load the layout using ```i3-append ...```

However, this plan has flaws.
Its not scalable, its not automated and loading a layout does not work when windows are already present in the current workspace.
To fix it, I built this **layout manager**.
Currently, its a hacky-type of a shell script, but feel free to contribute :-).

## How does it work?

1. The workspace tree is exported usin ```i3-save-tree --workspace ...```
2. The tree for all workspaces on the currently focused monitor exported using ```i3-save-tree --output ...```
3. The location of the current workspace in the all-tree is found by matching the workspace-tree file on the monitor-tree file.
4. The parameters of the root split are extracted and the workspace tree is wrapped in a new split.
5. User is then asked about how should the windows be matched. The options are:
  1. All by _instance_ (instance will be uncommented for all windows)
  2. Match any window to any placeholder
  3. Choose an option for each window. With this option, the user will be asked to choose between the _class_, _instance_ and _title_ for each window. The tree file will be modified according to the selected options.

## Dependencies

* vim/nvim
* jq
* i3
* rofi
* xdotool
* x11-xserver-utils

```bash
sudo apt-install jq vim rofi xdotool x11-xserver-utils
```
