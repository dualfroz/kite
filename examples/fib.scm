; Naive recursive Fibonacci.
(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))

(display "fib 10 = ")
(display (fib 10))
(newline)
(display "fib 20 = ")
(display (fib 20))
(newline)
(display "fib 25 = ")
(display (fib 25))
(newline)
