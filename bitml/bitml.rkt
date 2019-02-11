#lang racket/base

(require (for-syntax racket/base syntax/parse)
         racket/list racket/bool racket/string
         "string-helpers.rkt" "env.rkt" "exp.rkt" "terminals.rkt")

(provide (all-defined-out))

;SYNTAX DEFINITIONS

;turns on the generation of the keys
(define-syntax (generate-keys stx)
  #'(set-gen-keys!))

;declaration of a participant
;associates a name to a public key
(define-syntax (participant stx)
  (syntax-parse stx
    [(_ ident:string pubkey:string)
     #'(add-participant 'ident pubkey)]))

;declaration of a participant
;associates a name and a term to a public key
(define-syntax (key stx)
  (syntax-parse stx
    [(_ ident:string term pubkey:string)
     #'(add-pk-for-term 'ident 'term pubkey)]))

;compiles withdraw to transaction
(define-syntax (withdraw stx)
  (syntax-parse stx    
    [(_ part parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(begin         
         (let* ([tx-name (new-tx-name)]
                [tx-sigs (participants->tx-sigs parts tx-name)]
                [sec-wit (list+sep->string (map (lambda (x) (if (member x sec-to-reveal) (format-secret x) "0")) all-secrets) " ")]
                [inputs (string-append "input = [ " parent-tx "@" (number->string input-idx) ": " sec-wit " " tx-sigs "]")])


           (add-output (participants->sigs-declar parts tx-name parent-contract))
         
           (add-output (string-append
                        (format "transaction ~a { \n ~a \n output = ~a BTC : fun(x) . versig(pubkey~a; x) \n "
                                tx-name inputs value part)
                        (if (> timelock 0)
                            (format "absLock = block ~a \n}\n" timelock)
                            "\n}\n")))))]
    [(_)
     (raise-syntax-error #f "wrong usage of withdraw" stx)]))

;handles after
(define-syntax (after stx)
  (syntax-parse stx   
    [(_ t (contract params ...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(contract params ... parent-contract parent-tx input-idx value parts (max t timelock) sec-to-reveal all-secrets)]
    
    [(_)
     (raise-syntax-error #f "wrong usage of after" stx)]))

;handles auth
(define-syntax (auth stx)
  (syntax-parse stx   
    [(_ part:string ... (contract params ...) orig-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     ;#'(contract params ... parent-tx input-idx value (remove part parts) timelock)]
     #'(contract params ... orig-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)] 

    [(_)
     (raise-syntax-error #f "wrong usage of auth" stx)]))

(define-syntax (deposit stx)
  (syntax-parse stx
    [(_ part:string v:number txout)
     #'(begin
         (add-part part)
         (add-deposit txout)
         (add-tx-v v))]
    [(_)
     (raise-syntax-error #f "wrong usage of deposit" stx)]))

(define-syntax (vol-deposit stx)
  (syntax-parse stx
    [(_ part:string ident:id val:number txout)
     #'(add-volatile-dep part 'ident val txout)]
    [(_)
     (raise-syntax-error #f "wrong usage of deposit" stx)]))

;TODO capisci come controllare l'errore a tempo statico
(define-syntax (secret stx)
  (syntax-parse stx
    [(_ part:string ident:id hash:string)     
     #'(add-secret part 'ident hash)]
    [(_)
     (raise-syntax-error 'deposit "wrong usage of secret" stx)]))


;prepares and displays the output of the compilation
(define (show-compiled)

  ;if the keys where auto-generated, add them to the output
  (when gen-keys
    ;compile pubkeys for terms
    (for-each
     (lambda (s)
       (let ([key-name (pk-for-term (first s) (rest s))])
         (add-output (format "const ~a = pubkey:~a" (second key-name) (first key-name)) #t)))
     (hash-keys pk-terms-table))
    (add-output "" #t))
           
  (displayln output))

;compiles the output-script for a Di branch. Corresponds to Bout(D) in formal def
(define-syntax (get-script stx)
  (syntax-parse stx
    #:literals (putrevealif auth after pred)
    [(_ (reveal (sec:id ...) (contract params ...)))
     #'(get-script (putrevealif () (sec ...) (contract params ...)))]
    [(_ (reveal (sec:id ...) (pred p) (contract params ...)))
     #'(get-script (putrevealif () (sec ...) (pred p) (contract params ...)))]
    [(_ (reveal (tx:id ...) (contract params ...)))
     #'(get-script (putrevealif (tx ...) () (contract params ...)))]
    [(_ (putrevealif (tx-id:id ...) (sec:id ...) (~optional (pred p)) (contract params ...)))
     (let [(contract #''(putrevealif (tx-id ...) (sec ...) (~? (pred p)) (contract params ...)) )]
       #`(get-script* #,contract #,contract))]

    [(_ (auth part ... cont)) #'(get-script* '(auth part ... cont) 'cont)]
    [(_ (after t cont)) #'(get-script* '(after t cont) 'cont)]
    [(_ x) #'(get-script* 'x 'x)]))

;auxiliar function that maintains the contract passed in the first call
(define-syntax (get-script* stx)
  (syntax-parse stx
    #:literals (putrevealif auth after pred)
    [(_ parent '(putrevealif (tx-id:id ...) (sec:id ...) (~optional (pred p)) (contract params ...)))

     #'(let ([pred-comp (~? (string-append (compile-pred p) " && ") "")]
             [secrets (list 'sec ...)]
             [compiled-continuation (~? (get-script* parent p) (get-script* parent ()))])
         (string-append
          (foldr (lambda (x res)
                   (string-append pred-comp "sha256(" (symbol->string x) ") == hash:" (get-secret-hash x)
                                  " && size(" (symbol->string x) ") >= " (number->string sec-param) " && " res))
                 "" secrets)
          compiled-continuation))]
    [(_ parent '(auth part ... cont)) #'(get-script* parent cont)]
    [(_ parent '(after t cont)) #'(get-script* parent cont)]
    [(_ parent x)
     #'(let* ([keys (for/list([part (get-participants)])
                      (second (pk-for-term part parent)))]
              [keys-string (list+sep->string keys)])
         (string-append "versig(" keys-string "; " (parts->sigs-params (get-participants))  ")"))]))


;return the parameters for the script obtained by get-script
(define-syntax (get-script-params stx)
  (syntax-parse stx
    #:literals (putrevealif auth after pred sum split)
    [(_ (reveal (sec:id ...) (contract params ...)))
     #'(get-script-params (putrevealif () (sec ...) (contract params ...)))]
    [(_ (revealif (sec:id ...) (pred p) (contract params ...)))
     #'(get-script-params (putrevealif () (sec ...) (pred p) (contract params ...)))]
    [(_ (put (tx:id ...) (contract params ...)))
     #'(get-script-params (putrevealif (tx ...) () (contract params ...)))]
    
    [(_ (sum (contract params ...)...))
     #'(remove-duplicates (append (get-script-params (contract params ...)) ...))]
    
    [(_ (putrevealif (tx-id:id ...) (sec:id ...) (~optional (pred p)) (~optional (contract params ...))))
     #'(list (string-append (symbol->string 'sec) ":int") ...)]
    [(_ (auth part ... cont)) #'(get-script-params cont)]
    [(_ (after t cont)) #'(get-script-params cont)]
    [(_ x) #''()]))
         

;compiles the Tinit transaction
(define (compile-init parts deposit-txout tx-v script script-params-list)
  (let* ([tx-sigs-list (for/list ([p parts]
                                  [i (in-naturals)])
                         (format "sig~a~a" p i))]                  
         [script-params (list+sep->string (append script-params-list (parts->sigs-param-list (get-participants))))]    
         [inputs (string-append "input = [ "
                                (list+sep->string (for/list ([p tx-sigs-list]
                                                             [out deposit-txout])
                                                    (format "~a:~a" out p))
                                                  "; ") " ]")])
    ;compile public keys    
    (for-each (lambda (s) (add-output (format "const pubkey~a = pubkey:~a" s (participant-pk s)))) (get-participants))
    (add-output "")

    (unless gen-keys
      ;compile pubkeys for terms
      (for-each
       (lambda (s)
         (let ([key-name (pk-for-term (first s) (rest s))])
           (add-output (format "const ~a = pubkey:~a" (second key-name) (first key-name)))))
       (hash-keys pk-terms-table))
      (add-output ""))

    ;compile signatures constants for Tinit
    (for-each (lambda (e t) (add-output (string-append "const " e " : signature = _ //add signature for output " t))) tx-sigs-list deposit-txout)
  
    (add-output (format "\ntransaction Tinit { \n ~a \n output = ~a BTC : fun(~a) . ~a \n}\n" inputs tx-v script-params script))))


(define-syntax (putrevealif stx)
  (syntax-parse stx
    #:literals(pred sum)
    [(_ (tx-id:id ...) (sec:id ...) (~optional (pred p)) (sum (contract params ...)...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(begin
         (let* ([tx-name (format "T~a" (new-tx-index))]
                [vol-dep-list (map (lambda (x) (get-volatile-dep x)) (list 'tx-id ...))] 
                [new-value (foldl (lambda (x acc) (+ (second x) acc)) value vol-dep-list)]

                [format-input (lambda (x sep acc) (format "~a:sig~a" (third (get-volatile-dep x)) (symbol->string x)))]

                [vol-inputs (list 'tx-id ...)]
              
                [vol-inputs-str (if (> 0 (length vol-inputs))
                                    (string-append "; " (list+sep->string (map (lambda (x) (format-input x)) vol-inputs)))
                                    "")]
                [scripts-list (list (get-script (contract params ...)) ...)]
                [script (list+sep->string scripts-list " || ")]
                [script-params (list+sep->string (append
                                                  (~? (append (get-script-params (contract params ...)) ...) '())
                                                  (parts->sigs-param-list (get-participants))))]
                ;[script-params (parts->sigs-params)]
                [sec-wit (list+sep->string (map (lambda (x) (if (member x sec-to-reveal) (format-secret x) "0")) all-secrets) " ")]
                [tx-sigs (participants->tx-sigs parts tx-name)]
                [inputs (string-append "input = [ " parent-tx "@" (number->string input-idx) ":" sec-wit " " tx-sigs vol-inputs-str "]")])

           ;compile signatures constants for the volatile deposits
           (for-each
            (lambda (x) (add-output (string-append "const sig" (symbol->string x) " : signature = _ //add signature for output " (third (get-volatile-dep x)))))
            (list 'tx-id ...))

           (add-output (participants->sigs-declar parts tx-name parent-contract))

           ;compile the secrets declarations
           (for-each
            (lambda (x) (add-output (string-append "const sec_" x " = _ //add value of secret " (string-replace x ":int" ""))))
            sec-to-reveal)

         
           (add-output (format "\ntransaction ~a { \n ~a \n output = ~a BTC : fun(~a) . ~a \n}\n" tx-name inputs new-value script-params script))
         
           (contract params ... '(sum (contract params ...)...)
                     tx-name 0 new-value parts 0 (get-script-params (contract params ...)) (get-script-params parent-contract))...))]
    
    [(_ (tx-id:id ...) (sec:id ...) (~optional (pred p)) (contract params ...) parent-contract parent-tx input-idx value parts timelock  sec-to-reveal all-secrets)
     #'(putrevealif (tx-id ...) (sec ...) (~? (pred p)) (sum (contract params ...)) parent-contract parent-tx input-idx value parts timelock  sec-to-reveal all-secrets)]))


(define-syntax (split stx)
  (syntax-parse stx
    #:literals(sum)    
    [(_ (val:number -> (sum (contract params ...)...))...
        parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #`(begin    
         (let* ([tx-name (format "T~a" (new-tx-index))]
                [values-list (list val ...)]
                [subscripts-list (list (list (get-script (contract params ...)) ...)...)]
                [script-list (for/list([subscripts subscripts-list])
                               (list+sep->string subscripts " || "))]
                [script-params-list (list (list+sep->string (append
                                                             (remove-duplicates (append (get-script-params (contract params ...)) ...))
                                                             (parts->sigs-param-list (get-participants))))...)]  
                [sec-wit (list+sep->string (map (lambda (x) (if (member x sec-to-reveal) (format-secret x) "\"\"")) all-secrets) " ")]
                [tx-sigs (participants->tx-sigs parts tx-name)]
                [inputs (string-append "input = [ " parent-tx "@" (number->string input-idx) ":" sec-wit " " tx-sigs "]")]
                [outputs (for/list([value values-list]
                                   [script script-list]
                                   [script-params script-params-list])
                           (format "~a BTC : fun(~a) . ~a" value script-params script))]
                [output (string-append "output = [ " (list+sep->string outputs ";\n\t") " ]")]
                [count 0])                

           (add-output (participants->sigs-declar parts tx-name parent-contract))

           (if(> (apply + values-list) value)
              (raise-syntax-error 'bitml
                                  (format "split spends ~a BTC but it receives ~a BTC" (+ val ...) value)
                                  '(split (val (sum (contract params ...)...))...))

              (begin
                ;compile the secrets declarations
                (for-each
                 (lambda (x) (add-output (string-append "const sec_" x " : string = _ //add value of secret " (string-replace x ":int" ""))))
                 sec-to-reveal)

                (add-output (format "\ntransaction ~a { \n ~a \n ~a \n~a}\n" tx-name inputs output (format-timelock timelock)))
           
                ;compile the continuations
                
                (begin             
                  (execute-split '(contract params ...)... tx-name count val parts)
                  (set! count (add1 count)))...))))]

    ;allow for split branches with unary sums
    [(_ (val:number -> (~or (sum (contract params ...)...) (scontract sparams ...)))...
        parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(split (val -> (~? (sum (scontract sparams ...))) (~? (sum (contract params ...)...)) )...
              parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)]))

(define-syntax (execute-split stx)
  (syntax-parse stx
    [(_ '(contract params ...) ... parent-tx input-idx value parts)     
     #'(let ([sum-secrets (get-script-params (sum (contract params ...)...))])
         ;(begin
         ;(displayln '(contract params ...))
         ;(displayln (format "parametri ~a ~a ~a ~a ~a" parent-tx input-idx value parts sum-secrets))
         ;(displayln (get-script-params (contract params ...)))
         ;(displayln ""))...
         
         (contract params ... '(contract params ...) parent-tx input-idx value parts 0
                   sum-secrets (get-script-params (contract params ...)))...)]))


;syntax sugar for putrevealif
;--------------------------------------------------------------------------
(define-syntax (put stx)
  (syntax-parse stx
    #:literals(sum)
    [(_ (tx-id:id ...) (sum (contract params ...)...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(putrevealif (tx-id ...) () (sum (contract params ...)...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)]
    [(_ (tx-id:id ...) (contract params ...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(putrevealif (tx-id ...) () (contract params ...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)]))

(define-syntax (reveal stx)
  (syntax-parse stx
    #:literals(sum)
    [(_ (sec:id ...) (sum (contract params ...)...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(putrevealif () (sec ...) (sum (contract params ...)...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)]
    [(_ (sec:id ...) (contract params ...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(putrevealif () (sec ...) (contract params ...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)]))

(define-syntax (revealif stx)
  (syntax-parse stx
    #:literals(sum pred)
    [(_ (sec:id ...) (pred p) (sum (contract params ...)...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(putrevealif () (sec ...) (pred p) (sum (contract params ...)...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)]
    [(_ (sec:id ...) (pred p) (contract params ...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #'(putrevealif () (sec ...) (pred p) (contract params ...) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)]))