(define text "the quick brown fox jumps over the lazy dog
the dog sleeps and the fox runs")

(define (read-word port)
  (let loop ((chars '()))
    (let ((c (peek-char port)))
      (cond ((eof-object? c)
             (if (null? chars) c (list->string (reverse chars))))
            ((char-alphabetic? c)
             (read-char port)
             (loop (cons c chars)))
            ((null? chars)
             (read-char port)
             (loop chars))
            (else (list->string (reverse chars)))))))

(define counts (make-hash-table))

(let ((port (open-input-string text)))
  (do ((word (read-word port) (read-word port)))
      ((eof-object? word))
    (hash-table-update!/default counts word (lambda (n) (+ n 1)) 0)))

(define (insert-sorted entry sorted)
  (cond ((null? sorted) (list entry))
        ((> (cdr entry) (cdar sorted)) (cons entry sorted))
        (else (cons (car sorted) (insert-sorted entry (cdr sorted))))))

(define ranking (fold-right insert-sorted '() (hash-table->alist counts)))

(display "distinct words: ")
(display (hash-table-count counts))
(newline)

(define report (open-output-string))
(for-each
  (lambda (entry)
    (write-string (car entry) report)
    (write-char #\= report)
    (write (cdr entry) report)
    (write-char #\space report))
  (list (car ranking) (cadr ranking) (caddr ranking)))
(display "top three: ")
(display (get-output-string report))
(newline)

(define lengths (make-vector 8 0))
(hash-table-walk counts
  (lambda (word n)
    (let ((len (string-length word)))
      (vector-set! lengths len (+ n (vector-ref lengths len))))))
(display "words by length: ")
(display lengths)
(newline)
