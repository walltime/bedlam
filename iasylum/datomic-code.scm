;;
;; Automatically convert input (sources) to jobject
;; and output to scm-object.
;;
(define (datomic/query qry . sources)
  (->scm-object
   (let ((sources (jlist->jarray (->jobject sources)))
         (qry (if (string? qry) (->jstring qry) qry)))
     (log-trace "Will execute query" (->string qry)
                "with sources:" (jarray->string sources))
     (j "datomic.Peer.q(qry, sources);" `((sources ,sources)
                                          (qry ,qry))))))

(define (datomic/smart-query qry . sources)
  (let ((result (apply datomic/query (flatten (list qry sources)))))
    (match result
      [((tresult)) tresult]
      [() #f]
      [anything-else result])))

(define* (datomic/connection uri (should-create? #t) (want-to-know-if-created? #f))
  (let ((did-I-create-it? (if should-create?
                              (->boolean (j "datomic.Peer.createDatabase(uri);" `((uri ,(->jstring uri)))))
                              #f)))
    (let ((connection-result (j "datomic.Peer.connect(uri);" `((uri ,(->jstring uri))))))
      (if want-to-know-if-created?
          (list did-I-create-it? connection-result)
          connection-result))))

(define (datomic/temp-id)
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

(define (datomic/make-with-one-connection-included-query-function connection-retriever)
  (let ((db-retriever (datomic/make-latest-db-retriever connection-retriever)))
    (cut datomic/smart-query
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
               "with params:" param-alist)
    (clj (string-append "(use '[datomic.api :only [q db] :as d])
                         @(d/transact conn " tx ")")
         final-param-alist)))

(define (datomic/make-with-one-connection-included-transact-function connection-retriever)
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

;; Usage example - test/q does not require a connection or anything besides what
;; is required for the immediate task at hand.
(define (test-query-parametrized connection)
  (let ((test/q (datomic/make-with-one-connection-included-query-function (connection))))
    (test/q "[:find ?eid :in $data ?targetemail  :where [$data ?eid :user-email ?targetemail]]"
            "nietzsche@CaballerosDeLaTristeFigura.net")))    

;; partition is a symbol and can be ':walltime for example
;; remember note: #db/id is a datomic macro
(define* (datomic/id partition-symbol (id #f))
  (clj (string-append* "#db/id [" partition-symbol
                       (if id (string-append* " " id) "") "]")))

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

; shortcuts
(define d/q datomic/query)
(define d/sq datomic/smart-query)
(define d/id datomic/temp-id)
(define d/t datomic/transact)
(define d/db datomic/db)
(define d/st datomic/smart-transact)
