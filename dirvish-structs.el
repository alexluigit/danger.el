;;; dirvish-structs.el --- Dirvish data structures -*- lexical-binding: t -*-

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;;; This library contains data structures for Dirvish.

;;; Code:

(declare-function dirvish--add-advices "dirvish-advices")
(declare-function dirvish--remove-advices "dirvish-advices")
(require 'dirvish-options)

(defun dirvish-curr (&optional frame)
  "Get current dirvish instance in FRAME.

FRAME defaults to current frame."
  (if dirvish--curr-name
      (gethash dirvish--curr-name (dirvish-hash))
    (frame-parameter frame 'dirvish--curr)))

(defun dirvish-drop (&optional frame)
  "Drop current dirvish instance in FRAME.

FRAME defaults to current frame."
  (set-frame-parameter frame 'dirvish--curr nil))

(defun dirvish-reclaim (&optional _window)
  "Reclaim current dirvish."
  (unless (active-minibuffer-window)
    (if dirvish--curr-name
        (or dirvish-override-dired-mode (dirvish--add-advices))
      (or dirvish-override-dired-mode (dirvish--remove-advices)))
    (set-frame-parameter nil 'dirvish--curr (gethash dirvish--curr-name (dirvish-hash)))))

(defmacro dirvish--get-buffer (type &rest body)
  "Return dirvish buffer with TYPE.
If BODY is non-nil, create the buffer and execute BODY in it."
  (declare (indent 1))
  `(progn
     (let* ((id (frame-parameter nil 'window-id))
            (h-name (format " *Dirvish %s-%s*" ,type id))
            (buf (get-buffer-create h-name)))
       (with-current-buffer buf ,@body buf))))

(defun dirvish-init-frame (&optional frame)
  "Initialize the dirvishs system in FRAME.
By default, this uses the current frame."
  (unless (frame-parameter frame 'dirvish--hash)
    (with-selected-frame (or frame (selected-frame))
      (set-frame-parameter frame 'dirvish--transient '())
      (set-frame-parameter frame 'dirvish--hash (make-hash-table :test 'equal))
      (dirvish--get-buffer 'preview
        (setq-local mode-line-format nil))
      (dirvish--get-buffer 'header
        (setq-local header-line-format nil)
        (setq-local window-size-fixed 'height)
        (setq-local face-font-rescale-alist nil)
        (setq-local mode-line-format (and dirvish-header-line-format
                                          '((:eval (dirvish-format-header-line)))))
        (set (make-local-variable 'face-remapping-alist)
             dirvish-header-face-remap-alist))
      (dirvish--get-buffer 'footer
        (setq-local header-line-format nil)
        (setq-local window-size-fixed 'height)
        (setq-local face-font-rescale-alist nil)
        (setq-local mode-line-format '((:eval (dirvish-format-mode-line))))
        (set (make-local-variable 'face-remapping-alist)
             '((mode-line-inactive mode-line-active)))))))

(defun dirvish-hash (&optional frame)
  "Return a hash containing all dirvish instance in FRAME.

The keys are the dirvish's names automatically generated by
`cl-gensym'.  The values are dirvish structs created by
`make-dirvish'.

FRAME defaults to the currently selected frame."
  ;; XXX: This must return a non-nil value to avoid breaking frames initialized
  ;; with after-make-frame-functions bound to nil.
  (or (frame-parameter frame 'dirvish--hash)
      (make-hash-table)))

(defun dirvish-get-all (slot &optional all-frame)
  "Gather slot value SLOT of all Dirvish in `dirvish-hash' as a flattened list.
If optional ALL-FRAME is non-nil, collect SLOT for all frames."
  (let* ((dv-slot (intern (format "dv-%s" slot)))
         (all-vals (if all-frame
                       (mapcar (lambda (fr)
                                 (with-selected-frame fr
                                   (mapcar dv-slot (hash-table-values (dirvish-hash)))))
                               (frame-list))
                     (mapcar dv-slot (hash-table-values (dirvish-hash))))))
    (delete-dups (flatten-tree all-vals))))

(cl-defstruct (dirvish (:conc-name dv-))
  "Define dirvish data type."
  (name
   (cl-gensym)
   :documentation "is a symbol that is unique for every instance.")
  (depth
   dirvish-depth
   :documentation "TODO.")
  (transient
   nil
   :documentation "TODO.")
  (parent-buffers
   ()
   :documentation "holds all parent buffers in this instance.")
  (parent-windows
   ()
   :documentation "holds all parent windows in this instance.")
  (preview-window
   nil
   :documentation "is the window to display preview buffer.")
  (preview-buffers
   ()
   :documentation "holds all file preview buffers in this instance.")
  (window-conf
   (current-window-configuration)
   :documentation "is the window configuration given by `current-window-configuration'.")
  (root-window
   (progn
     (when (window-parameter nil 'window-side) (delete-window))
     (frame-selected-window))
   :documentation "is the main dirvish window.")
  (index-path
   ""
   :documentation "is the file path under cursor in ROOT-WINDOW.")
  (preview-dispatchers
   dirvish-preview-dispatchers
   :documentation "Preview dispatchers used for preview in this instance.")
  (ls-switches
   dired-listing-switches
   :documentation "is the list switches passed to `ls' command.")
  (sort-criteria
   (cons "default" "")
   :documentation "is the addtional sorting flag added to `dired-list-switches'."))

(defmacro dirvish-new (&rest args)
  "Create a new dirvish struct and put it into `dirvish-hash'.

ARGS is a list of keyword arguments followed by an optional BODY.
The keyword arguments set the fields of the dirvish struct.
If BODY is given, it is executed to set the window configuration
for the dirvish.

Save point, and current buffer before executing BODY, and then
restore them after."
  (declare (indent defun))
  (let ((keywords))
    (while (keywordp (car args))
      (dotimes (_ 2) (push (pop args) keywords)))
    (setq keywords (reverse keywords))
    `(let ((dv (make-dirvish ,@keywords)))
       (dirvish-init-frame)
       (puthash (dv-name dv) dv (dirvish-hash))
       ,(when args `(save-excursion ,@args)) ; Body form given
       dv)))

(defmacro dirvish-kill (dv &rest body)
  "Kill a dirvish instance DV and remove it from `dirvish-hash'.

DV defaults to current dirvish instance if not given.  If BODY is
given, it is executed to unset the window configuration brought
by this instance."
  (declare (indent defun))
  `(progn
    (unless (dirvish-dired-p ,dv)
      (set-window-configuration (dv-window-conf ,dv)))
    (let ((tran-list (frame-parameter nil 'dirvish--transient)))
      (set-frame-parameter nil 'dirvish--transient (remove dv tran-list)))
    (cl-labels ((kill-when-live (b) (and (buffer-live-p b) (kill-buffer b))))
      (mapc #'kill-when-live (dv-parent-buffers ,dv))
      (mapc #'kill-when-live (dv-preview-buffers ,dv)))
    (remhash (dv-name ,dv) (dirvish-hash))
    ,@body))

(defun dirvish-start-transient (old-dv new-dv)
  "Doc."
  (setf (dv-transient new-dv) old-dv)
  (let ((tran-list (frame-parameter nil 'dirvish--transient)))
    (set-frame-parameter nil 'dirvish--transient (push old-dv tran-list))))

(defun dirvish-end-transient (tran)
  "Doc."
  (cl-loop
   with hash = (dirvish-hash)
   with tran-dv = (if (dirvish-p tran) tran (gethash tran hash))
   for dv-name in (mapcar #'dv-name (hash-table-values hash))
   for dv = (gethash dv-name hash)
   for dv-tran = (dv-transient dv) do
   (when (or (eq dv-tran tran) (eq dv-tran tran-dv))
     (dirvish-kill dv))
   finally (dirvish-deactivate tran-dv)))

(defun dirvish-activate (dv)
  "Activate dirvish instance DV."
  (setq tab-bar-new-tab-choice "*scratch*")
  (setq display-buffer-alist dirvish-display-buffer-alist)
  (when-let (old-dv (dirvish-live-p))
    (unless (dirvish-dired-p old-dv)
      (setf (dv-window-conf dv) (dv-window-conf old-dv)))
    (dirvish-deactivate old-dv))
  (set-frame-parameter nil 'dirvish--curr dv)
  (run-hooks 'dirvish-activation-hook)
  dv)

(defun dirvish-deactivate (dv)
  "Deactivate dirvish instance DV."
  (dirvish-kill dv
    (unless (dirvish-get-all 'name t)
      (setq tab-bar-new-tab-choice dirvish-saved-new-tab-choice)
      (setq display-buffer-alist dirvish-saved-display-buffer-alist)
      (dolist (tm dirvish-repeat-timers) (cancel-timer (symbol-value tm))))
    (dirvish-reclaim))
  (and dirvish-debug-p (message "leftover: %s" (dirvish-get-all 'name t))))

(defun dirvish-dired-p (&optional dv)
  "Return t if DV is a `dirvish-dired' instance.
DV defaults to the current dirvish instance if not provided."
  (when-let ((dv (or dv (dirvish-curr)))) (eq (dv-depth dv) 0)))

;;;###autoload
(defun dirvish-live-p (&optional win)
  "If WIN is occupied by a `dirvish' instance, return this instance.
WIN defaults to `selected-window' if not provided."
  (when-let ((dv (dirvish-curr)))
    (and (memq (or win (selected-window)) (dv-parent-windows dv)) dv)))

(provide 'dirvish-structs)
;;; dirvish-structs.el ends here
