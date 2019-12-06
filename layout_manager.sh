#!/bin/bash
# Author: klaxalk (klaxalk@gmail.com, github.com/klaxalk)
#
# Dependencies:
# - vim/nvim  : scriptable file editing
# - jq        : json manipulation
# - rofi      : nice dmenu alternative
# - xdotool   : window manipulation
# - xrandr    : getting info of current monitor
# - i3-msg    : i3 tui
# - awk+sed+cat ...
#
# vim: set foldmarker=#\ #{,#\ #}

# #{ CHECK DEPENDENCIES

VIM_BIN="$(whereis -b vim | awk '{print $2}')"
NVIM_BIN="$(whereis -b nvim | awk '{print $2}')"
JQ_BIN="$(whereis -b jq | awk '{print $2}')"
XDOTOOL_BIN="$(whereis -b xdotool | awk '{print $2}')"
XRANDR_BIN="$(whereis -b xrandr | awk '{print $2}')"
ROFI_BIN="$(whereis -b rofi | awk '{print $2}')"

if [ -z "$NVIM_BIN" ] && [ -z "$VIM_BIN" ]; then
  echo missing vim or neovim, please install dependencies
  exit 1
fi

if [ -z "$JQ_BIN" ]; then
  echo missing jq, please install dependencies
  exit 1
fi

if [ -z "$XDOTOOL_BIN" ]; then
  echo missing xdotool, please install dependencies
  exit 1
fi

if [ -z "$XRANDR_BIN" ]; then
  echo missing xrandr, please install dependencies
  exit 1
fi

if [ -z "$ROFI_BIN" ]; then
  echo missing rofi, please install dependencies
  exit 1
fi

# #}

if [ -z "$XDG_CONFIG_HOME" ]; then
  LAYOUT_PATH=~/.layouts
else
  LAYOUT_PATH="$XDG_CONFIG_HOME/i3-layout-manager/layouts"
fi

# make directory for storing layouts
mkdir -p $LAYOUT_PATH > /dev/null 2>&1

# logs
LOG_FILE=/tmp/i3_layout_manager.txt
echo "" > "$LOG_FILE"

# #{ ASK FOR THE ACTION

