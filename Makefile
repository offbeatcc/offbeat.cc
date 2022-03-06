site:
	@echo Generating main website ...
	rm -rf _site/ && mkdir -p _site/
	# Build website.
	sbcl --script site.lisp
	# Clone dependencies.
	git -C _site/ clone -b v4.0.12 --depth 1 https://github.com/markedjs/marked.git
	git -C _site/ clone -b 3.2.0 --depth 1 https://github.com/mathjax/mathjax.git
	git -C _site/ clone -b 1.2.0 --depth 1 https://github.com/susam/texme.git
	git -C _site/ clone -b 0.5.2 --depth 1 https://github.com/susam/muboard.git
	rm -rf _site/marked/.git/
	rm -rf _site/mathjax/.git/
	rm -rf _site/texme/.git/
	rm -rf _site/muboard/.git/
	@echo Done; echo

all: site iant cses

loop:
	while true; do make site; sleep 5; done

localize:
	mkdir -p "$$(dirname "$(OUT)")"
	sed -e 's|https:.*chtml.js|$(ROOT)mathjax/es5/tex-mml-chtml.js|' \
	    -e 's|<script.*muboard.*></script>|<script>window.muboard = { texmeURL: "$(ROOT)texme/texme.js" }; window.texme = { markdownURL: "$(ROOT)marked/marked.min.js", MathJaxURL: "$(ROOT)mathjax/es5/tex-mml-chtml.js"}</script><script src="$(ROOT)muboard/muboard.js"></script>|' \
	    "$(IN)" > "$(OUT)"

iant: site
	@echo Generating IANT website ...
	rm -rf iant/
	git clone --depth 1 https://github.com/offbeatcc/iant.git
	for f in iant/boards/*.*; do \
	    make localize ROOT=../../ IN="$$f" OUT="_site/$$f"; done
	rm -rf iant/
	@echo Done; echo

cses: site
	@echo Generating CSES website ...
	rm -rf cses/
	git clone --depth 1 https://github.com/offbeatcc/cses.git
	for f in cses/boards/*.*; do \
	    make localize ROOT=../../ IN="$$f" OUT="_site/$$f"; done
	for f in cses/boards/book/*.*; do \
	    make localize ROOT=../../../ IN="$$f" OUT="_site/$$f"; done
	for f in cses/boards/problems/*.*; do \
	    make localize ROOT=../../../ IN="$$f" OUT="_site/$$f"; done
	rm -rf cses/
	@echo Done; echo

live:
	pwd | grep live$$ || false
	git init
	git config user.name susam
	git config user.email susam@susam.net
	# Prepare live branch.
	git checkout -b live
	git add .
	git commit -m "Publish live ($$(date -u +"%Y-%m-%d %H:%M:%S"))"
	git log
	# Publish main website to https://offbeat.cc/.
	git remote add origin https://github.com/offbeatcc/offbeat.cc.git
	git push -f origin live
	# Publish mirror to https://offbeatcc.github.io/.
	git rm CNAME
	git commit -m "Remove CNAME file from mirror"
	git remote add mirror https://github.com/offbeatcc/offbeatcc.github.io.git
	git push -f mirror live

pub: all
	git push
	rm -rf /tmp/live
	mv _site /tmp/live
	REPO_DIR="$$PWD"; cd /tmp/live && make -f "$$REPO_DIR/Makefile" live

# Checks
test:
	sbcl --noinform --eval "(defvar *quit* t)" --script test.lisp

checks:
	# Ensure punctuation goes inside inline-math.
	! grep -IErn '\\)[^ ]' content | grep -vE '\\)(th|-|</a>|\)|:)'
	! grep -IErn '(th|-|</h[1-6]>|:) \\)' content
	# Ensure all page headings are hyperlinks to themselves.
	! grep -IErn '<h1' content | grep -vE '<h1><a href="./">'
	# Ensure all section headings are hyperlinks to themselves.
	! grep -IErn '<h[2-6]' content | grep -vE '<h[2-6] id=".*"><a'
	@echo Done; echo

FORCE:
