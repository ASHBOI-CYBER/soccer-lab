"""Fills the App Store page for version 2.0 from appstore/listing.json and appstore/screenshots (2026-11-20).

Run by .github/workflows/appstore-page.yml. MODE=check only prints what is there; MODE=apply writes:
  - the 2.0 version (made if it doesn't exist), its description, keywords, promo text, What's New, support URL
  - the app's name, subtitle and privacy policy URL
  - the review notes (no demo account: the app uses Sign in with Apple)
  - the newest processed build, attached to the version
  - the iPhone 6.9" screenshots (the old set is replaced)
It never submits for review: a person presses Submit in App Store Connect.
"""
import hashlib, json, os, sys, time, urllib.request, urllib.error
import jwt

APP = "6814847450"
VERSION = "2.0"
MODE = os.environ.get("MODE", "check")
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = json.load(open(os.path.join(HERE, "appstore", "listing.json"), encoding="utf-8"))
KEY = "\n".join(l.strip() for l in os.environ["P8"].replace("\r", "").split("\n") if l.strip())


def call(m, p, b=None):
    now = int(time.time())
    tok = jwt.encode({"iss": os.environ["ISS"].strip(), "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}, KEY,
                     algorithm="ES256", headers={"kid": os.environ["ID"].strip(), "typ": "JWT"})
    url = p if p.startswith("http") else "https://api.appstoreconnect.apple.com" + p
    r = urllib.request.Request(url, method=m, data=json.dumps(b).encode() if b is not None else None,
                               headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            x = urllib.request.urlopen(r, timeout=60)
            t = x.read()
            return x.status, json.loads(t) if t else {}
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()[:600]
        except Exception as e:  # timeouts: Apple's API has been slow
            if attempt == 2:
                return 0, str(e)
            time.sleep(5)


def say(label, status, body=None):
    ok = status in (200, 201, 204)
    print(("OK   " if ok else "FAIL ") + label + ("" if ok else f" -> {status} {str(body)[:300]}"))
    return ok


def patch(kind, id_, attrs, label):
    if MODE != "apply":
        return True
    s, r = call("PATCH", f"/v1/{kind}/{id_}", {"data": {"type": kind, "id": id_, "attributes": attrs}})
    return say(label, s, r)


# ---- the version
s, d = call("GET", f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=10")
if s != 200:
    sys.exit(f"can't list versions: {s} {d}")
for v in d["data"]:
    print("version", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
ver = next((v for v in d["data"] if v["attributes"]["versionString"] == VERSION), None)
if ver is None:
    if MODE != "apply":
        print(f"version {VERSION} doesn't exist yet (apply will create it)")
    else:
        s, r = call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
                    "attributes": {"platform": "IOS", "versionString": VERSION},
                    "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
        if not say(f"create version {VERSION}", s, r):
            sys.exit(1)
        ver = r["data"]
editable = ver is not None and ver["attributes"]["appStoreState"] in (
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")
if ver is not None and not editable:
    print("version", VERSION, "is", ver["attributes"]["appStoreState"], "- it can't be edited in this state")

# ---- name, subtitle, privacy policy (app info)
s, d = call("GET", f"/v1/apps/{APP}/appInfos")
infos = d["data"] if s == 200 else []
for i in infos:
    print("appInfo", i["id"][:8], i["attributes"].get("appStoreState") or i["attributes"].get("state"))
info = next((i for i in infos if (i["attributes"].get("appStoreState") or i["attributes"].get("state")) not in
             ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")), infos[-1] if infos else None)
if info:
    s, d = call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")
    for loc in d["data"] if s == 200 else []:
        a = loc["attributes"]
        print("  info", a["locale"], "| name:", a.get("name"), "| subtitle:", a.get("subtitle"), "| privacy:", a.get("privacyPolicyUrl"))
        if a["locale"] == "en-US":
            patch("appInfoLocalizations", loc["id"],
                  {"name": L["name"], "subtitle": L["subtitle"], "privacyPolicyUrl": L["privacyPolicyUrl"]}, "name, subtitle, privacy URL")

if ver is None:
    sys.exit(0)

# ---- version text
s, d = call("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")
locs = d["data"] if s == 200 else []
en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
for l in locs:
    a = l["attributes"]
    print("  version text", a["locale"], "| description:", len(a.get("description") or ""), "chars | keywords:", a.get("keywords"))
if en and editable:
    patch("appStoreVersionLocalizations", en["id"],
          {"description": L["description"], "keywords": L["keywords"], "promotionalText": L["promotionalText"],
           "whatsNew": L["whatsNew"], "supportUrl": L["supportUrl"]}, "description, keywords, promo text, What's New, support URL")

# ---- review notes
s, d = call("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreReviewDetail")
if s == 200 and d.get("data"):
    a = d["data"]["attributes"]
    print("  review detail: contact", bool(a.get("contactEmail")), "| demo required:", a.get("demoAccountRequired"), "| notes:", len(a.get("notes") or ""), "chars")
    if editable:
        patch("appStoreReviewDetails", d["data"]["id"], {"notes": L["reviewNotes"], "demoAccountRequired": False}, "review notes")
elif editable and MODE == "apply":
    s, r = call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails",
                "attributes": {"notes": L["reviewNotes"], "demoAccountRequired": False},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
    say("review notes (new)", s, r)
else:
    print("  review detail: none yet")

# ---- the build
s, d = call("GET", f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit=5&fields[builds]=version,processingState,expired")
builds = [b for b in (d["data"] if s == 200 else []) if b["attributes"]["processingState"] == "VALID" and not b["attributes"].get("expired")]
want = os.environ.get("BUILD", "").strip()
build = next((b for b in builds if b["attributes"]["version"] == want), None) if want else (builds[0] if builds else None)
s, cur = call("GET", f"/v1/appStoreVersions/{ver['id']}/build")
print("  build attached now:", (cur.get("data") or {}).get("attributes", {}).get("version") if s == 200 and isinstance(cur, dict) else None,
      "| newest processed:", build["attributes"]["version"] if build else None)
if build and editable and MODE == "apply":
    s, r = call("PATCH", f"/v1/appStoreVersions/{ver['id']}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
    say(f"attach build {build['attributes']['version']}", s, r)

# ---- screenshots (iPhone 6.9")
shots = sorted(f for f in os.listdir(os.path.join(HERE, "appstore", "screenshots")) if f.endswith(".png"))
if en:
    s, d = call("GET", f"/v1/appStoreVersionLocalizations/{en['id']}/appScreenshotSets?include=appScreenshots&limit=50")
    sets = d["data"] if s == 200 else []
    for st in sets:
        n = len(st.get("relationships", {}).get("appScreenshots", {}).get("data", []))
        print("  screenshot set", st["attributes"]["screenshotDisplayType"], n, "images")
    DISPLAY = "APP_IPHONE_67"
    if editable and MODE == "apply":
        # screenshot sets carried over from the old app (other sizes): the 6.9-inch set is used for every iPhone
        for old in [x for x in sets if x["attributes"]["screenshotDisplayType"] != DISPLAY]:
            say("remove the old " + old["attributes"]["screenshotDisplayType"] + " screenshots",
                call("DELETE", f"/v1/appScreenshotSets/{old['id']}")[0])
    if editable and MODE == "apply" and os.environ.get("SHOTS", "yes") == "yes":
        st = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == DISPLAY), None)
        if st is None:
            s, r = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                        "attributes": {"screenshotDisplayType": DISPLAY},
                        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": en["id"]}}}}})
            if not say("make the 6.9-inch screenshot set", s, r):
                sys.exit(1)
            st = r["data"]
        else:
            for old in st.get("relationships", {}).get("appScreenshots", {}).get("data", []):
                say("remove an old screenshot", call("DELETE", f"/v1/appScreenshots/{old['id']}")[0])
        for name in shots:
            data = open(os.path.join(HERE, "appstore", "screenshots", name), "rb").read()
            s, r = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                        "attributes": {"fileName": name, "fileSize": len(data)},
                        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": st["id"]}}}}})
            if not say(f"reserve {name}", s, r):
                continue
            shot = r["data"]
            good = True
            for op in shot["attributes"]["uploadOperations"]:
                req = urllib.request.Request(op["url"], method=op["method"], data=data[op["offset"]:op["offset"] + op["length"]],
                                             headers={h["name"]: h["value"] for h in op["requestHeaders"]})
                try:
                    urllib.request.urlopen(req, timeout=120).read()
                except Exception as e:
                    good = False
                    print("FAIL upload part of", name, str(e)[:200])
            if good:
                s, r = call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
                            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
                say(f"upload {name}", s, r)
print("done (" + MODE + ")")
