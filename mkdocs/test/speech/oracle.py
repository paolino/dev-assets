#!/usr/bin/env python3
"""Compare the speech companions of a docs directory with the pages the site renders.

usage: oracle.py SITE_DIR DOCS_DIR

For every PAGE.speech.json under DOCS_DIR, the words in its segments must equal,
in order, the words a reader sees in the prose of the built page (inside the main
content, outside tables, code, diagrams, navigation and buttons). Page titles
that own no prose are not spoken and are left out of the page side. It reads the
built site, not the Markdown, so it is independent of the extraction. Exit 1 on
any difference.
"""
import json,re,sys,os,difflib
from html.parser import HTMLParser
SILENT=('pre','table','svg','script','style','button','nav','dialog','figure')
VOID=('br','hr','img','input','meta','link','wbr','area','col','source','track','embed','param')
FIG=re.compile(r'(^|\s)diagram(-links)?(\s|$)|headerlink')
class Main(HTMLParser):
    def __init__(s): super().__init__(convert_charrefs=True); s.main=0; s.stack=[]; s.sil=0; s.txt=[]; s.ids=set(); s.h1=set(); s.inh1=None
    def handle_starttag(s,t,a):
        if t in VOID: return
        a=dict(a)
        sil = t in SILENT or bool(FIG.search(a.get('class','')))
        s.stack.append((t,sil,(t=='main' and a.get('id')=='terminal-mkdocs-main-content') or (t=='article' and 'md-content__inner' in a.get('class',''))))
        if s.stack[-1][2]: s.main+=1
        if sil: s.sil+=1
        if s.main and not s.sil and t in('h1','h2','h3') and 'id' in a: s.ids.add(a['id'])
        if s.main and not s.sil and t=='h1':
            s.inh1=a.get('id'); s.h1.add(s.inh1); s.txt.append(('<h1>',s.inh1))
    def handle_endtag(s,t):
        if t in VOID or t not in [x[0] for x in s.stack]: return
        while s.stack:
            c,sil,m=s.stack.pop()
            if sil: s.sil-=1
            if m: s.main-=1
            if c=='h1' and s.inh1 is not None: s.txt.append(('</h1>',s.inh1)); s.inh1=None
            if c==t: break
    def handle_data(s,d):
        if s.main and not s.sil: s.txt.append(d)
tok=lambda t:re.findall(r"\w+",t.lower())
def run(site,comp,pages):
    out={'pages':0,'exact':0,'diff_pages':[],'segments':0,'placeholders':0,'tags':0,'badkeys':[]}
    for pg,compfile in pages:
        pgn=pg[:-len('/index')] if pg.endswith('/index') else pg
        f=site+('/index.html' if pgn=='index' else '/'+pgn+'/index.html')
        if not os.path.exists(f) or not os.path.exists(compfile): out['diff_pages'].append((pg,'missing page or companion')); continue
        m=Main(); m.feed(open(f).read())
        data=json.load(open(compfile)); keys=[k for k in data if not k.startswith('_')]
        segs=[s['text'] for k in keys for s in data[k]]
        flat=[];skip=False
        for x in m.txt:
            if isinstance(x,tuple):
                skip = (x[0]=='<h1>' and x[1] not in keys)
                continue
            if not skip: flat.append(x)
        m.txt=flat
        out['segments']+=len(segs)
        out['placeholders']+=sum(1 for x in segs if re.match(r'^A (diagram|code block|table)',x))
        out['tags']+=sum(1 for x in segs if re.search(r'</?[a-zA-Z][^>]*>',x))
        bad=[k for k in keys if k not in m.ids]; 
        if bad: out['badkeys'].append((pg,bad))
        a=tok(''.join(m.txt)); b=tok(' '.join(segs)); out['pages']+=1
        if a==b: out['exact']+=1
        else:
            sm=difflib.SequenceMatcher(None,a,b,autojunk=False)
            d=[(t,' '.join(a[i1:i2])[:60],' '.join(b[j1:j2])[:60]) for t,i1,i2,j1,j2 in sm.get_opcodes() if t!='equal']
            out['diff_pages'].append((pg,len(a),len(b),d[:4]))
    return out
if __name__=='__main__':
    import glob
    site,docs=sys.argv[1],sys.argv[2]
    pages=[]
    for f in sorted(glob.glob(docs+'/**/*.speech.json',recursive=True)):
        pages.append((os.path.relpath(f,docs)[:-len('.speech.json')],f))
    r=run(site,None,pages)
    print({k:(v if not isinstance(v,list) else len(v)) for k,v in r.items()})
    for d in r['diff_pages'][:12]: print(d)
    for d in r['badkeys'][:5]: print('badkeys',d)
    sys.exit(1 if r['diff_pages'] or r['badkeys'] else 0)
