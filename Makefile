# mmix 빌드용 Makefile: 커누스의 MMIXware를 한글 GWEB(Go)로 옮긴 것.
#
#   make            # tangle + go vet + go test
#   make tangle     # 각 .w -> .go (+ _test.go)
#   make doc        # 각 .w의 .pdf 조판 (한글이라 luatex)
#   make twill      # gtwill로 오른쪽 쪽마다 미니 색인을 단 책꼴 .pdf 조판
#   make intro      # 어셈블러와 시뮬레이터의 앞머리 안내서 (*-intro.pdf)
#   make nnix       # NNIX 커널 nnix/nnix.mmo(mmmix -k로 싣는다)와 셸 nnix/sh.mmo
#   make test       # go vet + go test
#   make clean      # 조판 생성물 삭제 (.w 원본은 남김)
#
# 일차 산출물은 .w다. 라이브러리 패키지의 .go는 go get이 되도록 커밋한다.

GTANGLE ?= gtangle
GWEAVE  ?= gweave
GTWILL  ?= gtwill
REFSORT ?= gtwill-refsort
LUATEX  ?= luatex
MUTOOL  ?= mutool
WARNS   := 'Overfull\|Underfull\|Error\|Missing\|Undefined'

# 옮기기가 진행되면서 여기에 디렉터리가 하나씩 늘어난다(라이브러리와 명령 모두).
PKGS := mmixarith abstime mmixal mmotype mmixio mmixsim mmmix nnixfs

# 디렉터리마다 든 .w 파일들. 따로 적지 않으면 디렉터리 이름과 같은 .w 하나다.
WEBS_mmmix := mmixpipe mmixconfig mmixmem mmmix
webs = $(or $(WEBS_$(1)),$(1))
# 코드가 없어 태글하지 않고 조판만 하는 문서들. 꾸러미가 아니므로 루트에 둔다.
DOCONLY := mmixdoc
DOCS := $(foreach p,$(PKGS),$(foreach w,$(call webs,$(p)),$(p)/$(w))) $(addprefix ./,$(DOCONLY))

.PHONY: all tangle doc twill intro nnix test clean $(PKGS) mmixsim-abstime mmmix-abstime
.DEFAULT_GOAL := all

all: tangle test

tangle: $(PKGS)

$(PKGS):
	cd $@ && for w in $(call webs,$@); do $(GTANGLE) $$w.w || exit 1; done

# 원본의 rN에는 컴파일한 시각이 들어간다. 커누스의 Makefile이 abstime.h를 새로 만들듯이,
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

