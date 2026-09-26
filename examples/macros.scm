(define-syntax swap!
  (syntax-rules ()
    ((_ a b)
     (let ((tmp a))
       (set! a b)
       (set! b tmp)))))

(define x 1)
(define y 2)
(swap! x y)
(display "swap x y -> ")
(display (list x y))
(newline)

(define tmp 10)
(define other 20)
(swap! tmp other)
(display "swap tmp other -> ")
(display (list tmp other))
(newline)

(define-syntax my-list
  (syntax-rules ()
    ((_ e ...) (list e ...))))
(display "my-list -> ")
(display (my-list 1 2 3 4 5))
(newline)

(define-syntax my-or
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e rest ...) (let ((t e)) (if t t (my-or rest ...))))))
(display "my-or -> ")
(display (my-or #f #f 7 8))
(newline)

(when (> 5 3)
  (display "when fired")
  (newline))
(unless (> 3 5)
  (display "unless fired")
  (newline))
