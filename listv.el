;;; listv.el --- a list viewer

;; Copyright (C) 2019 zbq

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;; Features:
;;   support item text property, so you can highlight some list item
;;   toggle visibility of item field
;;   filter item by field

;; History:
;; 2019/11/09 - initial release

(require 'subr-x)
(eval-when-compile (require 'cl))

;; Usage:
;; Here we use listv to implement a log viewer
;; (let ((buffer (get-buffer "*logviewer*")))
;;   (listv-init-buffer buffer '(level time source pid msg) '(?l ?t ?s ?p ?m) '(level time msg))
;;   (listv-append-item buffer (cons '(face error) '(level "ERROR" time "2019/11/09-11:18" source "UI" pid "1990" msg "error from UI component")))
;;   (listv-append-item buffer (cons '(face warning) '(level "WARNING" time "2019/11/09-11:18" source "UI" pid "1990" msg "warning from UI component")))
;;   (listv-append-item buffer (cons nil '(level "INFO" time "2019/11/09-11:18" source "UI" pid "1990" msg "info from UI component")))
;;   (switch-to-buffer-other-window buffer))

;; (('face 'error) . ('level "ERROR" 'time "2019/11/09-17:38" 'source "UI" 'pid "1988")) ...
(defvar-local listv-items nil)
(defvar-local listv-items-tail nil)
;; '(?l ?t ?s ?p ...)
(defvar-local listv-field-choices nil)
;; '(level time source pid ...)
(defvar-local listv-item-fields nil)
;; '(level time source ...)
(defvar-local listv-visible-fields nil)
;; ('level ("ERROR" "INFO") ...)
(defvar-local listv-filters nil)

(defun listv-item-text-property (item)
  (car item))

(defun listv-item-value (item)
  (cdr item))

(defun listv-is-item-selected (item field)
  (let ((filters (getf listv-filters field))
        (field-value (getf (listv-item-value item) field)))
    (if filters
        (loop for filter in filters thereis (search filter field-value))
      t)))

(defun listv-show-item (item)
  (when (loop for field in listv-filters by #'cddr always
              (listv-is-item-selected item field))
    (let ((inhibit-read-only t)
          (start (point))
          (text-prop (listv-item-text-property item))
          (value (listv-item-value item))
          (inserted nil))
      (loop for field in listv-item-fields when (find field listv-visible-fields) do
            (when-let ((v (getf value field)))
              (insert v "\t")
              (setf inserted t)))
      (when inserted
        (delete-char -1) ; delete last \t
        (put-text-property start (point) 'listv-item-value value)
        (loop for prop in text-prop by #'cddr do
              (put-text-property start (point) prop (getf text-prop prop)))
        (insert "\n")
        (set-buffer-modified-p nil)))))

(defun listv-append-item (buffer item)
  (with-current-buffer buffer
    (setf (cdr listv-items-tail) (list item))
    (setf listv-items-tail (cdr listv-items-tail))
    (listv-show-item item)))

(defun listv-suggest-filters (item-value field)
  (let ((filters (getf listv-filters field))
        (suggest (getf item-value field)))
    (when (and suggest (not (string-empty-p suggest)))
      (setq filters (loop for filter in filters
                          when (not (search filter suggest)) collect filter))
      (setq filters (append filters (list suggest))))
    (string-join filters "|")))

(defun listv-refresh ()
  (let ((inhibit-read-only t))
    (erase-buffer))
  (loop for item in (cdr listv-items) do
        (listv-show-item item)))

(defun listv-filter-items ()
  (interactive)
  (let* ((choice (read-multiple-choice "Filter by: "
                                       (map 'list 'list
                                            listv-field-choices
                                            (mapcar 'symbol-name listv-item-fields))))
         (field (nth (position (car choice) listv-field-choices) listv-item-fields))
         (filter-string (read-string (format "Use '|' to separate %s filters: " field)
                                     (listv-suggest-filters (get-text-property
                                                             (line-beginning-position)
                                                             'listv-item-value)
                                                            field)))
         (filters (remove-duplicates
                   (split-string filter-string "|" t "[ \t\n\r]+")
                   :test #'string=)))
    (setf (getf listv-filters field) filters)
    (listv-refresh)))

(defun listv-clear-all-filters ()
  (interactive)
  (loop for field in listv-filters by #'cddr do
        (setf (getf listv-filters field) nil))
  (listv-refresh))

(defun listv-toggle-visibility ()
  (interactive)
  (let* ((choice (read-multiple-choice "Toggle visibility of: "
                                       (map 'list 'list
                                            listv-field-choices
                                            (mapcar 'symbol-name listv-item-fields))))
         (field (nth (position (car choice) listv-field-choices) listv-item-fields)))
    (setf listv-visible-fields (if (find field listv-visible-fields)
                                   (remove field listv-visible-fields)
                                 (append listv-visible-fields (list field))))
    (listv-refresh)))

(defvar-local listv-keymap
  (let ((map (make-sparse-keymap))
        (submap (make-sparse-keymap)))
    (define-key submap "f" 'listv-filter-items)
    (define-key submap "F" 'listv-clear-all-filters)
    (define-key submap "t" 'listv-toggle-visibility)
    (define-key map "\C-c" submap)
    map))

(defun listv-init-buffer (buffer item-fields field-choices visible-fields)
  (assert (= (length item-fields) (length field-choices)))
  (dolist (c field-choices)
    (assert (eq (type-of c) 'integer)))
  (with-current-buffer buffer
    (setq buffer-read-only nil)
    (kill-all-local-variables)
    (buffer-disable-undo)
    (erase-buffer)
    (setq listv-items (cons 'head nil))
    (setq listv-items-tail listv-items)
    (setq listv-item-fields item-fields)
    (setq listv-field-choices field-choices)
    (setq listv-visible-fields visible-fields)
    (set-buffer-modified-p nil)
    (setq buffer-read-only t)
    (use-local-map listv-keymap)
    (linum-mode)))

(provide 'listv)
