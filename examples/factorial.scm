(define (factorial n)
  (let loop ((i n) (acc 1))
    (if (= i 0)
        acc
        (loop (- i 1) (* acc i)))))

(display "10! = ")
(display (factorial 10))
(newline)
(display "20! = ")
(display (factorial 20))
(newline)
