SHELLS=		bash ksh zsh
BUILD_TARGETS=	tweet

prefix=		/usr/local
exec_prefix=	$(prefix)
bindir=		$(exec_prefix)/bin

default: build

clean:
	rm -rf *.tmp $(BUILD_TARGETS)

build: $(BUILD_TARGETS)

install: $(BUILD_TARGETS)
	mkdir -p $(DESTDIR)$(bindir)
	cp $(BUILD_TARGETS) $(DESTDIR)$(bindir)/

tweet: tweet.sh
	@rm -f $@.tmp
	@for shell in $(SHELLS); do \
	  printf 'Check if %s exists... ' "$$shell"; \
	  if shell="`which $$shell 2>/dev/null`"; then \
	    echo "$$shell"; \
	    echo "#!$$shell" >$@.tmp; \
	    break; \
	  fi; \
	  echo 'not found'; \
	done
	@[ -f $@.tmp ] || { echo 'Suitable shell not found'; exit 1; }
	@sed '1d' $< >>$@.tmp
	@chmod +x $@.tmp
	@mv $@.tmp $@

