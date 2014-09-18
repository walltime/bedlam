;;
;; Automatically convert input (sources) to jobject
;; and output to scm-object.
;;
(define (datomic/query qry-input . sources)
  (->scm-object
   (let ((sources (jlist->jarray (->jobject sources)))
         (qry (if (string? qry-input)
                  (->jstring qry-input)
                  qry-input)))
     (log-trace "Will execute query: " (->string qry)
                "with sources:" (jarray->string sources))
     (let ((result (j "datomic.Peer.q(qry, sources);" `((sources ,sources)
                                                        (qry ,qry)))))
       (log-trace "=> Query result: " (iasylum-write-string result))
       result))))

;;
;; This is deprecated because it's TOO DANGEROUS when the caller is expecting
;; many results as response. When the list has only one single element or nothing
;; this function simply change its behavior. The only element is returned instead the list,
;; and no result is converted to #f.
;;
;; If the caller is expecting more than one element, it forces the (unaware) caller to
;; treat different and check if the result has one element. A simple example:
;;
;; (map (lambda (e) (display e)) (datomic/smart-query ...)) would fail miserably
;; (and probably silently and late) when the result has only one or no element.
;;
(define (datomic/smart-query qry . sources)
  (log-warn "datomic/smart-query **IS DEPRECATED!** Please use datomic/smart-query-single or datomic/smart-query-multiple instead!")
  (let ((result (apply datomic/query (flatten (list qry sources)))))
    (match result
      [((tresult)) tresult]
      [() #f]
      [anything-else result])))

;;
;; Expect only one result and return this only single element or #f if it is not present.
;; This is useful if you are searching by a specific ID for example.
;;
;; If the query is searching for only one attribute so return the value of this attribute,
;; otherwise a list with the specified attributes in the query.
;;
;; Example: (datomic/smart-query-single "[:find ?v :where ?e :att ?v]" db) will return ?v and
;;          (datomic/smart-query-single "[:find ?e ?v :where ?e :att ?v]" db) will return (list ?e ?v)
;;
(define (datomic/smart-query-single qry . sources)
  (let ((result (apply datomic/query (flatten (list qry sources)))))
    (match result
      [((single-result-only-att)) single-result-only-att]
      [(tuple) tuple]
      [() #f]
      [else (throw (make-error 'datomic/smart-query "Multiple results are not expected here.
Please use datomic/smart-query-multiple instead if multiple results are expected. This is probably a collateral bug: do you have duplicated ids?"))])))

;;
;; Always will return a list of results. Use this when the result can be a set of elements.
;;
(define (datomic/smart-query-multiple qry . sources)
  (apply datomic/query (flatten (list qry sources))))

(define* (datomic/connection uri (should-create? #t) (want-to-know-if-created? #f))
  (let ((did-I-create-it? (if should-create?
                              (->boolean (j "datomic.Peer.createDatabase(uri);" `((uri ,(->jstring uri)))))
                              #f)))
    (let ((connection-result (j "datomic.Peer.connect(uri);" `((uri ,(->jstring uri))))))
      (if want-to-know-if-created?
          (list did-I-create-it? connection-result)
          connection-result))))

(define (datomic/temp-id-native)
  (define-java-classes (<datomic.peer> |datomic.Peer|))
  (define-generic-java-method tempid)
  
  (let ((<datomic.peer>-java-null (java-null <datomic.peer>)))
    ;; spec: (j "temp_id = datomic.Peer.tempid(\":db.part/user\");")
    (tempid <datomic.peer>-java-null partition)))

(define (datomic/transact conn tx)
  (define-generic-java-method transact)
  ;;spec: (j "conn.transact(tx);" `((conn ,conn) (tx ,tx)))
  (transact conn tx))

(define (datomic/transact-async conn tx)
  (define-generic-java-method transact-async |transactAsync|)
  ;;spec:
  ;;(j "conn.transactAsync(tx);" `((conn ,conn) (tx ,tx)))
  ;;(transact conn tx)
  (transact-async conn tx))

(define (datomic/db cn)
  (j "connection.db();" `((connection ,cn))))

(define (datomic/make-latest-db-retriever connection-retriever)
  (lambda ()
    (datomic/db (connection-retriever))))

;;
;; This is deprecated: see datomic/smart-query to more information.
;; Use datomic/make-query-function-with-one-connection-included instead.
;;
(define (datomic/make-with-one-connection-included-query-function connection-retriever)
  (log-warn "datomic/make-with-one-connection-included-query-function **IS DEPRECATED!** Please read the doc for more info. Use datomic/make-query-function-with-one-connection-included instead.")
  (datomic/make-query-function-with-one-connection-included datomic/smart-query connection-retriever))

;;
;; - smart-query-lambda can be datomic/smart-query-multiple or datomic/smart-query-single depending on
;;                      what kind of result are expected.
;;
(define (datomic/make-query-function-with-one-connection-included smart-query-lambda connection-retriever)
  (let ((db-retriever (datomic/make-latest-db-retriever connection-retriever)))
    (cut smart-query-lambda
         <> ; Query.
         (db-retriever) ; Recent db fetched.
         <...> ; Whatever other insanity and/or fixed parameters one may pass.
         )))

;;
;; Differently of smart-query, this DOES NOT convert input (params) to jobject
;; and output to scm-object. You have to send java objects in params.
;;
(define* (datomic/smart-transact conn tx (param-alist '()))
  (let ((final-param-alist (append param-alist `((conn ,conn)))))
    (log-trace "Will execute transact" tx
               "with params:" (iasylum-write-string param-alist))
    (let ((result (clj (string-append "(use '[datomic.api :only [q db] :as d])
                                       @(d/transact conn " tx ")")
                       final-param-alist)))
      (log-trace "=> Transaction result " (iasylum-write-string result))
      result)))

(define (datomic/make-transact-function-with-one-connection-included connection-retriever)
  (cut datomic/smart-transact
       (connection-retriever) ; Current connection
       <>    ; tx
       <...> ; param-alist (or nothing)
       ))

(define (datomic/uuid)
  (j "datomic.Peer.squuid()"))

(define (datomic/extract-time-millis-from-uuid datomic-uuid)
  (j "datomic.Peer.squuidTimeMillis(squuid)"
     `((squuid ,datomic-uuid))))

;;
;; Usage example - test/q does not require a connection or anything besides what
;; is required for the immediate task at hand.
;;
(define (test-query-parametrized connection)
  (let ((test/q (datomic/make-with-one-connection-included-query-function (connection))))
    (test/q "[:find ?eid :in $data ?targetemail  :where [$data ?eid :user-email ?targetemail]]"
            "nietzsche@CaballerosDeLaTristeFigura.net")))    

;; partition-symbol CANNOT include the colon ":" in the symbol/keyword
;; example:
;; (datomic/id 'example)
;;
;; id -1 to -1000000, inclusive, are reserved for
;; user-created tempids. Use other negative number or just don't
;; pass the ID to create a new secure fresh one.
;;
;; partition-symbol is option only to backward compatibility, it SHOULD be defined
;; otherwise an ERROR is logged.
;;
;; note: #db/id[<partition> [<id>]] macro also creates a tempid, it was used before (see history).
;;
(define* (datomic/temp-id (partition-symbol 'db.part/user) (id #f))
  (if (equal? partition-symbol 'db.part/user)
      (log-error "*** Please use it ONLY FOR TESTS! Define a partition explicitly. db.part/user is only for TESTS purposes."))
  (let ((params `((partition ,(symbol->clj-keyword partition-symbol)))))
    (if (not id)
        (clj "(d/tempid partition)" params)
        (clj "(d/tempid partition id)" (append params `((id ,(->jlong id))))))))

(define-nongenerative-struct transaction-set a9c14080-0fb1-11e4-99e0-78ca39b1ca29
  (transaction-string parameters))

;;
;; It is a composition of a tx in string format (starts with empty string)
;; and a list of parameters (starts with empty list).
;; @see datomic/push-transaction! datomic/extract-transaction-and-parameters-pair
;;
(define (datomic/make-empty-transaction-set)
  (make-transaction-set "" '()))

;;
;; Adds a trasanction (in string format) and a list of parameters into a transaction-set.
;; The transaction-string would be a clojure map or list like "{:key value :key2 value2}"
;; or "[:fn p1 p2 ...]".
;;
;; parameters should be something like `((key ,value) (key2 ,value2)) - it is the same
;; input as datomic/smart-transact except by in datomic/smart-transact the tx should be
;; a list of maps or lists.
;;
(define (datomic/push-transaction! transaction-set
                                   transaction-string
                                   parameters)
  (set-transaction-set-transaction-string! transaction-set
                                           (string-append (transaction-set-transaction-string transaction-set)
                                                          transaction-string))
  (set-transaction-set-parameters! transaction-set
                                   (append (transaction-set-parameters transaction-set)
                                           parameters))
  transaction-set)

;;
;; Transform the final string into a list (just add [ ] around) and return
;; the pair formed by tx string + params, so (car (datomic/extract-transaction-and-parameters-pair ...))
;; is the first parameter of datomic/smart-transact and (cdr (datomic/extract-transaction-and-parameters-pair ...))
;; is the second one.
;;
(define (datomic/extract-transaction-and-parameters-pair transaction-set)
  `(,(string-append "[" (transaction-set-transaction-string transaction-set) "]")
    .
    ,(transaction-set-parameters transaction-set)))

;;
;; The input must be a list with lists of two elements being the first one
;; a clojure keyword and the second one the value.
;;
(define (datomic/query-result->alist input)
  (map (lambda (element)
         (cons (clj-keyword->symbol (car element))
               (cadr element)))
       input))

(create-shortcuts (datomic/query -> d/q)
                  (datomic/smart-query -> d/sq) ; <-- deprecated!
                  (datomic/smart-query-single -> d/sq1)
                  (datomic/smart-query-multiple -> d/sqm)
                  (datomic/temp-id -> d/id)
                  (datomic/transact -> d/t)
                  (datomic/db -> d/db)
                  (datomic/smart-transact -> d/st))
