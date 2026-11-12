#!/usr/bin/env python3
"""Point this project at a different App Store app (bundle ID, Apple team, App Store ID).

The code was written for com.jacksteiner.soccermax (team M9YGAL979V, App Store ID 6828180179). To ship it as an
update to another listing, everything that carries that identity has to change together: the two targets, the widget
app group, the in-app purchase product IDs, the local StoreKit test file and the "rate us" link.

    python set-identity.py <bundle-id> <team-id> <app-store-id>
    python set-identity.py com.example.skieerai ABCDE12345 1234567890

Run it once from this folder. It prints every file it changed and refuses to run if the old identity is already gone.
Afterwards, in App Store Connect / RevenueCat / Supabase (this script can't do these):
  - create the subscriptions and lifetime purchase with the new product IDs (<bundle-id>.monthly, .yearly, ...);
  - add the app group  group.<bundle-id>  and Sign in with Apple to the App ID, and the widget App ID <bundle-id>.widgets;
  - add <bundle-id> to Supabase > Authentication > Apple > Client IDs, or Sign in with Apple is rejected.
"""
import os
import re
import sys

OLD_BUNDLE = "com.jacksteiner.soccermax"
OLD_TEAM = "M9YGAL979V"
OLD_APP_ID = "6828180179"

FILES = [
    "project.yml",
    "SoccerMax.xcodeproj/project.pbxproj",
    "SoccerMax.storekit",
    "SoccerMax/Info.plist",
    "SoccerMax/SoccerMax.entitlements",
    "SoccerMaxWidgets/SoccerMaxWidgets.entitlements",
    "SoccerMax/Shared/WidgetSnapshot.swift",
    "SoccerMax/Data/Purchases.swift",
    "SoccerMax/Screens/StayOffer.swift",
    "SoccerMax/Screens/CardViews.swift",
    "sim.sh",
    "duo-check.sh",
]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    bundle, team, app_id = sys.argv[1:]
    if not re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+", bundle):
        sys.exit(f"'{bundle}' doesn't look like a bundle ID (like com.company.app)")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        sys.exit(f"'{team}' doesn't look like an Apple team ID (10 letters and digits)")
    if not re.fullmatch(r"[0-9]{6,12}", app_id):
        sys.exit(f"'{app_id}' doesn't look like an App Store ID (digits only, from the app's App Store link)")

    here = os.path.dirname(os.path.abspath(__file__))
    prefix = bundle.rsplit(".", 1)[0]
    total = 0
    for rel in FILES:
        path = os.path.join(here, *rel.split("/"))
        with open(path, encoding="utf-8", newline="") as f:
            old = f.read()
        new = old.replace(OLD_BUNDLE, bundle).replace(OLD_TEAM, team).replace(OLD_APP_ID, app_id)
        if rel == "project.yml":
            new = new.replace("bundleIdPrefix: com.jacksteiner", f"bundleIdPrefix: {prefix}")
        if new != old:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(new)
            n = old.count(OLD_BUNDLE) + old.count(OLD_TEAM) + old.count(OLD_APP_ID)
            total += n
            print(f"  {rel}: {n} place(s)")
    if total == 0:
        sys.exit("Nothing changed: the old identity is not in these files any more (already switched?).")
    print(f"Done: {total} places now use {bundle} / {team} / {app_id}.")


if __name__ == "__main__":
    main()
