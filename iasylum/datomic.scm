(require-extension (lib iasylum/jcode))

(module iasylum/datomic
  (datomic/query d/q
   datomic/smart-query d/sq
   datomic/smart-transact d/st
   datomic/connection
   datomic/temp-id d/id
   datomic/temp-id-native
   datomic/transact d/t
   datomic/transact-async
   datomic/db d/db
   datomic/make-latest-db-retriever   
   datomic/make-query-function-with-one-connection-included
   datomic/make-transact-function-with-one-connection-included
   datomic/uuid
   datomic/extract-time-millis-from-uuid
   datomic/make-empty-transaction-set
   datomic/push-transaction!
   datomic/extract-transaction-and-parameters-pair
   datomic/query-result->alist

   ; deprecated:
   datomic/make-with-one-connection-included-query-function
   )

  (include "datomic-code.scm")
)
