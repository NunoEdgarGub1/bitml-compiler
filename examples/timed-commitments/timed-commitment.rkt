#lang bitml

(participant "A" "029c5f6f5ef0095f547799cb7861488b9f4282140d59a6289fbc90c70209c1cced")
(participant "B" "022c3afb0b654d3c2b0e2ffdcf941eaf9b6c2f6fcf14672f86f7647fa7b817af30")

(generate-keys)

(define timeout (after 10 (withdraw "B")))

(contract
 (pre (deposit "A" 1 "txA@0")(secret "A" a "000a"))
 
 (sum (reveal (a) (withdraw "A"))
      (ref timeout))

 (check-liquid
  #;(strategy "A" (do-reveal a)))

 (check "A" has-more-than 1
        (strategy "A" (do-reveal a))))
