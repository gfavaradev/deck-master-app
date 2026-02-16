import json, urllib.request, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

url = "https://deck-master-backend-kappa.vercel.app/api/yugioh/sync?page=1&limit=2"
print("Fetching:", url)
with urllib.request.urlopen(url, context=ctx, timeout=30) as r:
    data = json.loads(r.read().decode("utf-8"))

print("Type:", type(data).__name__)
if isinstance(data, dict):
    print("Keys:", list(data.keys()))
    cards = data.get("cards") or data.get("data") or []
    for k in ["totalPages","total_pages","total","page","pagination"]:
        if k in data: print(f"{k}: {data[k]}")
    print(f"Cards: {len(cards)}")
    if cards:
        c = cards[0]
        print(f"\n=== Card keys: {sorted(c.keys())}")
        print(f"name: {c.get('name')}")
        for lang in ['It','Fr','De','Pt']:
            print(f"name{lang}: {c.get(f'name{lang}', 'KEY NOT FOUND')}")
            print(f"description{lang}: {str(c.get(f'description{lang}', 'KEY NOT FOUND'))[:80]}")
        prints = c.get("prints", [])
        print(f"\nPrints: {len(prints)}")
        if prints:
            p = prints[0]
            print(f"Print keys: {sorted(p.keys())}")
            for lang in ['It','Fr','De','Pt']:
                for f in [f'setName{lang}', f'setCode{lang}', f'rarity{lang}']:
                    print(f"  {f}: {p.get(f, 'KEY NOT FOUND')}")
            prices = p.get("prices", {})
            print(f"Prices keys: {list(prices.keys()) if isinstance(prices, dict) else type(prices)}")
            if isinstance(prices, dict):
                for lk in ['EN','IT','FR','DE','PT']:
                    if lk in prices:
                        print(f"  Prices[{lk}]: {prices[lk]}")
                if not any(k in prices for k in ['EN','IT','FR','DE','PT']):
                    print(f"  Flat prices: {prices}")
elif isinstance(data, list):
    print("List len:", len(data))
