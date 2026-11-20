#!/usr/bin/env python3
# Copyright © 2026 Robert Bartis. All rights reserved.
"""
Upload GeoNap App Store metadata from appstore/metadata/<locale>/*.txt
to App Store Connect via the App Store Connect API.

DRY RUN BY DEFAULT: prints what would change. Pass --apply to write.

Files per locale folder (all optional — a missing file leaves that field as is):
    keywords.txt          (max 100 characters)
    whats_new.txt         (max 4000; not allowed on an app's very first version)
    description.txt       (max 4000)
    promotional_text.txt  (max 170; can change any time, no review needed)
    subtitle.txt          (max 30; stored on App Info, not on the version)

Setup (once):
    pip3 install pyjwt cryptography requests
    App Store Connect > Users and Access > Integrations > App Store Connect API:
      create a Team key with the "App Manager" role, download AuthKey_XXXX.p8
      (download is one-time; keep it OUT of git — *.p8 is in .gitignore).
    export ASC_KEY_ID=XXXXXXXXXX
    export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    export ASC_KEY_PATH=~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8

Usage:
    python3 appstore/upload_metadata.py --version 1.1.0            # dry run
    python3 appstore/upload_metadata.py --version 1.1.0 --apply    # write
    add --create-missing to add localizations that don't exist yet
"""
import argparse, os, sys, time
from pathlib import Path

try:
    import jwt, requests
except ImportError:
    sys.exit("Missing packages. Run: pip3 install pyjwt cryptography requests")

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.rmbartis.GeoNap"
METADATA_DIR = Path(__file__).resolve().parent / "metadata"

# file name -> (API attribute, max chars, lives on "version" or "appinfo")
FIELDS = {
    "keywords.txt":         ("keywords",        100,  "version"),
    "whats_new.txt":        ("whatsNew",        4000, "version"),
    "description.txt":      ("description",     4000, "version"),
    "promotional_text.txt": ("promotionalText", 170,  "version"),
    "subtitle.txt":         ("subtitle",        30,   "appinfo"),
}


def token():
    key_path = os.path.expanduser(os.environ.get("ASC_KEY_PATH", ""))
    kid, iss = os.environ.get("ASC_KEY_ID"), os.environ.get("ASC_ISSUER_ID")
    if not (key_path and kid and iss):
        sys.exit("Set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (see the top of this file).")
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      Path(key_path).read_text(), algorithm="ES256",
                      headers={"kid": kid, "typ": "JWT"})


class ASC:
    def __init__(self):
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {token()}"

    def call(self, method, path, **kw):
        r = self.s.request(method, API + path, timeout=30, **kw)
        if r.status_code >= 400:
            sys.exit(f"{method} {path} failed: HTTP {r.status_code}\n{r.text}")
        return r.json() if r.text else {}

    def get_all(self, path, params=None):
        out, url, params = [], API + path, dict(params or {}, limit=200)
        while url:
            r = self.s.get(url, params=params, timeout=30)
            if r.status_code >= 400:
                sys.exit(f"GET {url} failed: HTTP {r.status_code}\n{r.text}")
            j = r.json(); out += j["data"]; url = j.get("links", {}).get("next"); params = None
        return out


def load_local():
    """{locale: {filename: text}} from appstore/metadata, with length checks."""
    data, errors = {}, []
    for loc_dir in sorted(p for p in METADATA_DIR.iterdir() if p.is_dir()):
        files = {}
        for fname, (_, limit, _) in FIELDS.items():
            f = loc_dir / fname
            if f.exists():
                text = f.read_text(encoding="utf-8").strip()
                if len(text) > limit:
                    errors.append(f"{loc_dir.name}/{fname}: {len(text)} chars (max {limit})")
                if fname == "keywords.txt" and ", " in text:
                    errors.append(f"{loc_dir.name}/keywords.txt: remove spaces after commas")
                files[fname] = text
        if files:
            data[loc_dir.name] = files
    if errors:
        sys.exit("Fix these before uploading:\n  " + "\n  ".join(errors))
    return data


