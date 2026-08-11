; Deep tail recursion: counting to a large number must not overflow the stack.
(define (count-up n)
  (let loop ((i 0))
    (if (= i n)
        i
        (loop (+ i 1)))))

(display "counted to ")
(display (count-up 1000000))
(newline)

; Mutual tail recursion should also stay in constant stack space.
(define (even-loop n)
  (if (= n 0) #t (odd-loop (- n 1))))
(define (odd-loop n)
  (if (= n 0) #f (even-loop (- n 1))))

(display "even? 1000000 -> ")
(display (even-loop 1000000))
(newline)
