from pathlib import Path
p=Path(r"c:\Users\Administrator\sagana\lib\presentation\screens\admin\pending_approvals_screen.dart")
s=p.read_text()
pairs={'(':')','[':']','{':'}'}
stack=[]
line=1
col=0
for i,ch in enumerate(s):
    col+=1
    if ch=='\n':
        line+=1; col=0
    if ch in '([{':
        stack.append((ch,line,col))
    elif ch in ')]}':
        if not stack:
            print('Unmatched closing',ch,'at',line,col); break
        last, lline, lcol = stack[-1]
        if pairs[last]==ch:
            stack.pop()
        else:
            print('Mismatched', last,'opened at',lline,lcol,'but',ch,'closed at',line,col); break
else:
    if stack:
        print('Unclosed at end:', stack[-1])
    else:
        print('All balanced')
