(in-package :gradual)

(defclass gradual-type ()
  ())

(defclass union-type (gradual-type)
  ((types :initarg :types
          :accessor types
          :initform (error "Provide the types")
          :type list)))

(defmethod print-object ((union-type union-type) stream)
  (format stream "(OR ~{~A~^ ~})" (types union-type)))

(defclass intersection-type (gradual-type)
  ((types :initarg :types
          :accessor types
          :initform (error "Provide the types")
          :type list)))

(defclass type-var (gradual-type)
  ((name :initarg :name
         :accessor name
         :type symbol
         :initform (error "Provide the type-var name"))))

(defclass values-type (gradual-type args-type)
  ((args :initarg :args :accessor args :initform nil)))

(defclass function-type (gradual-type args-type)
  ((return-type :initarg :return-type
                :initform (error "Provide the return type")
                :accessor return-type)))

(defclass member-type (gradual-type)
  ((types :initarg :types
          :accessor types
          :initform (error "Provide the types")
          :type list)))

(defmethod print-object ((type intersection-type) stream)
  (format stream "(AND ~{~A~^ ~})" (types type)))


(defun equidimensional (a)
  (or (< (array-rank a) 2)
      (apply #'= (array-dimensions a))))

(deftype square-matrix (&optional type size)
  `(and (array ,type (,size ,size))
        (satisfies equidimensional)))

(defun plistp (list)
  (and (listp list)
       (evenp (length list))
       (loop
          for result = t then (and result (keywordp k))
          for k in list by #'cddr
          finally (return result))))

(deftype plist ()
  `(and cons
        (satisfies plistp)))

;;(subtypep 'plist 'cons)

(defun alistp (list)
  (and (listp list)
       (reduce (lambda (b elem)
                 (and b (consp elem)))
               list :initial-value t)))

(deftype alist ()
  `(and cons
        (satisfies alistp)))

;; Objects equality. See mw-equiv docs

(defmethod mw-equiv:object-frozenp ((object gradual-type))
  t)

(defmethod mw-equiv:object-frozenp ((object cons))
  t)


;; Function types

;; TODO:

;; Look at sb-kernel::values-specifier-type
;; Example: (sb-kernel::values-specifier-type 'number)
;; Actually, lots of function types stuff here is a reimplementation of
;; sb-kernel::values-specifier-type.
;; For instance, evaluate this:
;; (sb-kernel::values-specifier-type '(function (string &optional boolean &key (x number)) string))
;; (sb-kernel::values-specifier-type '(function (integer &rest string) (values boolean integer)))

;; Ideas?::
;; Consider (optional) checked-exceptions declarations and (optional) dynamic variable (implicit parameters) usage declarations in function types
;; Like:
;; (defun open-file (f)
;;     (declare (signals 'file-not-found-error))
;;   ...)
;;
;; (defun scoped-function ()
;;   (declare (uses *var*))
;;   ...)

(defclass args-type ()
  ((required-args-types
    :initarg :required-args-types
    :initform nil
    :accessor required-args-types)
   (optional-args-types
    :initarg :optional-args-types
    :initform nil
    :accessor optional-args-types)
   (keyword-args-types
    :initarg :keyword-args-types
    :initform nil
    :accessor keyword-args-types)
   (rest-arg-type
    :initarg :rest-arg-type
    :initform nil
    :accessor rest-arg-type)))

(defun print-args-type (struct stream)
  (format stream "~A~A~A~A"
          (format nil "~{~a~^ ~}" (required-args-types struct))
          (or (aand (optional-args-types struct)
                    (format nil " &optional ~{~a~^ ~}" it))
              "")
          (or (aand (keyword-args-types struct)
                    (with-output-to-string (s)
                      (format s " &key ")
                      (loop for (var . type) in it
                         do (format s "(~A ~A)" var type))))
              "")
          (or (aand (rest-arg-type struct)
                    (format nil " &rest ~A" it))
              "")))

(defmethod mw-equiv:object-constituents ((type (eql 'function-type)))
  (list #'required-args-types
        #'optional-args-types
        #'keyword-args-types
        #'rest-arg-type))

(defun make-function-type (&rest args)
  (apply #'make-instance 'function-type args))

(defmethod print-object ((function-type function-type) stream)
  (format stream "(FUNCTION (")
  (print-args-type function-type stream)
  (format stream ") ~A)" (return-type function-type)))

(defun function-type-spec (function-type)
  `(FUNCTION (
              ,@(required-args-types function-type)
                ,@(awhen (optional-args-types function-type)
                    (cons '&optional it))
                ,@(awhen (keyword-args-types function-type)
                    (cons '&key
                          (mapcar (lambda (var-and-type)
                                    (list (car var-and-type)
                                          (cdr var-and-type)))
                                  it)))
                ,@(awhen (rest-arg-type function-type)
                    (list '&rest
                          it))
                )
             ,(return-type function-type)))

(defgeneric types-consistentp (t1 t2)
  (:documentation "Gradual typing type consistency relation"))

(defmethod types-consistentp (t1 t2)
  )

(defgeneric gradual-subtypep (t1 t2))

(defmethod gradual-subtypep (t1 t2)
  (if (object= t2 t)
      t
      (subtypep t1 t2)))

(defmethod gradual-subtypep (t1 (t2 cons))
  (if (object= (first t2) 'values)
      (gradual-subtypep t1 (second t2))
      (call-next-method)))

(defmethod gradual-subtypep ((t1 cons) t2)
  (if (object= (first t1) 'values)
      (gradual-subtypep (second t1) t2)
      (call-next-method)))

;; (defmethod gradual-subtypep ((t1 function-type) t2)
;;   (gradual-subtypep (function-type-spec t1) t2))

;; (defmethod gradual-subtypep (t1 (t2 function-type))
;;   (gradual-subtypep t1 (function-type-spec t2)))

(defmethod gradual-subtypep (t1 (t2 union-type))
  (some (lambda (type)
          (gradual-subtypep t1 type))
        (types t2)))

(defmethod gradual-subtypep ((t1 union-type) t2)
  nil)

(defmethod gradual-subtypep (t1 (t2 values-type))
  (gradual-subtypep t1 (first (required-args-types t2))))

(defmethod gradual-subtypep ((t1 values-type) t2)
  (gradual-subtypep (first (required-args-types t1)) t2))

;; Types parsing

(defmethod print-object ((type-var type-var) stream)
  (format stream "<~A>" (name type-var)))

(defmethod print-object ((type values-type) stream)
  (format stream "(VALUES ")
  (print-args-type type stream)
  (format stream ")"))

(defmethod print-object ((type member-type) stream)
  (format stream "(MEMBER ~{~A~^ ~})" (types type)))

(defun parse-type (spec)
  (cond
    ((symbolp spec)
     (let ((spec-string (symbol-name spec)))
       (if (and (equalp (char spec-string 0) #\<)
                (equalp (char spec-string (1- (length spec-string)))
                        #\>))
           ;; It is a type variable
           (make-instance 'type-var
                          :name (intern
                                 (subseq spec-string 1
                                         (1- (length spec-string)))))
           ;; else, just use the symbol
           spec)))
    ((consp spec)
     (cond
       ((equalp (first spec) 'or)
        (make-instance 'union-type :types (mapcar #'parse-type (rest spec))))
       ((equalp (first spec) 'and)
        (make-instance 'intersection-type :types (mapcar #'parse-type (rest spec))))
       ((equalp (first spec) 'values)
        (parse-values-type spec))
       ((equalp (first spec) 'function)
        (parse-function-type spec))
       (t ;; just return the list
        spec)))
    (t (error "Error parsing the type ~A" spec))))

(defun parse-function-type (spec)
  (when (not (and (consp spec)
                  (equalp (first spec) 'function)
                  (equalp (length spec) 3)))
    (simple-program-error "Invalid function type spec ~S" spec))
  (destructuring-bind (function args return-type) spec
    (declare (ignore function))
    (if (listp args)
        (multiple-value-bind (required-args-types
                              optional-args-types
                              rest-arg-type
                              keyword-args-types)
            (parse-types-lambda-list args)
          (make-function-type :required-args-types (mapcar #'parse-type required-args-types)
                              :optional-args-types (mapcar #'parse-type optional-args-types)
                              :keyword-args-types (mapcar #'parse-type keyword-args-types)
                              :rest-arg-type (parse-type rest-arg-type)
                              :return-type (parse-type return-type)))
                                        ;else
        (if (equalp args '*)
            (make-function-type :rest-arg-type t
                                :return-type (parse-type return-type))
            ;; else
            (simple-program-error "Invalid function type spec ~S" spec)))))

(defmacro fun (args-types return-type)
  `(parse-type '(function ,args-types ,return-type)))

(defun parse-values-type (spec)
  (multiple-value-bind (required-args-types
                        optional-args-types
                        rest-arg-type
                        keyword-args-types)
      (parse-types-lambda-list (rest spec))
    (make-instance 'values-type
                   :required-args-types (mapcar #'parse-type required-args-types)
                   :optional-args-types (mapcar #'parse-type optional-args-types)
                   :rest-arg-type (parse-type rest-arg-type)
                   :keyword-args-types (mapcar #'parse-type keyword-args-types))))
