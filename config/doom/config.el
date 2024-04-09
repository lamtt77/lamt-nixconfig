;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "LamT"
      user-mail-address "lamtt77@gmail.com")

(when (featurep :system 'macos)
  ;; hack to enable magit when running directly doom-emacs in graphics mode
  (setenv "SSH_AUTH_SOCK" (concat (getenv "GNUPGHOME") "/S.gpg-agent.ssh"))
  (shell-command "gpgconf --launch gpg-agent")
  ;; Restore right-option as meta changed by doom-emacs https://github.com/hlissner/doom-emacs/issues/4178
  (setq mac-right-option-modifier 'meta
        ns-right-option-modifier  'meta))

;; List of gpg keys for file encryption here, else doom will scan for all
;; available 'Encrypt' keys in the key-ring
(setq epa-file-encrypt-to '("0x33C207DE4C1A0CC7"))

;; from 'doom doctor', if using fish shell
;; (setq shell-file-name (executable-find "bash"))
;; (setq-default vterm-shell (executable-find "fish"))
;; (setq-default explicit-shell-file-name (executable-find "fish"))

;; https://github.com/doomemacs/doomemacs/issues/7431
;; (setq nerd-icons-font-names '("SymbolsNerdFontMono-Regular.ttf"))

;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
;; (setq doom-font (font-spec :family "monospace" :size 12 :weight 'semi-light)
;;       doom-variable-pitch-font (font-spec :family "sans" :size 13))

(when (featurep :system 'macos)
    (setq doom-font (font-spec :family "Monaco Nerd Font" :size 15 :weight 'light)
          doom-variable-pitch-font (font-spec :family "LiterationSans Nerd Font" :size 16)))

(when (featurep :system 'linux) (setq doom-font (font-spec :family "Liberation Mono" :size 10.5)))

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)
;; (setq doom-theme 'doom-gruvbox)

;; hard-coded for my large monitor iMac
;; (setq default-frame-alist '((left . 240) (width . 268) (top . 65) (height . 78)))
;; MacAir15
(setq default-frame-alist '((left . 0) (width . 188) (top . 40) (height . 78)))

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org-lam/")

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)


;; Here are some additional functions/macros that could help you configure Doom:
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; LamT - tramp slowness issue, does not seem to get improved
;; (setq remote-file-name-inhibit-cache nil)
;; (setq vc-ignore-dir-regexp
;;       (format "%s\\|%s"
;;                     vc-ignore-dir-regexp
;;                     tramp-file-name-regexp))
;;
;; set verbose to 10 in rare case
;; (setq tramp-verbose 6)
;; (eval-after-load 'tramp '(setenv "SHELL" "/bin/bash"))

;; Fix my zsh custom prompt (z4h) issue as per tramp hangs #6: https://www.emacswiki.org/emacs/TrampMode
(setq tramp-shell-prompt-pattern "\\(?:^\\|\\)[^]#$%>\n]*#?[]#$%>].* *\\(\\[[[:digit:];]*[[:alpha:]] *\\)*")

;; I use back-tick quite often, so change the default org cdlatex-math-symbol from back-tick to C-M-`, :i is for insert state
(after! cdlatex
  (map! :map org-cdlatex-mode-map
        "`"     nil
        :i "C-M-`" #'cdlatex-math-symbol))

;; testing eglot & clangd
;; (set-eglot-client! 'cc-mode '("clangd" "-j=3" "--clang-tidy"))

;; from https://www.reddit.com/r/DoomEmacs/comments/jl6p9x/whitespacemode/
;; LamT: FIXME this will get doom's default whitespace-mode broken
(defun me:see-all-whitespace () (interactive)
       (setq whitespace-style (default-value 'whitespace-style))
       (setq whitespace-display-mappings (default-value 'whitespace-display-mappings))
       (whitespace-mode 'toggle))
(global-set-key (kbd "C-<f4>") 'me:see-all-whitespace)

;; if not like to load ranger by default
;; (ranger-override-dired-mode nil)
;; (setq ranger-show-hidden t)
;; (setq ranger-cleanup-on-disable t)
;; (setq ranger-cleanup-eagerly t)
