#lang racket/base

(require (for-syntax racket/base syntax/parse)
         racket/list racket/bool racket/string)

;provides the default reader for an s-exp lang
(module reader syntax/module-reader
  bitml)

(provide  participant compile withdraw deposit guards
          after auth key secret vol-deposit putrevealif
          pred sum split generate-keys
          (rename-out [btrue true] [band and] [bnot not] [b= =] [b< <] [b+ +] [b- -] [b<= <=] [bsize size])
          #%module-begin #%datum #%top-interaction)

;--------------------------------------------------------------------------------------
;ENVIRONMENT

(define output "")

(define (add-output str [pre #f])
  (if pre
      (set! output (string-append str "\n" output))
      (set! output (string-append output "\n" str))))

;generate keys for debug purposes
(define gen-keys #f)

(define (set-gen-keys!)
  (set! gen-keys #t))

;security parameter (minimun secret length)
(define sec-param 128)

;function to enumerate tx indexes
(define tx-index 0)

(define (new-tx-index)
  (set! tx-index (add1 tx-index))
  tx-index)

(define (new-tx-name)
  (format "T~a" (new-tx-index)))

;helpers to store and retrieve participants' public keys
(define participants-table
  (make-hash))

(define (add-participant id pk)
  (hash-set! participants-table id pk))

(define (participant-pk id)
  (hash-ref participants-table id))

(define (get-participants)
  (hash-keys participants-table))

;helpers to store and retrieve participants' public keys for terms
(define pk-terms-table
  (make-hash))

(define (add-pk-for-term id term pk)
  (let ([name (format "pubkey~a~a" id (new-key-index))])
    (hash-set! pk-terms-table (cons id term) (list pk name))))

(define (pk-for-term id term)
  (hash-ref pk-terms-table (cons id term)
            (lambda ()
              (if gen-keys
                  (begin 
                    (add-pk-for-term id term "0277dc31c59a49ccdad15969ef154674b390e0028b50bdc1fa9b8de98be1320652")
                    (pk-for-term id term))
                  (raise (error 'bitml "no public key defined for participant ~a and contract ~a" id term))))))

(define key-index 0)

(define (new-key-index)
  (set! key-index (add1 key-index))
  key-index)

;helpers to store permanent deposits
(define parts empty)
(define (add-part id)
  (set! parts (cons id parts)))

(define deposit-txout empty)
(define (add-deposit txout)
  (set! deposit-txout (cons txout deposit-txout)))

(define tx-v 0)
(define (add-tx-v v)
  (set! tx-v (+ v tx-v)))

;helpers to store volatile deposits
(define volatile-deps-table
  (make-hash))

(define (add-volatile-dep part id val tx)
  (hash-set! volatile-deps-table id (list part val tx)))

(define (get-volatile-dep id)
  (hash-ref volatile-deps-table id))

;helpers to store the secrets
(define secrets-table
  (make-hash))

(define (add-secret id hash)
  (hash-set! secrets-table id hash))

(define (get-secret-hash id)
  (hash-ref secrets-table id))

;clear the state
(define (reset-state)
  (set! tx-v 0)
  (set! secrets-table (make-hash))
  (set! volatile-deps-table (make-hash))
  (set! deposit-txout empty)
  (set! parts empty)
  (set! tx-index 0))

;--------------------------------------------------------------------------------------
;STRING HELPERS

;helpers to generate string transactions
(define (participants->tx-sigs participants tx-name)
  (foldl (lambda (p acc) (format "sig~a~a ~a" p tx-name acc))  "" participants))

(define (participants->sigs-declar participants tx-name [contract #f])
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

(define (parts->sigs-params)
  (list+sep->string (map (lambda (s) (string-append "s" s)) (get-participants))))

(define (parts->sigs-param-list)
  (map (lambda (s) (string-append "s" s)) (get-participants)))

(define format-secret (lambda (x) (string-append "sec_" (string-replace x ":int" ""))))

(define (format-timelock tl)
  (if (> tl 0) (format " absLock = block ~a\n" tl) ""))
;--------------------------------------------------------------------------------------
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
                [sec-wit (list+sep->string (map (lambda (x) (if (member x sec-to-reveal) (format-secret x) "\"\"")) all-secrets) " ")]
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

  
(define-syntax (guards stx) (raise-syntax-error #f "wrong usage of guards" stx))

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
    [(_ ident:id hash:string)     
     #'(add-secret 'ident hash)]
    [(_)
     (raise-syntax-error 'deposit "wrong usage of secret" stx)]))


(define-syntax (sum stx) (raise-syntax-error #f "wrong usage of sum" stx))

;compilation command
;todo: output script
(define-syntax (compile stx)
  (syntax-parse stx
    #:literals (guards sum)
    [(_ (guards guard ...)
        (sum (contract params ...) ...))
     
     #`(begin
         (reset-state)
         guard ...

         (let* ([scripts-list (list (get-script (contract params ...)) ...)]
                [script (list+sep->string scripts-list " || ")]
                [script-params (remove-duplicates (append (get-script-params (contract params ...)) ...))])

           (compile-init parts deposit-txout tx-v script script-params)

           ;start the compilation of the continuation contracts
           (contract params ... '(sum (contract params ...)...) "Tinit" 0 tx-v (get-participants) 0 (get-script-params (contract params ...)) script-params)...

           (if gen-keys
               ;compile pubkeys for terms
               (for-each
                (lambda (s)
                  (let ([key-name (pk-for-term (first s) (rest s))])
                    (add-output (format "const ~a = pubkey:~a" (second key-name) (first key-name)) #t)))
                (hash-keys pk-terms-table))
               (add-output "" #t))
           
           (displayln output)))]
    
    [(_ (guards guard ...)
        (contract params ...))
     
     #`(begin
         (reset-state)
         guard ...
         
         (let ([script (get-script (contract params ...))]
               [script-params (get-script-params (contract params ...))])
           (compile-init parts deposit-txout tx-v script script-params)

           ;start the compilation of the contract
           (contract params ... '(contract params ...) "Tinit" 0 tx-v (get-participants) 0 script-params script-params)

           (if gen-keys
               ;compile pubkeys for terms
               (for-each
                (lambda (s)
                  (let ([key-name (pk-for-term (first s) (rest s))])
                    (add-output (format "const ~a = pubkey:~a" (second key-name) (first key-name)) #t)))
                (hash-keys pk-terms-table))
               (add-output "" #t))
           
           (displayln output)))]))

;compiles the output-script for a Di branch. Corresponds to Bout(D) in formal def
(define-syntax (get-script stx)
  (syntax-parse stx
    #:literals (putrevealif auth after pred)
    [(_ (putrevealif (tx-id:id ...) (sec:id ...) (~optional (pred p)) (~optional (contract params ...))))

     #'(get-script* '(putrevealif (tx-id ...) (sec ...) (~? (pred p)) (~? (contract params ...) ()))
                    '(putrevealif (tx-id ...) (sec ...) (~? (pred p)) (~? (contract params ...) ())))]
    [(_ (auth part ... cont)) #'(get-script* '(auth part ... cont) 'cont)]
    [(_ (after t cont)) #'(get-script* '(after t cont) 'cont)]
    [(_ x) #'(get-script* 'x 'x)]))

;auxiliar function that maintains the contract passed in the first call
(define-syntax (get-script* stx)
  (syntax-parse stx
    #:literals (putrevealif auth after pred)
    [(_ parent '(putrevealif (tx-id:id ...) (sec:id ...) (~optional (pred p)) (~optional (contract params ...))))

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
         (string-append "versig(" keys-string "; " (parts->sigs-params)  ")"))]))


;return the parameters for the script obtained by get-script
(define-syntax (get-script-params stx)
  (syntax-parse stx
    #:literals (putrevealif auth after pred)
    [(_ (putrevealif (tx-id:id ...) (sec:id ...) (~optional (pred p)) (~optional (contract params ...))))

     #'(let ([cont-params (~? (get-script-params p) '())])
         (append (list (string-append (symbol->string 'sec) ":int") ...) cont-params))]
    [(_ (auth part ... cont)) #'(get-script-params cont)]
    [(_ (after t cont)) #'(get-script-params cont)]
    [(_ x) #''()]))
         

;compiles the Tinit transaction
(define (compile-init parts deposit-txout tx-v script script-params-list)
  (let* ([tx-sigs-list (for/list ([p parts]
                                  [i (in-naturals)])
                         (format "sig~a~a" p i))]                  
         [script-params (list+sep->string (append script-params-list (parts->sigs-param-list)))]    
         [inputs (string-append "input = [ "
                                (list+sep->string (for/list ([p tx-sigs-list]
                                                             [out deposit-txout])
                                                    (format "~a:~a" out p))
                                                  "; ") " ]")])
    ;compile public keys
    (for-each (lambda (s) (add-output (format "const pubkey~a = pubkey:~a" s (participant-pk s)))) (get-participants))
    (add-output "")

    ;compile pubkeys for terms
    (for-each
     (lambda (s)
       (let ([key-name (pk-for-term (first s) (rest s))])
         (add-output (format "const ~a = pubkey:~a" (second key-name) (first key-name)))))
     (hash-keys pk-terms-table))
    (add-output "")

    ;compile signatures constants for Tinit
    (for-each (lambda (e t) (add-output (string-append "const " e " : signature = _ //add signature for output " t))) tx-sigs-list deposit-txout)
  
    (add-output (format "\ntransaction Tinit { \n ~a \n output = ~a BTC : fun(~a) . ~a \n}\n" inputs tx-v script-params script))))


(define-syntax (putrevealif stx)
  (syntax-parse stx
    #:literals(pred sum)
    [(_ (tx-id:id ...) (sec:id ...) (~optional (pred p)) (~optional (sum (contract params ...)...)) parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     
     #'(begin        
         (let* ([tx-name (format "T~a" (new-tx-index))]
                [vol-dep-list (map (lambda (x) (get-volatile-dep x)) (list 'tx-id ...))] 
                [new-value (foldl (lambda (x acc) (+ (second x) acc)) value vol-dep-list)]

                [format-input (lambda (x sep acc) (format "~a:sig~a" (third (get-volatile-dep x)) (symbol->string x)))]

                [vol-inputs (list 'tx-id ...)]
              
                [vol-inputs-str (if (> 0 (length vol-inputs))
                                    (string-append "; " (list+sep->string (map (lambda (x) (format-input x)) vol-inputs)))
                                    "")]
                [scripts-list (~? (list (get-script (contract params ...)) ...) null)]
                [script (list+sep->string scripts-list " || ")]
                [script-params (list+sep->string (append
                                                  (~? (append (get-script-params (contract params ...)) ...) '())
                                                  (parts->sigs-param-list)))]
                ;[script-params (parts->sigs-params)]
                [sec-wit (list+sep->string (map (lambda (x) (if (member x sec-to-reveal) (format-secret x) "\"\"")) all-secrets) " ")]
                [tx-sigs (participants->tx-sigs parts tx-name)]
                [inputs (string-append "input = [ " parent-tx "@" (number->string input-idx) ":" sec-wit " " tx-sigs vol-inputs-str "]")])

           ;compile signatures constants for the volatile deposits
           (for-each
            (lambda (x) (add-output (string-append "const sig" (symbol->string x) " : signature = _ //add signature for output " (third (get-volatile-dep x)))))
            (list 'tx-id ...))

           (add-output (participants->sigs-declar parts tx-name parent-contract))

           ;compile the secrets declarations
           (for-each
            (lambda (x) (add-output (string-append "const sec_" (symbol->string x) " : string = _ //add secret for output " (symbol->string x))))
            sec-to-reveal)

         
           (add-output (format "\ntransaction ~a { \n ~a \n output = ~a BTC : fun(~a) . ~a \n}\n" tx-name inputs new-value script-params script))
         
           (~? (contract params ... '(sum (contract params ...)...) tx-name 0 new-value parts 0 (get-script-params (contract params ...)) (get-script-params parent-contract)))...))]
    
    [(_ (tx-id:id ...) (sec:id ...) (~optional (pred p)) (~optional (contract params ...)) parent-contract parent-tx input-idx value parts timelock  sec-to-reveal all-secrets)     
     #'(begin
         (let* ([tx-name (format "T~a" (new-tx-index))]
                [vol-dep-list (map (lambda (x) (get-volatile-dep x)) (list 'tx-id ...))] 
                [new-value (foldl (lambda (x acc) (+ (second x) acc)) value vol-dep-list)]

                [format-input (lambda (x sep acc) (format "~a:sig~a" (third (get-volatile-dep x)) (symbol->string x)))]

                [vol-inputs (list 'tx-id ...)]
              
                [vol-inputs-str (if (> 0 (length vol-inputs))
                                    (string-append "; " (list+sep->string (map (lambda (x) (format-input x)) vol-inputs)))
                                    "")]
              
                [script (~? (get-script (contract params ...)) null)]
                [script-params (list+sep->string (append
                                                  (~? (get-script-params (contract params ...)) '())
                                                  (parts->sigs-param-list)))]
                ;[script-params (parts->sigs-params)]
                [sec-wit (list+sep->string (map (lambda (x) (if (member x sec-to-reveal) (format-secret x) "\"\"")) all-secrets) " ")]
                [tx-sigs (participants->tx-sigs parts tx-name)]
                [inputs (string-append "input = [ " parent-tx "@" (number->string input-idx) ": " sec-wit " " tx-sigs vol-inputs-str "]")])

           ;compile signatures constants for the volatile deposits
           (for-each
            (lambda (x) (add-output (string-append "const sig" (symbol->string x) " : signature = _ //add signature for output " (third (get-volatile-dep x)))))
            (list 'tx-id ...))

           (add-output (participants->sigs-declar parts tx-name parent-contract))
           
           ;compile the secrets declarations
           (for-each
            (lambda (x) (add-output (string-append "const sec_" x " = _ //add secret for output " x)))
            sec-to-reveal)
         
           (add-output (format "\ntransaction ~a { \n ~a \n output = ~a BTC : fun(~a) . ~a\n~a}\n"
                               tx-name inputs new-value script-params script (format-timelock timelock)))
         
           (~? (contract params ... '(contract params ...) tx-name 0 new-value parts 0 (get-script-params (contract params ...)) (get-script-params parent-contract) ))))]))


;operators for predicate in putrevealif
(define-syntax (btrue stx) (raise-syntax-error #f "wrong usage of true" stx))
(define-syntax (band stx) (raise-syntax-error #f "wrong usage of and" stx))
(define-syntax (bnot stx) (raise-syntax-error #f "wrong usage of not" stx))
(define-syntax (b= stx) (raise-syntax-error #f "wrong usage of =" stx))
(define-syntax (b< stx) (raise-syntax-error #f "wrong usage of <" stx))
(define-syntax (b<= stx) (raise-syntax-error #f "wrong usage of <" stx))
(define-syntax (b+ stx) (raise-syntax-error #f "wrong usage of +" stx))
(define-syntax (b- stx) (raise-syntax-error #f "wrong usage of -" stx))
(define-syntax (bsize stx) (raise-syntax-error #f "wrong usage of size" stx))
(define-syntax (pred stx) (raise-syntax-error #f "wrong usage of pred" stx))

(define-syntax (compile-pred stx)
  (syntax-parse stx
    #:literals(btrue band bnot)
    [(_ btrue) #'"true"]
    [(_ (band a b)) #'(string-append (compile-pred a) " && " (compile-pred b))]
    [(_ (bnot a)) #'(string-append "!(" (compile-pred a) ")")]
    [(_ p) #'(compile-pred-exp p)]))


(define-syntax (compile-pred-exp stx)
  (syntax-parse stx
    #:literals(b= b< b<= b+ b- bsize)
    [(_ (b= a b)) #'(string-append (compile-pred-exp a) "==" (compile-pred-exp b))]
    [(_ (b< a b)) #'(string-append (compile-pred-exp a) "<" (compile-pred-exp b))]
    [(_ (b<= a b)) #'(string-append (compile-pred-exp a) "<=" (compile-pred-exp b))]
    [(_ (b+ a b)) #'(string-append "(" (compile-pred-exp a) "+" (compile-pred-exp b) ")")]
    [(_ (b- a b)) #'(string-append "(" (compile-pred-exp a) "-" (compile-pred-exp b) ")")]
    [(_ (bsize a)) #'(string-append "(size(" (compile-pred-exp a) ") - " (number->string sec-param) ")")]
    [(_ a:number) #'(number->string a)]
    [(_ a:string) #'a]
    [(_ a:id) #'(symbol->string 'a)]
    [(_) (raise-syntax-error #f "wrong if predicate" stx)]))


(define-syntax (split stx)
  (syntax-parse stx
    #:literals(sum)
    [(_ (val:number (sum (contract params ...)...))... parent-contract parent-tx input-idx value parts timelock sec-to-reveal all-secrets)
     #`(begin    
         (let* ([tx-name (format "T~a" (new-tx-index))]
                [values-list (list val ...)]
                [subscripts-list (list (list (get-script (contract params ...)) ...)...)]
                [script-list (for/list([subscripts subscripts-list])
                               (list+sep->string subscripts " || "))]
                [script-params-list (list (list+sep->string (append
                                                             (remove-duplicates (append (get-script-params (contract params ...)) ...))
                                                             (parts->sigs-param-list)))...)]  
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
                 (lambda (x) (add-output (string-append "const sec_" (symbol->string x) " : string = _ //add secret for output " (symbol->string x))))
                 sec-to-reveal)

                (add-output (format "\ntransaction ~a { \n ~a \n ~a \n~a}\n" tx-name inputs output (format-timelock timelock)))
           
                ;compile the continuations
                
                (begin             
                  (execute-split (sum '(contract params ...)...) tx-name count val parts)
                  (set! count (add1 count)))...))))]))

(define-syntax (execute-split stx)
  (syntax-parse stx
    #:literals (sum)
    [(_ (sum '(contract params ...) ...) parent-tx input-idx value parts)     
     #'(let ([sum-secrets (remove-duplicates (append (get-script-params (contract params ...))...))])
         (begin
           ;(begin
           ;(displayln '(contract params ...))
           ;(displayln (format "parametri ~a ~a ~a ~a ~a" parent-tx input-idx value parts sum-secrets))
           ;(displayln (get-script-params (contract params ...)))
           ;(displayln ""))...


           (contract params ... '(contract params ...) parent-tx input-idx value parts 0
                     sum-secrets  (get-script-params (contract params ...)))...

                                                                            ))]))