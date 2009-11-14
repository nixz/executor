;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: EXECUTOR; Base: 10; indent-tabs-mode: nil -*-
;;;
;;;  (c) copyright 2007-2009 by
;;;           Samium Gromoff (_deepfire@feelingofgreen.ru)
;;;
;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Library General Public License for more details.
;;;
;;; You should have received a copy of the GNU Library General Public
;;; License along with this library; if not, write to the
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;; Boston, MA  02111-1307  USA.

(in-package :executor)

(defvar *search-path* #-win32 '(#p"/usr/bin/" #p"/bin/"))

(defparameter *executables* (make-hash-table :test 'eq))

(define-root-container *executables* executable :type pathname)

(defvar *execute-explanatory* nil
  "Whether to print provided explanations while executing.")

(defvar *execute-verbosely* nil
  "Whether to echo the invoked external programs to standard output.
Implies *EXECUTE-EXPLANATORY*.")

(defvar *execute-dryly* nil
  "Whether to substitute actual execution of external programs with
mere printing of their paths and parameters.
Implies *EXECUTE-VERBOSELY*")

(define-reported-condition executable-failure (serious-condition)
  ((program :accessor cond-program :initarg :program)
   (parameters :accessor cond-parameters :initarg :parameters)
   (status :accessor cond-status :initarg :status)
   (output :accessor cond-output :initarg :output))
  (:report (program parameters status output)
           "~@<running ~A~{ ~S~} failed with exit status ~S~:[~;, output:~@:_~:*~@<...~;~A~:@>~]~%~:@>" program parameters status output))

(define-reported-condition executable-not-found (warning)
  ((name :accessor cond-name :initarg :name)
   (search-path :accessor cond-search-path :initarg :search-path))
  (:report (name search-path)
           "~@<an executable, named ~S, wasn't found in search path ~S~:@>" name search-path))

(define-reported-condition required-executable-not-found (error)
  ((name :accessor cond-name :initarg :name)
   (search-path :accessor cond-search-path :initarg :search-path))
  (:report (name search-path)
           "~@<a required executable, named ~D, wasn't found in search path ~S~:@>" name search-path))

(defun find-executable (name &key (paths *search-path*) &aux (realname (string-downcase (string name))))
  "See if executable with NAME is available in PATHS. When it is, associate NAME with that path and return the latter;
   otherwise, return NIL."
  (dolist (path paths)
    (let ((exec-path (subfile path (list realname) #+win32 #+win32 :type "exe")))
      (when (probe-file exec-path) 
        (return-from find-executable (setf (gethash name *executables*) exec-path)))))
  (warn 'executable-not-found :name realname :search-path paths))

(defmacro with-dry-execution (&body body)
  "Execute BODY with *EXECUTE-DRYLY* bound to T."
  `(let ((*execute-dryly* t))
     (declare (special *execute-dryly*))
     ,@body))

(defmacro with-verbose-execution (&body body)
  "Execute BODY with *EXECUTE-VERBOSELY* bound to T."
  `(let ((*execute-verbosely* t))
     (declare (special *execute-verbosely*))
     ,@body))

(defmacro with-explained-execution (&body body)
  "Execute BODY with *EXECUTE-EXPLANATORY* bound to T."
  `(let ((*execute-explanatory* t))
     (declare (special *execute-explanatory*))
     ,@body))

(defstruct process
  process
  output-stream)

(defun execute-external (name parameters &key (valid-exit-codes (acons 0 t nil)) (wait t) translated-error-exit-codes (output nil) input (environment '("HOME=/tmp"))
                         explanation
                         &aux (pathname (etypecase name
                                          (string (find-executable name))
                                          (pathname name)
                                          (symbol (executable name)))))
  "Run an external program at PATHNAME with PARAMETERS. 
Return a value associated with the exit code, by the means of
VALID-EXIT-CODES, or signal a condition of type EXECUTABLE-FAILURE.
OUTPUT should be either a stream, T, NIL or :CAPTURE, with
following interpretation of the latter three:
   T - *STANDARD-OUTPUT*,
   NIL - /dev/null, nul or whatever is the name of the local void,
   :CAPTURE - capture into a string."
  (when (or *execute-explanatory* *execute-verbosely* *execute-dryly*)
    (destructuring-bind (format-control &rest format-arguments) (ensure-cons explanation)
      (apply #'format *standard-output* (concatenate 'string "~@<;;; ~@;" format-control "~:@>~%") format-arguments)))
  (when (or *execute-verbosely* *execute-dryly*)
    (format *standard-output* ";;; ~S '~S~% :environment '~S :output ~S~%" pathname parameters environment output)
    (finish-output *standard-output*))
  (multiple-value-bind (final-output capturep) (if (streamp output)
                                                   output
                                                   (case output
                                                     ((t) *standard-output*)
                                                     ((nil) nil)
                                                     (:capture (values (make-string-output-stream) t))
                                                     (t (error "~@<Bad OUTPUT passed to EXECUTE-EXTERNAL: ~
                                                                   should be either a stream, or one of (T NIL :CAPTURE).~:@>"))))
    (if *execute-dryly*
        (values (cdar valid-exit-codes)
                (when capturep ""))
        (if wait
            (let ((exit-code (process-exit-code (spawn-process-from-executable pathname parameters :wait t :input input :output final-output :environment environment))))
              (apply #'values
                     (cdr (or (assoc exit-code valid-exit-codes)
                              (let ((error-output (if (or capturep (and (typep final-output 'string-stream) (output-stream-p final-output)))
                                                      (get-output-stream-string final-output) "#<not captured>")))
                                (if-let ((error (assoc exit-code translated-error-exit-codes)))
                                  (destructuring-bind (type &rest error-initargs) (rest error)
                                    (apply #'error type (list* :program pathname :parameters parameters :status exit-code :output error-output
                                                               error-initargs)))
                                  (error 'executable-failure :program pathname :parameters parameters :status exit-code :output error-output)))))
                     (when capturep
                       (list (get-output-stream-string final-output)))))
            (spawn-process-from-executable pathname parameters :wait nil :input input :output final-output :environment environment)))))

(defmacro with-input-from-execution ((stream-var name params) &body body)
  (with-gensyms (block str)
    `(block ,block
       (with-output-to-string (,str)
         (execute-external ,name ,params :output ,str (when (boundp '*explanation*) *explanation*))
         (with-input-from-string (,stream-var (get-output-stream-string ,str))
           (return-from ,block (progn ,@body)))))))

(defvar *valid-exit-codes* nil)
(defvar *translated-error-exit-codes* nil)
(defvar *environment* '("HOME=/tmp"))
(defvar *explanation* '("<unexplained action>"))
(defvar *executable-standard-output-direction* :capture)
(defvar *executable-input-stream* nil)
(defvar *execute-asynchronously* nil)

(defmacro with-explanation (explanation &body body)
  "Execute BODY with *EXPLANATION* bound to EXPLANATION."
  `(let ((*explanation* ,(if (consp explanation) `(list ,@explanation) explanation)))
     ,@body))

(defun execution-output-string (name &rest params)
  (with-output-to-string (str)
    (execute-external name params :output str :explanation (when (boundp '*explanation*) *explanation*))))

(defmacro without-captured-executable-output (&body body)
  "Execute BODY without capturing standard output from executables."
  `(let ((*executable-standard-output-direction* t))
     ,@body))

(defmacro with-captured-executable-output (&body body)
  "Execute BODY while capturing standard output from executables."
  `(let ((*executable-standard-output-direction* :capture))
     ,@body))

(defmacro with-avoided-executable-output (&body body)
  "Execute BODY while avoiding standard output from executables."
  `(let ((*executable-standard-output-direction* nil))
     ,@body))

(defmacro with-environment (environment &body body)
  "Execute BODY with process variable environment set to ENVIRONMENT."
  `(let ((*environment* ,environment))
     ,@body))

(defmacro with-environment-extension (extension &body body)
  "Execute BODY with process variable environment prepended with EXTENSION."
  `(let ((*environment* (append ,extension *environment*)))
     ,@body))

(defmacro with-executable-input-stream (stream &body body)
  "Execute BODY with process input set to STREAM."
  `(let ((*executable-input-stream* ,stream))
     ,@body))

(defmacro with-asynchronous-execution (&body body)
  "Execute BODY within dynamic extent in which all calls to EXECUTE-EXTERNAL
immediately return a process structure, without waiting for the process
to finish."
  `(let ((*execute-asynchronously* t))
     ,@body))

(defun process-arg (arg)
  (etypecase arg
    (pathname (namestring arg))
    (list (apply #'concatenate 'string (mapcar #'process-arg arg)))
    (string arg)))

(defmacro define-executable (name &key may-want-display fixed-environment)
  `(defun ,name (&rest parameters)
     (let ((environment ,(if fixed-environment `',fixed-environment '*environment*)))
       (with-retry-restarts ((retry () :report "Retry execution of the external program.")
                             (accept () :report "Accept results of external program execution as successful. Return T."
                                     (return-from ,name t))
                             (fail () :report "Accept results of external program execution as failure. Return NIL."
                                   (return-from ,name nil))
                             ,@(when may-want-display
                                     `((retry (display)
                                              :report "Retry execution of the external program with DISPLAY set."
                                              :interactive (lambda ()
                                                             (format *query-io* "Enter value for the DISPLAY variable: ")
                                                             (finish-output *query-io*)
                                                             (list (read-line *query-io*)))
                                              (push (concatenate 'string "DISPLAY=" display) environment)))))
         (apply #'execute-external ',name (mapcar #'process-arg parameters)
                :explanation (when (boundp '*explanation*) *explanation*)
                :valid-exit-codes (acons 0 t *valid-exit-codes*)
                :translated-error-exit-codes *translated-error-exit-codes*
                :wait (not *execute-asynchronously*)
                :input *executable-input-stream*
                :output *executable-standard-output-direction*
                (when environment (list :environment environment)))))))

(defmacro with-valid-exit-codes ((&rest bindings) &body body)
  `(let ((*valid-exit-codes* (list ,@(mapcar (curry #'cons 'cons) bindings))))
     ,@body))

(defmacro with-exit-code-to-error-translation ((&rest bindings) &body body)
  `(let ((*translated-error-exit-codes* (list ,@(mapcar (curry #'cons 'list) bindings))))
     ,@body))

(defmacro exit-code-bind ((&rest bindings) &body body)
  `(handler-bind ((executable-failure (lambda (cond)
                                        (case (cond-status cond)
                                          ,@bindings))))
     ,@body))

(defmacro with-shell-predicate (form)
  `(with-valid-exit-codes ((1 nil)) ,form))
