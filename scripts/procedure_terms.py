"""Shared terminology for nontransvenous ICDs (Python 3.6+)."""
import re

SEP = r"[\s\u2010-\u2015-]*"
SUBCUTANEOUS_ICD = re.compile(
    r"\b(?:sub" + SEP + r"(?:q|cutaneous)" + SEP + r"(?:ICD|defibrillator)|"
    r"S(?:Q)?" + SEP + r"ICD)\b", re.I)
EXTRAVASCULAR_ICD = re.compile(
    r"\b(?:extra" + SEP + r"vascular" + SEP + r"(?:ICD|defibrillator)|EV" + SEP + r"I?CD|"
    r"EV240163|DVEA3E4|Medtronic\s+(?:ICD\s+)?Aurora|Aurora\s+(?:EV" + SEP + r"I?CD|ICD))\b", re.I)


def device_mentions(text):
    text = re.sub(r"\s+", " ", text or "").strip()
    evidence = []
    for pattern in (SUBCUTANEOUS_ICD, EXTRAVASCULAR_ICD):
        for match in pattern.finditer(text):
            evidence.append(text[max(0, match.start() - 100):match.end() + 150])
    return bool(SUBCUTANEOUS_ICD.search(text)), bool(EXTRAVASCULAR_ICD.search(text)), " || ".join(dict.fromkeys(evidence))
