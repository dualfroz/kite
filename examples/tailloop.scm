(define (count-up n)
  (let loop ((i 0))
    (if (= i n)
        i
        (loop (+ i 1)))))

(display "counted to ")
(display (count-up 100000))
(newline)

(define (even-loop n)
  (if (= n 0) #t (odd-loop (- n 1))))
(define (odd-loop n)
  (if (= n 0) #f (even-loop (- n 1))))

(display "even? 100000 -> ")
(display (even-loop 100000))
(newline)
