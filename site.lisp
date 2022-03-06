;;; Site Generator
;;;; ==============

(require "uiop")


;;; Special Modes
;;; -------------

(defvar *log-mode* t
  "Write logs iff true.")

(defvar *main-mode* t
  "Run main function iff true.")


;;; General Definitions
;;; -------------------

(defun make-directory (path)
  "Create a new directory along with its parents."
  (ensure-directories-exist path))

(defun directory-exists-p (path)
  "Check whether the specified directory exists on the filesystem."
  (uiop:directory-exists-p path))

(defun remove-directory (path)
  "Remove the specified directory tree from the file system."
  (uiop:delete-directory-tree (pathname path) :validate t
                                              :if-does-not-exist :ignore))

(defun directory-name (path)
  "Return only the directory portion of path."
  (namestring (make-pathname :directory (pathname-directory path))))

(defun directory-basename (path)
  "Return the parent directory of the specified pathname."
  (let ((name (car (last (pathname-directory path)))))
    (namestring (make-pathname :directory (list :relative name)))))

(defun copy-file (input output)
  "Copy file from a file path to a file/directory path."
  (when (uiop:directory-pathname-p output)
    (setq output (merge-pathnames (file-namestring input) output)))
  (uiop:copy-file input output))

(defun copy-files (input output)
  "Copy files from a wildcard path to a directory path."
  (dolist (pathname (directory input))
    (copy-file pathname output)))

(defun copy-directory (src dst)
  "Copy directory from a directory path to a directory path"
  (make-directory dst)
  (dolist (pathname (uiop:directory-files src))
    (let* ((basename (file-namestring pathname))
           (destpath (merge-pathnames basename dst)))
      (uiop:copy-file pathname destpath)))
  (dolist (pathname (uiop:subdirectories src))
    (let* ((basename (directory-basename pathname))
           (destpath (merge-pathnames basename dst)))
      (make-directory destpath)
      (copy-directory pathname destpath))))

(defun read-file (filename)
  "Read file and close the file."
  (uiop:read-file-string filename))

(defun write-file (filename text)
  "Write text to file and close the file."
  (make-directory filename)
  (with-open-file (f filename :direction :output :if-exists :supersede)
    (write-sequence text f)))

