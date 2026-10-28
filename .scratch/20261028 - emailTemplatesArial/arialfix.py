"""Set font-family Arial,Helvetica,sans-serif inline on every text element of an email template / letterhead.

transform(html, classic_html=False) -> new html
normalize(html) strips every font declaration; normalize(before) == normalize(after) proves only fonts changed.
"""
import re

F = 'Arial,Helvetica,sans-serif'
TAGS = r'body|p|a|div|td|th|span|li|ul|ol|strong|b|em|i|u|h[1-6]|font|center|blockquote|label|small|big'
TAG_RE = re.compile(r'<(' + TAGS + r')(?=[\s>/])([^>]*)>', re.I)
# value of a font-family declaration: entities like &quot; contain ';', so consume them as a unit
VAL = r'(?:&[a-zA-Z]+;|&#\d+;|[^;"\'>])*'
VAL_SQ = r'(?:&[a-zA-Z]+;|&#\d+;|[^;\'>])*'   # inside style='...' double quotes are literal
FF_RE = re.compile(r'(?<![-\w])font-family\s*:\s*' + VAL + r';?\s*', re.I)
FF_SQ_RE = re.compile(r'(?<![-\w])font-family\s*:\s*' + VAL_SQ + r';?\s*', re.I)
MSO_RE = re.compile(r'(mso-(?:ascii|hansi|fareast|bidi)-font-family\s*:\s*)' + VAL + r'(;?)', re.I)
MSO_SQ_RE = re.compile(r'(mso-(?:ascii|hansi|fareast|bidi)-font-family\s*:\s*)' + VAL_SQ + r'(;?)', re.I)
STYLE_RE = re.compile(r'(\sstyle\s*=\s*)("([^"]*)"|\'([^\']*)\')', re.I)
FACE_RE = re.compile(r'(\sface\s*=\s*)("[^"]*"|\'[^\']*\'|[^\s>]+)', re.I)
STYLEBLOCK_RE = re.compile(r'(<style[^>]*>)(.*?)(</style>)', re.I | re.S)
CSS_FF_RE = re.compile(r'(?<![-\w])(font-family\s*:\s*)[^;}]*', re.I)
CDATA_RE = re.compile(r'(<!\[CDATA\[)(.*?)(\]\]>)', re.S)


def _fix_tag(m):
    name, attrs = m.group(1), m.group(2)
    if name.lower() == 'font':
        attrs = FACE_RE.sub(lambda f: f.group(1) + '"Arial"', attrs) if FACE_RE.search(attrs) else attrs
    sm = STYLE_RE.search(attrs)
    if sm:
        dq = sm.group(3) is not None
        css = sm.group(3) if dq else sm.group(4)
        css = (FF_RE if dq else FF_SQ_RE).sub('', css)
        css = (MSO_RE if dq else MSO_SQ_RE).sub(lambda x: x.group(1) + 'Arial' + x.group(2), css)
        css = 'font-family:' + F + ';' + (' ' + css.lstrip() if css.strip() else '')
        q = '"' if dq else "'"
        attrs = attrs[:sm.start()] + sm.group(1) + q + css.rstrip() + q + attrs[sm.end():]
    else:
        # insert before a trailing '/' of a self-closing tag
        tail = re.search(r'\s*/?\s*$', attrs)
        attrs = attrs[:tail.start()] + ' style="font-family:' + F + ';"' + attrs[tail.start():]
    return '<' + name + attrs + '>'


def _fix_fragment(html):
    html = STYLEBLOCK_RE.sub(lambda m: m.group(1) + CSS_FF_RE.sub(lambda c: c.group(1) + F, m.group(2)) + m.group(3), html)
    return TAG_RE.sub(_fix_tag, html)


def transform(html, classic_html=False):
    if not html:
        return html
    if classic_html:
        # Classic letterhead templates: only touch the editable content inside CDATA, never the editor's td structure
        return CDATA_RE.sub(lambda m: m.group(1) + _fix_fragment(m.group(2)) + m.group(3), html)
    return _fix_fragment(html)


def normalize(html):
    if not html:
        return html
    h = FF_RE.sub('', html)
    h = FF_SQ_RE.sub('', h)
    h = re.sub(r'mso-(?:ascii|hansi|fareast|bidi)-font-family\s*:\s*' + VAL + r';?', '', h, flags=re.I)
    h = re.sub(r'(<font\b[^>]*?)\sface\s*=\s*("[^"]*"|\'[^\']*\'|[^\s>]+)', r'\1', h, flags=re.I)
    h = STYLEBLOCK_RE.sub(lambda m: m.group(1) + CSS_FF_RE.sub('', m.group(2)) + m.group(3), h)
    h = re.sub(r'\sstyle\s*=\s*(""|\'\')', '', h, flags=re.I)
    h = re.sub(r'\s+', '', h)
    return h
