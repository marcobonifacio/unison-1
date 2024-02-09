; This library implements various syntactic constructs and functions
; that are used in the compilation of unison (intermediate) source to
; scheme. The intent is to provide for writing scheme definitions that
; more directly match the source, so that the compiler doesn't need to
; emit all the code necessary to fix up the difference itself.
;
; Probably the best example of this is the define-unison macro, which
; looks similar to scheme's define, but the function being defined is
; allowed to be under/over applied similar to a unison function. It
; has an 'arity' at which computation happens, but the function
; automatically handles being applied to fewer or more arguments than
; that arity appropriately.
#!racket/base
(provide
  bytevector
  control
  define-unison
  handle
  name
  data
  data-case

  expand-sandbox
  check-sandbox
  set-sandbox

  (struct-out unison-data)
  (struct-out unison-termlink)
  (struct-out unison-termlink-con)
  (struct-out unison-termlink-builtin)
  (struct-out unison-termlink-derived)
  (struct-out unison-typelink)
  (struct-out unison-typelink-builtin)
  (struct-out unison-typelink-derived)
  declare-function-link
  declare-code

  request
  request-case
  sum
  sum-case
  unison-force
  string->chunked-string
  empty-chunked-list

  identity

  describe-value
  decode-value

  top-exn-handler

  reference->termlink
  reference->typelink
  referent->termlink
  typelink->reference
  termlink->referent

  unison-tuple->list
  list->unison-tuple
  unison-tuple
  unison-seq)

(require
  (for-syntax
    racket/set
    (only-in racket partition))
  (rename-in
    (except-in racket false true unit any)
    [make-continuation-prompt-tag make-prompt])
  ; (for (only (compatibility mlist) mlist->list list->mlist) expand)
  ; (for (only (racket base) quasisyntax/loc) expand)
  ; (for-syntax (only-in unison/core syntax->list))
  (only-in racket/control prompt0-at control0-at)
  unison/core
  unison/data
  unison/sandbox
  unison/data-info
  unison/crypto
  (only-in unison/chunked-seq
           string->chunked-string
           chunked-string->string
           vector->chunked-list
           empty-chunked-list))

; Computes a symbol for automatically generated partial application
; cases, based on number of arguments applied. The partial
; application of `f` is (locally) named `f-partial-N`
; (meta define (partial-symbol name m)
;   (fun-sym (symbol->string name) "partial" (number->string m)))

; As above, but takes a syntactic object representing the arguments
; rather than their count.
; (define (partial-name name us)
;   (datum->syntax name (syntax->datum name)))

(define-syntax with-name
  (syntax-rules ()
    [(with-name name e) (let ([name e]) name)]))

; function definition with slow/fast path. Slow path allows for
; under/overapplication. Fast path is exact application.
;
; The intent is for the scheme compiler to be able to recognize and
; optimize static, fast path calls itself, while still supporting
; unison-like automatic partial application and such.
(define-syntax (define-unison x)
  (define (fast-path-symbol name)
    (string->symbol
      (string-append
        (symbol->string name)
        ":fast-path")))

  (define (fast-path-name name)
    (datum->syntax name (fast-path-symbol (syntax->datum name))))

  ; Helper function. Turns a list of syntax objects into a
  ; list-syntax object.
  (define (list->syntax l) #`(#,@l))
  ; Builds partial application cases for unison functions.
  ; It seems most efficient to have a case for each posible
  ; under-application.
  (define (build-partials name formals)
    (let rec ([us formals] [acc '()])
      (syntax-case us ()
        [() (list->syntax (cons #`[() #,name] acc))]
        [(a ... z)
         (rec #'(a ...)
              (cons
                #`[(a ... z)
                   (with-name
                     #,(datum->syntax name (syntax->datum name))
                     (partial-app #,name a ... z))]
                acc))])))

  ; Given an overall function name, a fast path name, and a list of
  ; arguments, builds the case-lambda body of a unison function that
  ; enables applying to arbitrary numbers of arguments.
  (define (func-cases name name:fast args)
    (syntax-case args ()
      [() (quasisyntax/loc x
            (case-lambda
              [() (#,name:fast)]
              [r (apply (#,name:fast) r)]))]
      [(a ... z)
       (quasisyntax/loc x
         (case-lambda
           #,@(build-partials name #'(a ...))
           [(a ... z) (#,name:fast a ... z)]
           [(a ... z . r) (apply (#,name:fast a ... z) r)]))]))

  (syntax-case x ()
    [(define-unison (name a ...) e ...)
     (let ([fname (fast-path-name #'name)])
       (with-syntax ([name:fast fname]
                     [fast (syntax/loc x (lambda (a ...) e ...))]
                     [slow (func-cases #'name fname #'(a ...))])
         (syntax/loc x
           (define-values (name:fast name) (values fast slow)))))]))

; call-by-name bindings
(define-syntax name
  (lambda (stx)
    (syntax-case stx ()
      ((name ([v (f . args)] ...) body ...)
       (with-syntax ([(lam ...)
                      (map (lambda (body)
                             (quasisyntax/loc stx
                               (lambda r #,body)))
                           (syntax->list #'[(apply f (append (list . args) r)) ...]))])
         #`(let ([v lam] ...)
             body ...))))))

; Wrapper that more closely matches `handle` constructs
;
; Note: this uses the prompt _twice_ to achieve the sort of dynamic
; scoping we want. First we push an outer delimiter, then install
; the continuation marks corresponding to the handled abilities
; (which tells which propt to use for that ability and which
; functions to use for each request). Then we re-delimit by the same
; prompt.
;
; If we just used one delimiter, we'd have a problem. If we pushed
; the marks _after_ the delimiter, then the continuation captured
; when handling would contain those marks, and would effectively
; retain the handler for requests within the continuation. If the
; marks were outside the prompt, we'd be in a similar situation,
; except where the handler would be automatically handling requests
; within its own implementation (although, in both these cases we'd
; get control errors, because we would be using the _function_ part
; of the handler without the necessary delimiters existing on the
; continuation). Both of these situations are wrong for _shallow_
; handlers.
;
; Instead, what we need to be able to do is capture the continuation
; _up to_ the marks, then _discard_ the marks, and this is what the
; multiple delimiters accomplish. There might be more efficient ways
; to accomplish this with some specialized mark functions, but I'm
; uncertain of what pitfalls there are with regard to that (whehter
; they work might depend on exact frame structure of the
; metacontinuation).
(define-syntax handle
  (syntax-rules ()
    [(handle [r ...] h e ...)
     (let ([p (make-prompt)])
       (prompt0-at p
         (let ([v (let-marks (list r ...) (cons p h)
                    (prompt0-at p e ...))])
           (h (make-pure v)))))]))

; wrapper that more closely matches ability requests
(define-syntax request
  (syntax-rules ()
    [(request r t . args)
     (let ([rq (make-request r t (list . args))])
       (let ([current-mark (ref-mark r)])
          (if (equal? #f current-mark)
            (error "Unhandled top-level effect! " (list r t . args))
            ((cdr current-mark) rq))))]))

; See the explanation of `handle` for a more thorough understanding
; of why this is doing two control operations.
;
; In-unison 'control' corresponds to a (shallow) handler jump, so we
; need to capture the continuation _and_ discard some dynamic scope
; information. The capture is accomplished via the first
; control0-at, while the second does the discard, based on the
; convention used in `handle`.
(define-syntax control
  (syntax-rules ()
    [(control r k e ...)
     (let ([p (car (ref-mark r))])
       (control0-at p k (control0-at p _k e ...)))]))

; forces something that is expected to be a thunk, defined with
; e.g. `name` above. In some cases, we might have a normal value,
; so just do nothing in that case.
(define (unison-force x)
  (if (procedure? x) (x) x))

; If #t, causes sum-case and data-case to insert else cases if
; they don't have one. The inserted case will report the covered
; cases and which tag was being matched.
(define-for-syntax debug-cases #t)

(define-for-syntax (tag? s)
  (and (syntax? s) (fixnum? (syntax->datum s))))

(define-for-syntax (tags? s)
  (andmap tag? (syntax->list s)))

(define-for-syntax (identifiers? s)
  (andmap identifier? (syntax->list s)))

(define-for-syntax (process-cases mac-name stx scstx tgstx flstx cs)
  (define (raiser msg sub)
    (raise-syntax-error #f msg stx sub))

  (define (raise-else sub)
    (raiser
      (string-append "else clause must be final in " mac-name)
      sub))

  (define (raise-tags sub)
    (raiser
      (string-append "non-tags used in " mac-name " branch")
      sub))

  (define (raise-vars sub)
    (raiser
      (string-append "non-variables used in " mac-name " binding")
      sub))

  (define (has-else? c)
    (syntax-case c (else)
      [(else . x) #t]
      [_ #f]))

  (define (syntax->tags ts)
    (list->set (map syntax->datum (syntax->list ts))))

  (define (process-case head tail)
    (with-syntax ([fields flstx] [scrut scstx])
      (syntax-case head (else)
        [(else e ...)
         (syntax-case tail ()
           [() (values (set) head)] ; case is already in the right form
           [_ (raise-else head)])]
        [((t ...) () e ...)
         (cond
           [(not (tags? #'(t ...))) (raise-tags head)]
           [else
             (values
               (syntax->tags #'(t ...))
               #'((t ...) e ...))])]
        [(t () e ...)
         (cond
           [(not (tag? #'t)) (raise-tags head)]
           [else
             (values
               (set (syntax->datum #'t))
               #'((t) e ...))])]
        [((t ...) (v ...) e ...)
         (cond
           [(not (tags? #'(t ...))) (raise-tags head)]
           [(not (identifiers? #'(v ...))) (raise-vars head)]
           [else
             (values
               (syntax->tags #'(t ...))
               #'((t ...)
                  (let-values
                    ([(v ...) (apply values (fields scrut))])
                    e ...)))])]
        [(t (v ...) e ...)
         (cond
           [(not (tag? #'t)) (raise-tags head)]
           [(not (identifiers? #'(v ...))) (raise-vars head)]
           [else
             (values
               (set (syntax->datum #'t))
               #'((t)
                  (let-values
                    ([(v ...) (apply values (fields scrut))])
                    e ...)))])]
        [((t ...) v e ...)
         (cond
           [(not (tags? #'(t ...))) (raise-tags head)]
           [(not (identifier? #'v)) (raise-vars head)]
           [else
             (values
               (syntax->tags #'(t ...))
               #'((t ...) (let ([v (fields scrut)]) e ...)))])]
        [(t v e ...)
         (cond
           [(not (tag? #'t)) (raise-tags head)]
           [(not (identifier? #'v)) (raise-vars head)]
           [else
             (values
               (set (syntax->datum #'t))
               #'((t) (let ([v (fields scrut)]) e ...)))])])))

  (define (build-else sts)
    (with-syntax ([tag tgstx])
      #`(else
          (let* ([ts (list #,@sts)]
                 [tg (tag #,scstx)]
                 [fmst "~a: non-exhaustive match:\n~a\n~a"]
                 [cst (format "      tag: ~v" tg)]
                 [tst (format "  covered: ~v" ts)]
                 [msg (format fmst #,mac-name cst tst)])
            (raise msg)))))

  (let rec ([el (not debug-cases)]
            [tags (list->set '())]
            [acc '()]
            [cur cs])
    (syntax-case cur ()
      [()
       (let ([acc (if el acc (cons (build-else (set->list tags)) acc))])
         (reverse acc))]
      [(head . tail)
       (let-values ([(ts pc) (process-case #'head #'tail)])
         (rec
           (or el (has-else? #'head))
           (set-union tags ts)
           (cons pc acc)
           #'tail))])))

(define-syntax sum-case
  (lambda (stx)
    (syntax-case stx ()
      [(sum-case scrut c ...)
       (with-syntax ([(tc ...)
                      (process-cases
                        "sum-case"
                        stx
                        #'scrut
                        #'unison-sum-tag
                        #'unison-sum-fields
                        #'(c ...))])
         #'(case (unison-sum-tag scrut) tc ...))])))

(define-syntax data-case
  (lambda (stx)
    (syntax-case stx ()
      [(data-case scrut c ...)
       (with-syntax ([(tc ...)
                      (process-cases
                        "data-case"
                        stx
                        #'scrut
                        #'unison-data-tag
                        #'unison-data-fields
                        #'(c ...))])
         (syntax/loc stx
           (case (unison-data-tag scrut) tc ...)))])))

(define-syntax request-case
  (lambda (stx)
    (define (pure-case? c)
      (syntax-case c (pure)
        [(pure . xs) #t]
        [_ #f]))

    (define (mk-pure scrut ps)
      (if (null? ps)
        #`(pure-val #,scrut)
        (syntax-case (car ps) (pure)
          [(pure (v) e ...)
           #`(let ([v (unison-pure-val #,scrut)])
               e ...)]
          [(pure vs e ...)
           (raise-syntax-error
             #f
             "pure cases receive exactly one variable"
             (car ps)
             #'vs)])))

    (define (mk-req scrut-stx)
      (lambda (stx)
        (syntax-case stx ()
          [(t vs e ...)
           (with-syntax ([scrut scrut-stx])
             #'((t) (let-values
                      ([vs (apply values (unison-request-fields scrut))])
                      e ...)))])))

    (define (mk-abil scrut-stx)
      (lambda (stx)
        (syntax-case stx ()
          [(t sc ...)
           (let ([sub (mk-req scrut-stx)])
             (with-syntax
               ([(sc ...) (map sub (syntax->list #'(sc ...)))]
                [scrut scrut-stx])
               #'((t) (case (unison-request-tag scrut) sc ...))))])))

    (syntax-case stx ()
      [(request-case scrut c ...)
       (let-values
         ([(ps as) (partition pure-case? (syntax->list #'(c ...)))])
         (if (> 1 (length ps))
           (raise-syntax-error
             #f
             "multiple pure cases in request-case"
             stx)
           (with-syntax
             ([pc (mk-pure #'scrut ps)]
              [(ac ...) (map (mk-abil #'scrut) as)])

             #'(cond
                 [(unison-pure? scrut) pc]
                 [else (case (unison-request-ability scrut) ac ...)]))))])))

; (define (describe-list n l)
;   (let rec ([pre "["] [post "[]"] [cur l])
;     (cond
;       [(null? cur) post]
;       [else
;         (let* ([sx (describe-value-depth (- n 1) (car cur))]
;                [sxs (rec ", " "]" (cdr cur))])
;           (string-append pre sx sxs))])))
;
; (define (describe-ref r)
;   (cond
;     [(symbol? r) (symbol->string r)]
;     [(data? r)
;      (data-case r
;        [0 (s) (string-append "##" s)]
;        [1 (i)
;          (data-case i
;            [0 (bs ix)
;              (let* ([bd (bytevector->base32-string b32h bs)]
;                     [td (istring-take 5 bd)]
;                     [sx (if (>= 0 ix)
;                           ""
;                           (string-append "." (number->string ix)))])
;                (string-append "#" td sx))])])]))
;
; (define (describe-bytes bs)
;   (let* ([s (bytevector->base32-string b32h bs)]
;          [l (string-length s)]
;          [sfx (if (<= l 10) "" "...")])
;     (string-append "32x" (istring-take 10 s) sfx)))
;
; (define (describe-value-depth n x) 
;   (if (< n 0) "..."
;     (cond
;       [(sum? x)
;        (let ([tt (number->string (sum-tag x))]
;              [vs (describe-list n (sum-fields x))])
;          (string-append "Sum " tt " " vs))]
;       [(data? x)
;        (let ([tt (number->string (data-tag x))]
;              [rt (describe-ref (data-ref x))]
;              [vs (describe-list n (data-fields x))])
;          (string-append "Data " rt " " tt " " vs))]
;       [(list? x) (describe-list n x)]
;       [(number? x) (number->string x)]
;       [(string? x) (string-append "\"" x "\"")]
;       [(bytevector? x) (describe-bytes x)]
;       [(procedure? x) (format "~a" x)]
;       [else
;         (format "describe-value: unimplemented case: ~a " x)])))
;
; (define (describe-value x) (describe-value-depth 20 x))
;
(define (decode-value x) '())

(define (reference->termlink rf)
  (match rf
    [(unison-data _ t (list nm))
     #:when (= t unison-reference-builtin:tag)
     (unison-termlink-builtin (chunked-string->string nm))]
    [(unison-data _ t (list id))
     #:when (= t unison-reference-derived:tag)
     (match id
       [(unison-data _ t (list rf i))
        #:when (= t unison-id-id:tag)
        (unison-termlink-derived rf i)])]))

(define (referent->termlink rn)
  (match rn
    [(unison-data _ t (list rf i))
     #:when (= t unison-referent-con:tag)
     (unison-termlink-con (reference->typelink rf) i)]
    [(unison-data _ t (list rf))
     #:when (= t unison-referent-def:tag)
     (reference->termlink rf)]))

(define (reference->typelink rf)
  (match rf
    [(unison-data _ t (list nm))
     #:when (= t unison-reference-builtin:tag)
     (unison-typelink-builtin (chunked-string->string nm))]
    [(unison-data _ t (list id))
     #:when (= t unison-reference-derived:tag)
     (match id
       [(unison-data _ t (list rf i))
        #:when (= t unison-id-id:tag)
        (unison-typelink-derived rf i)])]))

(define (typelink->reference tl)
  (match tl
    [(unison-typelink-builtin nm)
     (unison-reference-builtin (string->chunked-string nm))]
    [(unison-typelink-derived hs i)
     (unison-reference-derived
       (unison-id-id hs i))]))

(define (termlink->referent tl)
  (match tl
    [(unison-termlink-builtin nm)
     (unison-referent-def
       (unison-reference-builtin nm))]
    [(unison-termlink-derived rf i)
     (unison-referent-def
       (unison-reference-derived
         (unison-id-id rf i)))]
    [(unison-termlink-con tyl i)
     (unison-referent-con
       (typelink->reference tyl)
       i)]))

(define (list->unison-tuple l)
  (foldr unison-tuple-pair unison-unit-unit l))

(define (unison-tuple . l) (list->unison-tuple l))

(define (unison-seq . l)
  (vector->chunked-list (list->vector l)))

; Top level exception handler, moved from being generated in unison.
; The in-unison definition was effectively just literal scheme code
; represented as a unison data type, with some names generated from
; codebase data.
;
; Note: the ref-4n0fgs00 stuff is probably not ultimately correct, but
; is how things work for now.
(define (top-exn-handler rq)
  (request-case rq
    [pure (x)
      (match x
        [(unison-data r 0 (list))
         (eq? r unison-unit:link)
         (display "")]
        [else
          (display (describe-value x))])]
    [ref-4n0fgs00
      [0 (f)
       (control 'ref-4n0fgs00 k
         (let ([disp (describe-value f)])
           (raise (make-exn:bug "builtin.bug" disp))))]]))