(defun write-log (fmt &rest args)
  "Log message with specified arguments."
  (when *log-mode*
    (apply #'format t fmt args)
    (terpri)))

(defun string-starts-with (prefix string)
  "Test that string starts with the given prefix."
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun string-ends-with (suffix string)
  "Test that the string ends with the given prefix."
  (and (<= (length suffix) (length string))
       (string= suffix string :start2 (- (length string) (length suffix)))))

(defun substring-at (substring string index)
  "Test that substring exists in string at given index."
  (let ((end-index (+ index (length substring))))
    (and (<= end-index (length string))
         (string= substring string :start2 index :end2 end-index))))

(defun string-replace (old new string)
  "Replace old substring in string with new substring."
  (with-output-to-string (s)
    (let* ((next-index 0)
           (match-index))
      (loop
        (setf match-index (search old string :start2 next-index))
        (unless match-index
          (format s "~a" (subseq string next-index))
          (return))
        (format s "~a~a" (subseq string next-index match-index) new)
        (cond ((zerop (length old))
               (when (= next-index (length string))
                 (return))
               (format s "~a" (char string next-index))
               (incf next-index))
              (t
               (setf next-index (+ match-index (length old)))))))))

(defun join-strings (strings)
  "Join strings into a single string."
  (format nil "~{~a~}" strings))

(defmacro add-value (key value alist)
  "Add key-value pair to alist."
  `(push (cons ,key ,value) ,alist))

(defmacro add-list-value (key value alist)
  "Add value to a list corresponding to the key in alist."
  `(progn
     (unless (assoc ,key ,alist :test #'string=)
       (push (cons ,key ()) ,alist))
     (push ,value (cdr (assoc ,key ,alist :test #'string=)))))

(defun get-value (key alist)
  "Given a key, return its value found in the list of parameters."
  (cdr (assoc key alist :test #'string=)))

(defun reverse-list-values-in-alist (alist)
  (loop for entry in alist
        collect (cons (car entry) (reverse (cdr entry)))))


;;; Tool Definitions
;;; ----------------

(defun read-header-line (text next-index)
  "Parse one line of header in text."
  (let* ((start-token "<!-- ")
         (end-token (format nil " -->~%"))
         (sep-token ": ")
         (search-index (+ next-index (length start-token)))
         (end-index)       ; Index of end-token.
         (sep-index)       ; Index of sep-token.
         (key)             ; Text between start-token and end-token.
         (val))            ; Text between sep-token and end-token.
    (when (and (substring-at start-token text next-index)
               (setf end-index (search end-token text :start2 search-index))
               (setf sep-index (search sep-token text :start2 search-index
                                                      :end2 end-index)))
      (setf key (subseq text search-index sep-index))
      (setf val (subseq text (+ sep-index (length sep-token)) end-index))
      (setf next-index (+ end-index (length end-token))))
    (values key val next-index)))

(defun read-headers (text next-index)
  "Parse all headers in text and return (values headers next-index)."
  (let ((key)
        (val)
        (headers))
    (loop
      (setf (values key val next-index)
            (read-header-line text next-index))
      (unless key
        (return))
      (push (cons key val) headers))
    (values headers next-index)))

(defun weekday-name (weekday-index)
  "Given an index, return the corresponding day of week."
  (nth weekday-index '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun")))

(defun month-name (month-number)
  "Given a number, return the corresponding month."
  (nth month-number '("X" "Jan" "Feb" "Mar" "Apr" "May" "Jun"
                      "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")))

(defun decode-weekday-name (year month date)
  "Given a date, return the day of week."
  (let* ((encoded-time (encode-universal-time 0 0 0 date month year))
         (decoded-week (nth-value 6 (decode-universal-time encoded-time)))
         (weekday-name (weekday-name decoded-week)))
    weekday-name))

(defun rss-date (date-string)
  "Convert yyyy-mm-dd[ HH:MM[:SS[ TZ]]] to RFC-2822 date."
  (let ((len (length date-string))
        (year (parse-integer (subseq date-string 0 4)))
        (month (parse-integer (subseq date-string 5 7)))
        (date (parse-integer (subseq date-string 8 10)))
        (hour 0)
        (minute 0)
        (second 0)
        (tz "+0000")
        (month-name)
        (weekday-name))
    (when (>= len 16)
      (setf hour (parse-integer (subseq date-string 11 13)))
      (setf minute (parse-integer (subseq date-string 14 16))))
    (when (>= len 19)
      (setf second (parse-integer (subseq date-string 17 19))))
    (when (>= len 21)
      (setf tz (subseq date-string 20)))
    (setf month-name (month-name month))
    (setf weekday-name (decode-weekday-name year month date))
    (format nil "~a, ~2,'0d ~a ~4,'0d ~2,'0d:~2,'0d:~2,'0d ~a"
            weekday-name date month-name year hour minute second tz)))

(defun simple-date (date-string)
  "Convert yyyy-mm-dd[ HH:MM[:SS[ TZ]]] to a human-readable date."
  (let ((len (length date-string))
        (year (parse-integer (subseq date-string 0 4)))
        (month (parse-integer (subseq date-string 5 7)))
        (date (parse-integer (subseq date-string 8 10)))
        (hour 0)
        (minute 0)
        (tz "GMT")
        (month-name)
        (result))
    (setf month-name (month-name month))
    (setf result (format nil "~2,'0d ~a ~4,'0d" date month-name year))
    (when (>= len 16)
      (setf hour (parse-integer (subseq date-string 11 13)))
      (setf minute (parse-integer (subseq date-string 14 16)))
      (setf result (format nil "~a ~2,'0d:~2,'0d" result hour minute)))
    (when (>= len 21)
      (setf tz (subseq date-string 20))
      (when (string= tz "+0000")
        (setf tz "GMT"))
      (setf result (format nil "~a ~a" result tz)))
    result))

(defun date-slug (filename)
  "Parse filename to extract date and slug."
  (let* ((basename (file-namestring filename))
         (dot-index (search "." basename))
         (slug (subseq basename 0 dot-index))
         (date))
    (when (and (>= (length basename) 11)
               (every #'digit-char-p (loop for i in '(0 1 2 3 5 6 8 9)
                                           collect (char basename i))))
      (setf date (subseq basename 0 10))
      (setf slug (subseq basename 11 dot-index)))
    (values date slug)))

(defun render (template params)
  "Render parameter tokens in template with their values from params."
  (let* ((start-token "{{ ")
         (end-token " }}")
         (next-index 0)     ; Next place to start searching "{{".
         (start-index)      ; Starting of "{{ ".
         (end-index)        ; Starting of " }}".
         (text)             ; Text between next-index and start-index.
         (result "")        ; Rendered result.
         (key)              ; Parameter key between "{{" and "}}".
         (val))             ; Parameter value found in params.
    (loop
      ;; Look for start-token and extract static text before it.
      (setf start-index (search start-token template :start2 next-index))
      (unless start-index
        (return))
      (setf text (subseq template next-index start-index))
      ;; Extract parameter name between start-token and end-token.
      (incf start-index (length start-token))
      (setf end-index (search end-token template :start2 start-index))
      (setf key (subseq template start-index end-index))
      ;; Replace parameter name with value if present. Otherwise leave
      ;; the parameter name along with start and end tokens intact.
      (setf val (get-value key params))
      (if val
          (setf result (format nil "~a~a~a" result text val))
          (setf result (format nil "~a~a{{ ~a }}" result text key)))
      (setf next-index (+ end-index (length end-token))))
    ;; Extract static text after the last parameter token.
    (setf text (subseq template next-index))
    (setf result (format nil "~a~a" result text))
    result))

(defun extra-markup (text)
  "Add extra markup to the page to create heading anchor links."
  (with-output-to-string (s)
    (let* ((begin-tag-index)
           (end-id-index)
           (end-tag-index)
           (next-index 0))
      (loop
        (setf begin-tag-index (search "<h" text :start2 next-index))
        (unless begin-tag-index
          (return))
        (cond ((and (digit-char-p (char text (+ begin-tag-index 2)))
                    (substring-at "id=\"" text (+ begin-tag-index 4)))

               (setf end-id-index (search "\"" text :start2 (+ begin-tag-index 8)))
               (setf end-tag-index (search "</h" text :start2 (+ end-id-index 2)))
               (format s "~a" (subseq text next-index end-tag-index))
               (format s "~a"
                       (format nil "<a href=\"#~a\"></a></h"
                               (subseq text (+ begin-tag-index 8) end-id-index)))
               (setf next-index (+ end-tag-index 3)))
              (t
               (format s "~a" (subseq text next-index (+ begin-tag-index 2)))
               (setf next-index (+ begin-tag-index 2)))))
      (format s (subseq text next-index)))))


;;; Posts
;;; -----

(defun read-post (filename)
  "Parse post file."
  (let ((text (read-file filename))
        (post)
        (date))
    (multiple-value-bind (date slug) (date-slug filename)
      (add-value "date" date post)
      (add-value "slug" slug post))
    (multiple-value-bind (headers next-index) (read-headers text 0)
      (setf post (append headers post))
      (add-value "body" (subseq text next-index) post))
    (setf date (get-value "date" post))
    (when date
      (add-value "rss-date" (rss-date date) post)
      (add-value "simple-date" (simple-date date) post))
    post))

(defmacro add-canonical-url (dst-path params)
  "Given an output file path, set a canonical URL for that file."
  `(let ((neat-url ,dst-path)
         (site-url (get-value "site-url" ,params)))
     (setf neat-url (string-replace "_site/" "" neat-url))
     (setf neat-url (string-replace "index.html" "" neat-url))
     (setf neat-url (format nil "~a~a" site-url neat-url))
     (add-value "canonical-url" neat-url ,params)))

(defun make-posts (src dst layout &optional params)
  "Generate pages from post files."
  (let ((post)           ; Parameters read from post.
        (page)           ; Parameters for current page.
        (posts)          ; List of post parameters.
        (dst-path))      ; Destination path to write rendered page to.
    (dolist (src-path (directory src))
      ;; Read post and merge its parameters with call parameters.
      (setf post (read-post src-path))
      (setf page (append post params post))
      (push post posts)
      ;; Determine destination path and URL.
      (setf dst-path (render dst page))
      (add-canonical-url dst-path page)
      ;; Render the post using the layout.
      (write-log "Rendering ~a => ~a ..." (get-value "slug" page) dst-path)
      (write-file dst-path (extra-markup (render layout page))))
    ;; Sort the posts in chronological order.
    (sort posts #'(lambda (x y) (string< (get-value "date" x)
                                         (get-value "date" y))))))

(defun make-post-list (posts dst list-layout item-layout
                       &optional params)
  "Generate list page for a list of posts."
  (let ((count (length posts))
        (rendered-posts)
        (dst-path))
    ;; Render each post.
    (dolist (post posts)
      (setf post (append post params))
      (push (render item-layout post) rendered-posts))
    ;; Add list parameters.
    (add-value "title" "Blog" params)
    (add-value "body" (join-strings rendered-posts) params)
    (add-value "count" count params)
    (add-value "post-label" (if (= count 1) "post" "posts") params)
    ;; Determine destination path and URL.
    (setf dst-path (render dst params))
    (add-canonical-url dst-path params)
    ;; Render the post using list layout.
    (write-log "Rendering list => ~a ..." dst-path)
    (write-file dst-path (extra-markup (render list-layout params)))))


;;; Site
;;; ----

(defun make-blog (page-layout &optional params)
  "Generate blog."
  (let* ((post-layout (read-file "layout/blog/post.html"))
         (list-layout (read-file "layout/blog/list.html"))
         (item-layout (read-file "layout/blog/item.html"))
         (feed-xml (read-file "layout/blog/feed.xml"))
         (item-xml (read-file "layout/blog/item.xml"))
         (posts))
    ;; Combine layouts to form final layouts.
    (setf post-layout (render page-layout (list (cons "body" post-layout))))
    (setf list-layout (render page-layout (list (cons "body" list-layout))))
    ;; Add parameters for blog rendering.
    (add-value "root" "../" params)
    ;; Read and render all posts.
    (setf posts (make-posts "content/blog/*.html" "_site/blog/{{ slug }}.html"
                            post-layout params))
    ;; Create blog list page.
    (make-post-list posts "_site/blog/index.html" list-layout item-layout params)
    ;; Create RSS feed.
    (make-post-list posts "_site/blog/rss.xml" feed-xml item-xml params)
    posts))

;;; Club.
(defun make-club (page-layout &optional params)
  "Generate club."
)

;;; Meeting Logs.

(defun format-meet-date (date)
  (string-replace " " "&nbsp;" (subseq (rss-date date) 0 22)))

(defun format-meet-topic (title topic)
  (format nil "~a: ~a" title topic))

(defun future-p (meet)
  (minusp (getf meet :members)))

(defun meets-html (meets)
  (format nil "~{~a~%~}"
          (loop for index from 1 to (length meets)
                for meet in meets
                collect (format nil "    <tr id=\"~a\" class=\"~a\">"
                                index
                                (if (future-p meet) "future" "past"))
                collect (format nil "      <td>~a<a href=\"#~a\"></a></td>"
                                index index)
                collect (format nil "      <td>~a&nbsp;UTC</td>"
                                (format-meet-date (getf meet :date)))
                collect (format nil "      <td>~a&nbsp;mins</td>"
                                (getf meet :duration))
                collect (format nil "      <td>~a</td>"
                                (if (future-p meet) "-" (getf meet :members)))
                collect (format nil "      <td>~a</td>"
                                (format-meet-topic (getf meet :title)
                                                   (getf meet :topic)))
                collect "    </tr>")))

(defun slugs-html (slugs)
  (format nil "~{~a~%~}"
          (loop for (slug track) in slugs
                collect (format nil "<li><a href=\"~a.html\">~a</a></li>"
                                slug track))))

(defun select-meets (slug meets)
  (remove-if-not (lambda (x) (string= (getf x :slug) slug)) meets))

(defun make-meeting-log (meets dst meets-layout params)
  (let* ((past-meets (loop for m in meets when (not (future-p m)) collect m))
         (past-count (length past-meets))
         (future-meets (loop for m in meets when (future-p m) collect m))
         (future-info-css (format nil ".future-info {display: ~a}"
                                  (if future-meets "inline" "none")))
         (minutes (reduce #'+ (loop for m in past-meets collect (getf m :duration))))
         (members (reduce #'+ (loop for m in past-meets collect (getf m :members))))
         (dst-path))
    (add-value "head" (format nil "<style>body {max-width: 60em}~%~a</style>"
                              future-info-css) params)
    (add-value "meet-rows" (meets-html meets) params)
    (add-value "total-count" past-count params)
    (add-value "meeting-label" (if (= past-count 1) "meeting" "meetings") params)
    (add-value "total-minutes" minutes params)
    (add-value "total-hours" (format nil "~,1f" (/ minutes 60)) params)
    ;; Avoid division-by-zero with a fake count.
    (when (zerop past-count)
      (setf past-count 1))
    (add-value "average-minutes" (format nil "~,1f" (/ minutes past-count)) params)
    (add-value "average-members" (format nil "~,1f" (/ members past-count)) params)
    ;; Determine destination path and URL.
    (setf dst-path (render dst params))
    (add-canonical-url dst-path params)
    (write-log "Rendering meets => ~a ..." dst-path)
    (write-file dst-path (extra-markup (render meets-layout params)))))

(defun make-meets (page-layout params)
  (let ((meets (read-from-string (read-file "meets.lisp")))
        (slugs (read-from-string (read-file "slugs.lisp")))
        (index-layout (read-file "layout/meets/index.html"))
        (track-layout (read-file "layout/meets/track.html"))
        (index-dst "_site/meets/index.html")
        (track-dst "_site/meets/{{ slug }}.html"))
    (setf index-layout (render page-layout (list (cons "body" index-layout))))
    (setf track-layout (render page-layout (list (cons "body" track-layout))))
    (setf meets (sort meets (lambda (x y)
                              (string< (getf x :date) (getf y :date)))))
    ;; Add meeting log for entire club.
    (add-value "root" "../" params)
    (add-value "title" "Meeting Log" params)
    (add-value "slug-items" (slugs-html slugs) params)
    (make-meeting-log meets index-dst index-layout params)
    ;; Add meeting log for each track.
    (loop for (slug track) in slugs
          with track-meets
          do (setf track-meets (select-meets slug meets))
             (add-value "slug" slug params)
             (add-value "track" track params)
             (add-value "title" (format nil "~a Meeting Log" track) params)
             (make-meeting-log track-meets track-dst track-layout params))))

(defun make-redirects (page-layout params)
  "Add redirect pages for pages that have moved to new locations."
  (let ((redirects '(("_site/blog/the-100th-meeting.html" .
                      "our-100th-meeting.html")
                     ("_site/blog/our-trip-to-the-prime-number-theorem.html" .
                      "our-trip-to-prime-number-theorem.html")))
        (redirect-layout (read-file "layout/redirect.html"))
        (meta-template "<meta http-equiv=\"refresh\" content=\"0; url={{ target }}\">"))
    (add-value "root" "../" params)
    (add-value "title" "This Page Has Moved" params)
    (setf redirect-layout (render page-layout (list (cons "body" redirect-layout))))
    (dolist (entry redirects)
      (let ((dst-path (car entry))
            (target (cdr entry)))
        (add-value "target" target params)
        (add-value "head" (render meta-template params) params)
        (write-log "Rendering redirect => ~a ..." dst-path)
        (write-file dst-path (render redirect-layout params))))))

(defun main ()
  ;; Create a new site directory from scratch.
  (remove-directory "_site/")
  (copy-directory "static/" "_site/")
  (let* ((params (list (cons "base-path" "")
                       (cons "subtitle" " - Offbeat Computation Club")
                       (cons "author" "Susam Pal")
                       (cons "site-url" "https://offbeat.cc/")
                       (cons "current-year"
                             (nth-value 5 (get-decoded-time)))
                       (cons "head" "")
                       (cons "index" "")))
         (page-layout (read-file "layout/page.html"))

         (slugs (read-from-string (read-file "slugs.lisp"))))
    ;; Top-level pages.
    (add-value "root" "" params)
    (make-posts "content/*.html" "_site/{{ slug }}.html" page-layout params)
    (add-value "root" "../" params)
    (make-posts "content/club/*.html" "_site/{{ slug }}/index.html"
                page-layout params)
    ;; Create blog.
    (make-blog page-layout params)
    ;; Create redirects.
    (make-redirects page-layout params)
    ;; Generate meeting log.
    (make-meets page-layout params))
  t)

(when *main-mode*
  (main))
