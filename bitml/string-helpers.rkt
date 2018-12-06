#lang racket

;STRING HELPERS

;helpers to generate string transactions
(define (participants->tx-sigs participants tx-name)
  (foldl (lambda (p acc) (format "sig~a~a ~a" p tx-name acc))  "" participants))

(define (participants->sigs-declar participants tx-name pk-for-term [contract #f])
  (foldr (lambda (p acc) (format "const sig~a~a : signature = _ ~a\n~a" p tx-name
                                 (if (false? contract)
                                     ""
                                     (string-append "//signature of " tx-name " with private key corresponding to " (second (pk-for-term p contract))))
                                 acc))
         "" participants))

(define (list+sep->string l [sep ", "])
  (let* ([s (foldr (lambda (s r) (string-append s sep r)) "" l)]
         [length (string-length s)])
    (if (> length (string-length sep))
        (substring s 0 (- length (string-length sep)))
        s)))

(define (parts->sigs-params participants)
  (list+sep->string (map (lambda (s) (string-append "s" s)) participants)))

(define (parts->sigs-param-list participants)
  (map (lambda (s) (string-append "s" s)) participants))

(define format-secret (lambda (x) (string-append "sec_" (string-replace x ":int" ""))))

(define (format-timelock tl)
  (if (> tl 0) (format " absLock = block ~a\n" tl) ""))

(provide (all-defined-out))