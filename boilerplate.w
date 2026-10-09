% 이 파일은 MMIXware를 한글 GWEB(Go)로 옮긴 모든 .w의 첫머리에 @i로 들어간다.
% 원본 MMIXware (c) 1999 Donald E. Knuth. 이 번역은 MMIXware 꾸러미의 일부가 아니다.

\def\botofcontents{\vskip 0pt plus 1filll
    \ninepoint\baselineskip12pt
    \noindent 원본 \copyright\ 1999 Donald E. Knuth
    \bigskip\noindent
    크누스의 원본 파일들은 아무것도 바꾸지 않는다는 조건으로 자유롭게 복사하고
    배포할 수 있다. 크누스는 모든 사용자에게 {\tt MMIX}ware 파일들이 세상 어디서나
    똑같이, ``오염되지 않은'' 채로 유지되도록 도와 달라고 부탁한다. 고친 파일은
    {\tt MMIX}ware 꾸러미에 있는 기존 파일과 다른 새 이름을 달고, 그 꾸러미의
    일부가 아님을 분명히 밝힐 때에만 허용된다.
    \bigskip\noindent
    이 문서는 그 조건에 따라 원본을 한글과 \GO/로 옮기면서 새 이름을 붙인 것이며,
    {\tt MMIX}ware 꾸러미의 일부가 아니다. 손대지 않은 원본은 크누스의
    누리집 {\tt https://www-cs-faculty.stanford.edu/\char`\~knuth/mmix.html}에서
    받을 수 있다. 번역에 잘못이 있다면 그것은 옮긴이의
    탓이지 크누스의 탓이 아니다.}

\def\MMIX{\.{MMIX}}
\def\MMIXAL{\.{MMIXAL}}
\def\Hex#1{\hbox{$^{\scriptscriptstyle\#}$\tt#1}} % 크누스의 십육진 상수 표기
\def\dts{\mathinner{\ldotp\ldotp}}
\def\<#1>{\hbox{$\langle\,$#1$\,\rangle$}}\let\is=\longrightarrow
\def\bull{\smallbreak\textindent{$\bullet$}}

% gweave가 형으로 알아보지 못하는 이름들. 표준 꾸러미와 이 저장소의 다른 꾸러미,
% 같은 꾸러미의 다른 .w에서 정의한 형이다.
@s atomic.Bool int
@s big.Int int
@s bufio.Reader int
@s bufio.Writer int
@s bytes.Buffer int
@s io.Reader int
@s io.Writer int
@s os.File int
@s os.Signal int
@s rand.Rand int
@s strings.Builder int
@s testing.T int
@s time.Location int
@s mmixarith.Octa int
@s mmixarith.Tetra int
@s mmixarith.Round int
@s mmixio.IO int
@s mmixio.Simulator int
@s Octa int
@s Tetra int
@s exitSignal int
@s machine int
@s coroutine int
@s control int
@s fetch int
@s specnode int
@s funcUnit int
@s cache int
@s cacheset int
@s cacheblock int
@s chunknode int
@s writeNode int
@s replacePolicy int
@s cfile int
@s hio int
@s blk int
@s FILE int
@s do int
@s while int
