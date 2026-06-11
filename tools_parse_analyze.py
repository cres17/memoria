import re
from collections import defaultdict, OrderedDict
p='analyze_output.txt'
counts=defaultdict(int)
examples={}
with open(p,encoding='utf-8') as f:
    for line in f:
        s=line.strip()
        if s.startswith('error -') or s.startswith('warning -'):
            parts = s.split(' - ')
            if len(parts) >= 3:
                severity = parts[0]
                code = parts[-1]
                loc = parts[-2]
                key=(severity,code)
                counts[key]+=1
                if key not in examples:
                    examples[key]=loc

sorted_items = sorted(counts.items(), key=lambda x: -x[1])
for (sev,code),cnt in sorted_items:
    print(f"{cnt}\t{sev}\t{code}\t{examples[(sev,code)]}")
print('\nTOTAL_ISSUES', sum(counts.values()))
