; Higher-order list operations.
(display "squares: ")
(display (map (lambda (x) (* x x)) '(1 2 3 4 5)))
(newline)

(display "odds: ")
(display (filter odd? '(1 2 3 4 5 6 7 8)))
(newline)

(display "sum via fold: ")
(display (fold-left + 0 '(1 2 3 4 5 6 7 8 9 10)))
(newline)

(display "zip-add: ")
(display (map + '(1 2 3) '(10 20 30)))
(newline)

(display "for-each: ")
(for-each display '(a b c d))
(newline)

(display "append+reverse: ")
(display (reverse (append '(1 2) '(3 4) '(5 6))))
(newline)
