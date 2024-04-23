{ ... }:

{
  targets.darwin = {
    keybindings = {
      /* Additional Emacs bindings for MacOS */
      "~f"    = "moveWordForward:";
      "~b"    = "moveWordBackward:";
      "~&lt;" = "moveToBeginningOfDocument:";
      "~&gt;" = "moveToEndOfDocument:";
      "~v"    = "pageUp:";
      "^v"    = "pageDown:";

      "~d"    = "deleteWordForward:";
      "~^h"   = "deleteWordBackward:";
      "^u"    = "deleteToBeginningOfLine:";
      "^w"    = "deleteWordBackward:";

      # emacs/MacOS complained: NSKeyBindingManager: Bad key binding atom
      # "~\010" = "deleteWordBackward:";  /* Option-backspace */
      # "~\177" = "deleteWordBackward:";  /* Option-delete */
      # "^/"    = "undo:";
      # "^g"    = "_cancelKey:";

      "~/"    = "complete:";
      /* Escape should really be complete: */
      /* "\033" = "complete:";  Escape */

      "^a"    = "moveToBeginningOfLine:";
      "^e"    = "moveToEndOfLine:";

      "~c"	  = "capitalizeWord:"; /* M-c */
      "~u"	  = "uppercaseWord:";	 /* M-u */
      "~l"	  = "lowercaseWord:";	 /* M-l */
      "^t"	  = "transpose:";      /* C-t */
      "~t"	  = "transposeWords:"; /* M-t */
    };
  };
}
