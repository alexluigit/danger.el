;;; dirvish-parents.el --- Parent windows for Dirvish -*- lexical-binding: t -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;;; Creating parent windows for dirvish.  A parent window is a window that holds a dirvish buffer,
;;; which exhibit information of parent directory for window on the right side.

;;; Code:

(declare-function dirvish-mode "dirvish")
(require 'dirvish-structs)
(require 'dirvish-vars)
(require 'dirvish-helpers)

(defun dirvish-parent-build ()
  "Create all dirvish parent windows."
  (let* ((current (expand-file-name default-directory))
         (parent (dirvish--get-parent current))
         (parent-dirs ())
         (one-window-p (dv-one-window-p (dirvish-curr)))
         (depth dirvish-depth)
         (i 0))
    (and one-window-p (setq depth 0))
    (dirvish-mode)
    (while (and (< i depth) (not (string= current parent)))
      (setq i (+ i 1))
      (push (cons current parent) parent-dirs)
      (setq current (dirvish--get-parent current))
      (setq parent (dirvish--get-parent parent)))
    (when (> depth 0)
      (let* ((remain (- 1 dirvish-preview-width dirvish-parent-max-width))
             (width (min (/ remain depth) dirvish-parent-max-width))
             (dired-after-readin-hook nil))
        (cl-dolist (parent-dir parent-dirs)
          (let* ((current (car parent-dir))
                 (parent (cdr parent-dir))
                 (win-alist `((side . left)
                              (inhibit-same-window . t)
                              (window-width . ,width)))
                 (buffer (dired-noselect parent))
                 (window (display-buffer buffer `(dirvish--display-buffer . ,win-alist))))
            (with-selected-window window
              (setq-local dirvish-child-entry current)
              (dirvish-mode))))))))

(provide 'dirvish-parents)

;;; dirvish-parents.el ends here
