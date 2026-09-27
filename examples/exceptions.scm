(define (safe-divide a b)
  (guard (e ((error-object? e)
             (display "error: ")
             (display (error-object-message e))
             (newline)
             #f))
    (if (= b 0)
        (error "division by zero" a)
        (/ a b))))

(display "10 / 4 = ")
(display (safe-divide 10 4))
(newline)
(safe-divide 1 0)

(define (parse-age text)
  (let ((n (string->number text)))
    (cond ((not n) (raise (list 'not-a-number text)))
          ((negative? n) (raise (list 'negative n)))
          (else n))))

(for-each
  (lambda (input)
    (display input)
    (display " -> ")
    (display (guard (e ((and (pair? e) (eq? (car e) 'not-a-number)) "rejected: not a number")
                       ((and (pair? e) (eq? (car e) 'negative)) "rejected: negative"))
               (parse-age input)))
    (newline))
  '("42" "abc" "-3"))

(define log '())
(define (note entry) (set! log (cons entry log)))

(guard (e (#t (note (list 'caught e))))
  (dynamic-wind
    (lambda () (note 'open))
    (lambda () (note 'work) (raise 'disk-full) (note 'unreachable))
    (lambda () (note 'close))))
(display "dynamic-wind trail: ")
(display (reverse log))
(newline)

(display "continuable: ")
(display (with-exception-handler
           (lambda (missing) 0)
           (lambda () (+ 1 (raise-continuable 'missing-value) 2))))
(newline)