# \MMIX\의처럼 쓰면 \의가 제어 순서가 되니, 조판하기 전에 먼저 걸러 낸다.
MACROCHECK = @perl -CSD -ne 'if (/\\[A-Za-z]+\\\p{Hangul}/) { print "$$ARGV:$$.: $$_"; $$bad=1 } \
	  close ARGV if eof; END { exit $$bad }' *.w */*.w || \
	  (echo '위 줄: \\MMIX\\의 꼴은 \\의가 제어 순서가 된다. \\MMIX의로 쓸 것'; false)

# luatex은 nonstopmode라야 오류가 나도 멈추지 않고 .log에 다 남긴다.
# 조판 경고(Overfull, Underfull, Error, Missing, Undefined)는 0이어야 한다.
doc:
	$(MACROCHECK)
	@for d in $(DOCS); do \
	  p=$${d%/*}; w=$${d#*/}; \
	  (cd $$p && $(GWEAVE) $$w.w && \
	   $(LUATEX) --interaction=nonstopmode $$w.tex >/dev/null; \
	   printf '%s: 조판 경고 %s개\n' $${d#./} \
	     $$(grep -ac $(WARNS) $$w.log)); \
	done

# 원본 MMIXware 책(LNCS 1750)은 CTWILL로 조판했다. gtwill이 그 GWEB판이다:
# gtwill이 .tex와 .aux를 쓰고, TeX 첫 판이 미니 색인 항목을 .mref로 내놓으면
# gtwill-refsort가 그것을 가나다순으로 .smref에 갈무리하고, TeX 둘째 판이 그것을
# 읽어 미니 색인을 짠다. 묵은 .smref는 이제 없는 쪽을 가리키므로 첫 판 전에
# 지운다. 출력 이름이 gweave와 같아서(foo.tex, foo.pdf) make doc과 make twill은
# 서로의 결과를 덮어쓴다. 셸 변수 d와 w에 웹의 경로와 이름을 두고 그 디렉터리에서
# 부른다. luatex이 치명적 오류로 죽으면 로그에는 소문자 `error'만 남아 WARNS에
# 걸리지 않으니, PDF가 생겼는지도 따로 본다. 뜻을 찾지 못한 미니 색인 항목은
# ???로 찍히므로(\uninitialized) 그 수도 센다.
TWILL_TEX = rm -f $$w.smref; \
	  $(LUATEX) --interaction=nonstopmode $$w.tex >/dev/null; \
	  $(REFSORT) < $$w.mref > $$w.smref && \
	  $(LUATEX) --interaction=nonstopmode $$w.tex >/dev/null; \
	  if [ -s $$w.pdf ]; then printf '%s: 조판 경고 %s개, ??? %s개\n' $${d\#./} \
	    `grep -ac $(WARNS) $$w.log` `grep -c '\\uninitialized' $$w.smref`; \
	  else echo "$${d\#./}.pdf: 만들어지지 않았다($$w.log를 볼 것)"; fi

# 웹마다 gtwill 앞에서 twill/bux.py가 그 디렉터리에 system.bux(가져온 꾸러미와
# 형제 웹의 이름)와 웹이름.bux(twill/hints.txt의 힌트)를 쓴다. 무엇을 어떻게
# 고르는지는 그 두 파일에 적혀 있다. 다른 웹의 .aux를 빌려 쓰는데 그 웹이 차례상
# 뒤에 올 수도 있으므로, 먼저 모든 웹에 gtwill을 한 번씩 돌려 .aux를 마련한다.
BUX = python3 $(CURDIR)/twill/bux.py

twill:
	$(MACROCHECK)
	@for d in $(DOCS); do \
	  p=$${d%/*}; w=$${d#*/}; \
	  (cd $$p && $(GTWILL) $$w.w >/dev/null 2>&1) || exit 1; \
	done
	@for d in $(DOCS); do \
	  p=$${d%/*}; w=$${d#*/}; \
	  (cd $$p && $(BUX) $$w $$w.w && $(GTWILL) $$w.w >/dev/null && \
	   { $(TWILL_TEX); }) || exit 1; \
	done

# 커누스의 Makefile은 dvips -pp로 mmixal.dvi의 0--13쪽과 mmix-sim.dvi의 0--8쪽을 떼어
# 사용자 안내서로 삼았다. 번역하면서 쪽이 달라졌으므로 쪽 번호 대신 안내가 끝난 뒤
# 처음 오는 별표 절의 번호를 적고, 그 절이 시작하는 쪽을 .toc에서 읽어 그 앞쪽까지
# 뗀다(별표 절은 늘 새 쪽에서 시작한다). 목차 쪽(N, 마지막 쪽)도 원본처럼 붙인다.
INTRO := mmixal/mmixal:27 mmixsim/mmixsim:8
intro:
	@for e in $(INTRO); do \
	  d=$${e%:*}; s=$${e#*:}; p=$${d%/*}; w=$${d#*/}; \
	  (cd $$p && \
	   { [ $$w.pdf -nt $$w.w ] && [ $$w.toc -nt $$w.w ] || \
	     { $(GWEAVE) $$w.w >/dev/null && \
	       luatex --interaction=nonstopmode $$w.tex >/dev/null; }; } && \
	   n=$$(sed -n "s/^\\\\Tline{0}{$$s}{.*}{\([0-9]*\)}$$/\1/p" $$w.toc) && \
	   [ -n "$$n" ] && \
	   $(MUTOOL) merge -o $$w-intro.pdf $$w.pdf 1-$$((n-1)),N && \
	   echo "$$p/$$w-intro.pdf: 1--$$((n-1))쪽과 목차") || exit 1; \
	done

# 커널의 한글 주석 때문에 줄이 길어 mmixal의 입력 버퍼를 늘린다.
nnix:
	go run ./mmixal -b 250 -o nnix/nnix.mmo nnix/nnix.mms
	go run ./mmixal -b 250 -o nnix/sh.mmo nnix/sh.mms

clean:
	rm -f *.tex *.idx *.scn *.toc *.log *.pdf *.dvi
	rm -f */*.tex */*.idx */*.scn */*.toc */*.log */*.pdf */*.dvi
	rm -f *.aux *.mref *.smref *.bux */*.aux */*.mref */*.smref */*.bux  # make twill
