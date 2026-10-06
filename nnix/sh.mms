% sh: NNIX의 작은 셸.
%
% 프롬프트를 찍고 표준 입력에서 한 줄을 읽어 빈칸으로 낱말을 나눈다. 첫 낱말이 exit이면
% 끝내고, 아니면 Fork한 뒤 자식은 그 낱말들을 argv로 삼아 Exec하고 부모는 Wait한다.
% Exec은 디스크에서 첫 낱말의 이름(없으면 그 이름에 .mmo를 붙인 것)을 찾는다.
%
%   mmixal -b 250 sh.mms && mmixsim -Dsh.mmb sh
%   nnixfs mkfs disk.img && nnixfs put disk.img hello.mmo
%   mmmix -knnix.mmo -ddisk.img plain.mmconfig sh.mmb
%
% mmmix의 표준 입력은 끝나도 EOF를 알리지 않으므로(옛 줄을 되풀이한다) exit으로 끝낸다.

Fork    IS    11
Exec    IS    12
Wait    IS    13

        LOC   Data_Segment
        GREG  @
Prompt  BYTE  "nnix$ ",0
NoExec  BYTE  "sh: cannot execute ",0
NewLine BYTE  #a,0
ExitW   BYTE  "exit",0
        LOC   (@+7)&-8
ArgL    OCTA  Line,256          Fgets(StdIn,Line,256)
        GREG  @
Argv    LOC   @+8*33            낱말의 포인터들과 끝의 0
        GREG  @
Line    LOC   @+256

p       IS    $2                줄을 훑는 자리
a       IS    $3                Argv
n       IS    $4                낱말의 수
c       IS    $5
t       IS    $6
s       IS    $7
e       IS    $8
        LOC   #100
Main    LDA   $255,Prompt
        TRAP  0,Fputs,StdOut
        LDA   $255,ArgL
        TRAP  0,Fgets,StdIn
        BN    $255,Done
% 줄을 낱말로 나눈다. 빈칸과 줄 바꿈은 널 문자로 바꾸고 낱말의 처음을 Argv에 적는다.
        LDA   p,Line
        LDA   a,Argv
        SET   n,0
1H      LDBU  c,p,0
        BZ    c,4F
        CMP   t,c,' '
        BZ    t,3F
        CMP   t,c,#a
        BZ    t,3F
        CMP   t,n,32
        BNN   t,4F              낱말은 32개까지
        SLU   t,n,3
        STOU  p,a,t             낱말이 시작한다
        ADD   n,n,1
2H      ADD   p,p,1
        LDBU  c,p,0
        BZ    c,4F
        CMP   t,c,' '
        BZ    t,3F
        CMP   t,c,#a
        BNZ   t,2B
3H      SET   t,0
        STB   t,p,0
        ADD   p,p,1
        JMP   1B
4H      SLU   t,n,3
        STCO  0,a,t             Argv의 끝
        BZ    n,Main            빈 줄
% 첫 낱말이 exit인가?
        LDOU  s,a,0
        LDA   e,ExitW
5H      LDBU  c,s,0
        LDBU  t,e,0
        CMP   t,c,t
        BNZ   t,6F
        BZ    c,Done
        ADD   s,s,1
        ADD   e,e,1
        JMP   5B
6H      TRAP  0,Fork,0
        BZ    $255,Child
        BN    $255,Main         Fork할 수 없으면 그냥 넘어간다
        TRAP  0,Wait,0
        JMP   Main
Child   LDA   $255,Argv
        TRAP  0,Exec,0          돌아오면 실패한 것이다
        LDA   $255,NoExec
        TRAP  0,Fputs,StdErr
        LDOU  $255,a,0
        TRAP  0,Fputs,StdErr
        LDA   $255,NewLine
        TRAP  0,Fputs,StdErr
        NEG   $255,0,1
        TRAP  0,Halt,0
Done    SET   $255,0
        TRAP  0,Halt,0
