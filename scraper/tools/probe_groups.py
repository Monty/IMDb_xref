#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright", "pydantic"]
# ///
"""Probe how category headings and credit rows interleave in the credits section.

IMDb puts every credit category (Actor, Writer, Director, ...) inside a single
<section>, separated only by <h4> headings, so section membership is positional.
This dumps that heading/row sequence in document order -- the quickest way to see
what changed the next time IMDb reshuffles the fullcredits DOM and get_filmography
starts misattributing jobs.

    ./probe_groups.py [nconst]
"""

import sys
from pathlib import Path

# Resolve the scraper package from this file's location (tools/ is one level
# below scraper/), so the tool works from any checkout without a hardcoded path.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from browser import close_manager, get_manager  # noqa: E402

JS = """
() => {
  const sections = [...document.querySelectorAll('section')];
  const leaf = sections.filter(s => s.querySelectorAll('section').length === 0
                                 && s.querySelectorAll('li.ipc-metadata-list-summary-item').length > 0)[0];
  if (!leaf) return {error: 'no leaf section found'};

  // Walk every descendant in document order, recording headings and rows
  const out = [];
  const walker = document.createTreeWalker(leaf, NodeFilter.SHOW_ELEMENT);
  let n = walker.currentNode;
  while (n) {
    if (/^H[2-6]$/.test(n.tagName)) {
      out.push({kind: 'heading', tag: n.tagName, text: n.innerText.trim().split('\\n')[0]});
    } else if (n.matches('li.ipc-metadata-list-summary-item')) {
      out.push({kind: 'row', title: (n.innerText.trim().split('\\n')[0] || '')});
    } else if (n.tagName === 'BUTTON' && /all|more/i.test(n.innerText)) {
      out.push({kind: 'button', text: n.innerText.trim().split('\\n')[0]});
    }
    n = walker.nextNode();
  }

  // Collapse consecutive rows into counts
  const summary = [];
  for (const item of out) {
    if (item.kind === 'row') {
      const last = summary[summary.length - 1];
      if (last && last.kind === 'rows') { last.n++; last.last = item.title; }
      else summary.push({kind: 'rows', n: 1, first: item.title, last: item.title});
    } else {
      summary.push(item);
    }
  }
  return {
    totalRows: leaf.querySelectorAll('li.ipc-metadata-list-summary-item').length,
    leafTestId: leaf.getAttribute('data-testid'),
    leafClass: leaf.className,
    summary
  };
}
"""


def main() -> None:
    nconst = sys.argv[1] if len(sys.argv) > 1 else "nm0000123"
    mgr = get_manager()
    page = mgr.goto(f"https://www.imdb.com/name/{nconst}/fullcredits")

    data = page.evaluate(JS)
    if "error" in data:
        print(data["error"])
    else:
        print(f"leaf rows={data['totalRows']}  testid={data['leafTestId']!r}")
        print(f"leaf class={data['leafClass']!r}")
        print()
        for item in data["summary"]:
            if item["kind"] == "heading":
                print(f"  <{item['tag']}> {item['text']!r}")
            elif item["kind"] == "button":
                print(f"      [button] {item['text']!r}")
            else:
                print(
                    f"      {item['n']:>4} rows   ({item['first']!r} … {item['last']!r})"
                )

    page.close()
    close_manager()


if __name__ == "__main__":
    main()
