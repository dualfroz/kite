(define-syntax stream-cons
  (syntax-rules ()
    ((_ head tail) (cons head (delay tail)))))

(define (stream-head s) (car s))
(define (stream-tail s) (force (cdr s)))

(define (stream-take s n)
  (if (= n 0)
      '()
      (cons (stream-head s) (stream-take (stream-tail s) (- n 1)))))

(define (stream-filter keep? s)
  (if (keep? (stream-head s))
      (stream-cons (stream-head s) (stream-filter keep? (stream-tail s)))
      (stream-filter keep? (stream-tail s))))

(define (integers-from n) (stream-cons n (integers-from (+ n 1))))

(define (sieve s)
  (stream-cons (stream-head s)
               (sieve (stream-filter (lambda (n) (not (= 0 (modulo n (stream-head s)))))
                                     (stream-tail s)))))

(display "primes: ")
(display (stream-take (sieve (integers-from 2)) 10))
(newline)

(define (fibs a b) (stream-cons a (fibs b (+ a b))))
(display "fib 100 = ")
(display (list-ref (stream-take (fibs 0 1) 101) 100))
(newline)

(define evaluations 0)
(define answer (delay (begin (set! evaluations (+ evaluations 1)) 42)))
(force answer)
(force answer)
(display "forced twice, evaluated ")
(display evaluations)
(display " time")
(newline)

(define (countdown n)
  (delay-force (if (= n 0) (delay 'liftoff) (countdown (- n 1)))))
(display "delay-force chain of 100000: ")
(display (force (countdown 100000)))
(newline)
