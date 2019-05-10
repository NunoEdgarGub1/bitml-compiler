#lang bitml

(debug-mode)

(auto-generate-secrets)

(participant "A" "029c5f6f5ef0095f547799cb7861488b9f4282140d59a6289fbc90c70209c1cced")
(participant "B" "022c3afb0b654d3c2b0e2ffdcf941eaf9b6c2f6fcf14672f86f7647fa7b817af30")

(contract (pre
           (deposit "A" 1 "txA@0")(secret "A" a "6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b")
           (deposit "B" 1 "txB@0")(secret "B" b "d4735e3a265e16eee03f59718b9b5d03019c07d8b6c51f90da3a666eec13ab35"))        

          (choice
           (revealif (b) (pred (between b 0 1))
                     (choice
                      (revealif (a b) (pred (= a b)) (withdraw "A"))
                      (revealif (a b) (pred (!= a b)) (withdraw "B"))
                      (after 10 (withdraw "B"))))
           (after 10 (withdraw "A")))
                   

          (check-liquid))