# if operating using dmenu
if [ -z $1 ]; then

  ACTION=$(echo "LOAD LAYOUT
SAVE LAYOUT
DELETE LAYOUT" | rofi -i -dmenu -no-custom -p "Select action")

  if [ -z "$ACTION" ]; then
    exit
  fi

  # get me layout names based on existing file names in the LAYOUT_PATH
  LAYOUT_NAMES=$(ls -Rt $LAYOUT_PATH | grep "layout.*json" | sed -nr 's/layout-(.*)\.json/\1/p' | sed 's/\s/\n/g' | sed 's/_/ /g') # layout names
  LAYOUT_NAME=$(echo "$LAYOUT_NAMES" | rofi -i -dmenu -p "Select layout (you may type new name when creating)" | sed 's/\s/_/g') # ask for selection
  LAYOUT_NAME=${LAYOUT_NAME^^} # upper case

# getting argument from command line
else

  ACTION="LOAD LAYOUT"
  # if the layout name is a full path, just pass it, otherwise convert it to upper case
  if [[ "${1}" == *".json" ]]; then
    LAYOUT_NAME="${1}"
  else
    LAYOUT_NAME="${1^^}"
  fi

fi

# no action, exit
if [ -z "$LAYOUT_NAME" ]; then
  exec "$0" "$@"
fi

# #}

# if the layout name is a full path, use it, otherwise fabricate the full path
if [[ $LAYOUT_NAME == *".json" ]]; then
  LAYOUT_FILE=`realpath "$LAYOUT_NAME"`
else
  LAYOUT_FILE=$LAYOUT_PATH/layout-"$LAYOUT_NAME".json
fi

echo $LAYOUT_FILE

if [ "$ACTION" == "LOAD LAYOUT" ] && [ ! -f "$LAYOUT_FILE" ]; then
  exit
fi

# get current workspace ID
WORKSPACE_ID=$(i3-msg -t get_workspaces | jq '.[] | select(.focused==true).num' | cut -d"\"" -f2)

# #{ LOAD

if [[ "$ACTION" = "LOAD LAYOUT" ]]; then

  # updating the workspace to the new layout is tricky
  # normally it does not influence existing windows
  # For it to apply to existing windows, we need to
  # first remove them from the workspace and then
  # add them back while we remove any empty placeholders
  # which would normally cause mess. The placeholders
  # are recognize by having no process inside them.

  # get the list of windows on the current workspace
  WINDOWS=$(xdotool search --all --onlyvisible --desktop $(xprop -notype -root _NET_CURRENT_DESKTOP | cut -c 24-) "" 2>/dev/null)

  echo "About to unload all windows from the workspace" >> "$LOG_FILE"

  for window in $WINDOWS; do

    # the grep filters out a line which reports on the command that was just being called
    # however, the line is not there when calling with rofi from i3
    HAS_PID=$(xdotool getwindowpid $window 2>&1 | grep -v command | wc -l)

    echo "Unloading window '$window'" >> "$LOG_FILE"

    if [ $HAS_PID -eq 0 ]; then
      echo "Window '$window' does not have a process" >> "$LOG_FILE"
    else
      xdotool windowunmap "$window" >> "$LOG_FILE" 2>&1
      echo "'xdotool windounmap $window' returned $?" >> "$LOG_FILE"
    fi

  done

  echo "" >> "$LOG_FILE"
  echo "About to delete all empty window placeholders" >> "$LOG_FILE"

  # delete all empty layout windows from the workspace
  # we just try to focus any window on the workspace (there should not be any, we unloaded them)
  for (( i=0 ; $a-100 ; a=$a+1 )); do

    # check window for STICKY before killing - if sticky do not kill
    xprop -id $(xdotool getwindowfocus) | grep -q '_NET_WM_STATE_STICK'

    if [ $? -eq 1 ]; then

      echo "Killing an unsued placeholder" >> "$LOG_FILE"
      i3-msg "focus parent, kill" >> "$LOG_FILE" 2>&1

      i3_msg_ret="$?"

      if [ "$i3_msg_ret" == 0 ]; then
        echo "Empty placeholder successfully killed" >> "$LOG_FILE"
      else
        echo "Empty placeholder could not be killed, breaking" >> "$LOG_FILE"
        break
      fi
    fi
  done

  echo "" >> "$LOG_FILE"
  echo "Applying the layout" >> "$LOG_FILE"

  # then we can apply to chosen layout
  i3-msg "append_layout $LAYOUT_FILE" >> "$LOG_FILE" 2>&1

  echo "" >> "$LOG_FILE"
  echo "About to bring all windows back" >> "$LOG_FILE"

  # and then we can reintroduce the windows back to the workspace
  for window in $WINDOWS; do

    # the grep filters out a line which reports on the command that was just being called
    # however, the line is not there when calling with rofi from i3
    HAS_PID=$(xdotool getwindowpid $window 2>&1 | grep -v command | wc -l)

    echo "Loading back window '$window'" >> "$LOG_FILE"

    if [ $HAS_PID -eq 0 ]; then
      echo "$window does not have a process" >> "$LOG_FILE"
    else
      xdotool windowmap "$window"
      echo "'xdotool windowmap $window' returned $?" >> "$LOG_FILE"
    fi
  done

fi

# #}

# #{ SAVE

if [[ "$ACTION" = "SAVE LAYOUT" ]]; then

  ACTION=$(echo "DEFAULT (INSTANCE)
SPECIFIC (CHOOSE)
MATCH ANY" | rofi -i -dmenu -p "How to identify windows? (xprop style)")


  if [[ "$ACTION" = "DEFAULT (INSTANCE)" ]]; then
    CRITERION="default"
  elif [[ "$ACTION" = "SPECIFIC (CHOOSE)" ]]; then
    CRITERION="specific"
  elif [[ "$ACTION" = "MATCH ANY" ]]; then
    CRITERION="any"
  fi

  ALL_WS_FILE=$LAYOUT_PATH/all-layouts.json

  CURRENT_MONITOR=$(i3-msg -t get_workspaces | jq '.[] | select(.focused==true).output' | cut -d"\"" -f2)

  # get the i3-tree for all workspaces for the current monitor
  i3-save-tree --output "$CURRENT_MONITOR" > "$ALL_WS_FILE" 2>&1

  # get the i3-tree for the current workspace
  i3-save-tree --workspace "$WORKSPACE_ID" > "$LAYOUT_FILE" 2>&1

  # for debug
  # cp $LAYOUT_FILE $LAYOUT_PATH/ws_temp.txt
  # cp $ALL_WS_FILE $LAYOUT_PATH/all_temp.txt

  # back the output file.. we are gonna modify it and alter we will need it back
  BACKUP_FILE=$LAYOUT_PATH/.layout_backup.txt
  cp $LAYOUT_FILE $BACKUP_FILE

  # get me vim, we will be using it alot to postprocess the generated json files
  if [ -x "$(whereis nvim | awk '{print $2}')" ]; then
    VIM_BIN="$(whereis nvim | awk '{print $2}')"
    HEADLESS="--headless"
  elif [ -x "$(whereis vim | awk '{print $2}')" ]; then
    VIM_BIN="$(whereis vim | awk '{print $2}')"
    HEADLESS=""
  fi

  # the allaround task is to produce a single json file with the description
  # of the current layout on the focused workspace. However, the
  #                   i3-save-tree --workspace
  # command only outputs the inner containers, without wrapping them into the
  # root container of the workspace, which leads to loosing the information
  # about the initial split .. vertical? or horizontal?...
  # We can solve it by asking for a tree, which contains all workspaces,
  # including the root splits and borrowing the root split info from there.
  # I do it by locating the right place in the all-tree by mathing the
  # workspace tree and then extracting the split part and adding it back
  # to the workspace json.

  # first we need to do some preprocessing, before we can find, where in the
  # all-tree file we can find the workspace part.

  # remove the floating window part, that would screw up out matching
  $VIM_BIN $HEADLESS -nEs -c '%g/"floating_con"/norm ?{nd%' -c "wqa" -- "$LAYOUT_FILE"

  # remove comments
  $VIM_BIN $HEADLESS -nEs -c '%g/\/\//norm dd' -c "wqa" -- "$LAYOUT_FILE"
  $VIM_BIN $HEADLESS -nEs -c '%g/\/\//norm dd' -c "wqa" -- "$ALL_WS_FILE"

  # remove indents
  $VIM_BIN $HEADLESS -nEs -c '%g/^/norm 0d^' -c "wqa" -- "$LAYOUT_FILE"
  $VIM_BIN $HEADLESS -nEs -c '%g/^/norm 0d^' -c "wqa" -- "$ALL_WS_FILE"

  # remove commas
  $VIM_BIN $HEADLESS -nEs -c '%s/^},$/}/g' -c "wqa" -- "$LAYOUT_FILE"
  $VIM_BIN $HEADLESS -nEs -c '%s/^},$/}/g' -c "wqa" -- "$ALL_WS_FILE"

  # remove empty lines in the the workspace file
  $VIM_BIN $HEADLESS -nEs -c '%g/^$/norm dd' -c "wqa" -- "$LAYOUT_FILE"

  # now I will try to find the part in the big file which containts the
  # small file. I have not found a suitable solution using off-the-shelf
  # tools, so custom bash it is...

  MATCH=0
  PATTERN_LINES=`cat $LAYOUT_FILE | wc -l` # get me the number of lines in the small file
  SOURCE_LINES=`cat $ALL_WS_FILE | wc -l` # get me the number of lines in the big file

  N_ITER=$(expr $SOURCE_LINES - $PATTERN_LINES)
  readarray pattern < $LAYOUT_FILE

  MATCH_LINE=0
  for (( a=1 ; $a-$N_ITER ; a=$a+1 )); do

    CURR_LINE=0
    MATCHED_LINES=0
    while read -r line1; do

      PATTERN_LINE=$(echo ${pattern[$CURR_LINE]} | tr -d '\n')

      if [[ "$line1" == "$PATTERN_LINE" ]]; then
        MATCHED_LINES=$(expr $MATCHED_LINES + 1)
      else
        break
      fi

      CURR_LINE=$(expr $CURR_LINE + 1)
    done <<< $(cat "$ALL_WS_FILE" | tail -n +"$a")

    if [[ "$MATCHED_LINES" == "$PATTERN_LINES" ]];
    then
      MATCH_LINE="$a"
      break
    fi
  done

  # lets extract the key part, containing the block with the root split

  # load old workspace file (we destroyed the old one, remember?)
  mv $BACKUP_FILE $LAYOUT_FILE

  $VIM_BIN $HEADLESS -nEs -c '%s/\\\\//g' -c "wqa" -- "$LAYOUT_FILE"

  # delete the part below and above the block
  $VIM_BIN $HEADLESS -nEs -c "normal ${MATCH_LINE}ggdGG{kdgg" -c "wqa" -- "$ALL_WS_FILE"
  # rename the "workspace to "con" (container)
  $VIM_BIN $HEADLESS -nEs -c '%g/type/norm ^Wlciwcon' -c "wqa" -- "$ALL_WS_FILE"
  # change the fullscrean to 0
  $VIM_BIN $HEADLESS -nEs -c '%g/fullscreen/norm ^Wr0' -c "wqa" -- "$ALL_WS_FILE"

  # extract the needed part of the file and add it to the workspace file
  # this part is mostly according to the i3 manual, except we actually put there
  # the information about the split type
  cat $ALL_WS_FILE | cat - $LAYOUT_FILE > /tmp/tmp.txt && mv /tmp/tmp.txt $LAYOUT_FILE
  # add closing bracked at the end
  $VIM_BIN $HEADLESS -nEs -c 'normal Go]}' -c "wqa" -- "$LAYOUT_FILE"

  # now we have to do some postprocessing on it, all is even advices on the official website
  # https://i3wm.org/docs/layout-saving.html

  # uncomment the instance swallow rule
  if [[ "$CRITERION" = "default" ]]; then
    $VIM_BIN $HEADLESS -nEs -c "%g/instance/norm ^dW" -c "wqa" -- "$LAYOUT_FILE"
  elif [[ "$CRITERION" = "any" ]]; then
    $VIM_BIN $HEADLESS -nEs -c '%g/instance/norm ^dW3f"di"' -c "wqa" -- "$LAYOUT_FILE"
  elif [[ "$CRITERION" = "specific" ]]; then

    LAST_LINE=1

    while true; do

      LINE_NUM=$(cat $LAYOUT_FILE | tail -n +$LAST_LINE | grep '// "class' -n | awk '{print $1}')
      HAS_INSTANCE=$(echo $LINE_NUM | wc -l)

      if [ ! -z "$LINE_NUM" ]; then

        LINE_NUM=$(echo $LINE_NUM | awk '{print $1}')
        LINE_NUM=${LINE_NUM%:}
        LINE_NUM=$(expr $LINE_NUM - 1)
        LINE_NUM=$(expr $LINE_NUM + $LAST_LINE )

        NAME=$(cat $LAYOUT_FILE | sed -n "$(expr ${LINE_NUM} - 4)p" | awk '{$1="";print $0}')

        SELECTED_OPTION=$(cat -n $LAYOUT_FILE | sed -n "${LINE_NUM},$(expr $LINE_NUM + 2)p" | awk '{$2="";print $0}' | rofi -i -dmenu -no-custom -p "Choose the matching method for${NAME%,}" | awk '{print $1}')

        # when user does not select, choose "instance" (class+1)
        if [ -z "$SELECTED_OPTION" ]; then
          SELECTED_OPTION=$(expr ${LINE_NUM} + 1)
        fi

        $VIM_BIN $HEADLESS -nEs -c "norm ${SELECTED_OPTION}gg^dW" -c "wqa" -- "$LAYOUT_FILE"

        LAST_LINE=$( expr $SELECTED_OPTION)

      else
        break
      fi

    done
  fi

  # uncomment the transient_for
  $VIM_BIN $HEADLESS -nEs -c '%g/transient_for/norm ^dW' -c "wqa" -- "$LAYOUT_FILE"

  # delete all comments
  $VIM_BIN $HEADLESS -nEs -c '%g/\/\//norm dd' -c "wqa" -- "$LAYOUT_FILE"

  # add a missing comma to the last element of array we just deleted
  $VIM_BIN $HEADLESS -nEs -c '%g/swallows/norm j^%k:s/,$//g' -c "wqa" -- "$LAYOUT_FILE"

  # delete all empty lines
  $VIM_BIN $HEADLESS -nEs -c '%g/^$/norm dd' -c "wqa" -- "$LAYOUT_FILE"

  # pick up floating containers and move them out of the root container
  $VIM_BIN $HEADLESS -nEs -c '%g/floating_con/norm ?{nd%GAp' -c "wqa" -- "$LAYOUT_FILE"

  # delete all empty lines
  $VIM_BIN $HEADLESS -nEs -c '%g/^$/norm dd' -c "wqa" -- "$LAYOUT_FILE"

  # add missing commas between the newly created inner parts of the root element
  $VIM_BIN $HEADLESS -nEs -c '%s/}\n{/},{/g' -c "wqa" -- "$LAYOUT_FILE"

  # surroun everythin in []
  $VIM_BIN $HEADLESS -nEs -c 'normal ggO[Go]' -c "wqa" -- "$LAYOUT_FILE"

  # autoformat the file
  $VIM_BIN $HEADLESS -nEs -c 'normal gg=G' -c "wqa" -- "$LAYOUT_FILE"

  rm "$ALL_WS_FILE"

  notify-send -u low -t 2000 "Layout saved" -h string:x-canonical-private-synchronous:anything

fi

# #}

# #{ DELETE

if [[ "$ACTION" = "DELETE LAYOUT" ]]; then
  rm "$LAYOUT_FILE"
  notify-send -u low -t 2000 "Layout deleted" -h string:x-canonical-private-synchronous:anything
  exec "$0" "$@"
fi

# #}
