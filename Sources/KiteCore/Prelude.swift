let preludeSource = """
(define-syntax when
  (syntax-rules ()
    ((_ test body ...) (if test (begin body ...) #f))))

(define-syntax unless
  (syntax-rules ()
    ((_ test body ...) (if test #f (begin body ...)))))

(define-syntax receive
  (syntax-rules ()
    ((_ formals expression body ...)
     (call-with-values (lambda () expression) (lambda formals body ...)))))

(define-syntax guard
  (syntax-rules ()
    ((_ (var clause ...) body ...)
     ((call/cc
        (lambda (guard-k)
          (with-exception-handler
            (lambda (condition)
              ((call/cc
                 (lambda (handler-k)
                   (guard-k
                     (lambda ()
                       (let ((var condition))
                         (cond clause ...
                               (else (handler-k (lambda () (raise-continuable condition))))))))))))
            (lambda ()
              (call-with-values
                (lambda () body ...)
                (lambda results (guard-k (lambda () (apply values results)))))))))))))

(define %reverse reverse)
(define %apply apply)

(define-syntax case-lambda
  (syntax-rules ()
    ((_ (formals body ...) ...)
     (%case-lambda (list (lambda formals body ...) ...)))))

(define (%case-lambda clauses)
  (lambda args
    (let ((count (length args)))
      (let loop ((remaining clauses))
        (cond ((null? remaining) (error "case-lambda: no clause accepts this many arguments" count))
              ((%accepts? (car remaining) count) (%apply (car remaining) args))
              (else (loop (cdr remaining))))))))

(define %parameter-set (list 'parameter-set))
(define %parameter-convert (list 'parameter-convert))

(define (make-parameter value . converter)
  (let* ((convert (if (pair? converter) (car converter) (lambda (x) x)))
         (current (convert value)))
    (lambda args
      (cond ((null? args) current)
            ((eq? (car args) %parameter-set) (set! current (car (cdr args))))
            ((eq? (car args) %parameter-convert) (convert (car (cdr args))))
            (else (error "parameter: expected no arguments" args))))))

(define-syntax parameterize
  (syntax-rules ()
    ((_ () body ...) (let () body ...))
    ((_ ((param value) ...) body ...)
     (%parameterize (list param ...) (list value ...) (lambda () body ...)))))

(define (%parameterize params new-values body)
  (let ((pending (%map (lambda (p v) (p %parameter-convert v)) params new-values)))
    (define (swap!)
      (set! pending
            (%map (lambda (p v) (let ((old (p))) (p %parameter-set v) old)) params pending)))
    (dynamic-wind swap! body swap!)))

(define (%any-null? lists)
  (if (pair? lists)
      (if (pair? (car lists)) (%any-null? (cdr lists)) #t)
      #f))

(define (%cars lists)
  (if (pair? lists) (cons (car (car lists)) (%cars (cdr lists))) '()))

(define (%cdrs lists)
  (if (pair? lists) (cons (cdr (car lists)) (%cdrs (cdr lists))) '()))

(define (map proc first . rest)
  (if (null? rest)
      (let loop ((xs first) (acc '()))
        (if (pair? xs)
            (loop (cdr xs) (cons (proc (car xs)) acc))
            (%reverse acc)))
      (let loop ((lists (cons first rest)) (acc '()))
        (if (%any-null? lists)
            (%reverse acc)
            (loop (%cdrs lists) (cons (%apply proc (%cars lists)) acc))))))

(define %map map)

(define (for-each proc first . rest)
  (if (null? rest)
      (let loop ((xs first))
        (if (pair? xs)
            (begin (proc (car xs)) (loop (cdr xs)))))
      (let loop ((lists (cons first rest)))
        (if (not (%any-null? lists))
            (begin (%apply proc (%cars lists)) (loop (%cdrs lists)))))))

(define %for-each for-each)

(define (filter keep? xs)
  (let loop ((xs xs) (acc '()))
    (cond ((not (pair? xs)) (%reverse acc))
          ((keep? (car xs)) (loop (cdr xs) (cons (car xs) acc)))
          (else (loop (cdr xs) acc)))))

(define (remove drop? xs)
  (filter (lambda (x) (not (drop? x))) xs))

(define (fold-left proc init first . rest)
  (if (null? rest)
      (let loop ((acc init) (xs first))
        (if (pair? xs) (loop (proc acc (car xs)) (cdr xs)) acc))
      (let loop ((acc init) (lists (cons first rest)))
        (if (%any-null? lists)
            acc
            (loop (%apply proc acc (%cars lists)) (%cdrs lists))))))

(define (fold-right proc init xs)
  (let loop ((acc init) (pending (%reverse xs)))
    (if (pair? pending) (loop (proc (car pending) acc) (cdr pending)) acc)))

(define (reduce proc initial xs)
  (if (pair? xs)
      (fold-left (lambda (acc x) (proc x acc)) (car xs) (cdr xs))
      initial))

(define (vector-map proc first . rest)
  (list->vector (%apply %map proc (vector->list first) (%map vector->list rest))))

(define (vector-for-each proc first . rest)
  (%apply %for-each proc (vector->list first) (%map vector->list rest)))

(define (string-map proc first . rest)
  (list->string (%apply %map proc (string->list first) (%map string->list rest))))

(define (string-for-each proc first . rest)
  (%apply %for-each proc (string->list first) (%map string->list rest)))

(define (force promise)
  (if (promise? promise) (%force promise) promise))

(define (%force promise)
  (if (%promise-done? promise)
      (%promise-payload promise)
      (let ((value ((%promise-payload promise))))
        (cond ((%promise-done? promise) (%promise-payload promise))
              ((and (%promise-lazy? promise) (promise? value))
               (%promise-adopt! promise value)
               (%force promise))
              (else (%promise-resolve! promise value) value)))))

(define (hash-table-ref table key . default-thunk)
  (cond ((hash-table-contains? table key) (hash-table-ref/default table key #f))
        ((pair? default-thunk) ((car default-thunk)))
        (else (error "hash-table-ref: key not found" key))))

(define (hash-table-update! table key proc . default-thunk)
  (hash-table-set! table key (proc (%apply hash-table-ref table key default-thunk))))

(define (hash-table-update!/default table key proc default)
  (hash-table-set! table key (proc (hash-table-ref/default table key default))))

(define (hash-table-walk table proc)
  (%for-each (lambda (entry) (proc (car entry) (cdr entry))) (hash-table->alist table)))

(define (call-with-output-string proc)
  (let ((port (open-output-string)))
    (proc port)
    (get-output-string port)))

(define (call-with-port port proc)
  (call-with-values
    (lambda () (proc port))
    (lambda results (close-port port) (%apply values results))))
"""
