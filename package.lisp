;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-

(cl:defpackage #:executor
  (:nicknames :exec)
  (:use :common-lisp :alexandria :pergamum :portable-spawn)
  (:export
   ;; tunables
   #:*search-path*
   #:*execute-explanatory*
   #:*execute-verbosely*
   #:*execute-dryly*
   ;; conditions
   #:executable-failure
   #:executable-not-found
   #:required-executable-not-found
   ;; functions and macros
   #:executable
   #:find-executable
   #:with-explained-execution
   #:with-verbose-execution
   #:with-dry-execution
   #:execute-external
   #:with-explanation
   #:*executable-standard-output-direction*
   #:with-avoided-executable-output
   #:with-captured-executable-output
   #:with-unaffected-executable-output
   #:with-maybe-avoided-executable-output
   #:with-maybe-captured-executable-output
   #:with-maybe-unaffected-executable-output
   #:with-executable-input-stream
   #:with-input-from-execution
   #:with-environment
   #:with-environment-extension
   #:execution-output-string
   #:define-executable
   #:with-valid-exit-codes
   #:with-exit-code-to-error-translation
   #:exit-code-bind
   #:with-shell-predicate
   #:*execute-asynchronously*
   #:with-asynchronous-execution
   ;; remote-executor
   #:ssh
   #:compile-shell-command
   #:invoke-with-captured-external-output-and-status
   #:run-remote-commands
   #:watch-remote-commands
   ))
