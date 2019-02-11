#lang racket/base

(require (for-syntax racket/base syntax/parse) "env.rkt" "terminals.rkt")

(provide (all-defined-out)) 

;---------------------------------------------------------------------------------------
;methods used to transcompile predicates to balzac predicates
(define-syntax (compile-pred stx)
  (syntax-parse stx
    #:literals(btrue band bnot b= b< b<= b!=)
    [(_ btrue) #'"true"]
    [(_ (band a b)) #'(string-append (compile-pred a) " && " (compile-pred b))]
    [(_ (bnot a)) #'(string-append "!(" (compile-pred a) ")")]
    [(_ (b= a b)) #'(string-append (compile-pred-exp a) "==" (compile-pred-exp b))]
    [(_ (b!= a b)) #'(string-append (compile-pred-exp a) "!=" (compile-pred-exp b))]
    [(_ (b< a b)) #'(string-append (compile-pred-exp a) "<" (compile-pred-exp b))]
    [(_ (b<= a b)) #'(string-append (compile-pred-exp a) "<=" (compile-pred-exp b))]))

(define-syntax (compile-pred-exp stx)
  (syntax-parse stx
    #:literals(b+ b- bsize)
    [(_ (b+ a b)) #'(string-append "(" (compile-pred-exp a) "+" (compile-pred-exp b) ")")]
    [(_ (b- a b)) #'(string-append "(" (compile-pred-exp a) "-" (compile-pred-exp b) ")")]
    [(_ (bsize a:id)) #'(string-append "(size(" (symbol->string 'a) ") - " (number->string sec-param) ")")]
    [(_ a:number) #'(number->string a)]
    [(_) (raise-syntax-error #f "wrong if predicate" stx)]))


;---------------------------------------------------------------------------------------
;methods used to transcompile predicates to maude predicates
(define-syntax (compile-pred-maude stx)
  (syntax-parse stx
    #:literals(btrue band bnot b= b< b<= b!=)
    [(_ btrue) #'"True"]
    [(_ (band a b)) #'(string-append (compile-pred-maude a) " && " (compile-pred-maude b))]
    [(_ (bnot a)) #'(string-append "!(" (compile-pred-maude a) ")")]
    [(_ (b= a b)) #'(string-append (compile-pred-exp-maude a) " == " (compile-pred-exp-maude b))]
    [(_ (b!= a b)) #'(string-append (compile-pred-exp-maude a) " != " (compile-pred-exp-maude b))]
    [(_ (b< a b)) #'(string-append (compile-pred-exp-maude a) " < " (compile-pred-exp-maude b))]
    [(_ (b<= a b)) #'(string-append (compile-pred-exp-maude a) " <= " (compile-pred-exp-maude b))]))

(define-syntax (compile-pred-exp-maude stx)
  (syntax-parse stx
    #:literals(b= b< b<= b+ b- bsize)
    [(_ (b+ a b)) #'(string-append "(" (compile-pred-exp-maude a) " + " (compile-pred-exp-maude b) ")")]
    [(_ (b- a b)) #'(string-append "(" (compile-pred-exp-maude a) " - " (compile-pred-exp-maude b) ")")]
    [(_ (bsize a:id)) #'(string-append "size(" (symbol->string 'a) ")")]
    [(_ a:number) #'(string-append "const(" (number->string a) ")")]
    [(_) (raise-syntax-error #f "wrong if predicate" stx)]))

;---------------------------------------------------------------------------------------
;methods used to compile preditcates contraints for constraint solving
(define-syntax (compile-pred-constraint stx)
  (syntax-parse stx
    #:literals(btrue band bnot b= b< b<= b!=)
    [(_ btrue) #'#t]
    [(_ (band a b)) #'(list 'and (compile-pred-constraint a) (compile-pred-constraint b))]
    [(_ (bnot a)) #'(list 'not (compile-pred-constraint a))]
    [(_ (b= a b)) #'(list 'equal? (compile-pred-exp-contraint a) (compile-pred-exp-contraint b))]
    [(_ (b!= a b)) #'(list 'not (list 'equal? (compile-pred-exp-contraint a) (compile-pred-exp-contraint b)))]
    [(_ (b< a b)) #'('< (compile-pred-exp-contraint a) (compile-pred-exp-contraint b))]
    [(_ (b<= a b)) #'(list '<= (compile-pred-exp-contraint a) (compile-pred-exp-contraint b))]))

(define-syntax (compile-pred-exp-contraint stx)
  (syntax-parse stx
    #:literals(b+ b- bsize)
    [(_ (b+ a b)) #'('+ (compile-pred-exp-contraint a) (compile-pred-exp-contraint b))]
    [(_ (b- a b)) #'('- (compile-pred-exp-contraint a) (compile-pred-exp-contraint b))]
    [(_ (bsize a:id)) #''a]
    [(_ a:number) #'a]
    [(_) (raise-syntax-error #f "wrong if predicate" stx)]))

(define-syntax (get-constr-var stx)
  (syntax-parse stx
    #:literals(btrue band bnot b= b< b<= b!=)
    [(_ btrue) #''()]
    [(_ (band a b)) #'(append (get-constr-var a) (get-constr-var b))]
    [(_ (bnot a)) #'(get-constr-var a)]
    [(_ (b= a b)) #'(append (get-constr-exp-var a) (get-constr-exp-var b))]
    [(_ (b!= a b)) #'(append (get-constr-exp-var a) (get-constr-exp-var b))]
    [(_ (b< a b)) #'(append (get-constr-exp-var a) (get-constr-exp-var b))]
    [(_ (b<= a b)) #'(append (get-constr-exp-var a) (get-constr-exp-var b))]))

(define-syntax (get-constr-exp-var stx)
  (syntax-parse stx
    #:literals(b+ b- bsize)
    [(_ (b+ a b)) #'(append (get-constr-exp-var a) (get-constr-exp-var b))]
    [(_ (b- a b)) #'(append (get-constr-exp-var a) (get-constr-exp-var b))]
    [(_ (bsize a:id)) #'(list 'a)]
    [(_ a:number) #''()]
    [(_) (raise-syntax-error #f "wrong if predicate" stx)]))