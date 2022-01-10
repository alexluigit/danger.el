;;; dirvish-updater.el ---  Update a Dirvish instance -*- lexical-binding: t -*-

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;;; This library provides functions for updating a Dirvish layout.

;;; Code:

(declare-function all-the-icons-icon-for-file "all-the-icons")
(declare-function all-the-icons-icon-for-dir "all-the-icons")
(require 'dirvish-structs)
(require 'dirvish-helpers)
(require 'dirvish-options)
(eval-when-compile (require 'subr-x))

(defun dirvish--header-text ()
  "Compose header string."
  (let* ((index (dv-index-path (dirvish-curr)))
         (file-path (file-name-directory index))
         (path-prefix-home (string-prefix-p (getenv "HOME") file-path))
         (path-regex (concat (getenv "HOME") "/\\|\\/$"))
         (path-tail (replace-regexp-in-string path-regex "" file-path))
         (file-name (file-name-nondirectory index)))
    (format "  %s %s %s" (propertize (if path-prefix-home "~" ":"))
            (propertize path-tail 'face 'dired-mark)
            (propertize file-name 'face 'font-lock-constant-face))))

(defun dirvish--render-icon (pos &optional face)
  "Render icon in POS with optional FACE."
  (let* ((entry (dired-get-filename 'relative 'noerror))
         (offset `(:v-adjust ,dirvish-icon-v-offset))
         (icon-face (or (when face `(:face ,face))
                        (when dirvish-icon-monochrome `(:face ,(face-at-point)))))
         (icon-attrs (append icon-face offset))
         (icon (if (file-directory-p entry)
                   (apply #'all-the-icons-icon-for-dir entry icon-attrs)
                 (apply #'all-the-icons-icon-for-file entry icon-attrs)))
         (icon-w/-offset (concat icon dirvish-icon-delimiter))
         (icon-str (propertize icon-w/-offset 'font-lock-face face))
         (ov (make-overlay (1- pos) pos)))
    (overlay-put ov 'dirvish-icons t)
    (overlay-put ov 'after-string icon-str)))

(defun dirvish--mode-line-sorter ()
  "Return a string showing current Dired file sort criteria."
  (with-current-buffer (window-buffer (dv-root-window (dirvish-curr)))
    (format " %s %s "
            (propertize "Sorter:" 'face 'bold)
            (propertize (car (dv-sort-criteria (dirvish-curr))) 'face 'font-lock-type-face))))

(defun dirvish--mode-line-filter ()
  "Return a string showing active Dired file filter."
  (with-current-buffer (window-buffer (dv-root-window (dirvish-curr)))
    (format " %s %s "
            (propertize "Filter:" 'face 'bold)
            (propertize (if dired-omit-mode "ON" "OFF") 'face 'font-lock-doc-face))))

(defun dirvish--mode-line-index ()
  "Return a string showing index in a Dirvish buffer."
  (with-current-buffer (window-buffer (dv-root-window (dirvish-curr)))
    (let ((cur-pos (- (line-number-at-pos (point)) 1))
          (fin-pos (number-to-string (- (line-number-at-pos (point-max)) 2))))
      (format " %d / %s " cur-pos (propertize fin-pos 'face 'bold)))))

(defun dirvish-header-update ()
  "Update header string.

This function trims header string to avoid vertical wobbling."
  (cond
   ((not dirvish-header-style) nil)
   ((dv-one-window-p (dirvish-curr))
    (setq header-line-format (funcall dirvish-header-text-fn)))
   (t
    (with-current-buffer (dv-header-buffer (dirvish-curr))
      (erase-buffer)
      (let* ((str (funcall dirvish-header-text-fn))
             (incr (if (eq dirvish-header-style 'large) 0.25 0.0))
             (max-width (floor (/ (if dirvish-enable-preview
                                      (1- (* (frame-width) (- 1 dirvish-preview-width)))
                                    (- (frame-width) dirvish-header-wobbling-offset))
                                  (1+ incr)))))
        (while (>= (+ (length str) (/ (- (string-bytes str) (length str)) 2)) max-width)
          (setq str (substring str 0 -1)))
        (insert str (if (eq dirvish-header-style 'large) "\n" ""))
      (add-text-properties
       (point-min) (point-max)
       `(display '(height ,(1+ incr)) line-height ,(1+ (* 2 incr)))))))))

(defun dirvish-body-update (&optional skip-icons skip-padding)
  "Update attributes in dirvish body.

By default update icons, padding, and current line.  If
SKIP-ICONS is non-nil, do not update icons.  If SKIP-PADDING is
non-nil, do not update padding."
  (when (and dirvish-show-icons (not skip-icons))
    (remove-overlays (point-min) (point-max) 'dirvish-icons t)
    (dirvish-render 'dirvish--render-icon))
  (when (and (> dirvish-body-fontsize-increment 0) (not skip-padding))
    (save-excursion
      (let ((o (make-overlay (point-min) (point-max))))
        (setq line-spacing dirvish-body-fontsize-increment)
        (overlay-put o 'display `(height ,(1+ dirvish-body-fontsize-increment))))))
  (remove-overlays (point-min) (point-max) 'dirvish-body t)
  (when-let* ((pos (dired-move-to-filename nil))
              (beg (line-beginning-position))
              (end (line-beginning-position 2))
              (ol (make-overlay beg end)))
    (when dirvish-show-icons
      (remove-overlays beg end 'dirvish-icons t)
      (dirvish--render-icon pos 'highlight))
    (overlay-put ol 'dirvish-body t)
    (overlay-put ol 'face 'highlight)))

(defun dirvish-footer-update ()
  "Show file details in mode line."
  (when-let ((dv (dirvish-curr)))
    (cond
     ((not dirvish-mode-line-format) nil)
     ((dv-one-window-p dv)
      (force-mode-line-update))
     (t
      (with-current-buffer (dv-footer-buffer dv)
        (force-mode-line-update))))))

(provide 'dirvish-updater)
;;; dirvish-updater.el ends here
