# mmix 빌드용 Makefile: 크누스의 MMIXware를 한글 GWEB(Go)로 옮긴 것.
#
#   make            # tangle + go vet + go test
#   make tangle     # 각 .w -> .go (+ _test.go)
#   make doc        # 각 .w의 .pdf 조판 (한글이라 luatex)
#   make test       # go vet + go test
#   make clean      # 조판 생성물 삭제 (.w 원본은 남김)
#
# 일차 산출물은 .w다. 라이브러리 패키지의 .go는 go get이 되도록 커밋한다.

GTANGLE ?= gtangle
GWEAVE  ?= gweave

# 옮기기가 진행되면서 여기에 디렉터리가 하나씩 늘어난다(라이브러리와 명령 모두).
PKGS := mmixarith abstime mmixal mmotype mmixio mmixsim mmmix

# 디렉터리마다 든 .w 파일들. 따로 적지 않으면 디렉터리 이름과 같은 .w 하나다.
WEBS_mmmix := mmixpipe mmixconfig mmixmem mmmix
webs = $(or $(WEBS_$(1)),$(1))
# 코드가 없어 태글하지 않고 조판만 하는 문서들.
DOCONLY := mmixdoc
DOCS := $(foreach p,$(PKGS) $(DOCONLY),$(foreach w,$(call webs,$(p)),$(p)/$(w)))

.PHONY: all tangle doc test clean $(PKGS) mmixsim-abstime mmmix-abstime
.DEFAULT_GOAL := all

all: tangle test

tangle: $(PKGS)

$(PKGS):
	cd $@ && for w in $(call webs,$@); do $(GTANGLE) $$w.w || exit 1; done

# 원본의 rN에는 컴파일한 시각이 들어간다. 크누스의 Makefile이 abstime.h를 새로 만들듯이,
# 시뮬레이터를 tangle할 때마다 abstime.go를 새로 만든다.
mmixsim: mmixsim-abstime
mmixsim-abstime: abstime
	go run ./abstime main > mmixsim/abstime.go
mmmix: mmmix-abstime
mmmix-abstime: abstime
	go run ./abstime main > mmmix/abstime.go

test:
	go vet ./...
	go test ./...

# luatex은 nonstopmode라야 오류가 나도 멈추지 않고 .log에 다 남긴다.
# 조판 경고(Overfull, Underfull, Error, Missing, Undefined)는 0이어야 한다.
doc:
	@perl -CSD -ne 'if (/\\[A-Za-z]+\\\p{Hangul}/) { print "$$ARGV:$$.: $$_"; $$bad=1 } \
	  close ARGV if eof; END { exit $$bad }' */*.w || \
	  (echo '위 줄: \\MMIX\\의 꼴은 \\의가 제어 순서가 된다. \\MMIX의로 쓸 것'; false)
	@for d in $(DOCS); do \
	  p=$${d%/*}; w=$${d#*/}; \
	  (cd $$p && $(GWEAVE) $$w.w && \
	   luatex --interaction=nonstopmode $$w.tex >/dev/null; \
	   printf '%s: 조판 경고 %s개\n' $$d \
	     $$(grep -ac 'Overfull\|Underfull\|Error\|Missing\|Undefined' $$w.log)); \
	done

clean:
	rm -f */*.tex */*.idx */*.scn */*.toc */*.log */*.pdf */*.dvi