def show(locale, attr, old, new):
    one = lambda v: (v or "").replace("\n", " ⏎ ")
    print(f"  [{locale}] {attr}:\n      now: {one(old)[:110]}\n      new: {one(new)[:110]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", required=True, help="App Store version string, e.g. 1.1.0")
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    ap.add_argument("--create-missing", action="store_true", help="add localizations that don't exist yet")
    args = ap.parse_args()

    local = load_local()
    asc = ASC()
    apps = asc.get_all("/apps", {"filter[bundleId]": BUNDLE_ID})
    if not apps:
        sys.exit(f"No app with bundle ID {BUNDLE_ID}")
    app_id = apps[0]["id"]

    versions = asc.get_all(f"/apps/{app_id}/appStoreVersions",
                           {"filter[platform]": "IOS", "filter[versionString]": args.version})
    if not versions:
        sys.exit(f"No iOS version {args.version} in App Store Connect — create or rename it first.")
    version_id = versions[0]["id"]

    remote = {l["attributes"]["locale"]: l for l in
              asc.get_all(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")}
    print(f"App {app_id}, version {args.version} ({version_id})")
    print(f"Existing App Store localizations: {', '.join(sorted(remote)) or 'none'}")
    print(f"Local metadata folders:           {', '.join(sorted(local))}\n")

    # App Info (subtitle) — the editable App Info is the one not yet live.
    info_locs = {}
    if any("subtitle.txt" in f for f in local.values()):
        infos = asc.get_all(f"/apps/{app_id}/appInfos")
        editable = [i for i in infos if i["attributes"].get("appStoreState") != "READY_FOR_SALE"] or infos
        info_locs = {l["attributes"]["locale"]: l for l in
                     asc.get_all(f"/appInfos/{editable[0]['id']}/appInfoLocalizations")}

    changes = 0
    for locale, files in local.items():
        v_attrs = {FIELDS[f][0]: t for f, t in files.items() if FIELDS[f][2] == "version"}
        rec = remote.get(locale)
        if rec is None:
            if not args.create_missing:
                print(f"  [{locale}] SKIPPED — no such localization in App Store Connect "
                      f"(add it there, or re-run with --create-missing)")
                continue
            print(f"  [{locale}] will be CREATED with: {', '.join(v_attrs)}")
            changes += 1
            if args.apply:
                rec = asc.call("POST", "/appStoreVersionLocalizations", json={"data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": dict(v_attrs, locale=locale),
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})["data"]
                remote[locale] = rec
        else:
            diff = {k: v for k, v in v_attrs.items() if (rec["attributes"].get(k) or "").strip() != v}
            for k, v in diff.items():
                show(locale, k, rec["attributes"].get(k), v)
            if diff:
                changes += len(diff)
                if args.apply:
                    asc.call("PATCH", f"/appStoreVersionLocalizations/{rec['id']}", json={"data": {
                        "type": "appStoreVersionLocalizations", "id": rec["id"], "attributes": diff}})

        if "subtitle.txt" in files:
            irec = info_locs.get(locale)
            new = files["subtitle.txt"]
            if irec is None:
                print(f"  [{locale}] subtitle SKIPPED — no App Info localization for this locale")
            elif (irec["attributes"].get("subtitle") or "") != new:
                show(locale, "subtitle", irec["attributes"].get("subtitle"), new)
                changes += 1
                if args.apply:
                    asc.call("PATCH", f"/appInfoLocalizations/{irec['id']}", json={"data": {
                        "type": "appInfoLocalizations", "id": irec["id"], "attributes": {"subtitle": new}}})

    if not changes:
        print("Everything already matches — nothing to do.")
    elif args.apply:
        print(f"\nDone: {changes} change(s) written. Review the version page in App Store Connect.")
    else:
        print(f"\nDRY RUN: {changes} change(s) would be made. Re-run with --apply to write them.")


if __name__ == "__main__":
    main()
